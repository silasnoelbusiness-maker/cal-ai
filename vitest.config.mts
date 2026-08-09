import { defineConfig } from "vitest/config";
import tsconfigPaths from "vite-tsconfig-paths";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [tsconfigPaths(), react()],
  resolve: {
    alias: {
      // The real "server-only" package throws when imported outside Next's
      // server-component bundling condition. Alias it to a no-op so
      // server-only modules stay importable under plain Vitest/Node.
      "server-only": new URL("./tests/setup/server-only-stub.ts", import.meta.url).pathname,
    },
  },
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
  },
});
