# Project: markmap-studio

A pure-frontend webapp: paste Markdown → live mindmap, with download (HTML/SVG/PNG/JPG), upload, and shareable URLs. Sister project to `article-to-mindmap` (CLI + future AI pipeline).

## Hard rules

1. **No backend.** Ever. This site stays purely static. If a feature requires a server, it does NOT belong here — it belongs in the sibling AI pipeline project.
2. **No telemetry, no analytics.** Privacy is the product.
3. **No AI / LLM dependencies.** Rendering only. The whole point of this repo's separation is that it has zero relationship with any LLM.

## Package manager: pnpm

Same conventions as the sibling project:
- `pnpm install` (the `preinstall` hook blocks npm)
- The pnpm installed by the Claude tool is sandboxed to a virtualized AppData; for running things in a real shell, use `pnpm` if available — or rely on the GitHub Actions deploy pipeline.

## Tech stack (and why)

- **Vite** — dev server with hot reload, builds static assets.
- **Vanilla JS, no framework** — UI is small enough; React/Vue would be ceremony.
- **CodeMirror 6** — pro-feel editor with markdown syntax. Bundled, not via CDN.
- **markmap-lib + markmap-view + markmap-toolbar** — the rendering chain. Bundled.
- **html-to-image** — for PNG / JPG export from the live SVG; handles font/CSS replication into the canvas.

## Deployment

- GitHub Actions workflow at `.github/workflows/deploy.yml` builds on push to `main` and deploys `dist/` to GitHub Pages.
- The site URL is `https://linzoie.github.io/markmap-studio/` so `vite.config.js` hard-codes `base: '/markmap-studio/'`. Override with `VITE_BASE=/foo/` if forked.
- After first push, repo owner must enable Pages in Settings → Pages → Source = `GitHub Actions`.

## Module conventions

- Each module exports a small `init…` function that sets up DOM listeners and returns a tiny API.
- `main.js` wires modules together; modules don't import each other.
- Shared mutable state lives in `main.js`; modules are otherwise pure.

## Adding a feature checklist

1. Decide if it actually belongs in this repo (no backend, no AI, no analytics).
2. Add a module under `src/` with `init…(opts)` signature.
3. Wire it from `main.js`.
4. Check it works in `pnpm dev`.
5. Run `pnpm build` to ensure it bundles cleanly.
6. Commit; CI deploys.
