<script lang="ts">
  import type { Library } from "../library.svelte";
  import type { ListState } from "../list.svelte";

  let { library, view }: { library: Library; view: ListState } = $props();

  /** The active tag stays pickable even once no bookmark carries it. */
  const tags = $derived(
    view.tag && !library.allTags.includes(view.tag)
      ? [...library.allTags, view.tag].sort()
      : library.allTags,
  );

  function pick(tag: string | null) {
    if (tag === null) view.tag = null;
    else view.toggleTag(tag);
    window.scrollTo({ top: 0 });
  }
</script>

{#if tags.length}
  <nav class="tag-bar" aria-label="Filter by tag">
    <button class="chip" aria-pressed={view.tag === null} onclick={() => pick(null)}>
      All<span class="n">{library.bookmarks.length}</span>
    </button>
    {#each tags as tag (tag)}
      <button class="chip" aria-pressed={view.tag === tag} onclick={() => pick(tag)}>
        {tag}<span class="n">{library.tagCounts.get(tag) ?? 0}</span>
      </button>
    {/each}
  </nav>
{/if}

<style>
  .tag-bar {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 4px;
    padding: 8px 0;
  }

  /* Touch swipes a single row sideways instead. */
  @media (pointer: coarse) {
    .tag-bar {
      flex-wrap: nowrap;
      margin-inline: -16px;
      padding-inline: 16px;
      overflow-x: auto;
      scrollbar-width: none;
      mask-image: linear-gradient(
        to right,
        transparent,
        #000 16px,
        #000 calc(100% - 16px),
        transparent
      );
    }
  }

  .chip {
    flex-shrink: 0;
    height: 34px;
    border: 0;
    border-radius: 17px;
    background: var(--surface-container);
    color: var(--on-surface);
    font-weight: 600;
  }

  .chip:hover {
    background: var(--surface-container-highest);
  }

  .chip[aria-pressed="true"] {
    background: var(--secondary-container);
    color: var(--on-secondary-container);
  }

  .n {
    font-size: 0.78rem;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    opacity: 0.6;
  }
</style>
