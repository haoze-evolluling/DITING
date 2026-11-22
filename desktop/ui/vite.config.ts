import { readFileSync } from "node:fs";

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

const apiTarget = process.env.DITING_DEV_API || "http://127.0.0.1:15353";

function desktopVersion(): string {
  try {
    const text = readFileSync(new URL("../service/VERSION", import.meta.url), "utf8");
    const line = text
      .split(/\r?\n/)
      .map((value) => value.trim())
      .find((value) => value && !value.startsWith("#"));
    return (line ?? "").replace(/^v/, "") || "0.0.0";
  } catch {
    return "0.0.0";
  }
}

export default defineConfig({
  plugins: [react(), tailwindcss()],
  define: {
    __APP_VERSION__: JSON.stringify(desktopVersion()),
  },
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    proxy: {
      "/api": {
        target: apiTarget,
        changeOrigin: true,
        ws: true,
      },
    },
  },
  build: {
    chunkSizeWarningLimit: 900,
  },
});
