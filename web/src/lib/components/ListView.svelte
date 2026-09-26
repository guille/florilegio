<script lang="ts">
  import { BookmarkPlus, CloudOff, Plus, SearchX } from "@lucide/svelte";
  import { tick } from "svelte";
  import type { Bookmark } from "../api";
  import type { Library } from "../library.svelte";
  import type { ListState } from "../list.svelte";
  import { toasts } from "../toasts.svelte";
  import { extractUrl, hostOf, plural } from "../url";
  import AddDialog from "./AddDialog.svelte";
  import BookmarkRow from "./BookmarkRow.svelte";
  import BulkTagDialog from "./BulkTagDialog.svelte";
  import EditDialog from "./EditDialog.svelte";
  import Favicon from "./Favicon.svelte";
  import RowMenu from "./RowMenu.svelte";
  import ShortcutsDialog from "./ShortcutsDialog.svelte";
  import StatsDialog from "./StatsDialog.svelte";
  import TagBar from "./TagBar.svelte";
  import Toolbar from "./Toolbar.svelte";

  let { library, view }: { library: Library; view: ListState } = $props();

  type Modal =
    | { kind: "add" }
    | { kind: "edit"; bookmark: Bookmark }
    | { kind: "bulk-tags"; selected: Map<string, Set<string>> }
    | { kind: "shortcuts" }
    | { kind: "stats" };

  let modal = $state<Modal | null>(null);
  let dragging = $state(false);
  let toolbar: Toolbar;
  let rowMenu: RowMenu;
  const rows: Record<string, BookmarkRow | null> = $state({});
  /** The bookmark whose row has focus, which keyboard shortcuts act on. */
  let cursor = $state<string | null>(null);

  const selecting = $derived(view.selection.length > 0);
  const neverSynced = $derived(library.lastRefreshed === null && library.bookmarks.length === 0);

  function bulkTags() {
    modal = {
      kind: "bulk-tags",
      selected: new Map(view.selection.map((b) => [b.id, new Set(b.tags)])),
    };
  }

  async function copy(bookmark: Bookmark) {
    try {
      await navigator.clipboard.writeText(bookmark.url);
      toasts.show("URL copied to clipboard");
    } catch {
      toasts.show("Couldn't access the clipboard");
    }
  }

  function focusRow(id: string | undefined) {
    if (id) rows[id]?.focus();
  }

  function moveCursor(step: number) {
    const ids = view.visible.map((b) => b.id);
    const at = cursor ? ids.indexOf(cursor) : -1;
    focusRow(ids[at === -1 ? 0 : Math.max(0, Math.min(ids.length - 1, at + step))]);
  }

  /** Delete, keeping keyboard focus in the list. If it was on (or came from)
   *  one of the doomed rows, it moves to the next survivor, or the previous
   *  one at the end; Undo brings it back. */
  function remove(ids: string[], from = cursor) {
    const gone = new Set(ids);
    const list = view.visible;
    const at = list.findIndex((b) => b.id === from);
    if (at !== -1) {
      const after = list.slice(at + 1).find((b) => !gone.has(b.id));
      const before = list.slice(0, at).findLast((b) => !gone.has(b.id));
      focusRow((after ?? before)?.id);
    }
    view.remove(ids, async () => {
      if (at === -1) return;
      await tick();
      // Unless the user has moved on to something else meanwhile.
      if (document.activeElement === document.body) focusRow(from!);
    });
  }

  /** The selection bar is about to disappear, and focus with it. */
  function removeSelection() {
    const ids = view.selection.map((b) => b.id);
    const gone = new Set(ids);
    focusRow(view.visible.find((b) => !gone.has(b.id))?.id);
    remove(ids, null);
  }

  // ── Keyboard, paste and drop ────────────────────────────────────────────

  function isTyping(target: EventTarget | null) {
    return (
      target instanceof HTMLElement &&
      (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))
    );
  }

  function keydown(e: KeyboardEvent) {
    if (modal || e.ctrlKey || e.metaKey || e.altKey || isTyping(e.target)) return;
    const focused = view.visible.find((b) => b.id === cursor);
    const actions: Record<string, (() => void) | undefined> = {
      "/": () => toolbar.focusSearch(),
      n: () => (modal = { kind: "add" }),
      r: () => library.sync({ force: true, manual: true }),
      "?": () => (modal = { kind: "shortcuts" }),
      j: () => moveCursor(1),
      k: () => moveCursor(-1),
      x: focused && (() => view.toggle(focused.id, e.shiftKey)),
      e: focused && (() => (modal = { kind: "edit", bookmark: focused })),
      c: focused && (() => copy(focused)),
      "#": focused && (() => remove([focused.id])),
      Delete: focused && (() => remove([focused.id])),
      Escape: () => {
        if (selecting) view.selected.clear();
        else if (view.hasFilters) view.clearFilters();
      },
    };
    const action = actions[e.key];
    if (!action) return;
    e.preventDefault();
    action();
  }

  function paste(e: ClipboardEvent) {
    if (modal || isTyping(e.target)) return;
    const url = extractUrl(e.clipboardData?.getData("text") ?? "");
    if (!url) return;
    e.preventDefault();
    view.save(url);
  }

  function carriesLink(e: DragEvent) {
    const types = e.dataTransfer?.types ?? [];
    return types.includes("text/uri-list") || types.includes("text/plain");
  }

  function dragover(e: DragEvent) {
    if (modal || !carriesLink(e)) return;
    e.preventDefault();
    dragging = true;
  }

  function drop(e: DragEvent) {
    if (!dragging) return;
    e.preventDefault();
    dragging = false;
    const data = e.dataTransfer;
    const uris = data
      ?.getData("text/uri-list")
      .split(/\r?\n/)
      .find((l) => l && !l.startsWith("#"));
    const url = extractUrl(uris ?? data?.getData("text/plain") ?? "");
    if (url) view.save(url);
    else toasts.show("That doesn't look like a link");
  }
