import { describe, expect, it } from "vitest";
import { BulkTagEditor } from "../src/lib/bulk-tags.svelte";

const editor = (items: Record<string, string[]>, library: string[] = []) =>
  new BulkTagEditor(new Map(Object.entries(items).map(([id, t]) => [id, new Set(t)])), library);

describe("BulkTagEditor", () => {
  it("splits tags into all, some and suggestions", () => {
    const e = editor({ a: ["x", "y"], b: ["x"] }, ["x", "y", "z"]);
    expect([...e.active]).toEqual([
      ["x", "all"],
      ["y", "some"],
    ]);
    expect([...e.suggestions]).toEqual(["z"]);
    expect(e.hasChanges).toBe(false);
  });

  it("cycles some → all → removed → suggestion", () => {
    const e = editor({ a: ["x", "y"], b: ["x"] }, ["x", "y"]);
    e.toggle("y");
    expect(e.active.get("y")).toBe("all");
    expect(Object.fromEntries(e.changes())).toEqual({ b: ["x", "y"] });
    e.toggle("y");
    expect(e.active.has("y")).toBe(false);
    expect(e.suggestions.has("y")).toBe(true);
    expect(Object.fromEntries(e.changes())).toEqual({ a: ["x"] });
  });

  it("removes a tag every item has", () => {
    const e = editor({ a: ["x"], b: ["x"] });
    e.toggle("x");
    expect(Object.fromEntries(e.changes())).toEqual({ a: [], b: [] });
  });

  it("adds suggestions and brand-new tags to every item", () => {
    const e = editor({ a: [], b: ["q"] }, ["s"]);
    e.add("s");
    e.add("new");
    expect(Object.fromEntries(e.changes())).toEqual({ a: ["new", "s"], b: ["new", "q", "s"] });
  });

  it("doesn't turn an undone new tag into a suggestion", () => {
    const e = editor({ a: [] });
    e.add("fresh");
    e.toggle("fresh");
    expect(e.suggestions.has("fresh")).toBe(false);
    expect(e.changes().size).toBe(0);
  });

  it("refuses to add an active tag twice", () => {
    const e = editor({ a: ["x"] });
    expect(e.add("x")).toBe(false);
  });
});
