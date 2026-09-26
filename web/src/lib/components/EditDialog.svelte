<script lang="ts">
  import type { Bookmark } from "../api";
  import Dialog from "./Dialog.svelte";
  import TagInput from "./TagInput.svelte";

  let {
    bookmark,
    library,
    onsave,
    onclose,
  }: {
    bookmark: Bookmark;
    library: readonly string[];
    /** Resolves false to keep the dialog open. */
    onsave: (changes: { title: string | null; tags: string[] }) => Promise<boolean>;
    onclose: () => void;
  } = $props();

  // Seeded once: the dialog edits a copy, not the live bookmark.
  // svelte-ignore state_referenced_locally
  let title = $state(bookmark.title ?? "");
  // svelte-ignore state_referenced_locally
  let tags = $state([...bookmark.tags]);
  let tagInput: TagInput;
</script>

<Dialog
  title="Edit bookmark"
  wide
  {onclose}
  onsubmit={() => {
    tagInput.commit();
    return onsave({ title: title.trim() || null, tags });
  }}
>
  <label class="field">
    <span>Title</span>
    <input class="input" bind:value={title} placeholder={bookmark.url} />
  </label>
  <div class="field tags">
    <span>Tags</span>
    <TagInput bind:this={tagInput} bind:tags {library} />
  </div>

  {#snippet actions()}
    <button class="btn text" formmethod="dialog">Cancel</button>
    <button class="btn filled">Save</button>
  {/snippet}
</Dialog>

<style>
  .tags {
    margin-top: 20px;
  }
</style>
