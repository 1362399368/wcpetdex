#!/usr/bin/env python3
"""Local-only administration. Secret values never appear in command arguments/output."""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
import tempfile
import time
from pathlib import Path

from migration import FORMAT, ROOM_KEY, backup_database, import_snapshot, read_tokens
from server import Store


def parser():
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument("--db", type=Path, required=True, help="SQLite path; stop service before an import")
    sub = root.add_subparsers(dest="command", required=True)
    for name in ("import-cloudflare", "import-tokens"):
        command = sub.add_parser(name)
        command.add_argument("--tokens-file", type=Path, required=True)
        command.add_argument("--pair-key", default=ROOM_KEY)
        command.add_argument("--dry-run", action="store_true", help="validate on a temporary database without changing the original")
        if name == "import-cloudflare":
            command.add_argument("--snapshot", type=Path, required=True)
    backup = sub.add_parser("backup")
    backup.add_argument("--output", type=Path, required=True)
    sub.add_parser("check")
    return root


def import_to_path(path, tokens, snapshot, pair_key, now):
    store = Store(str(path))
    try:
        return import_snapshot(store, tokens, snapshot, pair_key=pair_key, now=now)
    finally:
        store.db.close()


def main(argv=None):
    args = parser().parse_args(argv)
    if args.command == "backup":
        backup_database(args.db, args.output)
        print(json.dumps({"ok": True, "backup": str(args.output)}))
        return 0
    if args.command == "check":
        with sqlite3.connect(args.db.resolve().as_uri() + "?mode=ro", uri=True) as db:
            if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                raise ValueError("database quick_check failed")
            devices = db.execute("SELECT COUNT(*) FROM devices").fetchone()[0]
            pending = db.execute("SELECT COUNT(*) FROM events WHERE acknowledged=0 AND sent_at>=?", (time.time()-86400,)).fetchone()[0]
            receipts = db.execute("SELECT COUNT(*) FROM events WHERE acknowledged=1 AND sent_at>=?", (time.time()-86400,)).fetchone()[0]
        print(json.dumps({"ok": True, "devices": devices, "pending": pending, "receipts": receipts}))
        return 0
    now = time.time()
    tokens = read_tokens(args.tokens_file)
    checksum = None
    if args.command == "import-cloudflare":
        if args.snapshot.stat().st_size > 32 * 1024 * 1024:
            raise ValueError("snapshot exceeds 32 MiB")
        data = args.snapshot.read_bytes()
        checksum = hashlib.sha256(data).hexdigest()
        snapshot = json.loads(data)
    else:
        snapshot = {"format": FORMAT, "pair_key": args.pair_key, "exported_at": now, "events": []}
    # Validate on a scratch copy first. This also leaves the original schema untouched on dry-run.
    with tempfile.TemporaryDirectory(prefix="petpair-import-") as directory:
        scratch = Path(directory) / "pair.sqlite3"
        if args.db.exists():
            backup_database(args.db, scratch)
        result = import_to_path(scratch, tokens, snapshot, args.pair_key, now)
    backup = None
    if not args.dry_run:
        if args.db.exists():
            backup = args.db.with_name(args.db.name + f".backup-{time.time_ns()}")
            backup_database(args.db, backup)
        result = import_to_path(args.db, tokens, snapshot, args.pair_key, now)
        args.db.chmod(0o600)
    print(json.dumps({"ok": True, "dry_run": args.dry_run, **result,
                      "snapshot_sha256": checksum, "backup": str(backup) if backup else None}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, sqlite3.Error):
        # Avoid echoing an untrusted file value, SQL argument, or secret in an exception.
        print("Import/check failed. Original token identities and event rows were not replaced; inspect the input format, paths, permissions and pair conflicts.", file=sys.stderr)
        raise SystemExit(1)
