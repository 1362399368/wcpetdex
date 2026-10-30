import asyncio
import hashlib
import sqlite3
import tempfile
import time
import unittest
import uuid
from unittest.mock import patch

from aiohttp import WSServerHandshakeError
from aiohttp.test_utils import TestClient, TestServer

from server import Store, create_app, event_message


ADMIN = "test-admin-token-" + "x" * 32


class PetPairTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.client = TestClient(TestServer(create_app(ADMIN)))
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close()

    async def pair(self):
        response = await self.client.post("/v1/pairs", headers={"Authorization": "Bearer " + ADMIN})
        self.assertEqual(response.status, 201)
        return (await response.json())["devices"]

    async def connect(self, device):
        ws = await self.client.ws_connect("/v1/ws", headers={"Authorization": "Bearer " + device["token"]})
        self.assertEqual(await ws.receive_json(), {"type": "ready", "protocol": 2})
        return ws

    async def test_authentication_and_pair_separation(self):
        response = await self.client.post("/v1/pairs")
        self.assertEqual(response.status, 401)
        with self.assertRaises(WSServerHandshakeError) as error:
            await self.client.ws_connect("/v1/ws", headers={"Authorization": "Bearer incorrect"})
        self.assertEqual(error.exception.status, 401)
        first, second = await self.pair(), await self.pair()
        sender, unrelated = await self.connect(first[0]), await self.connect(second[1])
        event_id = str(uuid.uuid4())
        await sender.send_json({"type": "miss", "id": event_id})
        self.assertEqual((await sender.receive_json())["state"], "queued")
        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(unrelated.receive_json(), 0.05)
        await sender.close()
        await unrelated.close()

    async def test_offline_queue_receipt_and_deduplication(self):
        devices = await self.pair()
        sender = await self.connect(devices[0])
        event_id = str(uuid.uuid4())
        await sender.send_json({"type": "miss", "id": event_id, "text": "ignored user input"})
        self.assertEqual((await sender.receive_json())["state"], "queued")
        recipient = await self.connect(devices[1])
        event = await recipient.receive_json()
        self.assertEqual(event["id"], event_id)
        self.assertEqual(event["text"], "我想你了")
        await recipient.send_json({"type": "ack", "id": event_id})
        self.assertEqual((await sender.receive_json())["type"], "delivered")
        await recipient.close()
        recipient = await self.connect(devices[1])
        await sender.send_json({"type": "miss", "id": event_id})
        self.assertEqual((await sender.receive_json())["type"], "accepted")
        self.assertEqual(await sender.receive_json(), {"type": "delivered", "id": event_id})
        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(recipient.receive_json(), 0.05)
        await sender.close()
        await recipient.close()

    async def test_online_receipt_rate_limit_and_invalid_input(self):
        devices = await self.pair()
        sender, recipient = await self.connect(devices[0]), await self.connect(devices[1])
        event_id = str(uuid.uuid4())
        await sender.send_json({"type": "miss", "id": event_id})
        self.assertEqual((await sender.receive_json())["state"], "online")
        self.assertEqual((await recipient.receive_json())["id"], event_id)
        await recipient.send_json({"type": "ack", "id": event_id})
        self.assertEqual((await sender.receive_json())["type"], "delivered")
        await sender.send_json({"type": "miss", "id": str(uuid.uuid4())})
        self.assertEqual((await sender.receive_json())["code"], "rate_limited")
        await sender.send_json({"type": "miss", "id": []})
        self.assertEqual((await sender.receive_json())["code"], "invalid_message")
        await sender.close()
        await recipient.close()

    async def test_unacknowledged_event_replayed_after_disconnect(self):
        devices = await self.pair()
        sender, recipient = await self.connect(devices[0]), await self.connect(devices[1])
        event_id = str(uuid.uuid4())
        await sender.send_json({"type": "miss", "id": event_id})
        await sender.receive_json()
        await recipient.receive_json()
        await recipient.close()
        recipient = await self.connect(devices[1])
        self.assertEqual((await recipient.receive_json())["id"], event_id)
        await sender.close()
        await recipient.close()

    async def test_anger_uses_fixed_text_and_authenticated_identity(self):
        devices = await self.pair()
        sender, recipient = await self.connect(devices[0]), await self.connect(devices[1])
        event_id = str(uuid.uuid4())
        await sender.send_json({
            "type": "anger", "id": event_id, "text": "forged text",
            "sender": devices[1]["device_id"], "recipient": devices[0]["device_id"],
            "member": "someone else", "sent_at": 0,
        })
        accepted = await sender.receive_json()
        self.assertEqual(accepted["type"], "accepted")
        self.assertEqual(accepted["state"], "online")
        self.assertGreater(accepted["sent_at"], 0)
        self.assertEqual(await recipient.receive_json(), {
            "type": "anger", "id": event_id, "text": "我生气了", "sent_at": accepted["sent_at"],
        })
        await recipient.send_json({"type": "ack", "id": event_id})
        self.assertEqual(await sender.receive_json(), {"type": "delivered", "id": event_id})
        await sender.close()
        await recipient.close()

    async def test_status_is_scoped_to_own_outgoing_events(self):
        devices, other_pair = await self.pair(), await self.pair()
        sender = await self.connect(devices[0])
        recipient = await self.connect(devices[1])
        unrelated = await self.connect(other_pair[0])
        event_id = str(uuid.uuid4())
        await sender.send_json({"type": "status", "id": event_id})
        self.assertEqual(await sender.receive_json(), {"type": "status", "id": event_id, "state": "unknown"})
        await sender.send_json({"type": "anger", "id": event_id})
        accepted = await sender.receive_json()
        await recipient.receive_json()
        await sender.send_json({"type": "status", "id": event_id})
        self.assertEqual(await sender.receive_json(), {
            "type": "status", "id": event_id, "state": "queued",
            "sent_at": accepted["sent_at"], "kind": "anger",
        })
        for socket in (recipient, unrelated):
            await socket.send_json({"type": "status", "id": event_id, "sender": devices[0]["device_id"]})
            self.assertEqual(await socket.receive_json(), {"type": "status", "id": event_id, "state": "unknown"})
        await recipient.send_json({"type": "ack", "id": event_id})
        self.assertEqual(await sender.receive_json(), {"type": "delivered", "id": event_id})
        await sender.send_json({"type": "status", "id": event_id})
        self.assertEqual(await sender.receive_json(), {
            "type": "status", "id": event_id, "state": "delivered",
            "sent_at": accepted["sent_at"], "kind": "anger",
        })
        await sender.close()
        await recipient.close()
        await unrelated.close()

    async def test_reusing_id_with_different_kind_is_conflict(self):
        devices = await self.pair()
        sender, recipient = await self.connect(devices[0]), await self.connect(devices[1])
        event_id = str(uuid.uuid4())
        await sender.send_json({"type": "anger", "id": event_id})
        accepted = await sender.receive_json()
        self.assertEqual((await recipient.receive_json())["type"], "anger")
        await sender.send_json({"type": "miss", "id": event_id})
        self.assertEqual(await sender.receive_json(), {"type": "error", "id": event_id, "code": "id_conflict"})
        await sender.send_json({"type": "anger", "id": event_id})
        self.assertEqual(await sender.receive_json(), accepted)
        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(recipient.receive_json(), 0.05)
        await sender.close()
        await recipient.close()


