<script lang="ts">
  import { parseUrlInput } from "../url";
  import Dialog from "./Dialog.svelte";

  let { onsave, onclose }: { onsave: (url: string) => void; onclose: () => void } = $props();

  let text = $state("");
  const url = $derived(parseUrlInput(text));
</script>

<Dialog title="Add bookmark" {onclose} onsubmit={() => (url ? onsave(url) : false)}>
  <label class="field">
    <span>URL</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      class="input"
      type="text"
      inputmode="url"
      bind:value={text}
      placeholder="https://example.com"
      autofocus
    />
  </label>
  <p class="hint">
    Tip: paste a link anywhere on the page, or drop one onto it, to save it without this dialog.
  </p>

  {#snippet actions()}
    <button class="btn text" formmethod="dialog">Cancel</button>
    <button class="btn filled" disabled={!url}>Save</button>
  {/snippet}
</Dialog>

<style>
  .hint {
    margin-top: 12px;
  }
</style>
