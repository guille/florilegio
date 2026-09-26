import type { Api } from "./api";

let source: Api | null = null;
let cache = new Map<string, Promise<string | null>>();

/** Object URLs for the proxied favicons, one fetch per host per session. */
export function setFaviconSource(api: Api | null) {
  for (const url of cache.values()) void url.then((u) => u && URL.revokeObjectURL(u));
  source = api;
  cache = new Map();
}

export function faviconFor(host: string): Promise<string | null> {
  let url = cache.get(host);
  if (!url) {
    url = (source?.favicon(host) ?? Promise.resolve(null))
      .then((blob) => (blob ? URL.createObjectURL(blob) : null))
      .catch(() => null);
    cache.set(host, url);
  }
  return url;
}

const waiting = new Map<Element, () => void>();
let observer: IntersectionObserver | undefined;

/** Run `fn` once `node` is about to scroll into view. Returns a canceller. */
export function whenNear(node: Element, fn: () => void): () => void {
  observer ??= new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        observer!.unobserve(entry.target);
        waiting.get(entry.target)?.();
        waiting.delete(entry.target);
      }
    },
    { rootMargin: "400px" },
  );
  waiting.set(node, fn);
  observer.observe(node);
  return () => {
    waiting.delete(node);
    observer!.unobserve(node);
  };
}
