<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    title,
    onclose,
    onsubmit,
    children,
    actions,
    wide = false,
  }: {
    title: string;
    onclose: () => void;
    /** Runs on submit (Enter in any field, or a submit button). The dialog
     *  closes once it settles, unless it returns false. */
    onsubmit?: () => unknown;
    children: Snippet;
    /** Buttons with `formmethod="dialog"` close without submitting. */
    actions: Snippet;
    wide?: boolean;
  } = $props();

  let dialog: HTMLDialogElement;
  let busy = $state(false);
  /** Where the pointer went down: a drag that ends on the backdrop isn't a click on it. */
  let downOnBackdrop = false;

  export function close() {
    dialog.close();
  }

  async function submit(e: SubmitEvent) {
    if ((e.submitter as HTMLButtonElement | null)?.formMethod === "dialog") return;
    e.preventDefault();
    busy = true;
    try {
      if ((await onsubmit?.()) !== false) dialog.close();
    } finally {
      busy = false;
    }
  }
</script>

<!-- Backdrop clicks land on the <dialog> itself, outside the inner surface. -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialog}
  class:wide
  {onclose}
  onpointerdown={(e) => (downOnBackdrop = e.target === e.currentTarget)}
  onclick={(e) => downOnBackdrop && e.target === e.currentTarget && e.currentTarget.close()}
  {@attach (dialog) => dialog.showModal()}
>
  <form class="surface" onsubmit={submit}>
    <h2>{title}</h2>
    <fieldset disabled={busy}>
      <div class="content">{@render children()}</div>
      <div class="actions">{@render actions()}</div>
    </fieldset>
  </form>
</dialog>

<style>
  dialog {
    width: min(440px, calc(100vw - 32px));
    max-height: calc(100dvh - 48px);
    padding: 0;
    border: 0;
    border-radius: 24px;
    background: var(--surface-container-high);
    color: var(--on-surface);
    box-shadow: var(--shadow-high);
    overflow: hidden;
  }

  dialog.wide {
    width: min(560px, calc(100vw - 32px));
  }

  dialog::backdrop {
    background: var(--scrim);
  }

  dialog[open] {
    animation: pop 160ms cubic-bezier(0.2, 0, 0, 1);
  }

  dialog[open]::backdrop {
    animation: fade 160ms ease-out;
  }

  @keyframes pop {
    from {
      opacity: 0;
      transform: translateY(8px) scale(0.97);
    }
  }

  @keyframes fade {
    from {
      opacity: 0;
    }
  }

  .surface {
    display: flex;
    flex-direction: column;
    max-height: inherit;
    padding: 24px;
  }

  fieldset {
    display: contents;
  }

  h2 {
    margin: 0 0 16px;
    font-size: 1.4rem;
    font-weight: 500;
  }

  .content {
    overflow-y: auto;
    margin: 0 -24px;
    padding: 2px 24px;
    color: var(--on-surface-variant);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 24px;
  }
</style>
