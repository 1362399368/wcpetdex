// Preserve the complete response, including WebSocket/101 upgrade metadata.
// This calls the existing Worker internally and never fetches workers.dev.
export async function onRequest(context) {
  const request = context.request;
  const path = new URL(request.url).pathname;
  if (path !== "/health" && path !== "/v1/ws") return new Response("Not found", { status: 404 });
  if (request.method !== "GET") return new Response("Method not allowed", { status: 405, headers: { Allow: "GET" } });
  if (!context.env.PET_SYNC || typeof context.env.PET_SYNC.fetch !== "function")
    return new Response("Pair service binding not configured", { status: 503 });
  try {
    return await context.env.PET_SYNC.fetch(request);
  } catch {
    return new Response("Pair service unavailable", { status: 502 });
  }
}
