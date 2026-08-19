/**
 * Read-later / bookmark API
 * Stack: Cloudflare Workers · Hono · D1 (SQLite)
 */

import { Hono } from "hono";
import { bearerAuth } from "hono/bearer-auth";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";

// ── Types ──────────────────────────────────────────────────────────────────────

type Bookmark = {
  id: string;
  url: string;
  title: string | null;
  tags: string | null; // "tag1,tag2,tag3"
  created_at: string;
  updated_at: string;
};

// ── App ────────────────────────────────────────────────────────────────────────

const app = new Hono<{ Bindings: CloudflareBindings }>();

// CORS — allow any origin
app.use(
  "*",
  cors({
    origin: "*",
    // If-None-Match is not a safelisted request header, so without it here the
    // preflight rejects the web client's conditional GET.
    allowHeaders: ["Authorization", "Content-Type", "If-None-Match"],
    // Not CORS-safelisted, so browsers hide these unless exposed explicitly.
    // ETag in particular: Last-Modified is safelisted, ETag is not.
    exposeHeaders: ["X-Total-Count", "ETag"],
    // Cache preflights; favicon loads trigger one per icon URL otherwise
    maxAge: 86400,
  }),
);

// Auth — every request must carry:  Authorization: Bearer <API_TOKEN>
// (Skip OPTIONS preflight — CORS middleware already handles it)
app.use("*", async (c, next) => {
  if (c.req.method === "OPTIONS") return next();
  return bearerAuth<{ Bindings: CloudflareBindings }>({ token: c.env.API_TOKEN })(c, next);
});

// ── List  GET /bookmarks ───────────────────────────────────────────────────────
//
//   ?tag=devops           bookmark carries that exact tag (case-insensitive)
//   ?q=hono               full-text search across title + url
//   ?limit=50&offset=0    pagination
//
//   q and tag compose when both are given.