class StoreTests(unittest.TestCase):
    def test_restart_persists_pair_and_queue(self):
        with tempfile.TemporaryDirectory() as directory:
            path = directory + "/pair.sqlite3"
            store = Store(path)
            devices = store.create_pair()["devices"]
            sender = store.authenticate(devices[0]["token"])
            recipient = store.peer(sender)
            event_id = str(uuid.uuid4())
            store.accept(sender["id"], recipient, event_id)
            store.db.close()
            store = Store(path)
            self.assertEqual(store.authenticate(devices[0]["token"])["id"], sender["id"])
            self.assertEqual(store.queued(recipient)[0]["id"], event_id)
            store.db.close()

    def test_expired_events_not_delivered(self):
        store = Store(":memory:")
        devices = store.create_pair()["devices"]
        sender = store.authenticate(devices[0]["token"])
        recipient = store.peer(sender)
        store.accept(sender["id"], recipient, str(uuid.uuid4()))
        store.db.execute("UPDATE events SET sent_at=0")
        self.assertEqual(store.queued(recipient), [])
        store.db.close()

    def test_queued_kind_and_delivered_status_survive_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path = directory + "/pair.sqlite3"
            store = Store(path)
            devices = store.create_pair()["devices"]
            sender = store.authenticate(devices[0]["token"])["id"]
            recipient = devices[1]["device_id"]
            miss_id, anger_id = str(uuid.uuid4()), str(uuid.uuid4())
            now = time.time()
            with patch("server.time.time", return_value=now):
                store.accept(sender, recipient, miss_id)
            with patch("server.time.time", return_value=now + 3):
                store.accept(sender, recipient, anger_id, kind="anger")
            store.db.close()
            store = Store(path)
            self.assertEqual([event_message(row)["type"] for row in store.queued(recipient)], ["miss", "anger"])
            self.assertEqual([event_message(row)["text"] for row in store.queued(recipient)], ["我想你了", "我生气了"])
            self.assertEqual(store.status(sender, anger_id)["kind"], "anger")
            self.assertIsNone(store.status(recipient, anger_id))
            store.acknowledge(recipient, anger_id)
            store.db.close()
            store = Store(path)
            self.assertEqual(store.status(sender, anger_id)["acknowledged"], 1)
            self.assertEqual(store.status(sender, anger_id)["kind"], "anger")
            self.assertEqual([row["id"] for row in store.queued(recipient)], [miss_id])
            store.db.close()

    def test_v1_schema_migration_preserves_pairs_and_events(self):
        with tempfile.TemporaryDirectory() as directory:
            path = directory + "/v1.sqlite3"
            db = sqlite3.connect(path)
            db.executescript("""
                CREATE TABLE devices(id TEXT PRIMARY KEY, pair_id TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL);
                CREATE TABLE events(id TEXT NOT NULL, sender TEXT NOT NULL, recipient TEXT NOT NULL,
                    sent_at REAL NOT NULL, acknowledged INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(sender,id));
            """)
            sender, recipient, pair_id = (str(uuid.uuid4()) for _ in range(3))
            token, other_token = "a" * 48, "b" * 48
            db.executemany("INSERT INTO devices VALUES(?,?,?)", [
                (sender, pair_id, hashlib.sha256(token.encode()).hexdigest()),
                (recipient, pair_id, hashlib.sha256(other_token.encode()).hexdigest()),
            ])
            pending, delivered = str(uuid.uuid4()), str(uuid.uuid4())
            now = time.time()
            db.executemany("INSERT INTO events VALUES(?,?,?,?,?)", [
                (pending, sender, recipient, now - 4, 0),
                (delivered, sender, recipient, now - 1, 1),
            ])
            db.commit()
            db.close()
            for _ in range(2):  # Opening a migrated database again is harmless.
                store = Store(path)
                device = store.authenticate(token)
                self.assertEqual(device["id"], sender)
                self.assertEqual(device["pair_id"], pair_id)
                self.assertEqual(store.peer(device), recipient)
                self.assertEqual([(row["id"], row["kind"]) for row in store.queued(recipient)], [(pending, "miss")])
                self.assertEqual(store.status(sender, delivered)["acknowledged"], 1)
                self.assertEqual(store.status(sender, delivered)["kind"], "miss")
                self.assertEqual([row["name"] for row in store.db.execute("PRAGMA table_info(events)")].count("kind"), 1)
                self.assertEqual(store.db.execute("SELECT COUNT(*) FROM events").fetchone()[0], 2)
                store.db.close()

    def test_acknowledgement_matches_actual_paired_sender(self):
        store = Store(":memory:")
        devices, unrelated = store.create_pair()["devices"], store.create_pair()["devices"]
        sender, recipient = (device["device_id"] for device in devices)
        wrong_sender = unrelated[0]["device_id"]
        event_id = str(uuid.uuid4())
        store.accept(sender, recipient, event_id, kind="anger")
        # A same-ID unrelated row must not be acknowledged by a recipient in another pair.
        with store.db:
            store.db.execute("INSERT INTO events(id,sender,recipient,sent_at,kind) VALUES(?,?,?,?,?)", (
                event_id, wrong_sender, recipient, time.time(), "miss",
            ))
        self.assertIsNone(store.acknowledge(sender, event_id))
        self.assertIsNone(store.acknowledge(unrelated[1]["device_id"], event_id))
        self.assertEqual(store.acknowledge(recipient, event_id)["sender"], sender)
        rows = {row["sender"]: row["acknowledged"] for row in store.db.execute("SELECT * FROM events WHERE id=?", (event_id,))}
        self.assertEqual(rows, {sender: 1, wrong_sender: 0})
        store.db.close()

    def test_expired_status_and_ack_are_unknown_with_exact_ttl_boundary(self):
        store = Store(":memory:")
        devices = store.create_pair()["devices"]
        sender, recipient = (device["device_id"] for device in devices)
        event_id = str(uuid.uuid4())
        with patch("server.time.time", return_value=1000):
            store.accept(sender, recipient, event_id, kind="anger")
        with patch("server.time.time", return_value=1000 + 86400):
            self.assertEqual(store.status(sender, event_id)["kind"], "anger")
            self.assertEqual(len(store.queued(recipient)), 1)
        with patch("server.time.time", return_value=1001 + 86400):
            self.assertIsNone(store.acknowledge(recipient, event_id))
            self.assertIsNone(store.status(sender, event_id))
            self.assertEqual(store.queued(recipient), [])
            self.assertEqual(store.db.execute("SELECT COUNT(*) FROM events").fetchone()[0], 0)
        store.db.close()


if __name__ == "__main__":
    unittest.main()
