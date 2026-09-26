import { mount } from "svelte";
import "./app.css";
import App from "./App.svelte";
import { MemoryKV, openIndexedDB } from "./lib/kv";
import { Library } from "./lib/library.svelte";
import { ListState } from "./lib/list.svelte";
import { Repository } from "./lib/repo.svelte";

if (import.meta.env.PROD && "serviceWorker" in navigator)
  void navigator.serviceWorker.register("/sw.js");

// Private windows can refuse IndexedDB; the app still works, it just forgets.
const kv = await openIndexedDB().catch(() => new MemoryKV());
const library = new Library(await Repository.open(kv));

mount(App, { target: document.body, props: { library, view: new ListState(library) } });
