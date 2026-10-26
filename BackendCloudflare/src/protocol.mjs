export const TTL_SECONDS = 86400;
export const PRESENCE_RETENTION_SECONDS = 3 * 86400;
export const MIN_INTERVAL_SECONDS = 3;
export const MAX_PENDING = 100;
export const MAX_FRAME_BYTES = 16384;

export class ProtocolError extends Error {
  constructor(code) { super(code); this.code = code; }
}

function equalSecret(a, b) {
  const aa = new TextEncoder().encode(a), bb = new TextEncoder().encode(b);
  let difference = aa.length ^ bb.length;
  for (let i = 0; i < Math.max(aa.length, bb.length); i++) difference |= (aa[i] ?? 0) ^ (bb[i] ?? 0);
  return difference === 0;
}

export function migrationAdminAuthorized(authorization, adminToken, deviceAToken, deviceBToken) {
  if (typeof adminToken !== "string" || adminToken.length < 32 ||
      adminToken === deviceAToken || adminToken === deviceBToken) return false;
  if (typeof authorization !== "string" || !authorization.startsWith("Bearer ") || authorization.length > 1024) return false;
  return equalSecret(authorization.slice(7), adminToken);
}

export function migrationAdminConfigured(adminToken, deviceAToken, deviceBToken) {
  return typeof adminToken === "string" && adminToken.length >= 32 &&
    adminToken !== deviceAToken && adminToken !== deviceBToken;
}

export function memberForAuthorization(authorization, deviceAToken, deviceBToken) {
  if (typeof deviceAToken !== "string" || typeof deviceBToken !== "string" ||
      deviceAToken.length < 32 || deviceBToken.length < 32 || deviceAToken === deviceBToken)
    throw new Error("device_tokens_not_configured");
  if (typeof authorization !== "string" || !authorization.startsWith("Bearer ") || authorization.length > 1024) return null;
  const token = authorization.slice(7);
  const isA = equalSecret(token, deviceAToken), isB = equalSecret(token, deviceBToken);
  return isA ? "A" : isB ? "B" : null;
}

export function peerOf(member) {
  if (member === "A") return "B";
  if (member === "B") return "A";
  throw new ProtocolError("unauthorized");
}

export function parseClientMessage(message) {
  let text;
  try {
    if (typeof message === "string") {
      if (new TextEncoder().encode(message).byteLength > MAX_FRAME_BYTES) throw new ProtocolError("message_too_large");
      text = message;
    } else if (message instanceof ArrayBuffer || ArrayBuffer.isView(message)) {
      if (message.byteLength > MAX_FRAME_BYTES) throw new ProtocolError("message_too_large");
      text = new TextDecoder("utf-8", { fatal: true }).decode(message);
    } else throw new ProtocolError("invalid_message");
    const event = JSON.parse(text);
    if (!event || typeof event !== "object" || Array.isArray(event) || typeof event.id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(event.id))
      throw new ProtocolError("invalid_message");
    if (!["miss", "anger", "pet", "ack", "status", "heartbeat", "peer_status"].includes(event.type)) throw new ProtocolError("invalid_type");
    // Caller-controlled member, text and timestamp fields are deliberately ignored.
    return { type: event.type, id: event.id };
  } catch (error) {
    if (error instanceof ProtocolError) throw error;
    throw new ProtocolError("invalid_message");
  }
}

export function missEvent(row) {
  const kind = ["anger", "pet"].includes(row.kind) ? row.kind : "miss";
  return { type: kind, id: row.id, text: kind === "anger" ? "我生气了！" : kind === "pet" ? "摸摸头" : "我想你了", sent_at: row.sent_at };
}
export function acceptedEvent(row, online) {
  return { type: "accepted", id: row.id, state: online ? "online" : "queued", sent_at: row.sent_at };
}

