import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { QueueStore, ProtocolError, TTL_SECONDS, MAX_PENDING, memberForAuthorization, migrationAdminAuthorized, migrationAdminConfigured, parseClientMessage, missEvent, acceptedEvent } from "../src/protocol.mjs";

const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
function storage() {
  const db = new DatabaseSync(":memory:");
  return {
    db,
    sql: { exec(query, ...bindings) {
      const statement = db.prepare(query);
      if (statement.columns().length) {
        const rows = statement.all(...bindings);
        return { toArray: () => rows };
      }
      statement.run(...bindings);
      return { toArray: () => [] };
    } },
    transactionSync(callback) {
      db.exec("BEGIN");
      try { const result = callback(); db.exec("COMMIT"); return result; }
      catch (error) { db.exec("ROLLBACK"); throw error; }
    }
  };
}
function hasCode(code) { return error => error instanceof ProtocolError && error.code === code; }

test("two distinct secrets are required and exact Bearer authentication selects one member", () => {
  const a = "a".repeat(64), b = "b".repeat(64);
  assert.equal(memberForAuthorization(`Bearer ${a}`, a, b), "A");
  assert.equal(memberForAuthorization(`Bearer ${b}`, a, b), "B");
  for (const value of [null, a, `bearer ${a}`, `Bearer ${a} `, "Bearer incorrect"])
    assert.equal(memberForAuthorization(value, a, b), null);
  assert.throws(() => memberForAuthorization(`Bearer ${a}`, a, a), /not_configured/);
  assert.throws(() => memberForAuthorization("Bearer short", "short", b), /not_configured/);
});

test("protocol accepts current client's binary JSON and preserves uppercase pending IDs", () => {
  const uuid = "ABCDEF12-1234-4000-8000-123456789012";
  const binary = new TextEncoder().encode(JSON.stringify({ type: "miss", id: uuid, member: "B", text: "injected", sent_at: 0 }));
  assert.deepEqual(parseClientMessage(binary), { type: "miss", id: uuid });
  assert.deepEqual(parseClientMessage(JSON.stringify({ type: "ack", id: uuid })), { type: "ack", id: uuid });
  for (const value of ["[]", "null", '{"type":"miss","id":[]}', "bad", new Uint8Array([255])])
    assert.throws(() => parseClientMessage(value), hasCode("invalid_message"));
  assert.throws(() => parseClientMessage("x".repeat(16385)), hasCode("message_too_large"));
  assert.throws(() => parseClientMessage(JSON.stringify({ type: "send_chat", id: uuid })), hasCode("invalid_type"));
});

test("offline queue survives room reconstruction, receipts clear it, and duplicate IDs do not replay", () => {
  const state = storage(); let queue = new QueueStore(state);
  const result = queue.accept("A", id(1), 1000);
  assert.equal(result.isNew, true);
  assert.deepEqual(acceptedEvent(result.row, false), { type: "accepted", id: id(1), state: "queued", sent_at: 1000 });
  queue = new QueueStore(state); // Simulates hibernation resetting all JS fields.
  assert.deepEqual(missEvent(queue.queued("B", 1001)[0]), { type: "miss", id: id(1), text: "我想你了", sent_at: 1000 });
  assert.equal(queue.acknowledge("B", id(1), 1001).sender, "A");
  assert.equal(queue.queued("B", 1001).length, 0);
  assert.equal(queue.accept("A", id(1), 1001).isNew, false);
  assert.equal(queue.queued("B", 1001).length, 0);
  state.db.close();
});

test("rate limit applies to new IDs with the 3 second boundary and transaction rollback", () => {
  const state = storage(), queue = new QueueStore(state);
  queue.accept("A", id(1), 1000);
  assert.equal(queue.accept("A", id(1), 1001).isNew, false);
  assert.throws(() => queue.accept("A", id(2), 1002.999), hasCode("rate_limited"));
  assert.equal(queue.accept("A", id(3), 1003).isNew, true);
  assert.equal(queue.queued("B", 1003).length, 2);
  state.db.close();
});

