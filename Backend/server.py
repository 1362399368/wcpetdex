"""Two-person foreground pet events. Run behind an HTTPS/WSS reverse proxy."""
from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import sqlite3
import time
import uuid
from pathlib import Path

from aiohttp import WSMsgType, web
from config import Settings


def token_hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


class Store:
    def __init__(self, path: str):
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS devices(
          id TEXT PRIMARY KEY, pair_id TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL);
        CREATE TABLE IF NOT EXISTS events(
          id TEXT NOT NULL, sender TEXT NOT NULL, recipient TEXT NOT NULL,
          sent_at REAL NOT NULL, acknowledged INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(sender,id));
        CREATE INDEX IF NOT EXISTS events_recipient ON events(recipient,acknowledged,sent_at);
        """)
        # Additive migration: preserve existing pair tokens, queues and receipts.
        if "kind" not in {row["name"] for row in self.db.execute("PRAGMA table_info(events)")}:
            with self.db:
                self.db.execute("ALTER TABLE events ADD COLUMN kind TEXT NOT NULL DEFAULT 'miss'")
        self.db.executescript("""
        CREATE INDEX IF NOT EXISTS events_sender_time ON events(sender,sent_at);
        CREATE INDEX IF NOT EXISTS events_expiry ON events(sent_at);
        """)

    def create_pair(self):
        pair_id = str(uuid.uuid4())
        devices = []
        with self.db:
            for _ in range(2):
                device_id, token = str(uuid.uuid4()), secrets.token_urlsafe(32)
                self.db.execute("INSERT INTO devices VALUES(?,?,?)", (device_id, pair_id, token_hash(token)))
                devices.append({"device_id": device_id, "token": token})
        return {"pair_id": pair_id, "devices": devices}

    def authenticate(self, token):
        return self.db.execute("SELECT * FROM devices WHERE token_hash=?", (token_hash(token),)).fetchone()

    def peer(self, device):
        return self.db.execute("SELECT id FROM devices WHERE pair_id=? AND id!=?", (device["pair_id"], device["id"])).fetchone()["id"]

    def purge(self):
        self.db.execute("DELETE FROM events WHERE sent_at < ?", (time.time() - 86400,))

    def accept(self, sender, recipient, event_id, kind="miss"):
        if kind not in {"miss", "anger"}:
            raise ValueError("invalid_type")
        now = time.time()
        with self.db:
            self.purge()
            existing = self.db.execute("SELECT * FROM events WHERE sender=? AND id=?", (sender, event_id)).fetchone()
            if existing:
                if existing["kind"] != kind:
                    raise ValueError("id_conflict")
                return existing, False
            last = self.db.execute("SELECT MAX(sent_at) FROM events WHERE sender=?", (sender,)).fetchone()[0]
            if last is not None and now - last < 3:
                raise ValueError("rate_limited")
            count = self.db.execute("SELECT count(*) FROM events WHERE recipient=? AND acknowledged=0", (recipient,)).fetchone()[0]
            if count >= 100:
                raise ValueError("queue_full")
            self.db.execute("INSERT INTO events(id,sender,recipient,sent_at,kind) VALUES(?,?,?,?,?)", (event_id, sender, recipient, now, kind))
            return self.db.execute("SELECT * FROM events WHERE sender=? AND id=?", (sender, event_id)).fetchone(), True

    def queued(self, recipient):
        with self.db:
            self.purge()
            return self.db.execute("SELECT * FROM events WHERE recipient=? AND acknowledged=0 AND sent_at>=? ORDER BY sent_at", (recipient, time.time() - 86400)).fetchall()

    def acknowledge(self, recipient, event_id):
        with self.db:
            self.purge()
            # A receipt can only acknowledge an event from this device's peer.
            row = self.db.execute("""SELECT * FROM events WHERE recipient=? AND id=? AND sender=(
              SELECT id FROM devices WHERE pair_id=(SELECT pair_id FROM devices WHERE id=?) AND id!=? LIMIT 1)
              """, (recipient, event_id, recipient, recipient)).fetchone()
            if row:
                self.db.execute("UPDATE events SET acknowledged=1 WHERE sender=? AND id=?", (row["sender"], event_id))
            return row

    def status(self, sender, event_id):
        with self.db:
            self.purge()
            return self.db.execute("SELECT * FROM events WHERE sender=? AND id=?", (sender, event_id)).fetchone()


def bearer(request):
    value = request.headers.get("Authorization", "")
    return value[7:] if value.startswith("Bearer ") else ""


def event_message(row):
    kind = "anger" if row["kind"] == "anger" else "miss"
    return {"type": kind, "id": row["id"], "text": "我生气了" if kind == "anger" else "我想你了", "sent_at": row["sent_at"]}


STORE = web.AppKey("store", Store)
CONNECTIONS = web.AppKey("connections", dict)


def create_app(admin_token: str, db_path: str = ":memory:"):
    if len(admin_token) < 32:
        raise ValueError("PETPAIR_ADMIN_TOKEN must contain at least 32 characters")
    app = web.Application(client_max_size=16384)
    app[STORE] = Store(db_path)
    app[CONNECTIONS] = {}

    async def health(request):
        app[STORE].db.execute("SELECT 1").fetchone()
        return web.json_response({"ok": True})

    async def create_pair(request):
        if not secrets.compare_digest(bearer(request), admin_token):
            raise web.HTTPUnauthorized()
        return web.json_response(app[STORE].create_pair(), status=201, headers={"Cache-Control": "no-store"})

    async def websocket(request):
        store, connections = app[STORE], app[CONNECTIONS]
        device = store.authenticate(bearer(request))
        if device is None:
            raise web.HTTPUnauthorized()
        ws = web.WebSocketResponse(heartbeat=30, max_msg_size=16384)
        await ws.prepare(request)
        device_id = device["id"]
        old = connections.get(device_id)
        connections[device_id] = ws
        if old is not None and not old.closed:
            await old.close(code=4001, message=b"Replaced by a new connection")
        await ws.send_json({"type": "ready", "protocol": 2})
        for event in store.queued(device_id):
            await ws.send_json(event_message(event))
        try:
            async for message in ws:
                if message.type not in (WSMsgType.TEXT, WSMsgType.BINARY):
                    continue
                event_id = ""
                try:
                    payload = json.loads(message.data)
                    if not isinstance(payload, dict):
                        raise ValueError("invalid_message")
                    event_id = payload.get("id", "")
                    if not isinstance(event_id, str) or re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", event_id, re.IGNORECASE) is None:
                        raise ValueError("invalid_id")
                    kind = payload.get("type")
                    if kind in ("miss", "anger"):
                        recipient = store.peer(device)
                        row, is_new = store.accept(device_id, recipient, event_id, kind)
                        peer_ws = connections.get(recipient)
                        online = peer_ws is not None and not peer_ws.closed
                        await ws.send_json({"type": "accepted", "id": event_id, "state": "online" if online else "queued", "sent_at": row["sent_at"]})
                        if row["acknowledged"]:
                            await ws.send_json({"type": "delivered", "id": event_id})
                        if is_new and online:
                            try:
                                await peer_ws.send_json(event_message(row))
                            except (ConnectionError, RuntimeError):
                                pass  # Durable queue delivers again on reconnect until acknowledged.
                    elif kind == "status":
                        row = store.status(device_id, event_id)
                        reply = {"type": "status", "id": event_id, "state": "delivered" if row and row["acknowledged"] else ("queued" if row else "unknown")}
                        if row:
                            reply.update(sent_at=row["sent_at"], kind=row["kind"])
                        await ws.send_json(reply)
                    elif kind == "ack":
                        row = store.acknowledge(device_id, event_id)
                        if row:
                            sender_ws = connections.get(row["sender"])
                            if sender_ws is not None and not sender_ws.closed:
                                try:
                                    await sender_ws.send_json({"type": "delivered", "id": event_id})
                                except (ConnectionError, RuntimeError):
                                    pass
                    else:
                        raise ValueError("invalid_type")
                except (ValueError, TypeError, UnicodeError, json.JSONDecodeError) as error:
                    code = str(error) if str(error) in {"rate_limited", "queue_full", "invalid_type", "id_conflict"} else "invalid_message"
                    await ws.send_json({"type": "error", "id": event_id if isinstance(event_id, str) and len(event_id) <= 64 else "", "code": code})
        finally:
            if connections.get(device_id) is ws:
                connections.pop(device_id, None)
        return ws

    async def shutdown(application):
        for ws in list(application[CONNECTIONS].values()):
            await ws.close(code=1001, message=b"Server shutdown")

    async def cleanup(application):
        application[STORE].db.close()

    app.router.add_get("/health", health)
    app.router.add_post("/v1/pairs", create_pair)
    app.router.add_get("/v1/ws", websocket)
    app.on_shutdown.append(shutdown)
    app.on_cleanup.append(cleanup)
    return app


if __name__ == "__main__":
    settings = Settings.from_environment(os.environ)
    app = create_app(settings.admin_token, settings.db_path)
    web.run_app(app, host=settings.host, port=settings.port, access_log=None)
