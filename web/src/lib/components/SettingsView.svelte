<script lang="ts">
  import { ArrowLeft, Download, Eye, EyeOff, Monitor, Moon, Sun, Upload } from "@lucide/svelte";
  import { createApi, friendlyError, type ImportResult, normalizeBaseUrl } from "../api";
  import type { Library } from "../library.svelte";
  import { settings, type Theme } from "../settings.svelte";
  import { toasts } from "../toasts.svelte";
  import { plural } from "../url";

  let {
    library,
    canGoBack,
    onconnect,
  }: { library: Library; canGoBack: boolean; onconnect: (reset: boolean) => Promise<void> } =
    $props();

  let baseUrl = $state(settings.baseUrl);
  let token = $state(settings.token);
  let showToken = $state(false);
  let exporting = $state(false);
  let importing = $state(false);
  let fileInput = $state<HTMLInputElement>();
  let testing = $state(false);
  /** Why the connection test failed; saving is then an explicit override. */
  let testError = $state<string | null>(null);

  const dirty = $derived(baseUrl.trim() !== settings.baseUrl || token.trim() !== settings.token);
  const complete = $derived(baseUrl.trim() !== "" && token.trim() !== "");
  const themes: [Theme, string, typeof Sun][] = [
    ["system", "System", Monitor],
    ["light", "Light", Sun],
    ["dark", "Dark", Moon],
  ];

  async function save(e: SubmitEvent) {
    e.preventDefault();
    const force = (e.submitter as HTMLButtonElement | null)?.value === "force";
    if (!force) {
      testing = true;
      testError = null;
      try {
        await createApi(baseUrl, token).ping();
      } catch (err) {
        testError = friendlyError(err);
        return;
      } finally {
        testing = false;
      }
    }
    testError = null;
    const first = !settings.configured;
    const serverChanged =
      !first && normalizeBaseUrl(baseUrl) !== normalizeBaseUrl(settings.baseUrl);
    settings.saveConnection(baseUrl, token);
    await onconnect(serverChanged);
    toasts.show("Settings saved");
    if (first) location.hash = "";
  }

  async function exportAll() {
    const api = library.api;
    if (!api) return toasts.show("Configure the connection first");
    exporting = true;
    try {
      const rows = await api.exportAll();
      const blob = new Blob([JSON.stringify(rows, null, 2)], { type: "application/json" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `florilegio-export-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      toasts.show(`Exported ${plural(rows.length, "bookmark")}`);
    } catch (e) {
      toasts.show(`Export failed: ${friendlyError(e)}`);
    } finally {
      exporting = false;
    }
  }

  async function importFile() {
    const api = library.api;
    const file = fileInput?.files?.[0];
    if (fileInput) fileInput.value = "";
    if (!file) return;
    if (!api) return toasts.show("Configure the connection first");

    let rows: unknown;
    try {
      rows = JSON.parse(await file.text());
    } catch {
      return toasts.show("File is not valid JSON");
    }
    if (!Array.isArray(rows)) return toasts.show("File must contain a JSON array of bookmarks");

    importing = true;
    let res: ImportResult;
    try {
      res = await api.importAll(rows);
    } catch (e) {
      toasts.show(`Import failed: ${friendlyError(e)}`);
      return;
    } finally {
      importing = false;
    }
    const parts = [`Imported ${plural(res.imported, "bookmark")}`];
    if (res.skipped) parts.push(`${res.skipped} skipped`);
    if (res.errors.length) parts.push(plural(res.errors.length, "error"));
    toasts.show(parts.join(", "));
    if (res.imported) library.sync({ force: true });
  }
</script>

<header class="app-bar">
  <div class="inner">
    {#if canGoBack}
      <a class="icon-btn" href="#/" aria-label="Back" title="Back"><ArrowLeft size={20} /></a>
    {:else}
      <img src="/icons/Icon-192.png" alt="" width="30" height="30" />
    {/if}
    <h1>{canGoBack ? "Settings" : "Welcome to Florilegio"}</h1>
  </div>
</header>

<main>
  {#if !canGoBack}
    <p class="intro">Point this app at your Florilegio worker to get started.</p>
  {/if}

  <section class="panel">
    <h2>Connection</h2>
    <form onsubmit={save}>
      <label class="field">
        <span>Endpoint base URL</span>
        <input
          class="input"
          bind:value={baseUrl}
          placeholder="https://florilegio.example.workers.dev"
          autocomplete="url"
        />
      </label>
      <label class="field">
        <span>Bearer token</span>
        <div class="with-toggle">
          <input
            class="input"
            type={showToken ? "text" : "password"}
            bind:value={token}
            autocomplete="off"
            spellcheck="false"
          />
          <button
            type="button"
            class="icon-btn"
            aria-label={showToken ? "Hide token" : "Show token"}
            onclick={() => (showToken = !showToken)}
          >
            {#if showToken}<EyeOff size={20} />{:else}<Eye size={20} />{/if}
          </button>
        </div>
      </label>
      {#if testError}
        <p class="error" role="alert">Couldn't connect: {testError}</p>
      {/if}
      <div class="row-end">
        {#if testError}
          <button class="btn text" value="force" disabled={!dirty || !complete}>Save anyway</button>
        {/if}
        <button class="btn filled" disabled={!dirty || !complete || testing}
          >{testing ? "Checking…" : "Save"}</button
        >
      </div>
    </form>
  </section>

  <section class="panel">
    <h2>Theme</h2>
    <div class="segmented" role="radiogroup" aria-label="Theme">
      {#each themes as [value, label, Icon] (value)}
        <button
          role="radio"
          aria-checked={settings.theme === value}
          onclick={() => settings.setTheme(value)}
        >
          <Icon size={17} />{label}
        </button>
      {/each}
    </div>
  </section>

  {#if settings.configured}
    <section class="panel">
      <h2>Your data</h2>
      <div class="buttons">
        <button class="btn tonal" onclick={exportAll} disabled={exporting}>
          <Download size={18} />{exporting ? "Exporting…" : "Export bookmarks"}
        </button>
        <button class="btn tonal" onclick={() => fileInput?.click()} disabled={importing}>
          <Upload size={18} />{importing ? "Importing…" : "Import bookmarks"}
        </button>
        <input
          bind:this={fileInput}
          type="file"
          accept=".json,application/json"
          hidden
          onchange={importFile}
        />
      </div>
    </section>
  {/if}
</main>

<style>
  .inner {
    display: flex;
    align-items: center;
    gap: 12px;
    max-width: 632px;
    min-height: 64px;
    margin: 0 auto;
    padding: 8px 16px;
  }

  .inner img {
    border-radius: 8px;
  }

  h1 {
    margin: 0;
    font-size: 1.3rem;
    font-weight: 500;
  }

  main {
    display: grid;
    gap: 16px;
    max-width: 632px;
    margin: 0 auto;
    padding: 16px 16px 64px;
  }

  .intro {
    margin: 8px 4px 0;
    font-size: 1.05rem;
    color: var(--on-surface-variant);
  }

  section {
    display: grid;
    gap: 14px;
    padding: 20px;
  }

  h2 {
    margin: 0;
    font-size: 1rem;
    font-weight: 700;
  }

  form {
    display: grid;
    gap: 16px;
  }

  .with-toggle {
    position: relative;
  }

  .with-toggle .input {
    padding-right: 48px;
  }

  .with-toggle .icon-btn {
    position: absolute;
    top: 2px;
    right: 2px;
  }

  .row-end {
    display: flex;
    justify-content: flex-end;
  }

  .segmented {
    display: flex;
    border: 1px solid var(--outline);
    border-radius: 20px;
    overflow: hidden;
  }

  .segmented button {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 40px;
    padding: 0 12px;
    border: 0;
    background: transparent;
    font-weight: 600;
    cursor: pointer;
  }

  .segmented button + button {
    border-left: 1px solid var(--outline);
  }

  .segmented button:hover {
    background: color-mix(in srgb, transparent, var(--on-surface) 8%);
  }

  .segmented button[aria-checked="true"] {
    background: var(--secondary-container);
    color: var(--on-secondary-container);
  }

  .buttons {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 8px;
  }

  .error {
    margin: 0;
    color: var(--error);
    font-size: 0.87rem;
  }

  .row-end {
    gap: 8px;
  }
</style>
