import { expect, it } from "vitest";
import type { Bookmark } from "../src/lib/api";
import { MemoryKV } from "../src/lib/kv";
import { Repository } from "../src/lib/repo.svelte";

const bookmark = (id: string): Bookmark => ({
  id,
  url: `https://example.com/${id}`,
  title: null,
  tags: [],
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
});

it("keeps every concurrent write", async () => {
  const kv = new MemoryKV();
  const repo = await Repository.open(kv);
  await Promise.all(["a", "b", "c"].map((id) => repo.upsert(bookmark(id))));
  expect(repo.bookmarks.map((b) => b.id).sort()).toEqual(["a", "b", "c"]);
  expect((await Repository.open(kv)).bookmarks).toHaveLength(3);
});

it("re-hides rows whose delete is still queued", async () => {
  const repo = await Repository.open(new MemoryKV());
  await repo.addPendingDelete("a");
  await repo.replaceAll([bookmark("a"), bookmark("b")]);
  expect(repo.bookmarks.map((b) => b.id)).toEqual(["b"]);
});

it("doesn't let one tab's stale memory overwrite another tab's write", async () => {
  const kv = new MemoryKV();
  const [a, b] = await Promise.all([Repository.open(kv), Repository.open(kv)]);
  await a.addPending("https://a.test");
  await b.addPending("https://b.test");
  expect((await Repository.open(kv)).pendingAdds.map((p) => p.url)).toEqual([
    "https://a.test",
    "https://b.test",
  ]);
  await Promise.resolve();
  expect(a.pendingAdds).toHaveLength(2);
});

it("forgets a server's data but keeps queued adds and the read count", async () => {
  const repo = await Repository.open(new MemoryKV());
  await repo.upsert(bookmark("a"));
  await repo.addPendingDelete("a");
  await repo.addPending("https://keep.test");
  await repo.setSyncToken('"1"');
  await repo.incrementDeleteCount(3);

  await repo.forgetServer();

  expect(repo.bookmarks).toEqual([]);
  expect(repo.pendingDeletes).toEqual([]);
  expect(repo.syncToken).toBeNull();
  expect(repo.pendingAdds.map((p) => p.url)).toEqual(["https://keep.test"]);
  expect(repo.deleteCount).toBe(3);
});
