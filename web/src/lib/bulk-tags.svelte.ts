import { SvelteMap, SvelteSet } from "svelte/reactivity";

/** How a tag sits across the selection: on every item, or on some. */
export type TagState = "all" | "some";

type TagAction = "add" | "remove";

/** Tri-state tag editing across several items. Tracks the user's edits and
 *  produces each item's resulting tag list. */
export class BulkTagEditor {
  #active = new SvelteMap<string, TagState>();
  #suggestions = new SvelteSet<string>();
  #actions = new SvelteMap<string, TagAction>();
  #original: Map<string, Set<string>>;
  /** Removed tags only return to suggestions if they exist in the library, so
   *  undoing a brand-new typed tag doesn't fabricate a suggestion. */
  #library: Set<string>;

  constructor(selected: Map<string, Set<string>>, libraryTags: Iterable<string>) {
    const counts = new Map<string, number>();
    for (const tags of selected.values()) {
      for (const tag of tags) counts.set(tag, (counts.get(tag) ?? 0) + 1);
    }
    for (const [tag, n] of counts) this.#active.set(tag, n === selected.size ? "all" : "some");
    this.#library = new Set([...libraryTags, ...counts.keys()]);
    for (const tag of this.#library) if (!counts.has(tag)) this.#suggestions.add(tag);
    this.#original = selected;
  }

  get active(): ReadonlyMap<string, TagState> {
    return this.#active;
  }

  get suggestions(): ReadonlySet<string> {
    return this.#suggestions;
  }

  get hasChanges(): boolean {
    return this.#actions.size > 0;
  }

  /** all → removed; some → all; a tag the user added → removed. */
  toggle(tag: string): void {
    const state = this.#active.get(tag);
    if (!state) return;
    if (this.#actions.get(tag) === "add" || state === "all") {
      this.#actions.set(tag, "remove");
      this.#active.delete(tag);
      if (this.#library.has(tag)) this.#suggestions.add(tag);
    } else {
      this.#actions.set(tag, "add");
      this.#active.set(tag, "all");
    }
  }

  /** Add `tag` to every item, whether it's a suggestion or brand new. Returns
   *  false if it's already active. */
  add(tag: string): boolean {
    if (this.#active.has(tag)) return false;
    this.#suggestions.delete(tag);
    this.#active.set(tag, "all");
    this.#actions.set(tag, "add");
    return true;
  }

  /** Each item's new tag list, only for items whose tags actually change. */
  changes(): Map<string, string[]> {
    const out = new Map<string, string[]>();
    for (const [id, original] of this.#original) {
      const next = new Set(original);
      for (const [tag, action] of this.#actions) {
        if (action === "add") next.add(tag);
        else next.delete(tag);
      }
      const changed = next.size !== original.size || [...next].some((t) => !original.has(t));
      if (changed) out.set(id, [...next].sort());
    }
    return out;
  }
}

export function normalizeTag(raw: string): string {
  return raw.trim().toLowerCase().replaceAll(",", "");
}
