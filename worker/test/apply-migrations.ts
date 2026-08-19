import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

// Apply the real migrations/ so tests exercise the schema that ships, rather
// than a hand-maintained copy of it.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
