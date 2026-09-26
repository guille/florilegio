import { hc } from "hono/client";
import type { AppType, Bookmark as WireBookmark } from "$worker";

export type Bookmark = {
  id: string;
  url: string;
  title: string | null;
  tags: string[];
  createdAt: string;
  updatedAt: string;
};

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }

  get userMessage(): string {
    const s = this.status;
    if (s === 0) return this.message;
    if (s === 401) return "Authentication failed — check your token";
    if (s === 403) return "Access denied";
    if (s === 404) return "Not found";
    if (s === 409) return "Bookmark already exists";
    if (s >= 500) return `Server error (${s})`;
    return `Request failed (${s})`;
  }
}

/** The request never reached the server (timeout, DNS, refused connection),
 *  so there is no status to report. */
export class NetworkError extends ApiError {
  constructor(message: string) {
    super(0, message);
  }
}

export function friendlyError(e: unknown): string {
  return e instanceof ApiError ? e.userMessage : "Something went wrong";
}

const TOTAL_TIMEOUT_MS = 15_000;
/** Export and import move the whole collection. */
const BULK_TIMEOUT_MS = 60_000;
const PAGE_SIZE = 200;

export function normalizeBaseUrl(url: string): string {
  let u = url.trim();
  if (!/^https?:\/\//.test(u)) u = `https://${u}`;
  return u.replace(/\/+$/, "");
}

export function fromWire(b: WireBookmark): Bookmark {
  return {
    id: b.id,
    url: b.url,
    title: b.title,
    tags: parseTags(b.tags),
    createdAt: b.created_at,
    updatedAt: b.updated_at ?? b.created_at,
  };
}

function parseTags(raw: string | null): string[] {
  if (!raw) return [];
  return raw
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean);
}

/** A timeout also covers reading the body: the signal outlives fetch(). */
function isTimeout(e: unknown): boolean {
  return e instanceof DOMException && (e.name === "TimeoutError" || e.name === "AbortError");
}

function toNetworkError(e: unknown): unknown {
  if (e instanceof ApiError) return e;
  if (isTimeout(e))
    return new NetworkError("Request timed out — check your connection and try again");
  if (e instanceof TypeError)
    return new NetworkError("Could not reach the server — check your connection");
  return e;
}

async function guardedFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  try {
    return await fetch(input, {
      ...init,
      signal: init?.signal ?? AbortSignal.timeout(TOTAL_TIMEOUT_MS),
    });
  } catch (e) {
    throw toNetworkError(e);
  }
}

async function fail(res: Response): Promise<never> {
  let message = res.statusText;
  try {
    message = ((await res.json()) as { error?: string }).error ?? message;
  } catch {}
  throw new ApiError(res.status, message);
}

async function read<T>(res: { json(): Promise<T> }): Promise<T> {
  try {
    return await res.json();
  } catch (e) {
    throw toNetworkError(e);
  }
}

export type ImportResult = { imported: number; skipped: number; errors: string[] };

export type Api = ReturnType<typeof createApi>;

export function createApi(baseUrl: string, token: string) {
  const client = hc<AppType>(normalizeBaseUrl(baseUrl), {
    headers: { Authorization: `Bearer ${token}` },
    fetch: guardedFetch,
  });
  const bulk = () => ({ init: { signal: AbortSignal.timeout(BULK_TIMEOUT_MS) } });

  return {
    /** Fetch the whole collection, paginating until exhausted. Null means the
     *  server answered 304 to `ifNoneMatch`. The returned validator is null
     *  when the snapshot cannot be trusted. */
    async listAll(
      ifNoneMatch?: string | null,
    ): Promise<{ bookmarks: Bookmark[]; syncToken: string | null } | null> {
      const all: Bookmark[] = [];
      let firstEtag: string | null = null;
      let torn = false;

      for (let offset = 0; ; offset += PAGE_SIZE) {
        const conditional = offset === 0 && ifNoneMatch;
        const res = await client.bookmarks.$get(
          { query: { limit: String(PAGE_SIZE), offset: String(offset) } },
          conditional ? { headers: { "If-None-Match": ifNoneMatch } } : undefined,
        );
        if (res.status === 304) return null;
        if (!res.ok) await fail(res);
        const page = (await read(res)) as WireBookmark[];
        const etag = res.headers.get("ETag");

        if (offset === 0) firstEtag = etag;
        // A write landed between pages: keep the rows, but don't cache a
        // validator for a state we never actually saw.
        else if (etag !== firstEtag) torn = true;

        all.push(...page.map(fromWire));
        if (page.length < PAGE_SIZE) break;
      }

      // A bookmark created mid-pagination shifts rows right, so the tail of
      // one page reappears at the head of the next.
      const seen = new Set<string>();
      const bookmarks = all.filter((b) => !seen.has(b.id) && seen.add(b.id));
      return { bookmarks, syncToken: torn ? null : firstEtag };
    },

    /** Resolves to the created bookmark, or the id of the one already saved. */
    async create(url: string): Promise<{ created: Bookmark } | { existingId: string | undefined }> {
      const res = await client.bookmarks.$post({ json: { url } });
      if (res.status === 409) return { existingId: (await read(res)).existing_id };
      if (res.status !== 201) await fail(res);
      return { created: fromWire((await read(res)) as WireBookmark) };
    },

    async update(
      id: string,
      changes: { title?: string | null; tags?: string[] },
    ): Promise<Bookmark> {
      const res = await client.bookmarks[":id"].$patch({ param: { id }, json: changes });
      if (!res.ok) await fail(res);
      return fromWire(await read(res));
    },

    async delete(id: string): Promise<void> {
      const res = await client.bookmarks[":id"].$delete({ param: { id } });
      if (!res.ok) await fail(res);
    },

    /** Cheapest authenticated request, to check the endpoint and token. */
    async ping(): Promise<void> {
      const res = await client.bookmarks.$get({ query: { limit: "1", offset: "0" } });
      if (!res.ok) await fail(res);
    },

    async exportAll(): Promise<WireBookmark[]> {
      const res = await client.bookmarks.export.$get({}, bulk());
      if (!res.ok) await fail(res);
      return read(res);
    },

    async importAll(rows: unknown[]): Promise<ImportResult> {
      const res = await client.bookmarks.import.$post({ json: rows }, bulk());
      if (!res.ok) await fail(res);
      return read(res);
    },

    /** The favicon proxy needs the bearer token, so an <img src> can't load it. */
    async favicon(host: string): Promise<Blob | null> {
      const res = await client.favicon[":host"].$get({ param: { host } });
      return res.ok ? res.blob() : null;
    },
  };
}
