import { defineConfig } from 'vite';

// GitHub Pages serves the site under /<repo-name>/, so we hard-code the
// base path to match the repo. If you fork or deploy elsewhere, override
// with the `VITE_BASE` environment variable.
const base = process.env.VITE_BASE ?? '/markmap-studio/';

export default defineConfig({
  base,
  build: {
    outDir: 'dist',
    sourcemap: false,
    target: 'es2020',
  },
  server: {
    port: 5173,
    open: true,
  },
});
