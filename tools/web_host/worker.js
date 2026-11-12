// Serves the private web build from an R2 bucket behind one shared password (D-041).
// Every file goes through this check, the bucket itself has no public access.

const TYPES = {
  html: "text/html; charset=utf-8",
  js: "text/javascript; charset=utf-8",
  json: "application/json",
  wasm: "application/wasm",
  pck: "application/octet-stream",
  zip: "application/zip",
  png: "image/png",
};

const encoder = new TextEncoder();

async function sameSecret(a, b) {
  // Hashing gives equal lengths, which timingSafeEqual requires.
  const [hashA, hashB] = await Promise.all([
    crypto.subtle.digest("SHA-256", a),
    crypto.subtle.digest("SHA-256", b),
  ]);
  return crypto.subtle.timingSafeEqual(hashA, hashB);
}

async function authorized(request, env) {
  const [scheme, encoded] = (request.headers.get("Authorization") ?? "").split(" ");
  if (scheme !== "Basic" || !encoded || !env.GAME_PASSWORD) return false;
  let decoded;
  try {
    decoded = atob(encoded);
  } catch {
    return false;
  }
  const separator = decoded.indexOf(":");
  if (separator < 0) return false;
  // The user name is ignored. atob() yields one char per byte, the browser sends UTF-8.
  const password = Uint8Array.from(decoded.slice(separator + 1), (c) => c.charCodeAt(0));
  return sameSecret(password, encoder.encode(env.GAME_PASSWORD));
}

function headersFor(key, object) {
  const headers = new Headers();
  headers.set("Content-Type", TYPES[key.split(".").pop()] ?? "application/octet-stream");
  headers.set("ETag", object.httpEtag);
  // Packs stay in the browser's HTTP cache, but no shared cache may keep them.
  headers.set("Cache-Control", "private, no-cache");
  headers.set("X-Robots-Tag", "noindex");
  headers.set("Cross-Origin-Opener-Policy", "same-origin");
  headers.set("Cross-Origin-Embedder-Policy", "require-corp");
  return headers;
}

export default {
  async fetch(request, env) {
    if (!(await authorized(request, env))) {
      return new Response("Password required", {
        status: 401,
        headers: { "WWW-Authenticate": 'Basic realm="Stuttgart Speed", charset="UTF-8"' },
      });
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    let key;
    try {
      key = decodeURIComponent(new URL(request.url).pathname.slice(1)) || "index.html";
    } catch {
      return new Response("Not found", { status: 404 });
    }
    if (request.method === "HEAD") {
      const object = await env.BUCKET.head(key);
      if (!object) return new Response("Not found", { status: 404 });
      const headers = headersFor(key, object);
      headers.set("Content-Length", String(object.size));
      return new Response(null, { headers });
    }
    const object = await env.BUCKET.get(key, { onlyIf: request.headers });
    if (!object) return new Response("Not found", { status: 404 });
    // Without a body the If-None-Match precondition failed: the browser's copy is current.
    if (!("body" in object)) return new Response(null, { status: 304, headers: headersFor(key, object) });
    return new Response(object.body, { headers: headersFor(key, object) });
  },
};
