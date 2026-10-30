// Run only against two local Wrangler processes with synthetic tokens.
// See BackendPages/README.md for the exact commands. Never use production tokens.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import WebSocket from "../../BackendCloudflare/node_modules/ws/wrapper.mjs";

const gateway = process.env.TEST_GATEWAY_URL || "ws://127.0.0.1:8898/v1/ws";
if (!/^ws:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/v1\/ws$/.test(gateway))
  throw new Error("Local integration test only accepts loopback gateway URLs");
const tokens = {
  A: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  B: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
};

function connect(member) {
  const socket = new WebSocket(gateway, { headers: { Authorization: `Bearer ${tokens[member]}` } });
  const buffered = [];
  const waiters = [];
  socket.on("message", data => {
    const message = JSON.parse(data.toString());
    const waiter = waiters.find(item => item.matches(message));
    if (waiter) {
      waiters.splice(waiters.indexOf(waiter), 1);
      clearTimeout(waiter.timer);
      waiter.resolve(message);
    } else buffered.push(message);
  });
  socket.on("error", error => {
    for (const waiter of waiters.splice(0)) {
      clearTimeout(waiter.timer);
      waiter.reject(error);
    }
  });
  const next = (matches, timeoutMs = 5000) => new Promise((resolve, reject) => {
    const index = buffered.findIndex(matches);
    if (index !== -1) { resolve(buffered.splice(index, 1)[0]); return; }
    const waiter = { matches, resolve, reject, timer: null };
    waiter.timer = setTimeout(() => {
      waiters.splice(waiters.indexOf(waiter), 1);
      reject(new Error(`Timed out waiting for ${member} message`));
    }, timeoutMs);
    waiters.push(waiter);
  });
  const opened = new Promise((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  });
  return { socket, next, opened };
}

async function run() {
  let a, b;
  try {
    b = connect("B");
    await b.opened;
    assert.equal((await b.next(m => m.type === "ready")).protocol, 3);
    a = connect("A");
    await a.opened;
    assert.equal((await a.next(m => m.type === "ready")).protocol, 3);

    const missId = randomUUID();
    a.socket.send(JSON.stringify({ type: "miss", id: missId }));
    assert.equal((await a.next(m => m.type === "accepted" && m.id === missId)).state, "online");
    assert.equal((await b.next(m => m.type === "miss" && m.id === missId)).text, "我想你了");
    b.socket.send(JSON.stringify({ type: "ack", id: missId }));
    assert.equal((await a.next(m => m.type === "delivered" && m.id === missId)).id, missId);
    a.socket.send(JSON.stringify({ type: "status", id: missId }));
    assert.equal((await a.next(m => m.type === "status" && m.id === missId)).state, "delivered");

    await new Promise(resolve => { b.socket.once("close", resolve); b.socket.close(); });
    await new Promise(resolve => setTimeout(resolve, 3200)); // Existing server limit: one event per 3 seconds.
    const angerId = randomUUID();
    a.socket.send(JSON.stringify({ type: "anger", id: angerId }));
    assert.equal((await a.next(m => m.type === "accepted" && m.id === angerId)).state, "queued");
    b = connect("B");
    await b.opened;
    assert.equal((await b.next(m => m.type === "ready")).protocol, 3);
    assert.equal((await b.next(m => m.type === "anger" && m.id === angerId)).text, "我生气了！");
    b.socket.send(JSON.stringify({ type: "ack", id: angerId }));
    assert.equal((await a.next(m => m.type === "delivered" && m.id === angerId)).id, angerId);
    process.stdout.write("PASS: local Pages binding; HTTP upgrade; ready; live miss/ack; status; offline anger queue/reconnect/ack.\n");
  } finally {
    a?.socket.terminate();
    b?.socket.terminate();
  }
}

await run();
