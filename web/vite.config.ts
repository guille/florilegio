import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [svelte()],
  // Settings live in localStorage, which is per origin: a fallback port would lose them.
  server: { port: 38952, strictPort: true },
});
