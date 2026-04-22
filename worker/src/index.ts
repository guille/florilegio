/**
 * Read-later / bookmark API
 * Stack: Cloudflare Workers · Hono · D1 (SQLite)
 */

import { Hono } from "hono";
import { bearerAuth } from "hono/bearer-auth";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";

// ── Types ──────────────────────────────────────────────────────────────────────

type Env = {
  DB: D1Database;
  API_TOKEN: string;
};

type Bookmark = {
  id: string;
  url: string;
  title: string | null;
  tags: string | null; // "tag1,tag2,tag3"
  created_at: string;
  updated_at: string;
};

// ── App ────────────────────────────────────────────────────────────────────────

const app = new Hono<{ Bindings: Env }>();

// CORS — allow any origin so a future webapp can call the API
app.use("*", cors({ origin: "*", allowHeaders: ["Authorization", "Content-Type"] }));

// Auth — every request must carry:  Authorization: Bearer <API_TOKEN>
// (Skip OPTIONS preflight — CORS middleware already handles it)
app.use("*", async (c, next) => {
  if (c.req.method === "OPTIONS") return next();
  return bearerAuth({ token: c.env.API_TOKEN })(c, next);
});

// ── List  GET /bookmarks ───────────────────────────────────────────────────────
//
//   ?tag=devops           tag contains "devops" (simple LIKE, good enough for personal use)
//   ?q=hono               full-text search across title + url
//   ?limit=50&offset=0    pagination

