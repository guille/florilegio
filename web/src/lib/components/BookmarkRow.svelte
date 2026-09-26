<script lang="ts">
  import { Check, Copy, EllipsisVertical, Pencil, Trash2 } from "@lucide/svelte";
  import type { Bookmark } from "../api";
  import { now } from "../clock";
  import { longpress } from "../gestures";
  import { formatDate, highlight, hostOf, timeAgo } from "../url";
  import Favicon from "./Favicon.svelte";

  let {
    bookmark,
    query,
    selected,
    selecting,
    highlighted,
    activeTag,
    ontoggle,
    onedit,
    oncopy,
    ondelete,
    onmenu,
    ontag,
    onfocus,
  }: {
    bookmark: Bookmark;
    query: string;
    selected: boolean;
    selecting: boolean;
    highlighted: boolean;
    activeTag: string | null;
    ontoggle: (range: boolean) => void;
    onedit: () => void;
    oncopy: () => void;
    ondelete: () => void;
    onmenu: (anchor: HTMLElement) => void;
    ontag: (tag: string) => void;
    onfocus: (focused: boolean) => void;
  } = $props();

  const MAX_TAGS = 3;

  const host = $derived(hostOf(bookmark.url));
  const shownTags = $derived(bookmark.tags.slice(0, MAX_TAGS));
  const hiddenTags = $derived(bookmark.tags.slice(MAX_TAGS));
  const label = $derived(bookmark.title || bookmark.url);
  let link: HTMLAnchorElement;

  export function focus() {
    link.focus();
  }

  /** While selecting, a plain click toggles; modified clicks still open. */
  function clickLink(e: MouseEvent) {
    if (!selecting || e.ctrlKey || e.metaKey || e.button !== 0) return;
    e.preventDefault();
    ontoggle(e.shiftKey);
  }
</script>

