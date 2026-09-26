import type { Bookmark } from "./api";
import type { KV } from "./kv";

export type PendingAdd = { url: string; createdAt: string };

type State = {
  bookmarks: Bookmark[];
  pendingAdds: PendingAdd[];
  pendingDeletes: string[];
  syncToken: string | null;
  lastRefreshed: string | null;
  deleteCount: number;
};

const EMPTY: State = {
  bookmarks: [],
  pendingAdds: [],
  pendingDeletes: [],
  syncToken: null,
  lastRefreshed: null,
  deleteCount: 0,
};

class Cell<T> {
  value = $state.raw() as T;

  constructor(value: T) {
    this.value = value;
  }
}

type Cells = { [K in keyof State]: Cell<State[K]> };

/** Local copy of the collection plus the offline queues, held in reactive
 *  memory and written through to a KV store. Reads are synchronous.
 *
 *  Writes are read-modify-writes against the store, so another tab's change
 *  is never overwritten by this tab's stale memory. */
export class Repository {
  #kv: KV;
  #cells: Cells;

  private constructor(kv: KV, cells: Cells) {
    this.#kv = kv;
    this.#cells = cells;
    kv.watch(async (key) => {
      if (!(key in cells)) return;
      const k = key as keyof State;
      this.#cells[k].value = (await kv.get(k)) ?? EMPTY[k];
    });
  }

  static async open(kv: KV): Promise<Repository> {
    const keys = Object.keys(EMPTY) as (keyof State)[];
    const values = await Promise.all(keys.map(async (k) => (await kv.get(k)) ?? EMPTY[k]));
    const cells = Object.fromEntries(keys.map((k, i) => [k, new Cell(values[i])])) as Cells;
    return new Repository(kv, cells);
  }

  async #update<K extends keyof State>(key: K, fn: (current: State[K]) => State[K]): Promise<void> {
    this.#cells[key].value = await this.#kv.update<State[K]>(key, (v) => fn(v ?? EMPTY[key]));
  }

  get bookmarks(): readonly Bookmark[] {
    return this.#cells.bookmarks.value;
  }

  get pendingAdds(): readonly PendingAdd[] {
    return this.#cells.pendingAdds.value;
  }

  get pendingDeletes(): readonly string[] {
    return this.#cells.pendingDeletes.value;
  }

  get syncToken() {
    return this.#cells.syncToken.value;
  }

  get lastRefreshed() {
    return this.#cells.lastRefreshed.value;
  }

  get deleteCount() {
    return this.#cells.deleteCount.value;
  }

  upsert(b: Bookmark) {
    return this.#update("bookmarks", (all) => [b, ...all.filter((x) => x.id !== b.id)]);
  }

  delete(id: string) {
    return this.#update("bookmarks", (all) => all.filter((b) => b.id !== id));
  }

  /** Rows with a queued delete stay hidden: the server just hasn't heard yet. */
  replaceAll(bookmarks: Bookmark[]) {
    return this.#update("bookmarks", () => {
      const doomed = new Set(this.pendingDeletes);
      return bookmarks.filter((b) => !doomed.has(b.id));
    });
  }

  addPending(url: string) {
    return this.#update("pendingAdds", (queue) =>
      queue.some((p) => p.url === url)
        ? queue
        : [...queue, { url, createdAt: new Date().toISOString() }],
    );
  }

  removePending(url: string) {
    return this.#update("pendingAdds", (queue) => queue.filter((p) => p.url !== url));
  }

  addPendingDelete(id: string) {
    return this.#update("pendingDeletes", (queue) => (queue.includes(id) ? queue : [...queue, id]));
  }

  removePendingDelete(id: string) {
    return this.#update("pendingDeletes", (queue) => queue.filter((x) => x !== id));
  }

  setSyncToken(v: string | null) {
    return this.#update("syncToken", () => v);
  }

  setLastRefreshed(v: string | null) {
    return this.#update("lastRefreshed", () => v);
  }

  incrementDeleteCount(n = 1) {
    return this.#update("deleteCount", (count) => count + n);
  }

  resetDeleteCount() {
    return this.#update("deleteCount", () => 0);
  }

  /** Forget everything that belongs to one server. Queued adds are only URLs,
   *  so they carry over rather than being lost; the read counter is local. */
  async forgetServer() {
    await this.#update("pendingDeletes", () => []);
    await this.#update("bookmarks", () => []);
    await this.#update("syncToken", () => null);
    await this.#update("lastRefreshed", () => null);
  }
}
