# AGENTS.md — markmap-studio

> 共用治理規則見工作區層 `../AGENTS.md`（Codex／Antigravity 會沿目錄向上自動載入；
> Claude Code 由 `CLAUDE.md` 匯入）。本檔只放**本專案專屬**內容。

## 這個專案是什麼

純前端 webapp：貼 Markdown → 即時繪製可互動心智圖，支援下載（HTML/SVG/PNG/JPG）、
拖曳上傳、把內容編碼進 URL hash 的可分享連結。`article-to-mindmap` 的姊妹站，
但**零後端、零 AI、零遙測**——這正是與姊妹站分家的原因（見下方紅線）。

## 技術棧與進入點

Vanilla JS（無框架）＋ Vite ＋ CodeMirror 6（編輯器）＋ markmap-lib/view/toolbar
（渲染鏈）＋ html-to-image（PNG/JPG 匯出），pnpm 管理。

- 安裝：`pnpm install`（`preinstall` 擋 npm，只能用 pnpm）
- 開發：`pnpm dev`（開瀏覽器在 `http://localhost:5173/markmap-studio/` 實際操作）
- 測試：`pnpm test`（`node --test "test/*.test.js"`，離線、無 DOM／無 vite，
  涵蓋 smoke.test.js 三類回歸 + property.test.js 決定性／結構保持／空輸入／
  已知結構節點數錨點；本次實跑 7 pass 0 fail，~4.9 秒）
- 建置：`pnpm build`（約 43 秒，手動跑；CI 也會跑，Stop hook 因耗時未納入）
- lint/format：`pnpm exec prettier --check .`（本次實跑 0 errors）
- 部署：push 到 `main` → GitHub Actions（`.github/workflows/deploy.yml`）
  自動 build 並 deploy 到 GitHub Pages（`vite.config.js` 寫死
  `base: '/markmap-studio/'`）

## 本專案的紅線

1. **永不加 backend。** 這個 repo 永遠純靜態。任何需要伺服器的功能不屬於這裡，
   屬於姊妹的 AI pipeline 專案。
2. **永不加 telemetry／analytics。** 隱私就是這個產品本身。
3. **永不加 AI／LLM 相依。** 只做渲染。這個 repo 存在的唯一理由就是與任何 LLM
   零關係——被要求加這類功能時 `.claude/skills/hard-constraints` 會自動載入攔擋；
   若確實要加（例如 fork 後的私有版），必須寫明動機並在該 skill 的例外清單裡
   明確同意豁免，不得默默加。
4. **貼上的內容永遠不離開瀏覽器。** Share 連結靠 URL hash 編碼、不經任何伺服器；
   不收集使用紀錄、不放追蹤碼、不用 cookie——這是產品承諾，不是內部細節。
5. **模組慣例（非安全紅線但違反會壞架構）**：每個模組匯出 `initX()`，模組間
   **不互相 import**；共用可變狀態只放 `main.js`，`main.js` 是唯一接線點——
   `.claude/skills/module-pattern` 會在動 `src/` 時自動提醒。
6. **這是 UI 工具，測試數字救不了你**：改 `src/` 後測試綠不代表沒有 regression，
   必須 `pnpm dev` 實際開瀏覽器操作確認。

## 接手前先讀

`.governance/handoff/projects/markmap-studio.md`（狀態卡＝「做到哪了」的權威來源，
含語法高亮這個懸而未決的坑的完整調查記錄）。