</script>

<svelte:window
  onkeydown={keydown}
  onpaste={paste}
  ondragover={dragover}
  ondragleave={(e) => e.relatedTarget === null && (dragging = false)}
  ondrop={drop}
/>

<Toolbar
  bind:this={toolbar}
  {library}
  {view}
  onadd={() => (modal = { kind: "add" })}
  onbulktags={bulkTags}
  onstats={() => (modal = { kind: "stats" })}
  ondeleteselection={removeSelection}
  onleavesearch={() => focusRow(view.visible[0]?.id)}
/>

<RowMenu
  bind:this={rowMenu}
  onedit={(bookmark) => (modal = { kind: "edit", bookmark })}
  onselect={(b) => view.toggle(b.id)}
  oncopy={copy}
  ondelete={(b) => remove([b.id], b.id)}
/>

<main>
  <TagBar {library} {view} />

  {#if view.pending.length}
    <section class="pending" aria-label="Waiting to sync">
      <h2><CloudOff size={14} />Waiting to sync</h2>
      <ul class="list">
        {#each view.pending as p (p.url)}
          <li>
            <Favicon host={hostOf(p.url)} />
            <a href={p.url} target="_blank" rel="noopener noreferrer">{p.url}</a>
          </li>
        {/each}
      </ul>
    </section>
  {/if}

  {#if neverSynced && library.syncing}
    <ul class="list panel skeleton" aria-label="Loading">
      {#each { length: 6 }, i (i)}<li><span></span><span></span></li>{/each}
    </ul>
  {:else if view.visible.length === 0}
    {#if view.hasFilters}
      <div class="empty">
        <SearchX size={56} strokeWidth={1.25} />
        <h2>No bookmarks match your filters</h2>
        <p>Try adjusting your search or tag.</p>
        <button class="btn tonal" onclick={() => view.clearFilters()}>Clear filters</button>
      </div>
    {:else if !view.pending.length}
      <div class="empty">
        <BookmarkPlus size={56} strokeWidth={1.25} />
        <h2>No bookmarks yet</h2>
        <p>Paste a link anywhere on this page, drop one onto it, or press <kbd>n</kbd>.</p>
        <button class="btn filled" onclick={() => (modal = { kind: "add" })}
          ><Plus size={18} />Add bookmark</button
        >
      </div>
    {/if}
  {:else}
    {#if view.hasFilters}
      <p class="summary">
        <span>
          {plural(view.visible.length, "bookmark")}
          {#if view.query.trim()}matching “{view.query.trim()}”{/if}
          {#if view.tag}tagged <strong>{view.tag}</strong>{/if}
        </span>
        <button class="btn text" onclick={() => view.clearFilters()}>Clear</button>
      </p>
    {/if}
    <ul class="list panel">
      {#each view.visible as bookmark (bookmark.id)}
        <BookmarkRow
          bind:this={rows[bookmark.id]}
          {bookmark}
          query={view.query}
          selected={view.selected.has(bookmark.id)}
          {selecting}
          highlighted={view.highlight === bookmark.id}
          activeTag={view.tag}
          ontoggle={(range) => view.toggle(bookmark.id, range)}
          onedit={() => (modal = { kind: "edit", bookmark })}
          oncopy={() => copy(bookmark)}
          ondelete={() => remove([bookmark.id])}
          onmenu={(anchor) => rowMenu.open(bookmark, anchor)}
          ontag={(tag) => {
            view.toggleTag(tag);
            window.scrollTo({ top: 0 });
          }}
          onfocus={(focused) => {
            if (focused) cursor = bookmark.id;
            else if (cursor === bookmark.id) cursor = null;
          }}
        />
      {/each}
    </ul>
    <p class="footer">
      <button class="btn text" onclick={() => (modal = { kind: "shortcuts" })}
        >Press <kbd>?</kbd> for keyboard shortcuts</button
      >
    </p>
  {/if}
</main>

{#if dragging}
  <div class="drop" aria-hidden="true"><div><BookmarkPlus size={40} />Drop to save</div></div>
{/if}

{#if modal?.kind === "add"}
  <AddDialog onsave={(url) => view.save(url)} onclose={() => (modal = null)} />
{:else if modal?.kind === "edit"}
  {@const { bookmark } = modal}
  <EditDialog
    {bookmark}
    library={library.allTags}
    onsave={(changes) => library.update(bookmark.id, changes)}
    onclose={() => (modal = null)}
  />
{:else if modal?.kind === "bulk-tags"}
  <BulkTagDialog
    selected={modal.selected}
    library={library.allTags}
    onapply={async (changes) => {
      await library.retag(changes);
      view.selected.clear();
    }}
    onclose={() => (modal = null)}
  />
{:else if modal?.kind === "shortcuts"}
  <ShortcutsDialog onclose={() => (modal = null)} />
{:else if modal?.kind === "stats"}
  <StatsDialog {library} onclose={() => (modal = null)} />
{/if}

<style>
  main {
    max-width: calc(var(--column) + 32px);
    margin: 0 auto;
    padding: 8px 16px calc(96px + env(safe-area-inset-bottom, 0px));
  }

  .list {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .panel {
    margin-top: 8px;
    /* Rows go edge to edge; the panel's corners trim them. */
    overflow: clip;
  }

  /* A panel still in pencil: not on the server yet. */
  .pending {
    margin-top: 8px;
    padding: 4px 0 8px;
    border: 1px dashed var(--outline-variant);
    border-radius: 16px;
  }

  .pending h2 {
    display: flex;
    align-items: center;
    gap: 6px;
    margin: 8px 12px 4px;
    font-size: 0.78rem;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--outline);
  }

  .pending li {
    display: grid;
    grid-template-columns: auto 1fr;
    align-items: center;
    gap: 14px;
    padding: 6px 12px;
    opacity: 0.75;
  }

  .pending a {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    text-decoration: none;
  }

  .summary {
    display: flex;
    align-items: center;
    gap: 4px;
    min-height: 40px;
    margin: 8px 0 0 12px;
    color: var(--on-surface-variant);
  }

  .summary strong {
    color: var(--on-surface);
  }

  .summary .btn {
    height: 32px;
  }

  .footer {
    display: flex;
    justify-content: center;
    margin: 32px 0 0;
  }

  .footer .btn {
    color: var(--outline);
    font-weight: 500;
    font-size: 0.84rem;
  }

  @media (hover: none) {
    .footer {
      display: none;
    }
  }

  .skeleton li {
    display: grid;
    gap: 8px;
    padding: 14px 12px 14px 44px;
  }

  .skeleton span {
    height: 14px;
    border-radius: 7px;
    background: var(--surface-container-high);
    animation: pulse 1.2s ease-in-out infinite alternate;
  }

  .skeleton span:first-child {
    width: 70%;
  }

  .skeleton span:last-child {
    width: 35%;
    height: 10px;
  }

  @keyframes pulse {
    to {
      opacity: 0.45;
    }
  }

  .empty {
    display: grid;
    justify-items: center;
    gap: 8px;
    padding: 72px 16px;
    text-align: center;
    color: var(--outline);
  }

  .empty h2 {
    margin: 8px 0 0;
    font-size: 1.15rem;
    font-weight: 600;
    color: var(--on-surface-variant);
  }

  .empty p {
    margin: 0 0 12px;
  }

  .drop {
    position: fixed;
    inset: 0;
    z-index: 30;
    display: grid;
    place-items: center;
    padding: 16px;
    background: color-mix(in srgb, var(--primary) 18%, transparent);
    pointer-events: none;
  }

  .drop div {
    display: grid;
    justify-items: center;
    gap: 12px;
    width: min(420px, 100%);
    padding: 48px 24px;
    border: 2px dashed var(--primary);
    border-radius: 24px;
    background: var(--surface-container-high);
    color: var(--primary);
    font-size: 1.2rem;
    font-weight: 600;
  }
</style>
