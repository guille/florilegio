export interface KV {
  get<T>(key: string): Promise<T | undefined>;
  /** Atomic read-modify-write, even across tabs. `fn` must be synchronous. */
  update<T>(key: string, fn: (current: T | undefined) => T): Promise<T>;
  /** Called with the key whenever another instance writes it. */
  watch(fn: (key: string) => void): void;
}

export class MemoryKV implements KV {
  #data = new Map<string, unknown>();
  #watchers = new Set<(key: string) => void>();

  async get<T>(key: string) {
    return structuredClone(this.#data.get(key)) as T | undefined;
  }

  async update<T>(key: string, fn: (current: T | undefined) => T) {
    const next = fn(structuredClone(this.#data.get(key)) as T | undefined);
    this.#data.set(key, structuredClone(next));
    for (const w of this.#watchers) queueMicrotask(() => w(key));
    return next;
  }

  watch(fn: (key: string) => void) {
    this.#watchers.add(fn);
  }
}

const STORE = "kv";

function request<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export async function openIndexedDB(name = "florilegio"): Promise<KV> {
  const open = indexedDB.open(name, 1);
  open.onupgradeneeded = () => open.result.createObjectStore(STORE);
  const db = await request(open);
  // Tabs share the database but not memory; tell the others what changed.
  const channel = new BroadcastChannel(`kv:${name}`);

  return {
    get: (key) => request(db.transaction(STORE, "readonly").objectStore(STORE).get(key)),

    // Readwrite transactions on one store never overlap, in this tab or any other.
    update: <T>(key: string, fn: (current: T | undefined) => T) =>
      new Promise<T>((resolve, reject) => {
        const tx = db.transaction(STORE, "readwrite");
        const store = tx.objectStore(STORE);
        let next: T;
        store.get(key).onsuccess = (e) => {
          next = fn((e.target as IDBRequest<T | undefined>).result);
          store.put(next, key);
        };
        tx.oncomplete = () => {
          channel.postMessage(key);
          resolve(next);
        };
        tx.onerror = tx.onabort = () => reject(tx.error);
      }),

    watch: (fn) => channel.addEventListener("message", (e: MessageEvent<string>) => fn(e.data)),
  };
}
