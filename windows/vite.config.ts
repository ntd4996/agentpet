import { defineConfig } from "vite";
import { resolve } from "path";

// Two HTML entry points: the transparent always-on-top pet overlay (index.html)
// and the Settings window (settings.html). Tauri serves these in separate windows.
export default defineConfig({
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        settings: resolve(__dirname, "settings.html"),
        popover: resolve(__dirname, "popover.html"),
        stats: resolve(__dirname, "stats.html"),
      },
    },
  },
});
