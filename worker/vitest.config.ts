import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

// Read at config time (Node context — the worker sandbox has no fs), then
// handed to the test worker as a binding and applied in setupFiles.
const migrations = await readD1Migrations("./migrations");

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: { API_TOKEN: "test-token", TEST_MIGRATIONS: migrations },
        d1Databases: ["DB"],
      },
    }),
  ],
  test: {
    setupFiles: ["./test/apply-migrations.ts"],
  },
});
