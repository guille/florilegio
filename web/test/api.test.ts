import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, createApi, NetworkError } from "../src/lib/api";

const row = (id: string) => ({
  id,
  url: `https://example.com/${id}`,
  title: null,
  tags: "a, b,,",
  created_at: "2026-01-01T00:00:00.000Z",
  updated_at: "2026-01-01T00:00:00.000Z",
});

function serve(handler: (url: URL, init: RequestInit) => Response) {
  const calls: { url: URL; init: RequestInit }[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init: RequestInit = {}) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      calls.push({ url, init });
      return handler(url, init);
    }),
  );
  return calls;
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });

afterEach(() => vi.unstubAllGlobals());

describe("listAll", () => {
  it("pages until a short page, parses tags and keeps the validator", async () => {
    const pages = [Array.from({ length: 200 }, (_, i) => row(`r${i}`)), [row("last")]];
    const calls = serve((url) =>
      json(pages[Number(url.searchParams.get("offset")) / 200], 200, { ETag: '"7"' }),
    );

    const result = await createApi("example.test/", "tok").listAll();

    expect(result?.bookmarks).toHaveLength(201);
    expect(result?.bookmarks[0].tags).toEqual(["a", "b"]);
    expect(result?.syncToken).toBe('"7"');
    expect(calls.map((c) => c.url.href)).toEqual([
      "https://example.test/bookmarks?limit=200&offset=0",
      "https://example.test/bookmarks?limit=200&offset=200",
    ]);
    expect(new Headers(calls[0].init.headers).get("Authorization")).toBe("Bearer tok");
  });

  it("sends If-None-Match on the first page only and maps 304 to null", async () => {
    const calls = serve(() => new Response(null, { status: 304 }));
    expect(await createApi("https://x.test", "t").listAll('"3"')).toBeNull();
    expect(new Headers(calls[0].init.headers).get("If-None-Match")).toBe('"3"');
  });

  it("drops the validator for a torn snapshot and dedupes shifted rows", async () => {
    const first = Array.from({ length: 200 }, (_, i) => row(`r${i}`));
    serve((url) =>
      url.searchParams.get("offset") === "0"
        ? json(first, 200, { ETag: '"1"' })
        : json([row("r199")], 200, { ETag: '"2"' }),
    );
    const result = await createApi("https://x.test", "t").listAll();
    expect(result?.bookmarks).toHaveLength(200);
    expect(result?.syncToken).toBeNull();
  });
});

describe("errors", () => {
  it("surfaces the server's status", async () => {
    serve(() => json({ error: "Unauthorized" }, 401));
    const err = await createApi("https://x.test", "t")
      .delete("id")
      .catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.userMessage).toBe("Authentication failed — check your token");
  });

  it("maps an unreachable server to NetworkError", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));
    const err = await createApi("https://x.test", "t")
      .delete("id")
      .catch((e) => e);
    expect(err).toBeInstanceOf(NetworkError);
  });

  it("reports a duplicate instead of throwing", async () => {
    serve(() => json({ error: "Bookmark already exists", existing_id: "abc" }, 409));
    expect(await createApi("https://x.test", "t").create("https://a.test")).toEqual({
      existingId: "abc",
    });
  });
});
