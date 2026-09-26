import { SvelteSet } from "svelte/reactivity";
import { type Bookmark, friendlyError } from "./api";
import type { Library } from "./library.svelte";
import { toasts } from "./toasts.svelte";
import { hostOf } from "./url";

export type SortOrder = "newest" | "oldest" | "random" | "host";

export const SORT_LABELS: Record<SortOrder, string> = {
  newest: "Newest first",
  oldest: "Oldest first",
  random: "Random",
  host: "By site",
};

const REVEAL_MS = 1600;

function matches(b: Bookmark, q: string): boolean {
  return (
    (b.title?.toLowerCase().includes(q) ?? false) ||
    b.url.toLowerCase().includes(q) ||
    b.tags.some((t) => t.toLowerCase().includes(q))
  );
}

/** How the list is being looked at: filters, order, selection. Outlives the
 *  list view, so a trip to Settings keeps it. */
export class ListState {
  #library: Library;
  #revealTimer: ReturnType<typeof setTimeout> | undefined;
  /** Anchor for shift-click range selection. */
  #anchor: string | null = null;

  query = $state("");
  tag = $state<string | null>(null);
  sort = $state<SortOrder>("newest");
  /** Shuffle order, drawn afresh each time Random is picked. */
  #ranks = $state.raw(new Map<string, number>());
  selected = new SvelteSet<string>();
  /** Bookmark to scroll to and flash, e.g. the one a duplicate save hit. */
  highlight = $state<string | null>(null);

  #q = $derived(this.query.trim().toLowerCase());

  visible = $derived.by(() => {
    const q = this.#q;
    const tag = this.tag?.toLowerCase();
    const rows = this.#library.bookmarks.filter(
      (b) => (!q || matches(b, q)) && (!tag || b.tags.some((t) => t.toLowerCase() === tag)),
    );
    const byDate = (a: Bookmark, b: Bookmark) => a.createdAt.localeCompare(b.createdAt);
    switch (this.sort) {
      case "newest":
        return rows.sort((a, b) => byDate(b, a));
      case "oldest":
        return rows.sort(byDate);
      case "host": {
        const host = new Map(rows.map((b) => [b.id, hostOf(b.url)]));
        return rows.sort((a, b) => host.get(a.id)!.localeCompare(host.get(b.id)!) || byDate(a, b));
      }
      case "random":
        return rows.sort((a, b) => (this.#ranks.get(a.id) ?? 0) - (this.#ranks.get(b.id) ?? 0));
    }
  });

  /** Saved offline, not yet on the server. Untagged, so a tag filter hides them. */
  pending = $derived.by(() =>
    this.tag
      ? []
      : this.#library.pendingAdds.filter((p) => !this.#q || p.url.toLowerCase().includes(this.#q)),
  );

  /** The selected bookmarks that still exist. */
  selection = $derived.by(() => this.#library.bookmarks.filter((b) => this.selected.has(b.id)));

  hasFilters = $derived(this.#q !== "" || this.tag !== null);

  constructor(library: Library) {
    this.#library = library;
  }

  setSort(order: SortOrder) {
    if (order === "random") {
      this.#ranks = new Map(this.#library.bookmarks.map((b) => [b.id, Math.random()]));
    }
    this.sort = order;
  }

  clearFilters() {
    this.query = "";
    this.tag = null;
  }

  toggleTag(tag: string) {
    this.tag = this.tag === tag ? null : tag;
  }

  reveal(id: string) {
    this.clearFilters();
    this.highlight = id;
    clearTimeout(this.#revealTimer);
    this.#revealTimer = setTimeout(() => (this.highlight = null), REVEAL_MS);
  }

  toggle(id: string, range = false) {
    const ids = this.visible.map((b) => b.id);
    const [from, to] = [ids.indexOf(this.#anchor ?? ""), ids.indexOf(id)];
    if (range && from !== -1) {
      const on = !this.selected.has(id);
      for (const i of ids.slice(Math.min(from, to), Math.max(from, to) + 1)) {
        if (on) this.selected.add(i);
        else this.selected.delete(i);
      }
    } else if (this.selected.has(id)) {
      this.selected.delete(id);
    } else {
      this.selected.add(id);
    }
    this.#anchor = id;
  }

  selectAll() {
    for (const b of this.visible) this.selected.add(b.id);
  }

  remove(ids: string[], onundo?: () => void) {
    for (const id of ids) this.selected.delete(id);
    this.#library.remove(ids, onundo);
  }

  async save(url: string) {
    const result = await this.#library.save(url);
    switch (result?.kind) {
      case "remote":
        this.reveal(result.bookmark.id);
        toasts.show("Bookmark saved");
        break;
      case "queued":
        this.clearFilters();
        toasts.show("Saved locally — will sync when online");
        break;
      case "duplicate": {
        const id = result.existingId;
        const known = id && this.#library.bookmarks.some((b) => b.id === id);
        toasts.show(
          "Already bookmarked",
          known ? { action: { label: "Show", run: () => this.reveal(id) } } : {},
        );
        break;
      }
      case "failed":
        toasts.show(`Failed to save: ${friendlyError(result.error)}`);
    }
  }
}
