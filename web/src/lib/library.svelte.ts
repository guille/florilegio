import { SvelteSet } from "svelte/reactivity";
import { type Api, friendlyError } from "./api";
import type { Repository } from "./repo.svelte";
import { type SaveResult, SyncService } from "./sync";
import { toasts } from "./toasts.svelte";
import { plural } from "./url";

/** Background syncs (focus, reconnect) are skipped if one ran this recently. */
const AUTO_SYNC_INTERVAL_MS = 60_000;

/** The collection and everything that changes it: sync, the offline queues,
 *  and the grace period that lets a delete be undone. */
export class Library {
  #repo: Repository;
  #sync: SyncService | null = null;
  /** Settles once the latest connect() has; work waits on it. */
  #connecting: Promise<void> = Promise.resolve();
  #lastSyncAt = 0;
  #bannerTimer: ReturnType<typeof setTimeout> | undefined;
  #inflight: Promise<void> | null = null;
  #manualQueued = false;
  /** Deleted, but still undoable: hidden here, untouched in the repo. */
  #doomed = new SvelteSet<string>();
  #commits = new Set<() => Promise<void>>();

  syncing = $state(false);
  banner = $state<{ message: string; ok: boolean } | null>(null);

  bookmarks = $derived.by(() => {
    const all = this.#repo.bookmarks;
    return this.#doomed.size ? all.filter((b) => !this.#doomed.has(b.id)) : all;
  });
  tagCounts = $derived.by(() => {
    const counts = new Map<string, number>();
    for (const b of this.bookmarks) for (const t of b.tags) counts.set(t, (counts.get(t) ?? 0) + 1);
    return counts;
  });
  allTags = $derived([...this.tagCounts.keys()].sort());
  queued = $derived.by(() => ({
    adds: this.#repo.pendingAdds.length,
    deletes: this.#repo.pendingDeletes.length,
  }));

  constructor(repo: Repository) {
    this.#repo = repo;
  }

  get pendingAdds() {
    return this.#repo.pendingAdds;
  }

  get lastRefreshed() {
    return this.#repo.lastRefreshed;
  }

  get deleteCount() {
    return this.#repo.deleteCount;
  }

  get api() {
    return this.#sync?.api ?? null;
  }

  /** Point at a server, or none. `reset` drops what belonged to the previous
   *  one, once its in-flight work has settled. */
  connect(api: Api | null, { reset = false } = {}): Promise<void> {
    this.#connecting = this.#connect(api, reset);
    return this.#connecting;
  }

  async #connect(api: Api | null, reset: boolean) {
    await this.commitRemovals();
    const old = this.#sync;
    this.#sync = null;
    await old?.idle;
    if (reset) await this.#repo.forgetServer();
    this.#sync = api && new SyncService(this.#repo, api);
    this.#lastSyncAt = 0;
  }

  #showBanner(message: string, ok: boolean) {
    clearTimeout(this.#bannerTimer);
    this.banner = { message, ok };
    if (ok) this.#bannerTimer = setTimeout(() => (this.banner = null), 3000);
  }

  dismissBanner() {
    clearTimeout(this.#bannerTimer);
    this.banner = null;
  }

  /** `manual` syncs report success too; background ones only report failure.
   *  A manual sync asked for mid-sync runs once the current one finishes. */
  async sync({ force = false, manual = false } = {}): Promise<void> {
    await this.#connecting;
    if (!this.#sync) return;
    if (this.#inflight) {
      if (!manual || this.#manualQueued) return;
      this.#manualQueued = true;
      await this.#inflight;
      this.#manualQueued = false;
      return this.sync({ force, manual });
    }
    this.#inflight = this.#runSync(this.#sync, force, manual);
    try {
      await this.#inflight;
    } finally {
      this.#inflight = null;
    }
  }

  async #runSync(sync: SyncService, force: boolean, manual: boolean) {
    this.syncing = true;
    this.#lastSyncAt = Date.now();
    try {
      const result = await sync.sync({ force });
      if (!result.ok) {
        this.#showBanner(`Sync failed: ${friendlyError(result.error)}`, false);
        return;
      }
      if (this.banner && !this.banner.ok) this.dismissBanner();
      if (!manual) return;
      const pushed = result.flushed > 0 ? ` (${plural(result.flushed, "queued item")} pushed)` : "";
      this.#showBanner(
        result.notModified
          ? `Already up to date${pushed}`
          : `Synced ${plural(result.count, "bookmark")}${pushed}`,
        true,
      );
    } finally {
      this.syncing = false;
    }
  }

  syncIfStale() {
    if (Date.now() - this.#lastSyncAt > AUTO_SYNC_INTERVAL_MS) void this.sync();
  }

  async save(url: string): Promise<SaveResult | null> {
    await this.#connecting;
    return this.#sync?.save(url) ?? null;
  }

  /** Resolves false, having said why, if the server refused. */
  async update(id: string, changes: { title?: string | null; tags?: string[] }): Promise<boolean> {
    await this.#connecting;
    if (!this.#sync) return false;
    try {
      await this.#sync.update(id, changes);
      return true;
    } catch (e) {
      toasts.show(`Failed to update: ${friendlyError(e)}`);
      return false;
    }
  }

  /** Only the bookmarks in `changes` are patched, in parallel. */
  async retag(changes: Map<string, string[]>) {
    await this.#connecting;
    const sync = this.#sync;
    if (!sync || changes.size === 0) return;
    const outcomes = await Promise.allSettled(
      [...changes].map(([id, tags]) => sync.update(id, { tags })),
    );
    const failed = outcomes.filter((o) => o.status === "rejected").length;
    const applied = changes.size - failed;
    toasts.show(`Updated ${plural(applied, "bookmark")}${failed ? `, ${failed} failed` : ""}`);
  }

  /** Hide the rows now; they're really deleted once the Undo toast goes away,
   *  or the page does. */
  remove(ids: string[], onundo?: () => void) {
    if (!this.#sync || ids.length === 0) return;
    for (const id of ids) this.#doomed.add(id);
    let settled = false;
    const settle = () => {
      if (settled) return false;
      settled = true;
      this.#commits.delete(commit);
      return true;
    };
    const commit = async () => {
      if (settle()) await this.#delete(ids);
    };
    this.#commits.add(commit);
    toasts.show(`Deleted ${plural(ids.length, "bookmark")}`, {
      action: {
        label: "Undo",
        run: () => {
          if (!settle()) return;
          for (const id of ids) this.#doomed.delete(id);
          onundo?.();
        },
      },
      onexpire: commit,
    });
  }

  async #delete(ids: string[]) {
    try {
      const failures = this.#sync ? (await this.#sync.delete(ids)).failures : null;
      if (failures?.size) {
        toasts.show(
          `Failed to delete ${plural(failures.size, "bookmark")}: ${friendlyError(failures.values().next().value)}`,
        );
      }
    } finally {
      // Deleted rows are gone from the repo by now; failed ones reappear.
      for (const id of ids) this.#doomed.delete(id);
    }
  }

  /** Stop waiting for Undo and delete now. */
  async commitRemovals() {
    await Promise.all([...this.#commits].map((commit) => commit()));
  }

  async resetStats() {
    await this.#repo.resetDeleteCount();
  }
}
