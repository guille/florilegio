<script lang="ts">
  import { CircleCheck, CircleX } from "@lucide/svelte";
  import { onMount } from "svelte";
  import { friendlyError } from "../api";
  import type { Library } from "../library.svelte";
  import type { SaveResult } from "../sync";

  let { url, library, ondone }: { url: string; library: Library; ondone: () => void } = $props();

  let result = $state<SaveResult | null>(null);

  const done: Record<Exclude<SaveResult["kind"], "failed">, string> = {
    remote: "Saved!",
    queued: "Saved offline — will sync later",
    duplicate: "Already saved",
  };

  onMount(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let mounted = true;
    void library.save(url).then((r) => {
      result = r;
      if (!mounted) return;
      timer = setTimeout(ondone, r?.kind === "failed" ? 2500 : 900);
    });
    return () => {
      mounted = false;
      clearTimeout(timer);
    };
  });
</script>

<div class="screen">
  <div class="card" role="status">
    {#if !result}
      <span class="spinner"></span>
      <h1>Saving…</h1>
    {:else if result.kind === "failed"}
      <CircleX size={44} color="var(--error)" />
      <h1>Failed to save</h1>
      <p>{friendlyError(result.error)}</p>
    {:else}
      <CircleCheck size={44} color="var(--primary)" />
      <h1>{done[result.kind]}</h1>
    {/if}
    <p class="url">{url}</p>
  </div>
</div>

<style>
  .screen {
    display: grid;
    place-items: center;
    min-height: 100dvh;
    padding: 16px;
  }

  .card {
    display: grid;
    justify-items: center;
    gap: 8px;
    width: min(380px, 100%);
    padding: 28px 24px;
    border-radius: 24px;
    background: var(--surface-container);
    box-shadow: var(--shadow);
    text-align: center;
    animation: rise 200ms cubic-bezier(0.2, 0, 0, 1);
  }

  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(8px);
    }
  }

  h1 {
    margin: 4px 0 0;
    font-size: 1.2rem;
    font-weight: 600;
  }

  p {
    margin: 0;
    color: var(--on-surface-variant);
  }

  .url {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    font-size: 0.84rem;
    overflow-wrap: anywhere;
  }

  .spinner {
    width: 40px;
    height: 40px;
    border: 4px solid var(--primary-container);
    border-top-color: var(--primary);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