app.get("/bookmarks", async (c) => {
  const { tag, q, limit: rawLimit, offset: rawOffset } = c.req.query();
  const limit = clampInt(rawLimit, 200, 1, 500);
  const offset = clampInt(rawOffset, 0, 0, Infinity);

  // ── Conditional GET ──────────────────────────────────────────────────────
  // The version counter is a valid strong validator for any list URL: for a
  // fixed URL, an unchanged version means an identical result set in an
  // identical order, so filtered requests get this too.
  const etag = `"${await getVersion(c.env.DB)}"`;
  c.header("ETag", etag);
  // A 304 must still carry the ETag it would have sent with a 200.
  if (matchesEtag(c.req.header("If-None-Match"), etag)) return c.body(null, 304);

  // Use FTS when there's a search term, plain table otherwise.
  if (q) {
    const match = '"' + q.replace(/"/g, '""') + '"*';
    const tagClause = tag ? ` AND ${TAG_MATCH("b.tags")}` : "";
    const filterParams = tag ? [match, tagNeedle(tag)] : [match];

    // Count (for the pagination header) and page in one round trip
    const [count, page] = await c.env.DB.batch([
      c.env.DB.prepare(
        `SELECT COUNT(*) as total
             FROM bookmarks b
             JOIN bookmarks_fts f ON b.rowid = f.rowid
            WHERE bookmarks_fts MATCH ?${tagClause}`,
      ).bind(...filterParams),
      c.env.DB.prepare(
        `SELECT b.*
             FROM bookmarks b
             JOIN bookmarks_fts f ON b.rowid = f.rowid
            WHERE bookmarks_fts MATCH ?${tagClause}
            ORDER BY b.created_at DESC, b.id ASC
            LIMIT ? OFFSET ?`,
      ).bind(...filterParams, limit, offset),
    ]);

    c.header("X-Total-Count", String((count.results[0] as { total: number })?.total ?? 0));
    return c.json(page.results as Bookmark[]);
  }

  const where = tag ? ` WHERE ${TAG_MATCH("tags")}` : "";
  const whereParams = tag ? [tagNeedle(tag)] : [];

  // Deterministic ordering: created_at DESC, then id ASC as tiebreaker
  const [count, page] = await c.env.DB.batch([
    c.env.DB.prepare(`SELECT COUNT(*) as total FROM bookmarks${where}`).bind(...whereParams),
    c.env.DB.prepare(
      `SELECT * FROM bookmarks${where} ORDER BY created_at DESC, id ASC LIMIT ? OFFSET ?`,
    ).bind(...whereParams, limit, offset),
  ]);

  c.header("X-Total-Count", String((count.results[0] as { total: number })?.total ?? 0));
  return c.json(page.results as Bookmark[]);
});

// ── Export  GET /bookmarks/export ───────────────────────────────────────────────
//
//   Returns all bookmarks as a JSON array (no pagination).

app.get("/bookmarks/export", async (c) => {
  const { results } = await c.env.DB.prepare(
    "SELECT * FROM bookmarks ORDER BY created_at DESC",
  ).all<Bookmark>();

  return c.json(results);
});

// ── Import  POST /bookmarks/import ─────────────────────────────────────────────
//
//   Accepts the same JSON array that GET /bookmarks/export produces.
//   Preserves original ids and timestamps.  Skips rows whose URL already exists.

app.post("/bookmarks/import", async (c) => {
  const body = await c.req.json();

  if (!Array.isArray(body)) {
    throw new HTTPException(400, { message: "Body must be a JSON array of bookmarks" });
  }

  if (body.length === 0) {
    return c.json({ imported: 0, skipped: 0, errors: [] });
  }

  // Validate every row up-front before touching the DB.
  const errors: string[] = [];
  const rows: Bookmark[] = [];

  for (let i = 0; i < body.length; i++) {
    const b = body[i];
    if (!isValidUrl(b?.url)) {
      errors.push(`[${i}] invalid or missing url`);
      continue;
    }
    const url = new URL(b.url).href;
    const title = typeof b.title === "string" ? b.title.slice(0, 2000) : null;
    const tags = Array.isArray(b.tags)
      ? b.tags.join(",")
      : typeof b.tags === "string"
        ? b.tags
        : null;
    const id = typeof b.id === "string" && b.id ? b.id : crypto.randomUUID();
    const now = new Date().toISOString();
    const createdAt = toIso(b.created_at) ?? now;
    const updatedAt = toIso(b.updated_at) ?? now;

    rows.push({ id, url, title, tags, created_at: createdAt, updated_at: updatedAt });
  }

  // OR IGNORE skips rows conflicting on url or id — whether against existing
  // data or duplicates within the payload itself — without failing the batch.
  // RETURNING tells apart inserted rows from ignored ones (meta.changes can't:
  // it also counts trigger writes).
  const stmts = rows.map((row) =>
    c.env.DB.prepare(
      `INSERT OR IGNORE INTO bookmarks (id, url, title, tags, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?) RETURNING id`,
    ).bind(row.id, row.url, row.title, row.tags, row.created_at, row.updated_at),
  );

  let imported = 0;

  if (stmts.length) {
    const results = await c.env.DB.batch<{ id: string }>(stmts);
    imported = results.filter((r) => r.results.length > 0).length;
  }

  return c.json({ imported, skipped: rows.length - imported, errors });
});

// ── Get one  GET /bookmarks/:id ────────────────────────────────────────────────

app.get("/bookmarks/:id", async (c) => {
  const bookmark = await findOrThrow(c.env.DB, c.req.param("id"));
  return c.json(bookmark);
});

// ── Create  POST /bookmarks ────────────────────────────────────────────────────
//
//   Body (JSON):
//     url*         string
//     title        string
//     tags         string   "tag1,tag2"  or pass an array → joined for you

app.post("/bookmarks", async (c) => {
  const body = await c.req.json<Partial<Bookmark> & { tags?: string | string[] }>();

  if (!isValidUrl(body.url))
    throw new HTTPException(400, { message: "A valid http(s) url is required" });

  const url = new URL(body.url).href; // normalize
  const title = typeof body.title === "string" ? body.title.slice(0, 2000) : null;
  const tags = Array.isArray(body.tags)
    ? body.tags.join(",")
    : typeof body.tags === "string"
      ? body.tags
      : null;

  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  // Atomic duplicate check via ON CONFLICT — avoids TOCTOU race.
  // RETURNING yields the created row, or nothing on conflict.
  const created = await c.env.DB.prepare(
    `INSERT INTO bookmarks (id, url, title, tags, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(url) DO NOTHING
       RETURNING *`,
  )
    .bind(id, url, title, tags, now, now)
    .first<Bookmark>();

  if (!created) {
    const existing = await c.env.DB.prepare("SELECT id FROM bookmarks WHERE url = ?")
      .bind(url)
      .first<{ id: string }>();
    return c.json({ error: "Bookmark already exists", existing_id: existing?.id }, 409);
  }

  return c.json(created, 201);
});

// ── Update  PATCH /bookmarks/:id ───────────────────────────────────────────────
//
//   Send only the fields you want to change.
//   Accepted: title, tags

app.patch("/bookmarks/:id", async (c) => {
  const body = await c.req.json<Partial<Bookmark> & { tags?: string | string[] }>();

  const fields: string[] = [];
  const values: unknown[] = [];

  if ("title" in body) {
    const title = typeof body.title === "string" ? body.title.slice(0, 2000) : null;
    fields.push("title = ?");
    values.push(title);
  }
  if ("tags" in body) {
    const tags = Array.isArray(body.tags) ? body.tags.join(",") : (body.tags ?? null);
    fields.push("tags = ?");
    values.push(tags);
  }

  if (!fields.length) throw new HTTPException(400, { message: "No updatable fields provided" });

  fields.push("updated_at = ?");
  values.push(new Date().toISOString(), c.req.param("id"));

  // Single statement: existence check, update, and read-back are atomic
  const updated = await c.env.DB.prepare(
    `UPDATE bookmarks SET ${fields.join(", ")} WHERE id = ? RETURNING *`,
  )
    .bind(...values)
    .first<Bookmark>();

  if (!updated) throw new HTTPException(404, { message: "Bookmark not found" });

  return c.json(updated);
});

// ── Delete  DELETE /bookmarks/:id ──────────────────────────────────────────────

app.delete("/bookmarks/:id", async (c) => {
  const { meta } = await c.env.DB.prepare("DELETE FROM bookmarks WHERE id = ?")
    .bind(c.req.param("id"))
    .run();

  if (!meta.changes) throw new HTTPException(404, { message: "Bookmark not found" });

  return c.body(null, 204);
});

// ── Favicon  GET /favicon/:host ────────────────────────────────────────────────
//
//   Proxies Google's favicon service: it sends no CORS headers, so browser
//   clients can't fetch it directly. Bearer auth (like every other route)
//   keeps this from being an open favicon proxy.
//
//   Google over DuckDuckGo because it always serves PNG: Flutter web's decoder
//   can't handle the ICO files DDG passes through unconverted.

const HOSTNAME_RE = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/;

app.get("/favicon/:host", async (c) => {
  const host = c.req.param("host").toLowerCase();
  if (host.length > 253 || !HOSTNAME_RE.test(host)) {
    throw new HTTPException(400, { message: "Invalid host" });
  }

  const upstream = await fetch(
    `https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://${host}&size=64`,
    { cf: { cacheEverything: true, cacheTtl: 604800 } },
  );
  if (!upstream.ok || !upstream.body) {
    // Unconsumed bodies pin the connection until GC
    await upstream.body?.cancel();
    throw new HTTPException(404, { message: "No favicon" });
  }

  return c.body(upstream.body, 200, {
    "Content-Type": upstream.headers.get("Content-Type") ?? "image/x-icon",
    // Icons rarely change and staleness is harmless; let browsers cache hard.
    // private: the request carries Authorization, keep shared caches out.
    "Cache-Control": "private, max-age=604800",
  });
});

// ── Error handling ─────────────────────────────────────────────────────────────

app.onError((err, c) => {
  if (err instanceof HTTPException) {
    const status = err.status;
    // If the exception carries a pre-built Response (e.g. bearerAuth), extract
    // its status but return a consistent JSON envelope.
    const message = err.message || (status === 401 ? "Unauthorized" : "Bad Request");
    return c.json({ error: message }, status as any);
  }
  if (err instanceof SyntaxError) {
    return c.json({ error: "Invalid JSON" }, 400);
  }
  console.error(err);
  return c.json({ error: "Internal server error" }, 500);
});

// ── Helpers ────────────────────────────────────────────────────────────────────

/** Match one whole tag inside the comma-separated `tags` column.
 *
 *  instr() rather than LIKE: a LIKE pattern would treat % and _ in the
 *  caller-supplied tag as wildcards, so ?tag=%25 matched every tagged row.
 *  lower() on both sides keeps LIKE's ASCII case-insensitivity. NULL tags
 *  concatenate to NULL and are correctly excluded either way. */
const TAG_MATCH = (col: string) => `instr(lower(',' || ${col} || ','), lower(?)) > 0`;

const tagNeedle = (tag: string) => `,${tag},`;

/** Normalize a caller-supplied timestamp to ISO-8601, or null if unusable.
 *  created_at is sorted lexicographically, so an arbitrary string would order
 *  unpredictably and corrupt pagination for every row. */
function toIso(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = Date.parse(v);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

/** Parse a query-string integer with bounds. */
function clampInt(raw: string | undefined, fallback: number, min: number, max: number): number {
  const n = parseInt(raw ?? "", 10);
  return Number.isNaN(n) ? fallback : Math.min(Math.max(n, min), max);
}

/** Validate that `v` looks like an HTTP(S) URL. */
function isValidUrl(v: unknown): v is string {
  if (typeof v !== "string") return false;
  try {
    const u = new URL(v);
    return u.protocol === "http:" || u.protocol === "https:";
  } catch {
    return false;
  }
}

async function findOrThrow(db: D1Database, id: string): Promise<Bookmark> {
  const row = await db.prepare("SELECT * FROM bookmarks WHERE id = ?").bind(id).first<Bookmark>();

  if (!row) throw new HTTPException(404, { message: "Bookmark not found" });
  return row;
}

/** Monotonic counter bumped by trigger on every bookmark insert/update/delete. */
async function getVersion(db: D1Database): Promise<number> {
  const row = await db
    .prepare("SELECT version FROM bookmarks_state WHERE id = 1")
    .first<{ version: number }>();
  return row?.version ?? 0;
}

/** Does an If-None-Match header match `etag`?
 *  RFC 9110 §13.1.2: weak comparison, so a W/ prefix is stripped before
 *  matching, the value may be a list, and `*` matches any representation. */
function matchesEtag(header: string | undefined, etag: string): boolean {
  if (!header) return false;
  if (header.trim() === "*") return true;
  return header.split(",").some((t) => t.trim().replace(/^W\//, "") === etag);
}

export default app;