/// Uses the same SQL operations on Cloudflare and on Node's real SQLite tests.
export class QueueStore {
  constructor(storage) {
    this.storage = storage;
    this.sql = storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS events (
      id TEXT NOT NULL, sender TEXT NOT NULL CHECK(sender IN ('A','B')),
      recipient TEXT NOT NULL CHECK(recipient IN ('A','B')),
      sent_at REAL NOT NULL, acknowledged INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(sender,id), CHECK(sender != recipient))`);
    const columns = this.sql.exec("PRAGMA table_info(events)").toArray();
    if (!columns.some(column => column.name === "kind"))
      this.sql.exec("ALTER TABLE events ADD COLUMN kind TEXT NOT NULL DEFAULT 'miss'");
    if (!columns.some(column => column.name === "actual_received"))
      this.sql.exec("ALTER TABLE events ADD COLUMN actual_received INTEGER NOT NULL DEFAULT 0");
    this.sql.exec("UPDATE events SET actual_received=1 WHERE acknowledged=1 AND actual_received=0");
    this.sql.exec("CREATE INDEX IF NOT EXISTS events_pending ON events(recipient,acknowledged,sent_at)");
    this.sql.exec("CREATE INDEX IF NOT EXISTS events_sender_time ON events(sender,sent_at)");
    this.sql.exec("CREATE INDEX IF NOT EXISTS events_expiry ON events(sent_at)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS migration_state (id INTEGER PRIMARY KEY CHECK(id=1), frozen INTEGER NOT NULL DEFAULT 0 CHECK(frozen IN (0,1)))");
    this.sql.exec("INSERT OR IGNORE INTO migration_state(id,frozen) VALUES(1,0)");
    this.sql.exec(`CREATE TABLE IF NOT EXISTS member_state (
      member TEXT PRIMARY KEY CHECK(member IN ('A','B')),
      hidden INTEGER NOT NULL DEFAULT 0, last_real_online REAL,
      last_public_online REAL, version INTEGER NOT NULL DEFAULT 0)`);
    this.sql.exec("INSERT OR IGNORE INTO member_state(member) VALUES('A'),('B')");
  }
  isFrozen() {
    return this.sql.exec("SELECT frozen FROM migration_state WHERE id=1").toArray()[0]?.frozen === 1;
  }
  setFrozen(frozen) {
    this.sql.exec("UPDATE migration_state SET frozen=? WHERE id=1", frozen ? 1 : 0);
  }
  exportSnapshot(now) {
    if (!this.isFrozen()) throw new ProtocolError("migration_not_frozen");
    const rows = this.sql.exec(
      "SELECT id,sender,recipient,sent_at,acknowledged,kind FROM events WHERE sent_at>=? ORDER BY sent_at,sender,id",
      now - TTL_SECONDS).toArray();
    return {
      format: "petpair-migration-v1",
      pair_key: "our-private-pair-v1",
      exported_at: now,
      events: rows.map(row => ({
        id: row.id, sender: row.sender, recipient: row.recipient,
        sent_at: row.sent_at, acknowledged: row.acknowledged ? 1 : 0,
        kind: ["anger", "pet"].includes(row.kind) ? row.kind : "miss"
      }))
    };
  }
  purge(now) {
    this.sql.exec("DELETE FROM events WHERE sent_at < ?", now - TTL_SECONDS);
    const cutoff=now-PRESENCE_RETENTION_SECONDS;
    this.sql.exec(`UPDATE member_state SET
      last_real_online=CASE WHEN last_real_online<=? THEN NULL ELSE last_real_online END,
      last_public_online=CASE WHEN last_public_online<=? THEN NULL ELSE last_public_online END,
      version=version+1 WHERE last_real_online<=? OR last_public_online<=?`,cutoff,cutoff,cutoff,cutoff);
  }
  nextRetentionDeadline(now) {
    const event=this.sql.exec("SELECT MIN(sent_at) AS stamp FROM events").toArray()[0]?.stamp;
    const presence=this.sql.exec(`SELECT MIN(stamp) AS stamp FROM (
      SELECT last_real_online AS stamp FROM member_state UNION ALL
      SELECT last_public_online AS stamp FROM member_state)`).toArray()[0]?.stamp;
    const deadlines=[];
    if(Number.isFinite(event))deadlines.push(event+TTL_SECONDS+.001);
    if(Number.isFinite(presence))deadlines.push(presence+PRESENCE_RETENTION_SECONDS+.001);
    return deadlines.length?Math.max(now+.001,Math.min(...deadlines)):null;
  }
  accept(sender, id, now, kind = "miss") {
    if (this.isFrozen()) throw new ProtocolError("service_unavailable");
    if (!["miss", "anger", "pet"].includes(kind)) throw new ProtocolError("invalid_type");
    const recipient = peerOf(sender);
    return this.storage.transactionSync(() => {
      this.purge(now);
      const existing = this.sql.exec("SELECT * FROM events WHERE sender=? AND id=?", sender, id).toArray()[0];
      if (existing) {
        if (existing.kind !== kind) throw new ProtocolError("id_conflict");
        return { row: existing, isNew: false };
      }
      const last = this.sql.exec("SELECT MAX(sent_at) AS last FROM events WHERE sender=?", sender).toArray()[0].last;
      if (last !== null && now - last < MIN_INTERVAL_SECONDS) throw new ProtocolError("rate_limited");
      const count = this.sql.exec("SELECT COUNT(*) AS count FROM events WHERE recipient=? AND actual_received=0", recipient).toArray()[0].count;
      if (count >= MAX_PENDING) throw new ProtocolError("queue_full");
      this.sql.exec("INSERT INTO events(id,sender,recipient,sent_at,kind) VALUES(?,?,?,?,?)", id, sender, recipient, now, kind);
      return { row: { id, sender, recipient, sent_at: now, acknowledged: 0, kind }, isNew: true };
    });
  }
  queued(recipient, now) {
    peerOf(recipient);
    this.purge(now);
    return this.sql.exec("SELECT * FROM events WHERE recipient=? AND actual_received=0 AND sent_at>=? ORDER BY sent_at", recipient, now - TTL_SECONDS).toArray();
  }
  acknowledge(recipient, id, now, publish = true) {
    if (this.isFrozen()) throw new ProtocolError("service_unavailable");
    const sender = peerOf(recipient);
    return this.storage.transactionSync(() => {
      this.purge(now);
      const row = this.sql.exec("SELECT * FROM events WHERE sender=? AND recipient=? AND id=?", sender, recipient, id).toArray()[0];
      if (row) this.sql.exec("UPDATE events SET actual_received=1, acknowledged=CASE WHEN ? THEN 1 ELSE acknowledged END WHERE sender=? AND id=?", publish ? 1 : 0, sender, id);
      return row ?? null;
    });
  }
  publishReceipts(recipient) {
    const rows=this.sql.exec("SELECT sender,id FROM events WHERE recipient=? AND actual_received=1 AND acknowledged=0",recipient).toArray();
    this.sql.exec("UPDATE events SET acknowledged=1 WHERE recipient=? AND actual_received=1",recipient);
    return rows;
  }
  memberState(member) { peerOf(member); return this.sql.exec("SELECT * FROM member_state WHERE member=?",member).toArray()[0]; }
  observe(member, now, hidden) {
    peerOf(member);
    this.sql.exec(`UPDATE member_state SET hidden=?, last_real_online=?,
      last_public_online=CASE WHEN ? THEN last_public_online ELSE ? END, version=version+1
      WHERE member=?`,hidden?1:0,now,hidden?1:0,now,member);
    return this.memberState(member);
  }
  bump(member) { this.sql.exec("UPDATE member_state SET version=version+1 WHERE member=?",member); }
  publicStatus(member, now, connected) {
    const state=this.memberState(member);
    return { online: !!connected && !state.hidden && Number.isFinite(state.last_real_online) && now-state.last_real_online<60,
      last_online: Number.isFinite(state.last_public_online)?state.last_public_online:null,
      version:state.version, server_time:now };
  }
  outgoing(sender, id, now) {
    peerOf(sender); this.purge(now);
    return this.sql.exec("SELECT * FROM events WHERE sender=? AND id=?", sender, id).toArray()[0] ?? null;
  }
}
