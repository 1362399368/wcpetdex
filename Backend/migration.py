"""Offline, atomic import of existing Cloudflare pair identity and protocol-2 rows.

This module never contacts a live pair and never logs tokens or event contents.
"""
from __future__ import annotations

import json
import math
import re
import sqlite3
import uuid
from contextlib import closing
from pathlib import Path

from server import Store, token_hash


FORMAT = "petpair-migration-v1"
ROOM_KEY = "our-private-pair-v1"
TTL_SECONDS = 86400
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.IGNORECASE)


def read_tokens(path: Path):
    """Read just the existing device-token keys; do not generate replacement tokens."""
    values = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(values, dict):
        raise ValueError("token file must be an object")
    tokens = {member: values.get(f"DEVICE_{member}_TOKEN") for member in ("A", "B")}
    if any(not isinstance(value, str) or not 32 <= len(value) <= 1017 or any(ord(char) < 33 or ord(char) > 126 for char in value)
           for value in tokens.values()) or tokens["A"] == tokens["B"]:
        raise ValueError("token file requires two distinct DEVICE_A_TOKEN / DEVICE_B_TOKEN strings, 32–1017 characters")
    return tokens


def validate_snapshot(snapshot, pair_key: str, now: float):
    if not isinstance(snapshot, dict) or snapshot.get("format") != FORMAT or snapshot.get("pair_key") != pair_key:
        raise ValueError("snapshot format or pair_key does not match")
    exported = snapshot.get("exported_at")
    if isinstance(exported, bool) or not isinstance(exported, (int, float)) or not math.isfinite(exported) or not 0 < exported <= now + 60:
        raise ValueError("invalid exported_at; check both server clocks")
    events = snapshot.get("events")
    if not isinstance(events, list) or len(events) > 100000:
        raise ValueError("events must be an array with at most 100000 rows")
    validated, seen, expired = [], {}, 0
    for row in events:
        if not isinstance(row, dict):
            raise ValueError("invalid event row")
        event_id, sender, recipient = row.get("id"), row.get("sender"), row.get("recipient")
        sent_at, acknowledged, kind = row.get("sent_at"), row.get("acknowledged"), row.get("kind", "miss")
        if (not isinstance(event_id, str) or UUID.fullmatch(event_id) is None
                or sender not in ("A", "B") or recipient != ("B" if sender == "A" else "A")
                or isinstance(sent_at, bool) or not isinstance(sent_at, (int, float))
                or not math.isfinite(sent_at) or not 0 < sent_at <= exported + 60
                or type(acknowledged) is not int or acknowledged not in (0, 1)
                or kind not in ("miss", "anger")):
            raise ValueError("invalid event identity, timestamp, receipt or kind")
        normalized = dict(id=event_id, sender=sender, recipient=recipient, sent_at=float(sent_at), acknowledged=acknowledged, kind=kind)
        key = (sender, event_id)
        if key in seen:
            if seen[key] != normalized:
                raise ValueError("conflicting duplicate event in snapshot")
            continue
        seen[key] = normalized
        if sent_at < now - TTL_SECONDS:
            expired += 1
        else:
            validated.append(normalized)
    return validated, expired


def import_snapshot(store: Store, tokens, snapshot, *, pair_key=ROOM_KEY, now):
    """All identities and rows commit together; existing receipts never regress."""
    rows, expired = validate_snapshot(snapshot, pair_key, now)
    digests = {member: token_hash(tokens[member]) for member in ("A", "B")}
    if digests["A"] == digests["B"]:
        raise ValueError("device tokens must differ")
    result = dict(devices_created=0, events_created=0, receipts_upgraded=0, unchanged=0, expired_skipped=expired)
    with store.db:
        existing = {member: store.db.execute("SELECT * FROM devices WHERE token_hash=?", (digest,)).fetchone()
                    for member, digest in digests.items()}
        if any(existing.values()):
            if not all(existing.values()) or existing["A"]["pair_id"] != existing["B"]["pair_id"]:
                raise ValueError("existing token identity conflicts; no identities were changed")
            pair_id = existing["A"]["pair_id"]
            count = store.db.execute("SELECT COUNT(*) FROM devices WHERE pair_id=?", (pair_id,)).fetchone()[0]
            if count != 2:
                raise ValueError("existing pair must contain exactly two devices")
            device_ids = {member: existing[member]["id"] for member in ("A", "B")}
        else:
            pair_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "petpair:" + pair_key))
            device_ids = {member: str(uuid.uuid5(uuid.UUID(pair_id), member)) for member in ("A", "B")}
            if store.db.execute("SELECT 1 FROM devices WHERE pair_id=? OR id IN (?,?)", (pair_id, device_ids["A"], device_ids["B"])).fetchone():
                raise ValueError("pair identity exists with different tokens; existing data was preserved")
            for member in ("A", "B"):
                store.db.execute("INSERT INTO devices(id,pair_id,token_hash) VALUES(?,?,?)", (device_ids[member], pair_id, digests[member]))
            result["devices_created"] = 2
        for row in rows:
            sender, recipient = device_ids[row["sender"]], device_ids[row["recipient"]]
            old = store.db.execute("SELECT * FROM events WHERE sender=? AND id=?", (sender, row["id"])).fetchone()
            if old:
                if old["recipient"] != recipient or old["kind"] != row["kind"] or old["sent_at"] != row["sent_at"]:
                    raise ValueError("existing event conflicts; entire import rolled back")
                if old["acknowledged"] == 0 and row["acknowledged"] == 1:
                    store.db.execute("UPDATE events SET acknowledged=1 WHERE sender=? AND id=?", (sender, row["id"]))
                    result["receipts_upgraded"] += 1
                else:
                    result["unchanged"] += 1
            else:
                store.db.execute("INSERT INTO events(id,sender,recipient,sent_at,acknowledged,kind) VALUES(?,?,?,?,?,?)",
                                 (row["id"], sender, recipient, row["sent_at"], row["acknowledged"], row["kind"]))
                result["events_created"] += 1
        for device_id in device_ids.values():
            pending = store.db.execute("SELECT COUNT(*) FROM events WHERE recipient=? AND acknowledged=0 AND sent_at>=?", (device_id, now - TTL_SECONDS)).fetchone()[0]
            if pending > 100:
                raise ValueError("merged pending queue exceeds 100; entire import rolled back")
    return result


def backup_database(source: Path, destination: Path):
    """SQLite online backup includes WAL; copying only the .sqlite3 file can lose data."""
    if destination.exists():
        raise ValueError("backup destination already exists")
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True)) as src:
            with closing(sqlite3.connect(destination)) as dst:
                src.backup(dst)
        destination.chmod(0o600)
    except BaseException:
        destination.unlink(missing_ok=True)
        raise
