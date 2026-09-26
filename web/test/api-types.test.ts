import type { hc, InferRequestType, InferResponseType } from "hono/client";
import { expectTypeOf, it } from "vitest";
import type { AppType } from "$worker";

type Client = ReturnType<typeof hc<AppType>>;

// Under skipLibCheck, an unresolvable import in the worker's emitted types
// silently turns the whole client into `any`, and everything type-checks.
it("sees the worker's API types", () => {
  expectTypeOf<InferResponseType<Client["bookmarks"]["$get"], 200>>().not.toBeAny();
  expectTypeOf<InferRequestType<Client["bookmarks"]["$post"]>>().not.toBeAny();
});
