<script lang="ts">
  import { createApi } from "./lib/api";
  import ListView from "./lib/components/ListView.svelte";
  import SettingsView from "./lib/components/SettingsView.svelte";
  import ShareSave from "./lib/components/ShareSave.svelte";
  import Toasts from "./lib/components/Toasts.svelte";
  import { setFaviconSource } from "./lib/favicons";
  import type { Library } from "./lib/library.svelte";
  import type { ListState } from "./lib/list.svelte";
  import { settings } from "./lib/settings.svelte";
  import { extractUrl } from "./lib/url";

  let { library, view }: { library: Library; view: ListState } = $props();

  let hash = $state(location.hash);

  // Shared in by the Android share sheet, which tends to put the link in ?text=.
  const params = new URLSearchParams(location.search);
  let shared = $state(
    extractUrl(params.get("url") || params.get("text") || params.get("title") || ""),
  );

  /** `reset` when the server changed: nothing local belongs to the new one. */
  async function connect(reset = false) {
    const api = settings.configured ? createApi(settings.baseUrl, settings.token) : null;
    setFaviconSource(api);
    await library.connect(api, { reset });
    void library.sync();
  }

  // Before children mount: a shared link is saved as soon as ShareSave appears.
  void connect();

  function shareDone() {
    shared = null;
    history.replaceState(null, "", location.pathname + location.hash);
  }

  // index.html's theme-color metas follow the OS; an explicit theme pins both to the app bar's color.
  const themeMetas = [
    ...document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]'),
  ].map((meta) => ({
    meta,
    content: meta.content,
  }));

  $effect(() => {
    const root = document.documentElement;
    if (settings.theme === "system") delete root.dataset.theme;
    else root.dataset.theme = settings.theme;
    const pinned =
      settings.theme !== "system" &&
      getComputedStyle(root).getPropertyValue("--surface-container").trim();
    for (const { meta, content } of themeMetas) meta.content = pinned || content;
  });
</script>

<svelte:window
  onhashchange={() => (hash = location.hash)}
  ononline={() => library.sync()}
  onfocus={() => library.syncIfStale()}
  onpagehide={() => library.commitRemovals()}
/>
<svelte:document
  onvisibilitychange={() => {
    if (document.visibilityState === "visible") library.syncIfStale();
    // Likely the last chance to run before the page is frozen or closed.
    else void library.commitRemovals();
  }}
/>

{#if !settings.configured}
  <SettingsView {library} canGoBack={false} onconnect={connect} />
{:else if shared}
  <ShareSave url={shared} {library} ondone={shareDone} />
{:else if hash === "#/settings"}
  <SettingsView {library} canGoBack onconnect={connect} />
{:else}
  <ListView {library} {view} />
{/if}

<Toasts />
