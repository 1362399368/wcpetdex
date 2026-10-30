import contextlib
import copy
import io
import json
import sqlite3
import tempfile
import time
import unittest
import uuid
from pathlib import Path

from config import Settings
from manage import main
from migration import FORMAT, ROOM_KEY, backup_database, import_snapshot, read_tokens
from server import Store


TOKENS = {"A": "fake-device-a-" + "a" * 32, "B": "fake-device-b-" + "b" * 32}


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.store = Store(":memory:")
        self.now = time.time()
        self.snapshot = {
            "format": FORMAT, "pair_key": ROOM_KEY, "exported_at": self.now,
            "events": [
                {"id": str(uuid.uuid4()), "sender": "A", "recipient": "B", "sent_at": self.now - 20, "acknowledged": 0, "kind": "miss"},
                {"id": str(uuid.uuid4()), "sender": "B", "recipient": "A", "sent_at": self.now - 10, "acknowledged": 1, "kind": "anger"},
            ],
        }

    def tearDown(self):
        self.store.db.close()

    def run_import(self, snapshot=None):
        return import_snapshot(self.store, TOKENS, snapshot or self.snapshot, now=self.now)

    def test_identity_queue_receipt_and_idempotent_reimport(self):
        result = self.run_import()
        self.assertEqual(result["devices_created"], 2)
        self.assertEqual(result["events_created"], 2)
        a, b = (self.store.authenticate(TOKENS[member]) for member in ("A", "B"))
        self.assertEqual(self.store.peer(a), b["id"])
        self.assertEqual([row["id"] for row in self.store.queued(b["id"])], [self.snapshot["events"][0]["id"]])
        receipt = self.store.status(b["id"], self.snapshot["events"][1]["id"])
        self.assertEqual((receipt["acknowledged"], receipt["kind"]), (1, "anger"))
        self.assertEqual(self.run_import()["unchanged"], 2)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM events").fetchone()[0], 2)

    def test_existing_original_device_ids_are_preserved(self):
        from server import token_hash
        original = {member: str(uuid.uuid4()) for member in ("A", "B")}
        with self.store.db:
            self.store.db.executemany("INSERT INTO devices VALUES(?,?,?)", [(original[member], "original-pair", token_hash(TOKENS[member])) for member in ("A", "B")])
        self.assertEqual(self.run_import()["devices_created"], 0)
        self.assertEqual(self.store.authenticate(TOKENS["A"])["id"], original["A"])
        self.assertEqual(self.store.authenticate(TOKENS["B"])["pair_id"], "original-pair")

    def test_receipts_upgrade_but_never_downgrade(self):
        self.run_import()
        upgraded = copy.deepcopy(self.snapshot)
        upgraded["events"][0]["acknowledged"] = 1
        self.assertEqual(self.run_import(upgraded)["receipts_upgraded"], 1)
        self.run_import()  # stale snapshot has acknowledged=0
        self.assertEqual(self.store.db.execute("SELECT SUM(acknowledged) FROM events").fetchone()[0], 2)

    def test_conflicting_event_rolls_back_new_rows_and_upgrades(self):
        self.run_import()
        conflict = copy.deepcopy(self.snapshot)
        conflict["events"][0]["acknowledged"] = 1
        conflict["events"][1]["kind"] = "miss"
        with self.assertRaises(ValueError):
            self.run_import(conflict)
        self.assertEqual(self.store.db.execute("SELECT SUM(acknowledged) FROM events").fetchone()[0], 1)

    def test_invalid_snapshot_does_not_create_pair(self):
        for field, value in (("format", "wrong"), ("pair_key", "other-pair"), ("exported_at", self.now+61)):
            invalid = copy.deepcopy(self.snapshot)
            invalid[field] = value
            with self.assertRaises(ValueError):
                self.run_import(invalid)
        invalid = copy.deepcopy(self.snapshot)
        invalid["events"][0]["recipient"] = "A"
        with self.assertRaises(ValueError):
            self.run_import(invalid)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM devices").fetchone()[0], 0)

    def test_expired_rows_skip_and_boundary_retained(self):
        self.snapshot["events"][0]["sent_at"] = self.now-86401
        self.snapshot["events"][1]["sent_at"] = self.now-86400
        result = self.run_import()
        self.assertEqual((result["expired_skipped"], result["events_created"]), (1, 1))

    def test_partial_identity_does_not_rebind_existing_token(self):
        from server import token_hash
        with self.store.db:
            self.store.db.execute("INSERT INTO devices VALUES(?,?,?)", ("existing-id", "existing-pair", token_hash(TOKENS["A"])))
        with self.assertRaises(ValueError):
            self.run_import()
        self.assertIsNone(self.store.authenticate(TOKENS["B"]))
        self.assertEqual(self.store.authenticate(TOKENS["A"])["id"], "existing-id")

    def test_excess_pending_queue_rejected_atomically(self):
        self.snapshot["events"] = [dict(id=str(uuid.uuid4()), sender="A", recipient="B", sent_at=self.now-5, acknowledged=0, kind="miss") for _ in range(101)]
        with self.assertRaises(ValueError):
            self.run_import()
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM devices").fetchone()[0], 0)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM events").fetchone()[0], 0)

    def test_duplicate_in_snapshot_requires_identical_values(self):
        self.snapshot["events"].append(copy.deepcopy(self.snapshot["events"][0]))
        self.assertEqual(self.run_import()["events_created"], 2)
        self.snapshot["events"][-1]["kind"] = "anger"
        with self.assertRaises(ValueError):
            self.run_import()

    def test_cli_dry_run_original_unchanged_and_backup_then_reimport(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db, token_file, snapshot = root/"pair.sqlite3", root/"tokens.json", root/"export.json"
            token_file.write_text(json.dumps({f"DEVICE_{member}_TOKEN": value for member, value in TOKENS.items()}))
            snapshot.write_text(json.dumps(self.snapshot))
            args = ["--db", str(db), "import-cloudflare", "--tokens-file", str(token_file), "--snapshot", str(snapshot)]
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main(args+["--dry-run"]), 0)
            self.assertFalse(db.exists())
            self.assertNotIn(TOKENS["A"], output.getvalue())
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(args), 0)
            before = db.read_bytes()
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(args+["--dry-run"]), 0)
            self.assertEqual(db.read_bytes(), before)
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main(args), 0)
            self.assertEqual(json.loads(output.getvalue())["unchanged"], 2)
            self.assertEqual(len(list(root.glob("*.backup-*"))), 1)
            restored = Store(str(db))
            self.assertIsNotNone(restored.authenticate(TOKENS["B"]))
            restored.db.close()

    def test_backup_preserves_committed_wal(self):
        with tempfile.TemporaryDirectory() as directory:
            db, backup = Path(directory)/"live.sqlite3", Path(directory)/"backup.sqlite3"
            store = Store(str(db))
            store.create_pair()
            backup_database(db, backup)
            with sqlite3.connect(backup) as copied:
                self.assertEqual(copied.execute("SELECT COUNT(*) FROM devices").fetchone()[0], 2)
            with self.assertRaises(ValueError):
                backup_database(db, backup)
            store.db.close()

    def test_token_file_validation_uses_existing_values_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"tokens.json"
            values = {f"DEVICE_{member}_TOKEN": value for member, value in TOKENS.items()}
            path.write_text(json.dumps({**values, "unrelated_setting": "ignored"}))
            self.assertEqual(read_tokens(path), TOKENS)
            path.write_text(json.dumps({**values, "DEVICE_B_TOKEN": TOKENS["A"]}))
            with self.assertRaises(ValueError):
                read_tokens(path)


