<script lang="ts">
  import {
    ArrowDownUp,
    Check,
    Plus,
    RefreshCw,
    Search,
    Settings,
    Tags,
    Trash2,
    X,
  } from "@lucide/svelte";
  import { tick } from "svelte";
  import type { Library } from "../library.svelte";
  import { type ListState, SORT_LABELS, type SortOrder } from "../list.svelte";
  import { menu } from "../menu";
  import { formatDate } from "../url";

  let {
    library,
    view,
    onadd,
    onbulktags,
    onstats,
    ondeleteselection,
    onleavesearch,
  }: {
    library: Library;
    view: ListState;
    onadd: () => void;
    onbulktags: () => void;
    onstats: () => void;
    ondeleteselection: () => void;
    /** Arrow down or Enter in the search box: move on to the results. */
    onleavesearch: () => void;
  } = $props();

  let search = $state<HTMLInputElement>();
  let sortMenu = $state<HTMLElement>();
  let sortButton = $state<HTMLButtonElement>();
  let scrolled = $state(false);
  /** On narrow screens search hides behind a button, taking the brand's place when open. */
  let searchOpen = $state(false);

  const selecting = $derived(view.selection.length > 0);
  const searching = $derived(searchOpen || view.query !== "");
  const syncStatus = $derived(
    [
      "Sync (r)",
      `Last refreshed: ${library.lastRefreshed ? formatDate(library.lastRefreshed) : "never"}`,
      library.queued.adds && `Queued adds: ${library.queued.adds}`,
      library.queued.deletes && `Queued deletes: ${library.queued.deletes}`,
    ]
      .filter(Boolean)
      .join("\n"),
  );

  export async function focusSearch() {
    searchOpen = true;
    await tick();
    search?.focus();
  }

  function closeSearch() {
    searchOpen = false;
    view.query = "";
  }

  function placeSortMenu(e: ToggleEvent) {
    if (e.newState !== "open" || !sortButton || !sortMenu) return;
    const r = sortButton.getBoundingClientRect();
    sortMenu.style.top = `${r.bottom + 4}px`;
    sortMenu.style.right = `${document.documentElement.clientWidth - r.right}px`;
  }

  function pickSort(order: SortOrder) {
    view.setSort(order);
    sortMenu?.hidePopover();
  }
</script>

<svelte:window onscroll={() => (scrolled = window.scrollY > 4)} />

