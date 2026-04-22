import { env, exports } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import "../src/index";

const TOKEN = "test-token";
const auth = { Authorization: `Bearer ${TOKEN}` };
const jsonHeaders = { ...auth, "Content-Type": "application/json" };

/** Apply schema to the test D1 database. */
async function applySchema() {
  const db = env.DB;
  await db.exec(
    "CREATE TABLE IF NOT EXISTS bookmarks(id TEXT PRIMARY KEY, url TEXT NOT NULL UNIQUE, title TEXT, tags TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
  );
  await db.exec(
    "CREATE VIRTUAL TABLE IF NOT EXISTS bookmarks_fts USING fts5(id UNINDEXED, title, url, content = bookmarks, content_rowid = rowid)",
  );
  await db.exec(
    "CREATE TRIGGER IF NOT EXISTS bookmarks_ai AFTER INSERT ON bookmarks BEGIN INSERT INTO bookmarks_fts(rowid, id, title, url) VALUES (new.rowid, new.id, new.title, new.url); END",
  );
  await db.exec(
    "CREATE TRIGGER IF NOT EXISTS bookmarks_ad AFTER DELETE ON bookmarks BEGIN INSERT INTO bookmarks_fts(bookmarks_fts, rowid, id, title, url) VALUES ('delete', old.rowid, old.id, old.title, old.url); END",
  );
  await db.exec(
    "CREATE TRIGGER IF NOT EXISTS bookmarks_au AFTER UPDATE ON bookmarks BEGIN INSERT INTO bookmarks_fts(bookmarks_fts, rowid, id, title, url) VALUES ('delete', old.rowid, old.id, old.title, old.url); INSERT INTO bookmarks_fts(rowid, id, title, url) VALUES (new.rowid, new.id, new.title, new.url); END",
  );
  // sync_metadata for If-Modified-Since support (including deletes)
  await db.exec(
    "CREATE TABLE IF NOT EXISTS sync_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
  );
  await db.exec(
    "INSERT OR IGNORE INTO sync_metadata (key, value) VALUES ('last_modified', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))",
  );
  await db.exec(
    "CREATE TRIGGER IF NOT EXISTS sync_meta_after_insert AFTER INSERT ON bookmarks BEGIN UPDATE sync_metadata SET value = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE key = 'last_modified'; END",
  );
  await db.exec(
    "CREATE TRIGGER IF NOT EXISTS sync_meta_after_update AFTER UPDATE ON bookmarks BEGIN UPDATE sync_metadata SET value = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE key = 'last_modified'; END",
  );
  await db.exec(
    "CREATE TRIGGER IF NOT EXISTS sync_meta_after_delete AFTER DELETE ON bookmarks BEGIN UPDATE sync_metadata SET value = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE key = 'last_modified'; END",
  );
}

async function clearBookmarks() {
  const db = env.DB;
  await db.exec("DELETE FROM bookmarks");
}

// ── Helpers ──────────────────────────────────────────────────────────────────

async function createBookmark(data: Record<string, unknown>) {
  return exports.default.fetch("http://localhost/bookmarks", {
    method: "POST",
    headers: jsonHeaders,
    body: JSON.stringify(data),
  });
}

// ── Tests ────────────────────────────────────────────────────────────────────