class SettingsTests(unittest.TestCase):
    def test_default_listener_is_loopback(self):
        settings = Settings.from_environment({"PETPAIR_ADMIN_TOKEN": "x"*32})
        self.assertEqual((settings.host, settings.port), ("127.0.0.1", 8765))
        self.assertNotIn("x"*32, repr(settings))

    def test_file_secret_and_conflicting_config(self):
        with tempfile.TemporaryDirectory() as directory:
            token_file = Path(directory)/"admin"
            token_file.write_text("fake-admin-"+"z"*32+"\n")
            settings = Settings.from_environment({"PETPAIR_ADMIN_TOKEN_FILE": str(token_file), "PETPAIR_DB": "/data/test.sqlite3"})
            self.assertEqual(settings.admin_token, "fake-admin-"+"z"*32)
            with self.assertRaises(ValueError):
                Settings.from_environment({"PETPAIR_ADMIN_TOKEN_FILE": str(token_file), "PETPAIR_ADMIN_TOKEN": "x"*32})

    def test_invalid_port_or_missing_secret(self):
        for env in ({}, {"PETPAIR_ADMIN_TOKEN": "x"*32, "PETPAIR_PORT": "0"}, {"PETPAIR_ADMIN_TOKEN": "x"*32, "PETPAIR_PORT": "bad"}):
            with self.assertRaises(ValueError):
                Settings.from_environment(env)


if __name__ == "__main__":
    unittest.main()
