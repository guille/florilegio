<script lang="ts">
  import type { Attachment } from "svelte/attachments";
  import { faviconFor, whenNear } from "../favicons";

  let { host }: { host: string } = $props();
  let src = $state<string | null>(null);
  let failed = $state(false);

  const name = $derived(host.replace(/^www\d?\./, ""));
  // A stable hue per site, so a monogram reads as that site's colour.
  const hue = $derived([...name].reduce((h, c) => (h * 31 + c.charCodeAt(0)) % 360, 7));

  const lazy: Attachment<HTMLElement> = (node) =>
    whenNear(node, () => faviconFor(host).then((url) => (url ? (src = url) : (failed = true))));
</script>

<span class="tile" class:monogram={failed} style:--hue={hue} {@attach lazy}>
  {#if src}
    <img {src} alt="" width="18" height="18" />
  {:else if failed}
    {name.charAt(0).toUpperCase()}
  {/if}
</span>

<style>
  .tile {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border-radius: 9px;
    /* Favicons are drawn for light pages; keep them on one in both themes. */
    background: var(--tile);
    box-shadow: inset 0 0 0 1px var(--tile-ring);
  }

  .monogram {
    background: oklch(0.9 0.05 var(--hue));
    color: oklch(0.4 0.09 var(--hue));
    box-shadow: none;
    font-weight: 700;
    font-size: 0.95rem;
  }

  img {
    border-radius: 3px;
  }
</style>
