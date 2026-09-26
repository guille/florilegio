import type { Attachment } from "svelte/attachments";

/** Keyboard behaviour for a popover `role="menu"`: focus lands on the checked
 *  (or first) item when it opens, and arrows, Home and End move between items. */
export const menu: Attachment<HTMLElement> = (node) => {
  const items = () => [...node.querySelectorAll<HTMLElement>('[role^="menuitem"]')];

  const toggle = (e: Event) => {
    if ((e as ToggleEvent).newState !== "open") return;
    const all = items();
    (all.find((i) => i.getAttribute("aria-checked") === "true") ?? all[0])?.focus();
  };

  const keydown = (e: KeyboardEvent) => {
    const all = items();
    const at = all.indexOf(document.activeElement as HTMLElement);
    const to = { ArrowDown: at + 1, ArrowUp: at - 1, Home: 0, End: all.length - 1 }[e.key];
    if (to === undefined) return;
    e.preventDefault();
    all[(to + all.length) % all.length]?.focus();
  };

  node.addEventListener("toggle", toggle);
  node.addEventListener("keydown", keydown);
  return () => {
    node.removeEventListener("toggle", toggle);
    node.removeEventListener("keydown", keydown);
  };
};
