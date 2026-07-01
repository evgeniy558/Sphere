/**
 * Thin proxy Worker used during backend migration to Cloudflare.
 *
 * Required env vars:
 * - BACKEND_ORIGIN: full HTTPS origin of your current backend (no trailing slash)
 */

function sanitizeOrigin(raw) {
  if (!raw) return null;
  const trimmed = String(raw).trim();
  if (!trimmed) return null;
  const normalized = trimmed.replace(/\/+$/, "");
  try {
    const u = new URL(normalized);
    if (u.protocol !== "https:") return null;
    return u.origin;
  } catch {
    return null;
  }
}

export default {
  async fetch(request, env) {
    const origin = sanitizeOrigin(env.BACKEND_ORIGIN);
    if (!origin) {
      return new Response(
        JSON.stringify({
          ok: false,
          error:
            "BACKEND_ORIGIN is not configured. Set an https origin in Worker environment variables.",
        }),
        {
          status: 500,
          headers: { "content-type": "application/json; charset=utf-8" },
        }
      );
    }

    const incoming = new URL(request.url);
    const upstream = new URL(incoming.pathname + incoming.search, origin);

    const upstreamReq = new Request(upstream.toString(), request);
    const res = await fetch(upstreamReq, {
      redirect: "follow",
      cf: { cacheTtl: 0, cacheEverything: false },
    });

    // Preserve upstream response while adding migration diagnostic header.
    const headers = new Headers(res.headers);
    headers.set("x-sphere-edge-proxy", "cloudflare-worker");

    return new Response(res.body, {
      status: res.status,
      statusText: res.statusText,
      headers,
    });
  },
};
