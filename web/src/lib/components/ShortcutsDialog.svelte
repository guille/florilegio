<script lang="ts">
  import Dialog from "./Dialog.svelte";

  let { onclose }: { onclose: () => void } = $props();
  let dialog: Dialog;

  const groups: [string, [string[], string][]][] = [
    [
      "Anywhere",
      [
        [["/"], "Search"],
        [["n"], "Add bookmark"],
        [["r"], "Sync"],
        [["Ctrl", "V"], "Save a copied link"],
        [["Esc"], "Clear selection, then search"],
        [["?"], "This help"],
      ],
    ],
    [
      "On a bookmark",
      [
        [["j"], "Next"],
        [["k"], "Previous"],
        [["Enter"], "Open"],
        [["x"], "Select"],
        [["e"], "Edit"],
        [["c"], "Copy URL"],
        [["#"], "Delete (undoable)"],
      ],
    ],
  ];
</script>

<svelte:window onkeydown={(e) => e.key === "?" && dialog.close()} />

<Dialog bind:this={dialog} title="Keyboard shortcuts" wide {onclose}>
  <div class="groups">
    {#each groups as [name, keys] (name)}
      <section>
        <h3>{name}</h3>
        <dl>
          {#each keys as [combo, label] (label)}
            <dt>
              {#each combo as key, i (key)}{#if i > 0}+{/if}<kbd>{key}</kbd>{/each}
            </dt>
            <dd>{label}</dd>
          {/each}
        </dl>
      </section>
    {/each}
  </div>

  {#snippet actions()}
    <button class="btn filled">Got it</button>
  {/snippet}
</Dialog>

<style>
  .groups {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 8px 32px;
  }

  h3 {
    margin: 0 0 8px;
    font-size: 0.8rem;
    color: var(--on-surface);
  }

  dl {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 8px 14px;
    margin: 0;
  }

  dt {
    display: flex;
    gap: 3px;
    align-items: center;
  }

  dd {
    margin: 0;
  }
</style>
