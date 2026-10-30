import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {DatabaseSync} from "node:sqlite";
import * as protocol from "../src/protocol.mjs";

function context(){
  const db=new DatabaseSync(":memory:");let alarm=null;
  const storage={sql:{exec(query,...bindings){const s=db.prepare(query);if(s.columns().length){const rows=s.all(...bindings);return {toArray:()=>rows};}s.run(...bindings);return {toArray:()=>[]};}},transactionSync(fn){db.exec("BEGIN");try{const r=fn();db.exec("COMMIT");return r;}catch(e){db.exec("ROLLBACK");throw e;}},async getAlarm(){return alarm;},async setAlarm(value){alarm=value;},async deleteAlarm(){alarm=null;},async sync(){}};
  return {storage,db,getWebSockets(){return [];}};
}
// Execute the shipped handler; only Cloudflare's base class/imports are supplied by the fixture.
let source=readFileSync(new URL("../src/worker.mjs",import.meta.url),"utf8");
source=source.replace(/^import .*;\n/gm,"").replace("export default {","const worker = {").replace("export class PetPairRoom","class PetPairRoom");
const names=Object.keys(protocol);
const {PetPairRoom,worker}=new Function("DurableObject",...names,source+";return {PetPairRoom,worker};")(class{constructor(ctx){this.ctx=ctx;}},...names.map(n=>protocol[n]));

test("actual room alarm removes expired records without connections and stops once empty",async()=>{
  const ctx=context(),room=new PetPairRoom(ctx,{}),now=Date.now()/1000;
  const id="00000000-0000-4000-8000-000000000001";
  room.queue.accept("A",id,now-86401);
  room.queue.observe("A",now-259201,false);
  await room.alarm();
  assert.equal(ctx.storage.sql.exec("SELECT COUNT(*) AS n FROM events").toArray()[0].n,0);
  assert.equal(room.queue.memberState("A").last_public_online,null);
  assert.equal(await ctx.storage.getAlarm(),null);ctx.db.close();
});
test("maintenance retains recent records and schedules the earliest deletion",async()=>{
  const ctx=context(),room=new PetPairRoom(ctx,{}),now=Date.now()/1000;
  const id="00000000-0000-4000-8000-000000000002";
  room.queue.accept("A",id,now);
  room.queue.observe("A",now,false);
  await room.maintainRetention(now);
  const deadline=await ctx.storage.getAlarm();
  assert.ok(Math.abs(deadline-(now+86400)*1000)<5);
  await room.maintainRetention(now+1);assert.equal(await ctx.storage.getAlarm(),deadline);
  assert.equal(room.queue.outgoing("A",id,now+1).id,id);ctx.db.close();
});
test("public worker does not expose the internal cleanup route",async()=>{
  const response=await worker.fetch(new Request("https://example.com/internal/retention",{method:"POST"}),{});
  assert.equal(response.status,404);
});
