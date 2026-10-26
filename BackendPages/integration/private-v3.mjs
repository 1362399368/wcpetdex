// Only local Wrangler processes and synthetic tokens. Never point at production.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import WebSocket from "../../BackendCloudflare/node_modules/ws/wrapper.mjs";
const url=process.env.TEST_GATEWAY_URL||"ws://127.0.0.1:8898/v1/ws";
if(!/^ws:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/v1\/ws$/.test(url))throw new Error("loopback only");
const tokens={A:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",B:"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"};
function connect(member,hidden=false){
  const socket=new WebSocket(url,{headers:{Authorization:"Bearer "+tokens[member],"X-Pet-Protocol":"3",...(member==="A"?{"X-Pet-Hidden":hidden?"1":"0"}:{})}});
  const buffer=[],waiters=[];
  socket.on("message",data=>{const message=JSON.parse(data.toString()),i=waiters.findIndex(w=>w.match(message));
    if(i>=0){const w=waiters.splice(i,1)[0];clearTimeout(w.timer);w.resolve(message);}else buffer.push(message);});
  const next=(match,ms=5000)=>new Promise((resolve,reject)=>{
    const i=buffer.findIndex(match);if(i>=0){resolve(buffer.splice(i,1)[0]);return;}
    const w={match,resolve,reject,timer:null};w.timer=setTimeout(()=>{waiters.splice(waiters.indexOf(w),1);reject(new Error("timed out"));},ms);waiters.push(w);
  });
  const opened=new Promise((resolve,reject)=>{socket.once("open",resolve);socket.once("error",reject);});
  return {socket,next,opened};
}
let a,b;
try{
  a=connect("A",true);await a.opened;
  assert.equal((await a.next(m=>m.type==="ready")).hidden_applied,true);
  b=connect("B");await b.opened;
  assert.equal((await b.next(m=>m.type==="ready")).hidden_applied,false);
  a.socket.send(JSON.stringify({type:"peer_status",id:randomUUID()}));
  assert.equal((await a.next(m=>m.type==="peer_status"&&m.online===true)).online,true);
  const blocked=randomUUID();a.socket.send(JSON.stringify({type:"miss",id:blocked}));
  assert.equal((await a.next(m=>m.type==="error"&&m.id===blocked)).code,"stealth_send_blocked");
  const pet=randomUUID();b.socket.send(JSON.stringify({type:"pet",id:pet}));
  assert.equal((await b.next(m=>m.type==="accepted"&&m.id===pet)).state,"queued");
  assert.equal((await a.next(m=>m.type==="pet"&&m.id===pet)).text,"摸摸头");
  a.socket.send(JSON.stringify({type:"ack",id:pet}));
  await new Promise(resolve=>setTimeout(resolve,250));
  b.socket.send(JSON.stringify({type:"status",id:pet}));
  assert.equal((await b.next(m=>m.type==="status"&&m.id===pet)).state,"queued");
  await new Promise(resolve=>{a.socket.once("close",resolve);a.socket.close();});
  a=connect("A",false);await a.opened;
  assert.equal((await a.next(m=>m.type==="ready")).hidden_applied,false);
  assert.equal((await b.next(m=>m.type==="delivered"&&m.id===pet)).id,pet);
  b.socket.send(JSON.stringify({type:"status",id:pet}));
  assert.equal((await b.next(m=>m.type==="status"&&m.id===pet)).state,"delivered");
  process.stdout.write("PASS: private-v3 hidden send block, peer presence, pet receive, private ACK, public receipt catch-up.\n");
}finally{a?.socket.terminate();b?.socket.terminate();}
