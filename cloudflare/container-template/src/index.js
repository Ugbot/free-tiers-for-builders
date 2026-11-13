// A Worker that runs containers you can't leave running.
//
// One Durable Object per runner owns the container and the clock that
// kills it. The alarm fires at the earlier of the lease and the hard
// deadline and destroys the container, even if whatever started it is gone.
// Renewing moves the lease, never past the hard deadline.
//
// Routes (all need "Authorization: Bearer <RUN_TOKEN>"):
//   POST /runners/<name>/start     start the container, take a lease
//   POST /runners/<name>/renew     extend the lease
//   POST /runners/<name>/destroy   stop it now
//   GET  /runners/<name>/status
//   ANY  /runners/<name>/app/...   forwarded to the container's port

import { DurableObject } from "cloudflare:workers";

const LEASE_MS = 10 * 60 * 1000;
const HARD_MS = 2 * 60 * 60 * 1000;
const APP_PORT = 8080;

export class LeasedRunner extends DurableObject {
  async start() {
    const now = Date.now();
    let hard = await this.ctx.storage.get("hard");
    if (!hard || hard <= now) {
      hard = now + HARD_MS;
      await this.ctx.storage.put("hard", hard);
    }
    const lease = Math.min(now + LEASE_MS, hard);
    await this.ctx.storage.put("lease", lease);
    if (!this.ctx.container.running) {
      // The agent inside gets its own TTL too: a third clock.
      const ttl = String(Math.ceil((hard - now) / 1000));
      this.ctx.container.start({ env: { AGENT_TTL_SECONDS: ttl } });
    }
    await this.ctx.storage.setAlarm(lease);
    return { lease, hard };
  }

  async renew() {
    const hard = await this.ctx.storage.get("hard");
    if (!hard || !this.ctx.container.running) return { error: "not running" };
    const lease = Math.min(Date.now() + LEASE_MS, hard);
    await this.ctx.storage.put("lease", lease);
    await this.ctx.storage.setAlarm(lease);
    return { lease, hard };
  }

  async destroy() {
    if (this.ctx.container.running) await this.ctx.container.destroy();
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    return { destroyed: true };
  }

  async status() {
    return {
      running: this.ctx.container.running,
      lease: (await this.ctx.storage.get("lease")) ?? null,
      hard: (await this.ctx.storage.get("hard")) ?? null,
    };
  }

  // Alarms run at least once, so this must be safe to run twice.
  async alarm() {
    const lease = (await this.ctx.storage.get("lease")) ?? 0;
    const hard = (await this.ctx.storage.get("hard")) ?? 0;
    const now = Date.now();
    if (now >= lease || now >= hard) {
      await this.destroy();
      return;
    }
    await this.ctx.storage.setAlarm(Math.min(lease, hard));
  }

  async fetch(request) {
    if (!this.ctx.container.running) return new Response("not running", { status: 409 });
    return this.ctx.container.getTcpPort(APP_PORT).fetch(request);
  }
}

async function authorised(request, env) {
  const got = new TextEncoder().encode(request.headers.get("Authorization") ?? "");
  const want = new TextEncoder().encode(`Bearer ${env.RUN_TOKEN ?? ""}`);
  if (!env.RUN_TOKEN || got.byteLength !== want.byteLength) return false;
  return crypto.subtle.timingSafeEqual(got, want);
}

const json = (body, status = 200) => Response.json(body, { status });

export default {
  async fetch(request, env) {
    if (!(await authorised(request, env))) return json({ error: "unauthorised" }, 401);

    const url = new URL(request.url);
    const m = url.pathname.match(/^\/runners\/([A-Za-z0-9_-]{1,64})\/(start|renew|destroy|status|app)(\/.*)?$/);
    if (!m) return json({ error: "not found" }, 404);
    const [, name, verb, rest] = m;
    const runner = env.RUNNER.get(env.RUNNER.idFromName(name));

    if (verb === "app") {
      const inner = new URL(rest ?? "/", "http://container");
      inner.search = url.search;
      return runner.fetch(new Request(inner, request));
    }
    if (verb === "status") return json(await runner.status());
    if (request.method !== "POST") return json({ error: "use POST" }, 405);
    return json(await runner[verb]());
  },
};
