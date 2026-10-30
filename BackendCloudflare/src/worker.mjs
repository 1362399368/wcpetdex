import { DurableObject } from "cloudflare:workers";
import { QueueStore, ProtocolError, memberForAuthorization, migrationAdminAuthorized, migrationAdminConfigured, peerOf, parseClientMessage, missEvent, acceptedEvent } from "./protocol.mjs";

const migrationMethods = new Map([
  ["/admin/migration/freeze", "POST"],
  ["/admin/migration/export", "GET"],
  ["/admin/migration/unfreeze", "POST"]
]);

function pairRoom(env) {
  return env.PET_PAIR.get(env.PET_PAIR.idFromName("our-private-pair-v1"));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") {
      const maintained=await pairRoom(env).fetch(new Request("https://pair.internal/internal/retention",{method:"POST"}));
      if(!maintained.ok)return new Response("Pair service unavailable",{status:503});
      return Response.json({ok:true,retention:{queue_seconds:86400,presence_seconds:259200,automatic:true}});
    }
    if (migrationMethods.has(url.pathname)) {
      if (!migrationAdminConfigured(env.MIGRATION_ADMIN_TOKEN, env.DEVICE_A_TOKEN, env.DEVICE_B_TOKEN))
        return new Response("Not found", { status: 404 });
      if (!migrationAdminAuthorized(request.headers.get("Authorization"), env.MIGRATION_ADMIN_TOKEN, env.DEVICE_A_TOKEN, env.DEVICE_B_TOKEN))
        return new Response("Unauthorized", { status: 401 });
      if (request.method !== migrationMethods.get(url.pathname))
        return new Response("Method not allowed", { status: 405 });
      // Build a fresh internal request: public identity and authorization headers cannot reach the room.
      const forwarded = new Request(request.url, {
        method: request.method,
        headers: { "X-Pet-Migration-Admin": `Bearer ${env.MIGRATION_ADMIN_TOKEN}` }
      });
      return pairRoom(env).fetch(forwarded);
    }
    if (url.pathname !== "/v1/ws" || request.method !== "GET") return new Response("Not found", { status: 404 });
    let member;
    try { member = memberForAuthorization(request.headers.get("Authorization"), env.DEVICE_A_TOKEN, env.DEVICE_B_TOKEN); }
    catch { return new Response("Pair service not configured", { status: 503 }); }
    if (!member) return new Response("Unauthorized", { status: 401 });
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return new Response("WebSocket required", { status: 426 });
    const forwarded = new Request(request);
    // Discard any client-supplied identity. The room is reachable only by binding.
    forwarded.headers.set("X-Pet-Member", member);
    forwarded.headers.delete("Authorization");
    return pairRoom(env).fetch(forwarded);
  }
};

