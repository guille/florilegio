<script lang="ts">
  import { CircleCheck, Copy, Pencil, Trash2 } from "@lucide/svelte";
  import type { Bookmark } from "../api";
  import { menu } from "../menu";

  type Action = (bookmark: Bookmark) => void;
  let {
    onedit,
    onselect,
    oncopy,
    ondelete,
  }: { onedit: Action; onselect: Action; oncopy: Action; ondelete: Action } = $props();

  let popover: HTMLElement;
  let target: Bookmark | null = null;
  let anchor: HTMLElement | null = null;

  /** Room the menu needs below its button before it opens upwards instead. */
  const MENU_HEIGHT = 200;

  export function open(bookmark: Bookmark, button: HTMLElement) {
    target = bookmark;
    anchor = button;
    const r = button.getBoundingClientRect();
    const below = r.bottom + MENU_HEIGHT < window.innerHeight;
    popover.style.top = below ? `${r.bottom + 4}px` : "";
    popover.style.bottom = below ? "" : `${window.innerHeight - r.top + 4}px`;
    popover.style.right = `${document.documentElement.clientWidth - r.right}px`;
    popover.showPopover();
  }

  function close() {
    if (popover.matches(":popover-open")) popover.hidePopover();
  }

  function run(action: Action) {
    const b = target;
    close();
    if (b) action(b);
  }

  function toggled(e: ToggleEvent) {
    // Only an invoker gets focus back for free; this menu is opened from script.
    if (
      e.newState === "closed" &&
      (popover.contains(document.activeElement) || document.activeElement === document.body)
    ) {
      anchor?.focus();
    }
  }
</script>

<!-- Fixed in place, it would drift away from its row. -->
<svelte:window onscroll={close} onresize={close} />

<div class="menu" popover bind:this={popover} role="menu" ontoggle={toggled} {@attach menu}>
  <button role="menuitem" onclick={() => run(onedit)}><Pencil size={18} />Edit</button>
  <button role="menuitem" onclick={() => run(onselect)}><CircleCheck size={18} />Select</button>
  <button role="menuitem" onclick={() => run(oncopy)}><Copy size={18} />Copy URL</button>
  <button role="menuitem" onclick={() => run(ondelete)}><Trash2 size={18} />Delete</button>
</div>