test("sender cannot acknowledge its own outgoing event or claim another member", () => {
  const state = storage(), queue = new QueueStore(state);
  queue.accept("A", id(1), 1000);
  assert.equal(queue.acknowledge("A", id(1), 1001), null);
  assert.equal(queue.queued("B", 1001).length, 1);
  assert.throws(() => queue.accept("C", id(2), 1003), hasCode("unauthorized"));
  state.db.close();
});

test("24 hour expiry excludes and lazily deletes stale events", () => {
  const state = storage(), queue = new QueueStore(state);
  queue.accept("A", id(1), 1000);
  assert.equal(queue.queued("B", 1000 + TTL_SECONDS).length, 1);
  assert.equal(queue.queued("B", 1001 + TTL_SECONDS).length, 0);
  assert.equal(state.sql.exec("SELECT COUNT(*) AS count FROM events").toArray()[0].count, 0);
  state.db.close();
});

test("pending queue is capped and a receipt releases capacity", () => {
  const state = storage(), queue = new QueueStore(state);
  for (let index = 0; index < MAX_PENDING; index++) queue.accept("A", id(index), 1000 + index * 3);
  assert.throws(() => queue.accept("A", id(101), 1400), hasCode("queue_full"));
  queue.acknowledge("B", id(0), 1400);
  queue.accept("A", id(101), 1400);
  assert.equal(queue.queued("B", 1400).length, MAX_PENDING);
  state.db.close();
});

test("mixed emotions remain distinct through offline replay and outgoing receipt recovery", () => {
  const state=storage(), queue=new QueueStore(state);
  queue.accept("A",id(1),1000,"miss");queue.accept("A",id(2),1003,"anger");
  assert.deepEqual(queue.queued("B",1004).map(missEvent),[
    {type:"miss",id:id(1),text:"我想你了",sent_at:1000},
    {type:"anger",id:id(2),text:"我生气了！",sent_at:1003}]);
  assert.equal(queue.outgoing("A",id(2),1004).acknowledged,0);
  assert.equal(queue.outgoing("B",id(2),1004),null);
  queue.acknowledge("B",id(2),1004);
  const restored=new QueueStore(state);
  assert.equal(restored.outgoing("A",id(2),1005).acknowledged,1);
  assert.equal(restored.outgoing("A",id(2),1005).kind,"anger");
  assert.throws(()=>restored.accept("A",id(2),1006,"miss"),hasCode("id_conflict"));
  assert.deepEqual(parseClientMessage(JSON.stringify({type:"status",id:id(2)})),{type:"status",id:id(2)});
  assert.deepEqual(parseClientMessage(JSON.stringify({type:"anger",id:id(2),text:"forged"})),{type:"anger",id:id(2)});
  state.db.close();
});

test("upgrading an existing database preserves queued misses and acknowledgements", () => {
  const state=storage();state.db.exec(`CREATE TABLE events(id TEXT NOT NULL,sender TEXT NOT NULL,recipient TEXT NOT NULL,sent_at REAL NOT NULL,acknowledged INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(sender,id))`);
  state.sql.exec("INSERT INTO events VALUES(?,?,?,?,?)",id(1),"A","B",1000,0);
  state.sql.exec("INSERT INTO events VALUES(?,?,?,?,?)",id(2),"A","B",1003,1);
  const queue=new QueueStore(state);
  assert.equal(queue.queued("B",1005)[0].kind,"miss");
  assert.equal(queue.outgoing("A",id(2),1005).acknowledged,1);
  new QueueStore(state); // Migration is idempotent.
  assert.equal(queue.queued("B",1005).length,1);state.db.close();
});

test("pet stays a distinct event and hidden receipt is real but not public",()=>{
  const state=storage(),queue=new QueueStore(state);
  queue.accept("B",id(30),1000,"pet");
  assert.equal(queue.queued("A",1001)[0].kind,"pet");
  assert.equal(missEvent(queue.queued("A",1001)[0]).type,"pet");
  queue.acknowledge("A",id(30),1001,false);
  assert.equal(queue.queued("A",1001).length,0);
  assert.equal(queue.outgoing("B",id(30),1001).acknowledged,0);
  assert.deepEqual(queue.publishReceipts("A").map(row=>row.id),[id(30)]);
  assert.equal(queue.outgoing("B",id(30),1001).acknowledged,1);
  assert.deepEqual(queue.publishReceipts("A"),[]);
  state.db.close();
});