export class PetPairRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.queue = new QueueStore(ctx.storage);
    this.adminToken = env.MIGRATION_ADMIN_TOKEN;
    this.deviceAToken = env.DEVICE_A_TOKEN;
    this.deviceBToken = env.DEVICE_B_TOKEN;
    this.personalMember = env.PERSONAL_MEMBER === "A" || env.PERSONAL_MEMBER === "B" ? env.PERSONAL_MEMBER : null;
  }
  sockets(member) { return this.ctx.getWebSockets(member).filter(socket => socket.readyState === 1); }
  send(socket, event) {
    try { socket.send(JSON.stringify(event)); return true; }
    catch { return false; }
  }
  attachment(socket){ return socket.deserializeAttachment() ?? {}; }
  async maintainRetention(now=Date.now()/1000) {
    this.queue.purge(now);
    const deadline=this.queue.nextRetentionDeadline(now);
    const existing=await this.ctx.storage.getAlarm();
    if(deadline===null){if(existing!==null)await this.ctx.storage.deleteAlarm();}
    else if(existing===null || Math.abs(existing-deadline*1000)>10)await this.ctx.storage.setAlarm(Math.ceil(deadline*1000));
    await this.ctx.storage.sync();
  }
  async alarm() {await this.maintainRetention();}
  canReceive(socket,row){ return row.kind !== "pet" || (this.attachment(socket).protocol ?? 2) >= 3; }
  peerStatus(socket, member, now) {
    if(member !== this.personalMember)return;
    const peer=peerOf(member);
    const state=this.queue.publicStatus(peer,now,this.sockets(peer).length>0);
    this.send(socket,{type:"peer_status",...state});
  }
  async fetch(request) {
    const url = new URL(request.url);
    // The outer Worker never exposes this binding-only maintenance endpoint.
    if(url.pathname==="/internal/retention" && request.method==="POST"){
      await this.maintainRetention();return Response.json({ok:true});
    }
    if (migrationMethods.has(url.pathname)) {
      if (!migrationAdminConfigured(this.adminToken, this.deviceAToken, this.deviceBToken) ||
          !migrationAdminAuthorized(request.headers.get("X-Pet-Migration-Admin"), this.adminToken, this.deviceAToken, this.deviceBToken))
        return new Response("Unauthorized", { status: 401 });
      if (request.method !== migrationMethods.get(url.pathname))
        return new Response("Method not allowed", { status: 405 });
      if (url.pathname === "/admin/migration/export") {
        if (!this.queue.isFrozen()) return new Response("Freeze required", { status: 409 });
        return Response.json(this.queue.exportSnapshot(Date.now() / 1000), {
          headers: { "Cache-Control": "no-store" }
        });
      }
      const frozen = url.pathname === "/admin/migration/freeze";
      this.queue.setFrozen(frozen);
      await this.ctx.storage.sync();
      const sockets = frozen ? this.ctx.getWebSockets() : [];
      for (const socket of sockets) {
        try {
          this.send(socket, { type: "error", id: "", code: "service_unavailable" });
          socket.close(4002, "Migration in progress");
        } catch { /* already closed */ }
      }
      return Response.json({ frozen, connections_signalled: sockets.length }, { headers: { "Cache-Control": "no-store" } });
    }
    const member = request.headers.get("X-Pet-Member");
    if (member !== "A" && member !== "B") return new Response("Unauthorized", { status: 401 });
    if (this.queue.isFrozen()) return new Response("Migration in progress", { status: 503 });
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return new Response("WebSocket required", { status: 426 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    for (const old of this.sockets(member)) old.close(4001, "Replaced by a new connection");
    const requested=request.headers.get("X-Pet-Hidden");
    // A legacy client has no hidden control. Never inherit a previous
    // connection's hidden choice when it reconnects after a downgrade.
    const hidden=member===this.personalMember && requested==="1";
    const protocol=request.headers.get("X-Pet-Protocol")==="3"?3:2;
    server.serializeAttachment({ member, hidden, protocol });
    this.ctx.acceptWebSocket(server, [member]);
    const now=Date.now()/1000;
    this.queue.observe(member,now,hidden);
    if(!hidden){
      const receipts=this.queue.publishReceipts(member);
      for(const row of receipts)for(const sender of this.sockets(row.sender))this.send(sender,{type:"delivered",id:row.id});
    }
    await this.maintainRetention(now);
    this.send(server, { type: "ready", protocol: 3, capabilities: ["pet", "presence", "private_receipts"], hidden_applied: hidden });
    for (const row of this.queue.queued(member, now))if(this.canReceive(server,row))this.send(server, missEvent(row));
    this.peerStatus(server,member,now);
    return new Response(null, { status: 101, webSocket: client });
  }
  async webSocketMessage(socket, message) {
    const attachment=this.attachment(socket),member=attachment.member;
    if (member !== "A" && member !== "B") { socket.close(1008, "Unauthorized"); return; }
    if (this.queue.isFrozen()) {
      this.send(socket, { type: "error", id: "", code: "service_unavailable" });
      socket.close(4002, "Migration in progress");
      return;
    }
    let event;
    try {
      event = parseClientMessage(message);
      const now = Date.now() / 1000;
      if (event.type === "miss" || event.type === "anger" || event.type === "pet") {
        if(attachment.hidden)throw new ProtocolError("stealth_send_blocked");
        const { row, isNew } = this.queue.accept(member, event.id, now, event.type);
        await this.maintainRetention(now); // Persist event and expiry before acceptance.
        const peers = this.sockets(peerOf(member)).filter(peer=>this.canReceive(peer,row));
        const peerState=this.queue.publicStatus(peerOf(member),now,peers.length>0);
        this.send(socket, acceptedEvent(row, peerState.online));
        if (row.acknowledged) this.send(socket, { type: "delivered", id: event.id });
        if (isNew) for (const peer of peers) this.send(peer, missEvent(row));
      } else if (event.type === "status") {
        const row = this.queue.outgoing(member, event.id, now);
        this.send(socket, { type: "status", id: event.id, state: row ? (row.acknowledged ? "delivered" : "queued") : "unknown", ...(row ? {sent_at: row.sent_at, kind: row.kind} : {}) });
      } else if(event.type==="ack"){
        const row = this.queue.acknowledge(member, event.id, now,!attachment.hidden);
        await this.maintainRetention(now);
        if (row && !attachment.hidden) for (const sender of this.sockets(row.sender)) this.send(sender, { type: "delivered", id: event.id });
      }else if(event.type==="heartbeat"){
        this.queue.observe(member,now,!!attachment.hidden);
        await this.maintainRetention(now);
        this.peerStatus(socket,member,now);
      }else if(event.type==="peer_status"){
        this.peerStatus(socket,member,now);
      }
    } catch (error) {
      const code = error instanceof ProtocolError ? error.code : "service_unavailable";
      this.send(socket, { type: "error", id: event?.id ?? "", code });
      if (code === "message_too_large") socket.close(1009, "Message too large");
    }
  }
  webSocketClose(socket, code) {
    // Hibernation API handles lifetime; no in-memory connection map or timers.
    const member=this.attachment(socket).member;
    if((member==="A" || member==="B") && this.sockets(member).length<=1)this.queue.bump(member);
    try { socket.close(code === 1005 || code === 1006 ? 1000 : code); } catch { /* already closed */ }
  }
  webSocketError(socket) { try { socket.close(1011, "Connection error"); } catch { /* already closed */ } }
}
