<script lang="ts">
  import { Check, Minus, Plus } from "@lucide/svelte";
  import { BulkTagEditor, normalizeTag } from "../bulk-tags.svelte";
  import Dialog from "./Dialog.svelte";

  let {
    selected,
    library,
    onapply,
    onclose,
  }: {
    selected: Map<string, Set<string>>;
    library: readonly string[];
    onapply: (changes: Map<string, string[]>) => Promise<void>;
    onclose: () => void;
  } = $props();

  // Seeded once from the selection the dialog opened with.
  // svelte-ignore state_referenced_locally
  const editor = new BulkTagEditor(selected, library);
  const active = $derived([...editor.active].sort(([a], [b]) => a.localeCompare(b)));
  const suggestions = $derived([...editor.suggestions].sort());

  let draft = $state("");

  function commitDraft() {
    const tag = normalizeTag(draft);
    if (tag) editor.add(tag);
    draft = "";
  }

  function keydown(e: KeyboardEvent) {
    if (e.key !== "Enter" || !draft.trim()) return;
    e.preventDefault();
    commitDraft();
  }
</script>

<Dialog
  title="Edit tags · {selected.size} bookmarks"
  wide
  {onclose}
  onsubmit={() => {
    commitDraft();
    return onapply(editor.changes());
  }}
>
  {#if active.length}
    <p class="label">On these bookmarks <span class="hint">· click to cycle</span></p>
    <div class="chips">
      {#each active as [tag, state] (tag)}
        <button
          type="button"
          class="chip"
          class:on={state === "all"}
          class:some={state === "some"}
          title={state === "all" ? "On all — click to remove" : "On some — click to add to all"}
          onclick={() => editor.toggle(tag)}
        >
          {#if state === "all"}<Check size={15} />{:else}<Minus size={15} />{/if}
          {tag}
        </button>
      {/each}
    </div>
  {/if}

  {#if suggestions.length}
    <p class="label">Add existing</p>
    <div class="chips">
      {#each suggestions as tag (tag)}
        <button type="button" class="chip" onclick={() => editor.add(tag)}
          ><Plus size={15} />{tag}</button
        >
      {/each}
    </div>
  {/if}

  <label class="field new">
    <span>New tag</span>
    <input
      class="input"
      bind:value={draft}
      onkeydown={keydown}
      placeholder="Type and press Enter"
      autocomplete="off"
    />
  </label>

  {#snippet actions()}
    <button class="btn text" formmethod="dialog">Cancel</button>
    <button class="btn filled" disabled={!editor.hasChanges && !normalizeTag(draft)}>Apply</button>
  {/snippet}
</Dialog>

<style>
  .label {
    margin: 0 0 8px;
    font-size: 0.8rem;
    font-weight: 600;
  }

  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-bottom: 20px;
  }

  .chip {
    padding-left: 8px;
  }

  .new {
    margin-bottom: 4px;
  }
</style>
