<script lang="ts">
  import { X } from "@lucide/svelte";
  import type { Attachment } from "svelte/attachments";
  import { fly } from "svelte/transition";
  import { toasts } from "../toasts.svelte";

  function holdWhileEngaged(id: number): Attachment<HTMLElement> {
    return (node) => {
      let hovered = false;
      let focused = false;
      const update = () => toasts.hold(id, hovered || focused);
      node.addEventListener("pointerenter", () => ((hovered = true), update()));
      node.addEventListener("pointerleave", () => ((hovered = false), update()));
      node.addEventListener("focusin", () => ((focused = true), update()));
      node.addEventListener("focusout", () => ((focused = false), update()));
    };
  }
</script>

<div class="toasts" role="status" aria-live="polite">
  {#if toasts.current}
    {@const toast = toasts.current}
    {#key toast.id}
      <div
        class="toast"
        role="group"
        transition:fly|global={{ y: 16, duration: 160 }}
        {@attach holdWhileEngaged(toast.id)}
      >
        <span>{toast.message}</span>
        {#if toast.action}
          <button class="action" onclick={() => toasts.act()}>{toast.action.label}</button>
        {/if}
        <button class="close" aria-label="Dismiss" onclick={() => toasts.dismiss()}
          ><X size={16} /></button
        >
      </div>
    {/key}
  {/if}
</div>

<style>
  .toasts {
    position: fixed;
    inset: auto 0 calc(24px + env(safe-area-inset-bottom, 0px));
    z-index: 20;
    display: grid;
    justify-items: center;
    padding: 0 16px;
    pointer-events: none;
  }

  /* Clear of the floating Add button. */
  @media (max-width: 640px) {
    .toasts {
      bottom: calc(96px + env(safe-area-inset-bottom, 0px));
    }
  }

  .toast {
    grid-area: 1 / 1;
    display: flex;
    align-items: center;
    gap: 4px;
    min-height: 48px;
    max-width: 560px;
    padding: 4px 4px 4px 16px;
    border-radius: 8px;
    /* Inverse surface: it reads as a toast in both themes. */
    background: var(--on-surface);
    color: var(--surface);
    box-shadow: var(--shadow-high);
    pointer-events: auto;
  }

  span {
    padding: 8px 8px 8px 0;
  }

  button {
    border: 0;
    background: transparent;
    color: inherit;
    cursor: pointer;
  }

  .action {
    height: 36px;
    padding: 0 12px;
    border-radius: 18px;
    color: var(--primary-container);
    font-weight: 700;
  }

  .close {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    opacity: 0.8;
  }

  button:hover {
    background: color-mix(in srgb, transparent, var(--surface) 12%);
  }
</style>