{#snippet marked(text: string)}
  {#each highlight(text, query) as part, i (i)}{#if part.hit}<mark>{part.text}</mark
      >{:else}{part.text}{/if}{/each}
{/snippet}

<li
  class="row"
  class:selected
  class:selecting
  class:highlighted
  onfocusin={() => onfocus(true)}
  onfocusout={() => onfocus(false)}
  {@attach (row) => {
    if (highlighted) row.scrollIntoView({ block: "center", behavior: "smooth" });
  }}
  {@attach longpress(() => ontoggle(false))}
>
  <button
    class="check"
    role="checkbox"
    aria-checked={selected}
    aria-label="Select “{label}”"
    onclick={(e) => ontoggle(e.shiftKey)}
  >
    <Favicon {host} />
    <span class="box"
      >{#if selected}<Check size={15} strokeWidth={3} />{/if}</span
    >
  </button>

  <div class="body">
    <a
      class="title"
      href={bookmark.url}
      target="_blank"
      rel="noopener noreferrer"
      onclick={clickLink}
      bind:this={link}
    >
      {@render marked(label)}
    </a>
    <div class="meta">
      <span class="host">{@render marked(host)}</span>
      <span class="dot" aria-hidden="true"></span>
      <time datetime={bookmark.createdAt} title={formatDate(bookmark.createdAt)}
        >{timeAgo(bookmark.createdAt, now())}</time
      >
      {#if bookmark.tags.length}
        <span class="tags">
          {#each shownTags as tag (tag)}
            <button
              class="tag"
              class:active={tag === activeTag}
              title="Show only “{tag}”"
              onclick={() => ontag(tag)}>{@render marked(tag)}</button
            >
          {/each}
          {#if hiddenTags.length}
            <span class="more-tags" title={hiddenTags.join(", ")}>+{hiddenTags.length}</span>
          {/if}
        </span>
      {/if}
    </div>
  </div>

  <div class="actions">
    <button class="icon-btn small" title="Edit (e)" aria-label="Edit" onclick={onedit}
      ><Pencil size={16} /></button
    >
    <button class="icon-btn small" title="Copy URL (c)" aria-label="Copy URL" onclick={oncopy}
      ><Copy size={16} /></button
    >
    <button class="icon-btn small" title="Delete (#)" aria-label="Delete" onclick={ondelete}
      ><Trash2 size={16} /></button
    >
  </div>
  <button
    class="icon-btn small more"
    aria-label="More actions"
    aria-haspopup="menu"
    onclick={(e) => onmenu(e.currentTarget)}
  >
    <EllipsisVertical size={18} />
  </button>
</li>

<style>
  .row {
    position: relative;
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: center;
    gap: 14px;
    padding: 10px 12px;
    /* Skip layout and paint for rows far offscreen; long lists stay cheap. */
    content-visibility: auto;
    contain-intrinsic-size: auto 64px;
    transition: background-color 120ms;
  }

  /* Inset past the favicon, so the tiles read as one column. */
  .row:not(:first-child)::before {
    content: "";
    position: absolute;
    top: 0;
    right: 0;
    left: 58px;
    border-top: 1px solid var(--hairline);
  }

  /* Touch leaves :hover stuck on the last row tapped. */
  @media (hover: hover) {
    .row:hover {
      background: color-mix(in srgb, var(--panel), var(--on-surface) 4%);
    }

    .row:hover .box {
      opacity: 1;
    }
  }

  .row.selected {
    background: var(--secondary-container);
    color: var(--on-secondary-container);
  }

  .row.highlighted {
    animation: flash 1.6s ease-out;
  }

  @keyframes flash {
    0%,
    30% {
      background: var(--primary-container);
    }
  }

  /* The favicon doubles as the checkbox: hover or select to reveal it. */
  .check {
    position: relative;
    z-index: 1;
    display: grid;
    padding: 0;
    border: 0;
    border-radius: 9px;
    background: transparent;
    cursor: pointer;
  }

  .check > :global(*) {
    grid-area: 1 / 1;
  }

  .box {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border-radius: 9px;
    background: var(--surface-bright);
    box-shadow: inset 0 0 0 2px var(--outline);
    color: var(--on-primary);
    opacity: 0;
    transition: opacity 100ms;
  }

  .selected .box {
    background: var(--primary);
    box-shadow: none;
  }

  .check:focus-visible .box,
  .selecting .box {
    opacity: 1;
  }

  .body {
    min-width: 0;
  }

  .title {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    font-size: 1rem;
    font-weight: 560;
    line-height: 1.35;
    text-decoration: none;
    overflow-wrap: anywhere;
    outline: none;
    /* Long-press selects; iOS would show its link preview instead. */
    -webkit-touch-callout: none;
  }

  /* The whole row is the link: middle-click and hover-for-URL work anywhere. */
  .title::after {
    content: "";
    position: absolute;
    inset: 0;
    border-radius: inherit;
  }

  .title:focus-visible::after {
    outline: 2px solid var(--primary);
    outline-offset: -2px;
  }

  mark {
    border-radius: 3px;
    background: var(--mark);
    color: inherit;
  }

  .meta {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    margin-top: 3px;
    color: var(--on-surface-variant);
    font-size: 0.83rem;
    flex-wrap: wrap;
    row-gap: 2px;
    white-space: nowrap;
  }

  .selected .meta {
    color: inherit;
  }

  .host {
    max-width: 26ch;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  time {
    flex-shrink: 0;
  }

  .dot {
    flex-shrink: 0;
    width: 3px;
    height: 3px;
    border-radius: 50%;
    background: currentColor;
    opacity: 0.5;
  }

  .tags {
    display: flex;
    gap: 2px;
    margin-left: -3px;
  }

  .tag {
    position: relative;
    z-index: 1;
    flex-shrink: 0;
    padding: 1px 5px;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--primary);
    font-size: inherit;
    font-weight: 600;
    cursor: pointer;
  }

  .more-tags {
    padding: 1px 4px;
    color: var(--outline);
    font-weight: 600;
  }

  .tag::before {
    content: "#";
    opacity: 0.55;
  }

  .tag:hover,
  .tag.active {
    background: var(--primary-container);
    color: var(--on-primary-container);
  }

  /* Overlaid, not in the grid: hidden, it shouldn't cost the text any room. */
  .actions {
    position: absolute;
    top: 50%;
    right: 10px;
    z-index: 1;
    display: flex;
    gap: 2px;
    padding: 3px;
    border-radius: 12px;
    background: var(--surface-bright);
    box-shadow: var(--shadow);
    opacity: 0;
    transform: translate(4px, -50%);
    transition:
      opacity 100ms,
      transform 100ms;
    pointer-events: none;
  }

  .row:hover .actions,
  .row:focus-within .actions {
    opacity: 1;
    transform: translateY(-50%);
    pointer-events: auto;
  }

  .actions .icon-btn {
    border-radius: 9px;
  }

  .selecting .actions,
  .selecting .more {
    visibility: hidden;
  }

  .more {
    display: none;
    position: relative;
    z-index: 1;
  }

  /* Touch: nothing to hover, so one menu button stands in for the toolbar. */
  @media (hover: none) {
    .actions {
      display: none;
    }

    .more {
      display: inline-grid;
    }

    .row {
      padding-right: 4px;
      /* A long-press selects the row, not its text; the row shows its own state. */
      -webkit-user-select: none;
      user-select: none;
      -webkit-tap-highlight-color: transparent;
    }
  }
</style>
