@../CLAUDE.md

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

## Known limitations (parked)

- **Code-block syntax highlighting in the live preview**: Prism is loaded
  with 14 pre-loaded languages, and `renderer.js` parses fenced langs
  out of the source Markdown to feed into `Prism.highlightElement`,
  but the visible result is unreliable. Investigations so far:
  - markmap-lib's HTML→tree pipeline strips the `language-X` class
    that markdown-it normally puts on `<code>`.
  - Monkey-patching the transformer's `md.renderer.rules.fence` had
    no observable effect (the patched md may not be the instance
    actually used, or output gets stripped after patching).
  - Falling back to Markdown-source parsing + DOM-order pairing did
    set `class="language-js"` correctly in test runs, but the user-
    visible highlighting was still inconsistent — possibly because
    markmap's animation re-applies innerHTML after our Prism pass.
  - The downloaded standalone HTML highlights correctly because its
    runtime does its own polling without markmap re-rendering it.

  Don't waste another evening on this without first capturing the
  exact DOM after Prism + after markmap's settle animation in a
  console snapshot. The fix probably lives in hooking markmap's
  post-render event rather than running our own polling.
- **KaTeX math** in live preview works. In the downloaded HTML it
  also works (CDN-loaded). No outstanding issues for math.

## Claude Code 治理（`.claude/`）

此專案已配置：

- **Hooks**：編輯後對 `.js/.json/.css/.md` 等跑 prettier、bash 指令前危險樣式攔截。
- **Skills**：
  - `module-pattern` —— `initX()` 慣例、模組不互 import、`main.js` 是唯一接線點
  - `hard-constraints` —— no backend / no AI / no telemetry 三條硬規則的自動守護
- **Slash 指令**：`/commit`
- **子代理**：`code-reviewer`

### prettier 安裝注意

`.prettierrc` 與 `.prettierignore` 已就位，但**相依套件需在你自己的 PowerShell** 執行
`pnpm add -Dw prettier` 安裝（Claude 沙盒的 pnpm virtual store 與真實 shell 不同）。
裝好前 after-edit hook 會 graceful no-op、不影響開發。GitHub Actions deploy
pipeline 不受影響（它在 CI 環境跑乾淨的 `pnpm install`）。

> **2026-05-25 狀態更新**：prettier 3.8.3 已裝、`.prettierignore` 已加 `*.md`、
> `.prettierrc` 已加 `endOfLine: auto`（避 Windows CRLF 衝突）、prettier --check . 已 0 errors。
> Stop hook `.claude/hooks/verify-before-done.ps1` 採客製版只跑 prettier --check
> （`pnpm build` 因 43 秒太重沒納入；改以 DoD 手動確認 + CI deploy.yml 兜底）。

## 開發流程

預設走 Superpowers 5.1.0 workflow（詳見工作區 `code/CLAUDE.md` 的「開發流程」段，
靠 `@../CLAUDE.md` import 已自動拉入）：

1. `/superpowers:brainstorming` — 收斂模糊需求
2. `/superpowers:writing-plans` — 產規格＋逐步計畫，寫進 `specs/`
3. `/superpowers:test-driven-development` — 先寫失敗測試，再實作
4. `/superpowers:verification-before-completion` — 宣稱完成前跑驗證
5. `/superpowers:requesting-code-review` — 完成／合併前審查

遇 bug 用 `/superpowers:systematic-debugging`。動到 `src/` 模組時 `module-pattern`
skill 會自動載入並提醒 `initX()` 慣例與「模組不互 import」原則；被要求加
analytics / backend / AI 相依時 `hard-constraints` skill 會自動載入並阻擋
（這是本 repo 的存在理由）。

## 完成的定義（Definition of Done）

markmap-studio 任務完成的具體門檻：

- `pnpm exec prettier --check .` **0 errors**
  （2026-05-25 已清乾淨；.md 已豁免）
- `pnpm build` 成功產出 `dist/`（**手動跑**，Stop hook 因 43 秒太重沒納入）
- 改 `src/` 後跑 `pnpm dev` 在本機開瀏覽器實際操作確認沒 regression
  （這個專案是 UI 工具，測試數字救不了你 —— 必須眼睛實際看）
- 加新 src/ 模組 → 對齊 `.claude/skills/module-pattern`（`initX()` 慣例、main.js 接線）
- 被要求加任何「會破壞純前端／無遙測／無 AI」的功能 → `.claude/skills/hard-constraints`
  會自動阻擋；如果你**確實**要加（fork 後私有版），請寫明動機並從 hard-constraints
  例外清單裡同意豁免
- 提交到 main → CI（`.github/workflows/deploy.yml`）會自動 build + deploy

> Stop hook `.claude/hooks/verify-before-done.ps1` 是**本專案客製版**，只跑 prettier --check。
> 因 `pnpm build` 在本機要 43 秒，放進每個 turn 結尾的 Stop 體感太差；
> 改以 CI（push 觸發）+ DoD 手動確認雙重把關。