test("public last online freezes during hidden heartbeat and survives room reconstruction",()=>{
  const state=storage();let queue=new QueueStore(state);
  queue.observe("A",1000,false);
  assert.deepEqual(queue.publicStatus("A",1001,true),{online:true,last_online:1000,version:1,server_time:1001});
  queue.observe("A",1020,true);
  assert.deepEqual(queue.publicStatus("A",1021,true),{online:false,last_online:1000,version:2,server_time:1021});
  queue=new QueueStore(state);
  assert.equal(queue.publicStatus("A",1100,false).last_online,1000);
  queue.observe("A",1101,false);
  assert.equal(queue.publicStatus("A",1101,true).last_online,1101);
  state.db.close();
});

test("migration administrator requires a separate secret and exact bearer authentication", () => {
  const a = "a".repeat(64), b = "b".repeat(64), admin = "c".repeat(64);
  assert.equal(migrationAdminConfigured(undefined, a, b), false);
  assert.equal(migrationAdminConfigured("short", a, b), false);
  assert.equal(migrationAdminConfigured(a, a, b), false);
  assert.equal(migrationAdminConfigured(admin, a, b), true);
  assert.equal(migrationAdminAuthorized(`Bearer ${admin}`, admin, a, b), true);
  for (const header of [null, `Bearer ${a}`, `Bearer ${b}`, `Bearer ${admin} `, `bearer ${admin}`])
    assert.equal(migrationAdminAuthorized(header, admin, a, b), false);
  assert.equal(migrationAdminAuthorized(`Bearer ${a}`, a, a, b), false);
});

test("migration freeze persists across room reconstruction and blocks writes until unfreeze", () => {
  const state = storage(); let queue = new QueueStore(state);
  queue.accept("A", id(1), 1000, "miss");
  queue.accept("B", id(2), 1003, "anger");
  queue.acknowledge("B", id(1), 1004);
  assert.throws(() => queue.exportSnapshot(1005), hasCode("migration_not_frozen"));
  queue.setFrozen(true);
  queue = new QueueStore(state);
  assert.equal(queue.isFrozen(), true);
  assert.throws(() => queue.accept("A", id(3), 1006), hasCode("service_unavailable"));
  assert.throws(() => queue.acknowledge("A", id(2), 1006), hasCode("service_unavailable"));
  const snapshot = queue.exportSnapshot(1007);
  assert.equal(snapshot.format, "petpair-migration-v1");
  assert.equal(snapshot.pair_key, "our-private-pair-v1");
  assert.equal(snapshot.exported_at, 1007);
  assert.deepEqual(snapshot.events, [
    { id: id(1), sender: "A", recipient: "B", sent_at: 1000, acknowledged: 1, kind: "miss" },
    { id: id(2), sender: "B", recipient: "A", sent_at: 1003, acknowledged: 0, kind: "anger" }
  ]);
  assert.equal(JSON.stringify(snapshot).includes("token"), false);
  queue.setFrozen(false);
  queue = new QueueStore(state);
  assert.equal(queue.isFrozen(), false);
  assert.equal(queue.acknowledge("A", id(2), 1008).id, id(2));
  state.db.close();
});

test("migration snapshot ignores expired rows without deleting or changing stored receipts", () => {
  const state = storage(), queue = new QueueStore(state);
  queue.accept("A", id(1), 1000, "anger");
  queue.setFrozen(true);
  const exported = queue.exportSnapshot(1001 + TTL_SECONDS);
  assert.deepEqual(exported.events, []);
  assert.equal(state.sql.exec("SELECT COUNT(*) AS count FROM events").toArray()[0].count, 1);
  state.db.close();
});
