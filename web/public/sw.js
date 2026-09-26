// Just enough to open the app offline. Navigations go to the network first,
// so an online visit always gets the latest deploy; the cache only answers
// when the network can't.

const CACHE = "florilegio-v1";
/** Same-origin static files worth keeping. Anything else, API calls
 *  included, never touches the cache. */
const STATIC = /^\/(assets|icons)\/|^\/(favicon\.png|manifest\.webmanifest)$/;

self.addEventListener("install", (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => c.add("/")));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== "GET" || url.origin !== location.origin) return;

  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) e.waitUntil(storeShell(res.clone()));
          return res;
        })
        .catch(async () => (await caches.match("/")) ?? Response.error()),
    );
  } else if (url.pathname.startsWith("/assets/")) {
    // Content-hashed: a cached copy is never stale.
    e.respondWith(caches.match(req).then((hit) => hit ?? fetchAndStore(req)));
  } else if (STATIC.test(url.pathname)) {
    e.respondWith(
      fetchAndStore(req).catch(async () => (await caches.match(req)) ?? Response.error()),
    );
  }
});

async function fetchAndStore(req) {
  const res = await fetch(req);
  if (res.ok) {
    const cache = await caches.open(CACHE);
    await cache.put(req, res.clone());
  }
  return res;
}

/** Cache the page under "/" (it's the same app whatever the query string),
 *  and drop hashed assets the new page no longer references. */
async function storeShell(res) {
  const html = await res.clone().text();
  const cache = await caches.open(CACHE);
  await cache.put("/", res);
  const live = new Set(html.match(/\/assets\/[^"')\s]+/g));
  for (const req of await cache.keys()) {
    const path = new URL(req.url).pathname;
    if (path.startsWith("/assets/") && !live.has(path)) await cache.delete(req);
  }
}
