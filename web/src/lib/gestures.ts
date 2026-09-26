import type { Attachment } from "svelte/attachments";

const LONG_PRESS_MS = 450;
const SLOP_PX = 10;

/** Swallows the click a long-press ends in, wherever it lands: acting on the
 *  press can move content under the finger. */
function swallowNextClick() {
  const swallow = (e: Event) => {
    e.preventDefault();
    e.stopPropagation();
  };
  window.addEventListener("click", swallow, { capture: true, once: true });
  // A press that ends without a click (drag, cancel) mustn't eat a later one.
  window.addEventListener("pointerdown", () => window.removeEventListener("click", swallow, true), {
    once: true,
  });
}

/** Touch long-press. Swallows the click and context menu that follow it. */
export function longpress(fn: () => void): Attachment<HTMLElement> {
  return (node) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let pressing = false;
    let fired = false;
    let x = 0;
    let y = 0;

    const fire = () => {
      clearTimeout(timer);
      pressing = false;
      fired = true;
      swallowNextClick();
      navigator.vibrate?.(10);
      fn();
    };
    const cancel = () => {
      clearTimeout(timer);
      pressing = false;
    };

    const down = (e: PointerEvent) => {
      if (e.pointerType !== "touch") return;
      ({ clientX: x, clientY: y } = e);
      pressing = true;
      fired = false;
      timer = setTimeout(fire, LONG_PRESS_MS);
    };
    const move = (e: PointerEvent) => {
      if (pressing && Math.hypot(e.clientX - x, e.clientY - y) > SLOP_PX) cancel();
    };
    // Android raises its own link menu around the same time; ours wins.
    const menu = (e: Event) => {
      if (pressing) fire();
      if (fired) e.preventDefault();
    };

    const listeners: [string, EventListener][] = [
      ["pointerdown", down as EventListener],
      ["pointermove", move as EventListener],
      ["pointerup", cancel],
      ["pointercancel", cancel],
      ["contextmenu", menu],
    ];
    for (const [type, fn] of listeners) node.addEventListener(type, fn);
    return () => {
      cancel();
      for (const [type, fn] of listeners) node.removeEventListener(type, fn);
    };
  };
}