<header class="app-bar bar" class:selecting class:searching class:scrolled>
  <div class="inner">
    {#if selecting}
      <button
        class="icon-btn"
        aria-label="Clear selection (Esc)"
        title="Clear selection (Esc)"
        onclick={() => view.selected.clear()}
      >
        <X size={20} />
      </button>
      <span class="count">{view.selection.length} selected</span>
      <button
        class="btn text"
        onclick={() => view.selectAll()}
        disabled={view.selection.length === view.visible.length}
      >
        Select all
      </button>
      <span class="spacer"></span>
      <button class="btn tonal" aria-label="Edit tags" onclick={onbulktags}
        ><Tags size={18} /><span>Edit tags</span></button
      >
      <button
        class="icon-btn"
        aria-label="Delete selected"
        title="Delete selected"
        onclick={ondeleteselection}
      >
        <Trash2 size={20} />
      </button>
    {:else}
      <button class="brand" title="Stats" onclick={onstats}>
        <img src="/icons/Icon-192.png" alt="" width="30" height="30" />
        <span>Florilegio</span>
      </button>
    {/if}

    <label class="search">
      <Search size={18} />
      <span class="visually-hidden">Search bookmarks</span>
      <input
        bind:this={search}
        bind:value={view.query}
        type="search"
        placeholder="Search bookmarks"
        autocomplete="off"
        onkeydown={(e) => {
          if (e.key === "Escape") {
            closeSearch();
            search?.blur();
          } else if (e.key === "ArrowDown" || e.key === "Enter") {
            e.preventDefault();
            onleavesearch();
          }
        }}
      />
      {#if view.query}
        <button
          class="icon-btn small clear"
          aria-label="Clear search"
          onclick={() => {
            view.query = "";
            search?.focus();
          }}><X size={17} /></button
        >
      {:else}
        <kbd aria-hidden="true">/</kbd>
      {/if}
    </label>

    {#if !selecting}
      <div class="tools">
        {#if searching}
          <button
            class="icon-btn search-toggle"
            aria-label="Close search"
            title="Close search"
            onclick={closeSearch}
          >
            <X size={20} />
          </button>
        {:else}
          <button
            class="icon-btn search-toggle"
            aria-label="Search"
            title="Search"
            onclick={focusSearch}
          >
            <Search size={20} />
          </button>
        {/if}
        <button
          class="icon-btn"
          class:spinning={library.syncing}
          aria-label="Sync"
          title={syncStatus}
          disabled={library.syncing}
          onclick={() => library.sync({ force: true, manual: true })}
        >
          <RefreshCw size={20} />
        </button>
        <button
          class="icon-btn"
          bind:this={sortButton}
          title="Sort order: {SORT_LABELS[view.sort]}"
          aria-label="Sort order: {SORT_LABELS[view.sort]}"
          aria-haspopup="menu"
          popovertarget="sort-menu"
        >
          <ArrowDownUp size={20} />
        </button>
        <a class="icon-btn" href="#/settings" aria-label="Settings" title="Settings"
          ><Settings size={20} /></a
        >
        <button
          class="btn filled add"
          title="Add bookmark (n)"
          aria-label="Add bookmark"
          onclick={onadd}
        >
          <Plus size={20} /><span>Add</span>
        </button>
      </div>
    {/if}
  </div>

  {#if library.banner}
    <div class="banner" class:error={!library.banner.ok} role="status">
      <span>{library.banner.message}</span>
      {#if !library.banner.ok}
        <button class="btn text" onclick={() => library.sync({ force: true, manual: true })}
          >Retry</button
        >
      {/if}
      <button class="btn text" onclick={() => library.dismissBanner()}>Dismiss</button>
    </div>
  {/if}
</header>

{#if !selecting}
  <button class="btn filled fab" aria-label="Add bookmark" onclick={onadd}
    ><Plus size={24} /></button
  >
{/if}

<div
  class="menu"
  id="sort-menu"
  popover
  bind:this={sortMenu}
  onbeforetoggle={placeSortMenu}
  role="menu"
  {@attach menu}
>
  {#each Object.entries(SORT_LABELS) as [order, label] (order)}
    <button
      role="menuitemradio"
      aria-checked={view.sort === order}
      onclick={() => pickSort(order as SortOrder)}
    >
      <span class="tick"
        >{#if view.sort === order}<Check size={16} />{/if}</span
      >
      {label}
      {#if order === "random" && view.sort === "random"}<span class="hint"
          >· again to reshuffle</span
        >{/if}
    </button>
  {/each}
</div>

<style>
  .bar.scrolled {
    box-shadow:
      0 1px 0 var(--hairline),
      0 4px 16px rgb(0 0 0 / 0.06);
  }

  .bar.selecting {
    background: var(--primary-container);
    color: var(--on-primary-container);
  }

  .bar.selecting .icon-btn,
  .bar.selecting .btn.text {
    color: inherit;
  }

  .inner {
    display: flex;
    align-items: center;
    gap: 8px;
    max-width: calc(var(--column) + 32px);
    min-height: 64px;
    margin: 0 auto;
    padding: 8px 16px;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 44px;
    margin-left: -8px;
    padding: 0 12px 0 8px;
    border: 0;
    border-radius: var(--radius-sm);
    background: transparent;
    font-size: 1.2rem;
    font-weight: 500;
    cursor: pointer;
  }

  .brand:hover {
    background: color-mix(in srgb, transparent, var(--on-surface) 8%);
  }

  .brand img {
    border-radius: 8px;
  }

  .search {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 10px;
    height: 44px;
    min-width: 0;
    margin: 0 8px;
    padding: 0 12px 0 16px;
    border-radius: 22px;
    background: var(--surface-container-highest);
    color: var(--on-surface-variant);
    cursor: text;
  }

  .bar.selecting .search {
    display: none;
  }

  .search:focus-within {
    background: var(--surface-bright);
    box-shadow: var(--shadow);
  }

  .search input::-webkit-search-cancel-button {
    display: none;
  }

  .search .clear {
    margin-right: -6px;
  }

  .search input {
    flex: 1;
    min-width: 0;
    height: 100%;
    border: 0;
    background: transparent;
    color: var(--on-surface);
    outline: none;
  }

  .tools {
    display: flex;
    align-items: center;
    gap: 2px;
  }

  .search-toggle {
    display: none;
  }

  .add {
    margin-left: 8px;
    padding: 0 18px 0 14px;
  }

  .fab {
    display: none;
    position: fixed;
    right: 16px;
    bottom: calc(24px + env(safe-area-inset-bottom, 0px));
    z-index: 10;
    width: 56px;
    height: 56px;
    padding: 0;
    border-radius: 16px;
    box-shadow: var(--shadow-high);
  }

  .spinning :global(svg) {
    animation: spin 0.9s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  .count {
    font-size: 1.1rem;
    font-weight: 600;
    margin-right: 4px;
  }

  .spacer {
    flex: 1;
  }

  .banner {
    position: absolute;
    top: calc(100% + 8px);
    left: 50%;
    display: flex;
    align-items: center;
    gap: 4px;
    width: max-content;
    max-width: calc(100% - 32px);
    padding: 4px 4px 4px 16px;
    border-radius: var(--radius);
    background: var(--primary-container);
    color: var(--on-primary-container);
    box-shadow: var(--shadow);
    transform: translateX(-50%);
    animation: drop-in 180ms cubic-bezier(0.2, 0, 0, 1);
  }

  .banner.error {
    background: var(--error-container);
    color: var(--on-error-container);
  }

  .banner .btn {
    color: inherit;
  }

  @keyframes drop-in {
    from {
      opacity: 0;
      transform: translate(-50%, -6px);
    }
  }

  .tick {
    display: grid;
    place-items: center;
    width: 20px;
  }

  .menu .hint {
    margin-left: auto;
  }

  @media (max-width: 640px) {
    .search {
      display: none;
      margin: 0;
    }

    .bar.searching:not(.selecting) .search {
      display: flex;
    }

    .bar.searching .brand {
      display: none;
    }

    /* The toggle closes and clears instead. */
    .search kbd,
    .search .clear {
      display: none;
    }

    .search-toggle {
      display: inline-grid;
    }

    .tools {
      margin-left: auto;
    }

    .tonal span {
      display: none;
    }

    .tonal {
      width: 40px;
      padding: 0;
    }

    .add {
      display: none;
    }

    /* Within thumb reach. */
    .fab {
      display: inline-flex;
    }
  }
</style>
