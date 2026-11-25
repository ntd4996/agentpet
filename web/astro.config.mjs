// @ts-check
import { defineConfig } from 'astro/config';

import tailwindcss from '@tailwindcss/vite';
import cloudflare from '@astrojs/cloudflare';

// https://astro.build/config
export default defineConfig({
  // Preserve Astro 6 inline spacing: https://docs.astro.build/en/guides/upgrade-to/v7/#new-default-whitespace-handling-compresshtml-jsx
  compressHTML: true,

  vite: {
    plugins: [tailwindcss()]
  },

  adapter: cloudflare({ platformProxy: { enabled: true } })
});