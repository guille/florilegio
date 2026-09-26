import { createSubscriber } from "svelte/reactivity";

const subscribe = createSubscriber((update) => {
  const timer = setInterval(update, 60_000);
  return () => clearInterval(timer);
});

/** The current time, re-read by effects once a minute while any are watching. */
export function now(): number {
  subscribe();
  return Date.now();
}