describe("Florilegio API", () => {
  beforeEach(async () => {
    await applySchema();
    await clearBookmarks();
  });

  // ── Auth ─────────────────────────────────────────────────────────────────

  it("rejects requests without auth", async () => {
    const res = await exports.default.fetch("http://localhost/bookmarks");
    expect(res.status).toBe(401);
  });

  it("rejects requests with wrong token", async () => {
    const res = await exports.default.fetch("http://localhost/bookmarks", {
      headers: { Authorization: "Bearer wrong" },
    });
    expect(res.status).toBe(401);
  });

  // ── CRUD ─────────────────────────────────────────────────────────────────

  it("creates a bookmark", async () => {
    const res = await createBookmark({
      url: "https://example.com",
      title: "Example",
      tags: "test,demo",
    });
    expect(res.status).toBe(201);
    const body = await res.json<any>();
    expect(body.url).toBe("https://example.com/");
    expect(body.title).toBe("Example");
    expect(body.tags).toBe("test,demo");
  });

  it("returns 409 for duplicate URL", async () => {
    await createBookmark({ url: "https://example.com" });
    const res = await createBookmark({ url: "https://example.com" });
    expect(res.status).toBe(409);
  });

  it("returns 400 for invalid URL", async () => {
    const res = await createBookmark({ url: "not-a-url" });
    expect(res.status).toBe(400);
  });

  it("lists bookmarks", async () => {
    await createBookmark({ url: "https://a.com", title: "A" });
    await createBookmark({ url: "https://b.com", title: "B" });
    const res = await exports.default.fetch("http://localhost/bookmarks", { headers: auth });
    expect(res.status).toBe(200);
    const body = await res.json<any[]>();
    expect(body.length).toBe(2);
  });

  it("gets a single bookmark", async () => {
    const created = await createBookmark({ url: "https://example.com", title: "T" });
    const bk = await created.json<any>();
    const res = await exports.default.fetch(`http://localhost/bookmarks/${bk.id}`, {
      headers: auth,
    });
    expect(res.status).toBe(200);
    expect((await res.json<any>()).title).toBe("T");
  });

  it("returns 404 for missing bookmark", async () => {
    const res = await exports.default.fetch("http://localhost/bookmarks/nonexistent", {
      headers: auth,
    });
    expect(res.status).toBe(404);
  });

  it("updates a bookmark", async () => {
    const created = await createBookmark({ url: "https://example.com", title: "Old" });
    const bk = await created.json<any>();
    const res = await exports.default.fetch(`http://localhost/bookmarks/${bk.id}`, {
      method: "PATCH",
      headers: jsonHeaders,
      body: JSON.stringify({ title: "New", tags: ["a", "b"] }),
    });
    expect(res.status).toBe(200);
    const updated = await res.json<any>();
    expect(updated.title).toBe("New");
    expect(updated.tags).toBe("a,b");
  });

  it("deletes a bookmark", async () => {
    const created = await createBookmark({ url: "https://example.com" });
    const bk = await created.json<any>();
    const res = await exports.default.fetch(`http://localhost/bookmarks/${bk.id}`, {
      method: "DELETE",
      headers: auth,
    });
    expect(res.status).toBe(204);

    const get = await exports.default.fetch(`http://localhost/bookmarks/${bk.id}`, {
      headers: auth,
    });
    expect(get.status).toBe(404);
  });

  // ── Export / Import ──────────────────────────────────────────────────────

  it("exports all bookmarks", async () => {
    await createBookmark({ url: "https://a.com", title: "A" });
    await createBookmark({ url: "https://b.com", title: "B" });
    const res = await exports.default.fetch("http://localhost/bookmarks/export", { headers: auth });
    expect(res.status).toBe(200);
    const body = await res.json<any[]>();
    expect(body.length).toBe(2);
  });

  it("imports bookmarks", async () => {
    const data = [
      {
        id: "id-1",
        url: "https://a.com",
        title: "A",
        tags: "t1",
        created_at: "2024-01-01T00:00:00.000Z",
        updated_at: "2024-01-01T00:00:00.000Z",
      },
      {
        id: "id-2",
        url: "https://b.com",
        title: "B",
        tags: "t2,t3",
        created_at: "2024-01-02T00:00:00.000Z",
        updated_at: "2024-01-02T00:00:00.000Z",
      },
    ];
    const res = await exports.default.fetch("http://localhost/bookmarks/import", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify(data),
    });
    expect(res.status).toBe(200);
    const result = await res.json<any>();
    expect(result.imported).toBe(2);
    expect(result.skipped).toBe(0);
    expect(result.errors.length).toBe(0);

    // Verify they're in the DB
    const list = await exports.default.fetch("http://localhost/bookmarks/export", {
      headers: auth,
    });
    const bookmarks = await list.json<any[]>();
    expect(bookmarks.length).toBe(2);
    expect(bookmarks.find((b: any) => b.id === "id-1").title).toBe("A");
  });

  it("import skips duplicate URLs", async () => {
    await createBookmark({ url: "https://a.com", title: "Existing" });
    const data = [
      { url: "https://a.com", title: "Duplicate" },
      { url: "https://b.com", title: "New" },
    ];
    const res = await exports.default.fetch("http://localhost/bookmarks/import", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify(data),
    });
    const result = await res.json<any>();
    expect(result.imported).toBe(1);
    expect(result.skipped).toBe(1);
  });

  it("import reports validation errors", async () => {
    const data = [{ url: "not-valid" }, { url: "https://good.com", title: "OK" }];
    const res = await exports.default.fetch("http://localhost/bookmarks/import", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify(data),
    });
    const result = await res.json<any>();
    expect(result.imported).toBe(1);
    expect(result.errors.length).toBe(1);
    expect(result.errors[0]).toContain("[0]");
  });

  it("import rejects non-array body", async () => {
    const res = await exports.default.fetch("http://localhost/bookmarks/import", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({ url: "https://a.com" }),
    });
    expect(res.status).toBe(400);
  });

  it("export → import roundtrip preserves data", async () => {
    // Create some bookmarks with varied data
    await createBookmark({ url: "https://x.com", title: "X", tags: "a,b" });
    await createBookmark({ url: "https://y.com", title: "Y", tags: "" });
    await createBookmark({ url: "https://z.com", title: "Z" });

    // Export
    const exportRes = await exports.default.fetch("http://localhost/bookmarks/export", {
      headers: auth,
    });
    const exported = await exportRes.json<any[]>();
    expect(exported.length).toBe(3);

    // Clear DB
    await clearBookmarks();

    // Verify empty
    const empty = await exports.default.fetch("http://localhost/bookmarks/export", {
      headers: auth,
    });
    expect((await empty.json<any[]>()).length).toBe(0);

    // Import the exported data
    const importRes = await exports.default.fetch("http://localhost/bookmarks/import", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify(exported),
    });
    const result = await importRes.json<any>();
    expect(result.imported).toBe(3);

    // Re-export and compare
    const reExportRes = await exports.default.fetch("http://localhost/bookmarks/export", {
      headers: auth,
    });
    const reExported = await reExportRes.json<any[]>();

    // Sort both by id for stable comparison
    const sortById = (arr: any[]) => [...arr].sort((a, b) => a.id.localeCompare(b.id));
    expect(sortById(reExported)).toEqual(sortById(exported));
  });

  // ── FTS ──────────────────────────────────────────────────────────────────

  it("searches bookmarks via FTS", async () => {
    await createBookmark({ url: "https://hono.dev", title: "Hono framework" });
    await createBookmark({ url: "https://react.dev", title: "React docs" });
    const res = await exports.default.fetch("http://localhost/bookmarks?q=hono", { headers: auth });
    const body = await res.json<any[]>();
    expect(body.length).toBe(1);
    expect(body[0].title).toBe("Hono framework");
  });

  // ── Tag filter ───────────────────────────────────────────────────────────

  it("filters by tag", async () => {
    await createBookmark({ url: "https://a.com", tags: "dev,rust" });
    await createBookmark({ url: "https://b.com", tags: "dev,js" });
    await createBookmark({ url: "https://c.com", tags: "design" });
    const res = await exports.default.fetch("http://localhost/bookmarks?tag=dev", {
      headers: auth,
    });
    const body = await res.json<any[]>();
    expect(body.length).toBe(2);
  });

  // ── Pagination ───────────────────────────────────────────────────────────

  it("returns X-Total-Count header", async () => {
    await createBookmark({ url: "https://a.com" });
    await createBookmark({ url: "https://b.com" });
    await createBookmark({ url: "https://c.com" });
    const res = await exports.default.fetch("http://localhost/bookmarks?limit=2", {
      headers: auth,
    });
    const body = await res.json<any[]>();
    expect(body.length).toBe(2);
    expect(res.headers.get("X-Total-Count")).toBe("3");
  });

  it("paginates with offset", async () => {
    await createBookmark({ url: "https://a.com", title: "A" });
    await createBookmark({ url: "https://b.com", title: "B" });
    await createBookmark({ url: "https://c.com", title: "C" });

    const page1 = await exports.default.fetch("http://localhost/bookmarks?limit=2&offset=0", {
      headers: auth,
    });
    const items1 = await page1.json<any[]>();
    expect(items1.length).toBe(2);

    const page2 = await exports.default.fetch("http://localhost/bookmarks?limit=2&offset=2", {
      headers: auth,
    });
    const items2 = await page2.json<any[]>();
    expect(items2.length).toBe(1);

    // No overlap
    const allIds = [...items1, ...items2].map((b: any) => b.id);
    expect(new Set(allIds).size).toBe(3);
  });

  it("deterministic ordering with same created_at", async () => {
    // Import bookmarks with identical timestamps to test id tiebreaker
    const data = [
      {
        id: "aaa",
        url: "https://a.com",
        title: "A",
        created_at: "2024-01-01T00:00:00.000Z",
        updated_at: "2024-01-01T00:00:00.000Z",
      },
      {
        id: "bbb",
        url: "https://b.com",
        title: "B",
        created_at: "2024-01-01T00:00:00.000Z",
        updated_at: "2024-01-01T00:00:00.000Z",
      },
      {
        id: "ccc",
        url: "https://c.com",
        title: "C",
        created_at: "2024-01-01T00:00:00.000Z",
        updated_at: "2024-01-01T00:00:00.000Z",
      },
    ];
    await exports.default.fetch("http://localhost/bookmarks/import", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify(data),
    });

    const res1 = await exports.default.fetch("http://localhost/bookmarks?limit=3", {
      headers: auth,
    });
    const order1 = (await res1.json<any[]>()).map((b: any) => b.id);

    const res2 = await exports.default.fetch("http://localhost/bookmarks?limit=3", {
      headers: auth,
    });
    const order2 = (await res2.json<any[]>()).map((b: any) => b.id);

    expect(order1).toEqual(order2);
  });

  // ── Conditional GET (Last-Modified / If-Modified-Since) ─────────────────

  it("returns Last-Modified header on GET /bookmarks", async () => {
    await createBookmark({ url: "https://a.com" });
    const res = await exports.default.fetch("http://localhost/bookmarks", { headers: auth });
    expect(res.status).toBe(200);
    expect(res.headers.get("Last-Modified")).toBeTruthy();
  });

  it("returns 304 when If-Modified-Since matches Last-Modified", async () => {
    await createBookmark({ url: "https://a.com" });
    const res1 = await exports.default.fetch("http://localhost/bookmarks", { headers: auth });
    const lastModified = res1.headers.get("Last-Modified")!;

    const res2 = await exports.default.fetch("http://localhost/bookmarks", {
      headers: { ...auth, "If-Modified-Since": lastModified },
    });
    expect(res2.status).toBe(304);
  });

  it("returns 200 when data changed after If-Modified-Since", async () => {
    await createBookmark({ url: "https://a.com" });
    // Use a date in the past
    const res = await exports.default.fetch("http://localhost/bookmarks", {
      headers: { ...auth, "If-Modified-Since": "Wed, 01 Jan 2020 00:00:00 GMT" },
    });
    expect(res.status).toBe(200);
  });

  it("does not return Last-Modified when filters are active", async () => {
    await createBookmark({ url: "https://a.com", tags: "dev" });
    const res = await exports.default.fetch("http://localhost/bookmarks?tag=dev", {
      headers: auth,
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("Last-Modified")).toBeNull();
  });

  it("returns Last-Modified header even on empty database", async () => {
    const res = await exports.default.fetch("http://localhost/bookmarks", { headers: auth });
    expect(res.status).toBe(200);
    expect(res.headers.get("Last-Modified")).toBeTruthy();
  });

  it("Last-Modified updates after a delete", async () => {
    const createRes = await createBookmark({ url: "https://delete-test.com" });
    const { id } = (await createRes.json()) as { id: string };

    const beforeDelete = await exports.default.fetch("http://localhost/bookmarks", {
      headers: auth,
    });
    const lmBefore = beforeDelete.headers.get("Last-Modified")!;

    // Small delay to ensure timestamp changes
    await new Promise((r) => setTimeout(r, 1100));

    await exports.default.fetch(`http://localhost/bookmarks/${id}`, {
      method: "DELETE",
      headers: auth,
    });

    const afterDelete = await exports.default.fetch("http://localhost/bookmarks", {
      headers: auth,
    });
    const lmAfter = afterDelete.headers.get("Last-Modified")!;

    expect(new Date(lmAfter).getTime()).toBeGreaterThan(new Date(lmBefore).getTime());
  });
});
