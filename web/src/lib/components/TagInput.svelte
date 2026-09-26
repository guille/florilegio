<script lang="ts">
  import { Plus, X } from "@lucide/svelte";
  import { normalizeTag } from "../bulk-tags.svelte";

  let { tags = $bindable(), library }: { tags: string[]; library: readonly string[] } = $props();

  let draft = $state("");
  const filter = $derived(normalizeTag(draft));
  const suggestions = $derived(library.filter((t) => !tags.includes(t) && t.includes(filter)));

  function add(raw: string) {
    const tag = normalizeTag(raw);
    if (tag && !tags.includes(tag)) tags = [...tags, tag];
    draft = "";
  }

  /** Keep whatever is half-typed. */
  export function commit() {
    add(draft);
  }

  function keydown(e: KeyboardEvent) {
    if (e.key === "Enter" || e.key === ",") {
      // Enter would otherwise submit the dialog.
      if (draft.trim() || e.key === ",") e.preventDefault();
      add(draft);
    } else if (e.key === "Backspace" && draft === "" && tags.length > 0) {
      tags = tags.slice(0, -1);
    }
  }
</script>

<div class="editor">
  <div class="field-box">
    {#each tags as tag (tag)}
      <span class="chip on">
        {tag}
        <button
          type="button"
          aria-label="Remove {tag}"
          onclick={() => (tags = tags.filter((t) => t !== tag))}><X size={14} /></button
        >
      </span>
    {/each}
    <input
      class="bare"
      bind:value={draft}
      onkeydown={keydown}
      placeholder={tags.length ? "Add another…" : "Add a tag…"}
      aria-label="Add tag"
      autocomplete="off"
    />
  </div>
  {#if suggestions.length}
    <div class="suggestions" aria-label="Suggestions">
      {#each suggestions as tag (tag)}
        <button type="button" class="chip" onclick={() => add(tag)}><Plus size={14} />{tag}</button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .field-box {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
    min-height: 48px;
    padding: 7px;
    border: 1px solid var(--outline);
    border-radius: var(--radius-sm);
    cursor: text;
  }

  .field-box:focus-within {
    border-color: var(--primary);
    box-shadow: inset 0 0 0 1px var(--primary);
  }

  .chip.on {
    padding-right: 4px;
    cursor: default;
  }

  .chip button {
    display: grid;
    place-items: center;
    width: 22px;
    height: 22px;
    padding: 0;
    border: 0;
    border-radius: 50%;
    background: transparent;
    color: inherit;
    cursor: pointer;
  }

  .chip button:hover {
    background: color-mix(in srgb, transparent, currentColor 14%);
  }

  .bare {
    flex: 1;
    min-width: 8ch;
    height: 32px;
    padding: 0 6px;
    border: 0;
    background: transparent;
    outline: none;
  }

  .suggestions {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    max-height: 132px;
    margin-top: 10px;
    overflow-y: auto;
  }

  .suggestions .chip {
    padding-left: 8px;
  }
</style>
