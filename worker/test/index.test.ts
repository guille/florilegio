import { env, exports } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import "../src/index";

const TOKEN = "test-token";
const auth = { Authorization: `Bearer ${TOKEN}` };
const jsonHeaders = { ...auth, "Content-Type": "application/json" };

// Schema comes from the real migrations/, applied once in test/apply-migrations.ts.

async function clearBookmarks() {
  // The FTS and version triggers fire on delete, keeping both consistent
  await env.DB.exec("DELETE FROM bookmarks");
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
  beforeEach(clearBookmarks);

  // ── Schema ───────────────────────────────────────────────────────────────
  //
  // The schema under test comes from migrations/, so these assert the migration
  // chain actually lands where we think it does.

  it("applied every migration", async () => {
    const { results } = await env.DB.prepare(
      "SELECT name FROM d1_migrations ORDER BY name",
    ).all<{ name: string }>();

    expect(results.map((r) => r.name)).toEqual([
      "001_create_schema.sql",
      "002_drop_is_read.sql",
      "003_sync_metadata.sql",
      "004_drop_fts_id_column.sql",
      "005_version_counter.sql",
      "006_created_at_id_index.sql",
    ]);
  });

  it("migrated to the expected final schema", async () => {
    const { results } = await env.DB.prepare(
      // Excluded: sqlite internals, D1's own bookkeeping, and the FTS shadow tables
      "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' AND name NOT LIKE 'bookmarks_fts_%' AND name != 'd1_migrations' ORDER BY type, name",
    ).all<{ type: string; name: string }>();

    expect(results).toEqual([
      { type: "index", name: "idx_bookmarks_created_at" },
      { type: "table", name: "bookmarks" },
      { type: "table", name: "bookmarks_fts" },
      { type: "table", name: "bookmarks_state" },
      { type: "trigger", name: "bookmarks_ad" },
      { type: "trigger", name: "bookmarks_ai" },
      { type: "trigger", name: "bookmarks_au" },
      { type: "trigger", name: "bookmarks_version_ad" },
      { type: "trigger", name: "bookmarks_version_ai" },
      { type: "trigger", name: "bookmarks_version_au" },
    ]);
  });

  it("dropped what later migrations remove", async () => {
    // 002 dropped is_read, 005 replaced sync_metadata with the version counter
    const cols = await env.DB.prepare("SELECT name FROM pragma_table_info('bookmarks')").all<{
      name: string;
    }>();
    expect(cols.results.map((c) => c.name)).not.toContain("is_read");

    const dropped = await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE name IN ('sync_metadata', 'idx_bookmarks_is_read')",
    ).all();
    expect(dropped.results).toEqual([]);
  });

  it("indexes created_at and id so the list ORDER BY needs no sort", async () => {
    const { results } = await env.DB.prepare(
      "EXPLAIN QUERY PLAN SELECT * FROM bookmarks ORDER BY created_at DESC, id ASC LIMIT 200",
    ).all<{ detail: string }>();

    const plan = results.map((r) => r.detail).join(" | ");
    expect(plan).toContain("USING INDEX idx_bookmarks_created_at");
    expect(plan).not.toContain("TEMP B-TREE");
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

  it("import normalizes timestamps and falls back on unparseable ones", async () => {
    const data = [
      { id: "ok", url: "https://ok.com", created_at: "2024-03-05T06:07:08Z" },
      { id: "loose", url: "https://loose.com", created_at: "Tue, 05 Mar 2024 06:07:08 GMT" },
      { id: "junk", url: "https://junk.com", created_at: "whenever" },
    ];
    await exports.default.fetch("http://localhost/bookmarks/import", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify(data),
    });

    const res = await exports.default.fetch("http://localhost/bookmarks/export", { headers: auth });
    const byId = Object.fromEntries((await res.json<any[]>()).map((b) => [b.id, b]));

    expect(byId.ok.created_at).toBe("2024-03-05T06:07:08.000Z");
    expect(byId.loose.created_at).toBe("2024-03-05T06:07:08.000Z");
    // Unparseable falls back to now, same as a missing field
    expect(Date.parse(byId.junk.created_at)).not.toBeNaN();
    expect(byId.junk.created_at).not.toBe("whenever");
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

  it("finds imported bookmarks via FTS", async () => {
    const importRes = await exports.default.fetch("http://localhost/bookmarks/import", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify([{ url: "https://hono.dev", title: "Hono framework" }]),
    });
    expect(importRes.status).toBe(200);
    const res = await exports.default.fetch("http://localhost/bookmarks?q=hono", { headers: auth });
    const body = await res.json<any[]>();
    expect(body.length).toBe(1);
    expect(body[0].title).toBe("Hono framework");
  });

  it("combines FTS search with tag filter", async () => {
    await createBookmark({ url: "https://hono.dev", title: "Hono framework", tags: "js,web" });
    await createBookmark({ url: "https://hono.dev/docs", title: "Hono docs", tags: "docs" });
    await createBookmark({ url: "https://react.dev", title: "React docs", tags: "js,web" });
    const res = await exports.default.fetch("http://localhost/bookmarks?q=hono&tag=js", {
      headers: auth,
    });
    const body = await res.json<any[]>();
    expect(body.length).toBe(1);
    expect(body[0].url).toBe("https://hono.dev/");
    expect(res.headers.get("X-Total-Count")).toBe("1");
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

  it("treats LIKE metacharacters in ?tag= literally", async () => {
    await createBookmark({ url: "https://a.com", tags: "dev,rust" });
    await createBookmark({ url: "https://b.com", tags: "design" });
    await createBookmark({ url: "https://c.com", tags: "news" });

    for (const tag of ["%", "de_", "d%v", "_ev"]) {
      const res = await exports.default.fetch(
        `http://localhost/bookmarks?tag=${encodeURIComponent(tag)}`,
        { headers: auth },
      );
      expect(await res.json<any[]>()).toHaveLength(0);
      expect(res.headers.get("X-Total-Count")).toBe("0");
    }
  });

  it("tag filter is case-insensitive", async () => {
    await createBookmark({ url: "https://a.com", tags: "DevOps,rust" });
    const res = await exports.default.fetch("http://localhost/bookmarks?tag=devops", {
      headers: auth,
    });
    expect(await res.json<any[]>()).toHaveLength(1);
  });

  it("tag filter combined with q treats metacharacters literally", async () => {
    await createBookmark({ url: "https://hono.dev", title: "Hono framework", tags: "js,web" });
    const res = await exports.default.fetch("http://localhost/bookmarks?q=hono&tag=%25", {
      headers: auth,
    });
    expect(await res.json<any[]>()).toHaveLength(0);
    expect(res.headers.get("X-Total-Count")).toBe("0");
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

  // ── CORS ─────────────────────────────────────────────────────────────────

  it("exposes ETag to browser clients", async () => {
    // ETag is not CORS-safelisted (unlike Last-Modified), so without this the
    // web build reads null and silently stops sending If-None-Match.
    const res = await exports.default.fetch("http://localhost/bookmarks", {
      headers: { ...auth, Origin: "https://example.com" },
    });
    expect(res.headers.get("Access-Control-Expose-Headers")).toContain("ETag");
  });

  it("allows If-None-Match through preflight", async () => {
    const res = await exports.default.fetch("http://localhost/bookmarks", {
      method: "OPTIONS",
      headers: {
        Origin: "https://example.com",
        "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "authorization,if-none-match",
      },
    });
    expect(res.headers.get("Access-Control-Allow-Headers")?.toLowerCase()).toContain(
      "if-none-match",
    );
  });

  // ── Conditional GET (ETag / If-None-Match) ──────────────────────────────

  const listEtag = async (path = "/bookmarks") => {
    const res = await exports.default.fetch(`http://localhost${path}`, { headers: auth });
    expect(res.status).toBe(200);
    return res.headers.get("ETag")!;
  };

  it("returns an ETag on GET /bookmarks", async () => {
    await createBookmark({ url: "https://a.com" });
    expect(await listEtag()).toMatch(/^"\d+"$/);
  });

  it("returns an ETag even on an empty database", async () => {
    expect(await listEtag()).toMatch(/^"\d+"$/);
  });

  it("returns 304 when If-None-Match matches", async () => {
    await createBookmark({ url: "https://a.com" });
    const etag = await listEtag();

    const res = await exports.default.fetch("http://localhost/bookmarks", {
      headers: { ...auth, "If-None-Match": etag },
    });
    expect(res.status).toBe(304);
    // RFC 9110: a 304 still carries the ETag it would have sent with a 200
    expect(res.headers.get("ETag")).toBe(etag);
    expect(await res.text()).toBe("");
  });

  it("returns 200 when If-None-Match is stale", async () => {
    await createBookmark({ url: "https://a.com" });
    const res = await exports.default.fetch("http://localhost/bookmarks", {
      headers: { ...auth, "If-None-Match": '"0"' },
    });
    expect(res.status).toBe(200);
  });

  it("honours weak comparison, lists, and *", async () => {
    await createBookmark({ url: "https://a.com" });
    const etag = await listEtag();

    for (const header of [`W/${etag}`, `"0", ${etag}`, "*"]) {
      const res = await exports.default.fetch("http://localhost/bookmarks", {
        headers: { ...auth, "If-None-Match": header },
      });
      expect(res.status, `If-None-Match: ${header}`).toBe(304);
    }
  });

  it("serves conditional GET for filtered requests too", async () => {
    await createBookmark({ url: "https://hono.dev", title: "Hono", tags: "dev" });

    for (const path of ["/bookmarks?tag=dev", "/bookmarks?q=hono"]) {
      const etag = await listEtag(path);
      const res = await exports.default.fetch(`http://localhost${path}`, {
        headers: { ...auth, "If-None-Match": etag },
      });
      expect(res.status, path).toBe(304);
    }
  });

  it("ETag advances on insert, update and delete", async () => {
    const created = await createBookmark({ url: "https://a.com" });
    const { id } = await created.json<{ id: string }>();
    const afterInsert = await listEtag();

    await exports.default.fetch(`http://localhost/bookmarks/${id}`, {
      method: "PATCH",
      headers: jsonHeaders,
      body: JSON.stringify({ title: "New" }),
    });
    const afterUpdate = await listEtag();
    expect(afterUpdate).not.toBe(afterInsert);

    await exports.default.fetch(`http://localhost/bookmarks/${id}`, {
      method: "DELETE",
      headers: auth,
    });
    const afterDelete = await listEtag();
    expect(afterDelete).not.toBe(afterUpdate);
  });

  // This is the regression the counter exists for: with a second-resolution
  // Last-Modified, two writes in the same second bracketing a read left the
  // client revalidating against a validator that never advanced.
  it("does not lose an update made in the same second as the read", async () => {
    await createBookmark({ url: "https://first.example" });
    const etag = await listEtag();

    // No delay: this lands in the same wall-clock second as the read above.
    await createBookmark({ url: "https://second.example" });

    const res = await exports.default.fetch("http://localhost/bookmarks", {
      headers: { ...auth, "If-None-Match": etag },
    });
    expect(res.status).toBe(200);
    expect(await res.json<any[]>()).toHaveLength(2);
  });
});

describe("Favicon proxy", () => {
  // Tests share the worker's isolate, so stubbing global fetch intercepts the
  // route's upstream call. Binding calls (exports.default.fetch, D1) bypass it.
  // Takes a factory: the Response must be created inside the handler's request
  // context, or workerd rejects reading its body from "a different request".
  function stubUpstream(makeResponse: () => Response) {
    const stub = vi.fn(async () => makeResponse());
    vi.stubGlobal("fetch", stub);
    return stub;
  }

  afterEach(() => vi.unstubAllGlobals());

  it("rejects requests without auth", async () => {
    const res = await exports.default.fetch("http://localhost/favicon/github.com");
    expect(res.status).toBe(401);
  });

  it("rejects invalid hostnames", async () => {
    for (const host of ["not a host", "-leading.dash", "trailing.dash-", "a..b"]) {
      const res = await exports.default.fetch(
        `http://localhost/favicon/${encodeURIComponent(host)}`,
        { headers: auth },
      );
      expect(res.status).toBe(400);
    }
  });

  it("rejects encoded path traversal", async () => {
    // Bare %2e%2e is a dot segment: URL parsing collapses it before routing.
    // Embedded in a longer segment it survives, and the router decodes it to
    // ../etc before the hostname check sees it.
    const res = await exports.default.fetch("http://localhost/favicon/%2e%2e%2fetc", {
      headers: auth,
    });
    expect(res.status).toBe(400);
  });

  it("proxies the upstream icon", async () => {
    const stub = stubUpstream(
      () => new Response("icon-bytes", { headers: { "Content-Type": "image/png" } }),
    );

    const res = await exports.default.fetch("http://localhost/favicon/GitHub.com", {
      headers: auth,
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("image/png");
    expect(res.headers.get("Cache-Control")).toContain("max-age");
    // arrayBuffer, not text(): workerd warns about .text() on an image body
    expect(new TextDecoder().decode(await res.arrayBuffer())).toBe("icon-bytes");
    // Host is lowercased before hitting the upstream
    expect(stub).toHaveBeenCalledWith(
      expect.stringContaining("url=https://github.com&"),
      expect.anything(),
    );
  });

  it("maps upstream failure to 404", async () => {
    stubUpstream(() => new Response("bad gateway", { status: 502 }));

    const res = await exports.default.fetch("http://localhost/favicon/unknown.example", {
      headers: auth,
    });
    expect(res.status).toBe(404);
  });
});
