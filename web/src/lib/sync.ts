import { type Api, ApiError, type Bookmark, NetworkError } from "./api";
import type { Repository } from "./repo.svelte";

export type SyncResult =
  | { ok: true; count: number; flushed: number; notModified: boolean }
  | { ok: false; error: unknown; flushed: number };

export type SaveResult =
  | { kind: "remote"; bookmark: Bookmark }
  | { kind: "queued" }
  | { kind: "duplicate"; existingId: string | undefined }
  | { kind: "failed"; error: unknown };

/** Deleted ids are gone locally and queued for the server; failed ones are
 *  still visible. */
export type DeleteResult = { deleted: string[]; failures: Map<string, unknown> };

type Flush = { flushed: number; offline: NetworkError | null };

export class SyncService {
  #repo: Repository;
  #api: Api;
  #tail: Promise<void> | null = null;
  #flushQueued = false;

  constructor(repo: Repository, api: Api) {
    this.#repo = repo;
    this.#api = api;
  }

  get api(): Api {
    return this.#api;
  }

  /** One queue-mutating pass (a sync or a delete flush) runs at a time:
   *  replaceAll must never interleave with removePendingDelete, or an
   *  in-flight fetch can resurrect a just-flushed delete. Saves touch neither
   *  and are deliberately not serialized.
   *
   *  Callers append rather than join, so a delete queued mid-pass is picked up
   *  by the next pass. Never call from inside a pass: it would deadlock. */
  #serial<T>(body: () => Promise<T>): Promise<T> {
    const result = this.#tail ? this.#tail.then(body) : body();
    this.#tail = result.then(
      () => {},
      () => {},
    );
    return result;
  }

  /** Settles once every pass queued so far has drained. */
  get idle(): Promise<void> {
    return this.#tail ?? Promise.resolve();
  }

  /** Coalesces with a flush that's queued but not yet started: that one reads
   *  the queue after this caller's write, so nothing is dropped. */
  #kickFlush() {
    if (this.#flushQueued) return;
    this.#flushQueued = true;
    void this.#serial(() => {
      this.#flushQueued = false;
      return this.#flushDeletes();
    });
  }

  /** Flush queued deletes, then queued adds, then fetch the collection.
   *  `force` skips the conditional GET. */
  sync({ force = false } = {}): Promise<SyncResult> {
    return this.#serial(() => this.#sync(force));
  }

  async #sync(force: boolean): Promise<SyncResult> {
    // Deletes before adds: a delete-then-re-add of the same URL must reach the
    // server in that order, or the add 409s against the doomed bookmark.
    const deletes = await this.#flushDeletes();
    // An unreachable server would make every add pay the same timeout.
    const adds = deletes.offline ? { flushed: 0, offline: null } : await this.#flushAdds();
    const flushed = deletes.flushed + adds.flushed;

    // The server changed under us, so the cached validator is stale.
    if (flushed > 0) await this.#repo.setSyncToken(null);

    const offline = deletes.offline ?? adds.offline;
    if (offline) return { ok: false, error: offline, flushed };

    try {
      const result = await this.#api.listAll(force ? null : this.#repo.syncToken);
      if (result) {
        await this.#repo.replaceAll(result.bookmarks);
        await this.#repo.setSyncToken(result.syncToken);
      }
      await this.#repo.setLastRefreshed(new Date().toISOString());
      return { ok: true, count: result?.bookmarks.length ?? 0, flushed, notModified: !result };
    } catch (error) {
      return { ok: false, error, flushed };
    }
  }

  async #flushAdds(): Promise<Flush> {
    let flushed = 0;
    for (const { url } of this.#repo.pendingAdds) {
      try {
        const result = await this.#api.create(url);
        // A 409 with a delete still queued may be the very bookmark that delete
        // hasn't removed yet; dropping the add now would lose it.
        if ("existingId" in result && this.#repo.pendingDeletes.length > 0) continue;
        await this.#repo.removePending(url);
        flushed++;
      } catch (e) {
        if (e instanceof NetworkError) return { flushed, offline: e };
        // Other API errors stay queued for the next sync. Anything else is a
        // local failure: stop rather than churn through the rest.
        if (!(e instanceof ApiError)) break;
      }
    }
    return { flushed, offline: null };
  }

  /** The delete counter was already bumped at queue time. */
  async #flushDeletes(): Promise<Flush> {
    let flushed = 0;
    for (const id of this.#repo.pendingDeletes) {
      try {
        await this.#api.delete(id).catch((e) => {
          // Already gone on the server.
          if (!(e instanceof ApiError && e.status === 404)) throw e;
        });
        await this.#repo.removePendingDelete(id);
        flushed++;
      } catch (e) {
        if (e instanceof NetworkError) return { flushed, offline: e };
        if (!(e instanceof ApiError)) break;
      }
    }
    return { flushed, offline: null };
  }

  /** Try the server first, queueing locally if it can't be reached.
   *  Never throws. */
  async save(url: string): Promise<SaveResult> {
    try {
      const result = await this.#api.create(url);
      if ("existingId" in result) return { kind: "duplicate", existingId: result.existingId };
      await this.#repo.upsert(result.created);
      return { kind: "remote", bookmark: result.created };
    } catch {
      try {
        await this.#repo.addPending(url);
        return { kind: "queued" };
      } catch (error) {
        return { kind: "failed", error };
      }
    }
  }

  async update(id: string, changes: { title?: string | null; tags?: string[] }): Promise<Bookmark> {
    const bookmark = await this.#api.update(id, changes);
    await this.#repo.upsert(bookmark);
    return bookmark;
  }

  /** Hide the rows and persist the deletes now; the server hears about them
   *  in the background. Never throws. */
  async delete(ids: Iterable<string>): Promise<DeleteResult> {
    const deleted: string[] = [];
    const failures = new Map<string, unknown>();
    for (const id of ids) {
      try {
        // Enqueue first: if that fails the row must stay, not vanish unsynced.
        await this.#repo.addPendingDelete(id);
        await this.#repo.delete(id);
        deleted.push(id);
      } catch (e) {
        failures.set(id, e);
      }
    }
    if (deleted.length === 0) return { deleted, failures };
    // The rows are gone and queued; a lost stat bump isn't worth failing over.
    await this.#repo.incrementDeleteCount(deleted.length).catch(() => {});
    this.#kickFlush();
    return { deleted, failures };
  }
}
