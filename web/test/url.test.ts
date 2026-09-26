import { describe, expect, it } from "vitest";
import { extractUrl, highlight, parseUrlInput, timeAgo } from "../src/lib/url";

describe("extractUrl", () => {
  it.each([
    ["https://example.com", "https://example.com"],
    ["Check this out: https://example.com/a?b=1.", "https://example.com/a?b=1"],
    ["(see https://example.com/x)", "https://example.com/x"],
    ["<https://example.com>", "https://example.com"],
    ["HTTP://EXAMPLE.COM/!?", "HTTP://EXAMPLE.COM/"],
    ["no link here", null],
    ["ftp://example.com", null],
  ])("%s", (text, url) => expect(extractUrl(text)).toBe(url));
});

describe("parseUrlInput", () => {
  it.each([
    ["https://example.com/a", "https://example.com/a"],
    ["example.com", "https://example.com"],
    [" news.ycombinator.com/item?id=1 ", "https://news.ycombinator.com/item?id=1"],
    ["not a url", null],
    ["3.14", null],
    ["localhost", null],
  ])("%s", (text, url) => expect(parseUrlInput(text)).toBe(url));
});

describe("timeAgo", () => {
  const now = Date.parse("2026-09-26T12:00:00Z");
  it.each([
    ["2026-09-26T11:59:30Z", "just now"],
    ["2026-09-26T11:55:00Z", "5m ago"],
    ["2026-09-26T09:00:00Z", "3h ago"],
    ["2026-09-20T12:00:00Z", "6d ago"],
    ["2026-06-01T12:00:00Z", "3mo ago"],
    ["2024-01-01T12:00:00Z", "2y ago"],
  ])("%s", (iso, label) => expect(timeAgo(iso, now)).toBe(label));
});

describe("highlight", () => {
  it("marks every case-insensitive match", () => {
    expect(highlight("Dart and DART", "dart")).toEqual([
      { text: "Dart", hit: true },
      { text: " and ", hit: false },
      { text: "DART", hit: true },
    ]);
  });

  it("keeps offsets when lowercasing changes the length", () => {
    expect(highlight("İstanbul guide", "guide")).toEqual([
      { text: "İstanbul ", hit: false },
      { text: "guide", hit: true },
    ]);
  });

  it("matches regex metacharacters literally", () => {
    expect(highlight("a.b axb", "a.b")).toEqual([
      { text: "a.b", hit: true },
      { text: " axb", hit: false },
    ]);
  });

  it("passes text through without a query", () => {
    expect(highlight("abc", " ")).toEqual([{ text: "abc", hit: false }]);
  });
});
