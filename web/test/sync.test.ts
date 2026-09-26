import { describe, expect, it } from "vitest";
import { type Api, ApiError, type Bookmark, NetworkError } from "../src/lib/api";
import { MemoryKV } from "../src/lib/kv";
import { Repository } from "../src/lib/repo.svelte";
import { SyncService } from "../src/lib/sync";

const bookmark = (id: string, url = `https://example.com/${id}`): Bookmark => ({
  id,
  url,
  title: null,
  tags: [],
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
});

/** A server holding `rows`, recording every call. Methods can be swapped out
 *  per test to inject failures or latency. */
function fakeApi(rows: Bookmark[] = []) {
  const server = { rows: [...rows], version: 1 };
  const calls: string[] = [];
  const api = {
    async listAll(ifNoneMatch?: string | null) {
      calls.push(`list ${ifNoneMatch ?? "-"}`);
      const etag = `"${server.version}"`;
      if (ifNoneMatch === etag) return null;
      return { bookmarks: [...server.rows], syncToken: etag };
    },
    async create(url: string) {
      calls.push(`create ${url}`);
      const existing = server.rows.find((b) => b.url === url);
      if (existing) return { existingId: existing.id };
      const created = bookmark(`new-${server.rows.length}`, url);
      server.rows.unshift(created);
      server.version++;
      return { created };
    },
    async update(id: string, changes: { title?: string | null; tags?: string[] }) {
      calls.push(`update ${id}`);
      const b = server.rows.find((x) => x.id === id);
      if (!b) throw new ApiError(404, "Bookmark not found");
      Object.assign(b, changes);
      server.version++;
      return { ...b };
    },
    async delete(id: string) {
      calls.push(`delete ${id}`);
      const before = server.rows.length;
      server.rows = server.rows.filter((b) => b.id !== id);
      if (server.rows.length === before) throw new ApiError(404, "Bookmark not found");
      server.version++;
    },
    ping: async () => {},
    exportAll: async () => [],
    importAll: async () => ({ imported: 0, skipped: 0, errors: [] }),
    favicon: async () => null,
  } satisfies Api;
  return { api, server, calls };
}

async function setup(rows: Bookmark[] = []) {
  const repo = await Repository.open(new MemoryKV());
  const fake = fakeApi(rows);
  return { repo, sync: new SyncService(repo, fake.api), ...fake };
}

const offline = () => Promise.reject(new NetworkError("offline"));

describe("sync", () => {
  it("replaces local data, then revalidates with the stored ETag", async () => {
    const { repo, sync, calls } = await setup([bookmark("a"), bookmark("b")]);

    expect(await sync.sync()).toMatchObject({ ok: true, count: 2, notModified: false });
    expect(repo.bookmarks.map((b) => b.id)).toEqual(["a", "b"]);
    expect(repo.lastRefreshed).not.toBeNull();

    expect(await sync.sync()).toMatchObject({ ok: true, notModified: true });
    expect(calls).toEqual(["list -", 'list "1"']);
  });

  it("skips the conditional GET when forced", async () => {
    const { sync, calls } = await setup([bookmark("a")]);
    await sync.sync();
    await sync.sync({ force: true });
    expect(calls).toEqual(["list -", "list -"]);
  });

  it("flushes deletes before adds, and drops the stale validator", async () => {
    const { repo, sync, calls } = await setup([bookmark("a", "https://same.test")]);
    await sync.sync();
    await repo.addPendingDelete("a");
    await repo.addPending("https://same.test");

    const result = await sync.sync();

    expect(result).toMatchObject({ ok: true, flushed: 2 });
    expect(calls.slice(1)).toEqual(["delete a", "create https://same.test", "list -"]);
    expect(repo.pendingAdds).toEqual([]);
    expect(repo.pendingDeletes).toEqual([]);
  });

  it("keeps a 409'd add queued while a delete is still pending", async () => {
    const { repo, sync, api } = await setup([bookmark("a", "https://same.test")]);
    api.delete = () => Promise.reject(new ApiError(500, "boom"));
    await repo.addPendingDelete("a");
    await repo.addPending("https://same.test");

    await sync.sync();

    expect(repo.pendingAdds.map((p) => p.url)).toEqual(["https://same.test"]);
    expect(repo.pendingDeletes).toEqual(["a"]);
  });

  it("treats a 404 on delete as already done", async () => {
    const { repo, sync } = await setup();
    await repo.addPendingDelete("ghost");
    expect(await sync.sync()).toMatchObject({ ok: true, flushed: 1 });
    expect(repo.pendingDeletes).toEqual([]);
  });

  it("stops at the first sign the server is unreachable", async () => {
    const { repo, sync, api, calls } = await setup();
    api.delete = offline;
    await repo.addPendingDelete("a");
    await repo.addPending("https://x.test");

    const result = await sync.sync();

    expect(result.ok).toBe(false);
    expect(!result.ok && result.error).toBeInstanceOf(NetworkError);
    expect(calls).toEqual([]);
    expect(repo.pendingAdds).toHaveLength(1);
  });

  it("doesn't resurrect a bookmark deleted while a fetch is in flight", async () => {
    const { repo, sync, api } = await setup([bookmark("a"), bookmark("b")]);
    const list = api.listAll;
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    api.listAll = async (etag) => {
      const snapshot = await list(etag);
      await gate;
      return snapshot;
    };

    const syncing = sync.sync();
    await new Promise((r) => setTimeout(r));
    await sync.delete(["a"]);
    release();
    await syncing;
    await sync.idle;

    expect(repo.bookmarks.map((b) => b.id)).toEqual(["b"]);
    expect(repo.pendingDeletes).toEqual([]);
  });
});

describe("save", () => {
  it("stores what the server created", async () => {
    const { repo, sync } = await setup();
    const result = await sync.save("https://new.test");
    expect(result.kind).toBe("remote");
    expect(repo.bookmarks.map((b) => b.url)).toEqual(["https://new.test"]);
  });

  it("reports duplicates without queueing them", async () => {
    const { repo, sync } = await setup([bookmark("a", "https://dup.test")]);
    expect(await sync.save("https://dup.test")).toEqual({ kind: "duplicate", existingId: "a" });
    expect(repo.pendingAdds).toEqual([]);
  });

  it("queues locally when offline, once per URL", async () => {
    const { repo, sync, api } = await setup();
    api.create = offline;
    expect((await sync.save("https://later.test")).kind).toBe("queued");
    await sync.save("https://later.test");
    expect(repo.pendingAdds.map((p) => p.url)).toEqual(["https://later.test"]);
  });
});

describe("delete", () => {
  it("hides rows at once, counts them, and flushes in the background", async () => {
    const { repo, sync, server } = await setup([bookmark("a"), bookmark("b"), bookmark("c")]);
    await sync.sync();

    const result = await sync.delete(["a", "b"]);

    expect(result.deleted).toEqual(["a", "b"]);
    expect(repo.bookmarks.map((b) => b.id)).toEqual(["c"]);
    expect(repo.deleteCount).toBe(2);
    await sync.idle;
    expect(server.rows.map((b) => b.id)).toEqual(["c"]);
    expect(repo.pendingDeletes).toEqual([]);
  });

  it("keeps deletes queued while offline", async () => {
    const { repo, sync, api } = await setup([bookmark("a")]);
    await sync.sync();
    api.delete = offline;
    await sync.delete(["a"]);
    await sync.idle;
    expect(repo.bookmarks).toEqual([]);
    expect(repo.pendingDeletes).toEqual(["a"]);
  });
});