app.get("/bookmarks", async (c) => {
  const { tag, q, limit: rawLimit, offset: rawOffset } = c.req.query();
  const limit = clampInt(rawLimit, 200, 1, 500);
  const offset = clampInt(rawOffset, 0, 0, Infinity);

  // ── Conditional GET ──────────────────────────────────────────────────────
  // When no filters are active, support If-Modified-Since to let clients
  // skip a full sync when nothing has changed.
  if (!q && !tag) {
    const lastModified = await getLastModified(c.env.DB);
    if (lastModified) {
      c.header("Last-Modified", lastModified.toUTCString());

      const ims = c.req.header("If-Modified-Since");
      if (ims) {
        const imsDate = new Date(ims);
        if (!isNaN(imsDate.getTime()) && lastModified <= imsDate) {
          return c.body(null, 304);
        }
      }
    }
  }

  // Use FTS when there's a search term, plain table otherwise.
  if (q) {
    // Count total matches for pagination header
    const { total } = (await c.env.DB.prepare(
      `SELECT COUNT(*) as total
           FROM bookmarks b
           JOIN bookmarks_fts f ON b.id = f.id
          WHERE bookmarks_fts MATCH ?`,
    )
      .bind('"' + q.replace(/"/g, '""') + '"*')
      .first<{ total: number }>()) ?? { total: 0 };

    const { results } = await c.env.DB.prepare(
      `SELECT b.*
           FROM bookmarks b
           JOIN bookmarks_fts f ON b.id = f.id
          WHERE bookmarks_fts MATCH ?
          ORDER BY b.created_at DESC, b.id ASC
          LIMIT ? OFFSET ?`,
    )
      .bind('"' + q.replace(/"/g, '""') + '"*', limit, offset)
      .all<Bookmark>();

    c.header("X-Total-Count", String(total));
    return c.json(results);
  }

  let countSql = "SELECT COUNT(*) as total FROM bookmarks WHERE 1=1";
  let sql = "SELECT * FROM bookmarks WHERE 1=1";
  const countParams: unknown[] = [];
  const params: unknown[] = [];

  if (tag) {
    countSql += " AND ',' || tags || ',' LIKE ?";
    countParams.push(`%,${tag},%`);
    sql += " AND ',' || tags || ',' LIKE ?";
    params.push(`%,${tag},%`);
  }

  const { total } = (await c.env.DB.prepare(countSql)
    .bind(...countParams)
    .first<{ total: number }>()) ?? { total: 0 };

  // Deterministic ordering: created_at DESC, then id ASC as tiebreaker
  sql += " ORDER BY created_at DESC, id ASC LIMIT ? OFFSET ?";
  params.push(limit, offset);

  const { results } = await c.env.DB.prepare(sql)
    .bind(...params)
    .all<Bookmark>();

  c.header("X-Total-Count", String(total));
  return c.json(results);
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
    const createdAt = typeof b.created_at === "string" ? b.created_at : now;
    const updatedAt = typeof b.updated_at === "string" ? b.updated_at : now;

    rows.push({ id, url, title, tags, created_at: createdAt, updated_at: updatedAt });
  }

  // Collect existing URLs in one query so we can skip duplicates.
  // D1 doesn't support large IN-clauses well, so batch in groups of 50.
  const urlSet = new Set(rows.map((r) => r.url));
  const existingUrls = new Set<string>();

  const urlList = [...urlSet];
  for (let i = 0; i < urlList.length; i += 50) {
    const chunk = urlList.slice(i, i + 50);
    const placeholders = chunk.map(() => "?").join(",");
    const { results } = await c.env.DB.prepare(
      `SELECT url FROM bookmarks WHERE url IN (${placeholders})`,
    )
      .bind(...chunk)
      .all<{ url: string }>();
    for (const r of results) existingUrls.add(r.url);
  }

  let imported = 0;
  let skipped = 0;

  // Insert in batches using D1 batch API.
  const stmts: D1PreparedStatement[] = [];

  for (const row of rows) {
    if (existingUrls.has(row.url)) {
      skipped++;
      continue;
    }
    stmts.push(
      c.env.DB.prepare(
        `INSERT INTO bookmarks (id, url, title, tags, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?)`,
      ).bind(row.id, row.url, row.title, row.tags, row.created_at, row.updated_at),
    );
  }

  if (stmts.length) {
    await c.env.DB.batch(stmts);
    imported = stmts.length;

    // Rebuild FTS index to guarantee consistency after batch insert
    await c.env.DB.exec("INSERT INTO bookmarks_fts(bookmarks_fts) VALUES('rebuild')");
  }

  return c.json({ imported, skipped, errors });
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
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO bookmarks (id, url, title, tags, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(url) DO NOTHING`,
  )
    .bind(id, url, title, tags, now, now)
    .run();

  if (!meta.changes) {
    const existing = await c.env.DB.prepare("SELECT id FROM bookmarks WHERE url = ?")
      .bind(url)
      .first<{ id: string }>();
    return c.json({ error: "Bookmark already exists", existing_id: existing?.id }, 409);
  }

  const created = await c.env.DB.prepare("SELECT * FROM bookmarks WHERE id = ?")
    .bind(id)
    .first<Bookmark>();

  return c.json(created, 201);
});

// ── Update  PATCH /bookmarks/:id ───────────────────────────────────────────────
//
//   Send only the fields you want to change.
//   Accepted: title, tags

app.patch("/bookmarks/:id", async (c) => {
  await findOrThrow(c.env.DB, c.req.param("id")); // 404 guard

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

  await c.env.DB.prepare(`UPDATE bookmarks SET ${fields.join(", ")} WHERE id = ?`)
    .bind(...values)
    .run();

  const updated = await c.env.DB.prepare("SELECT * FROM bookmarks WHERE id = ?")
    .bind(c.req.param("id"))
    .first<Bookmark>();

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

/** Get the most recent updated_at as a Date, or null if table is empty.
 *  Truncated to seconds since HTTP dates have 1-second resolution. */
async function getLastModified(db: D1Database): Promise<Date | null> {
  const row = await db
    .prepare("SELECT value FROM sync_metadata WHERE key = 'last_modified'")
    .first<{ value: string | null }>();
  if (!row?.value) return null;
  const d = new Date(row.value);
  if (isNaN(d.getTime())) return null;
  // Truncate to second precision so round-tripping through HTTP date headers
  // (which lack milliseconds) produces stable comparisons.
  d.setMilliseconds(0);
  return d;
}

export default app;
