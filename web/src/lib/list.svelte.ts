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
/** Typing pauses this long before the list is filtered. */
const SEARCH_DEBOUNCE_MS = 120;

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
  #searchTimer: ReturnType<typeof setTimeout> | undefined;
  /** Anchor for shift-click range selection. */
  #anchor: string | null = null;

  #query = $state("");
  /** What the list is filtered and highlighted by: `query`, once typing pauses. */
  search = $state("");
  tag = $state<string | null>(null);
  sort = $state<SortOrder>("newest");
  /** Shuffle order, drawn afresh each time Random is picked. */
  #ranks = $state.raw(new Map<string, number>());
  /** Replaced, never mutated: a SvelteSet wakes every row on each add. */
  selected = $state.raw<ReadonlySet<string>>(new Set());
  /** Bookmark to scroll to and flash, e.g. the one a duplicate save hit. */
  highlight = $state<string | null>(null);

  #q = $derived(this.search.trim().toLowerCase());

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

  /** What's typed in the search box. Clearing it applies at once. */
  get query() {
    return this.#query;
  }

  set query(value: string) {
    this.#query = value;
    clearTimeout(this.#searchTimer);
    if (value.trim()) this.#searchTimer = setTimeout(() => this.applySearch(), SEARCH_DEBOUNCE_MS);
    else this.applySearch();
  }

  applySearch() {
    clearTimeout(this.#searchTimer);
    this.search = this.#query;
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
    const span =
      range && from !== -1 ? ids.slice(Math.min(from, to), Math.max(from, to) + 1) : [id];
    const next = new Set(this.selected);
    const on = !next.has(id);
    for (const i of span) {
      if (on) next.add(i);
      else next.delete(i);
    }
    this.selected = next;
    this.#anchor = id;
  }

  selectAll() {
    this.selected = new Set([...this.selected, ...this.visible.map((b) => b.id)]);
  }

  clearSelection() {
    this.selected = new Set();
  }

  remove(ids: string[], onundo?: () => void) {
    this.selected = this.selected.difference(new Set(ids));
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
