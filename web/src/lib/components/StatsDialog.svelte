<script lang="ts">
  import type { Library } from "../library.svelte";
  import { plural } from "../url";
  import Dialog from "./Dialog.svelte";

  let { library, onclose }: { library: Library; onclose: () => void } = $props();
</script>

<Dialog title="Stats" {onclose}>
  <p title="Deleting a bookmark counts it as read">
    You have read {plural(library.deleteCount, "item")}.
  </p>

  {#snippet actions()}
    <button class="btn text" formmethod="dialog" onclick={() => library.resetStats()}>Reset</button>
    <button class="btn filled">OK</button>
  {/snippet}
</Dialog>

<style>
  p {
    margin: 0;
  }
</style>
