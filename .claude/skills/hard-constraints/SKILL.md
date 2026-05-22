---
name: hard-constraints
description: |
  Use this skill whenever adding any new dependency, or when the user requests
  features like analytics, login, backend, AI integration, tracking, or telemetry
  — even if not explicitly asked. 守護 no backend / no AI / no telemetry 三條硬規則。
allowed-tools: Read, Write, Edit, Grep, Glob
---

# markmap-studio：三條硬規則（不可違反）

這個 repo 存在的理由就是「**純前端、純隱私、純渲染**」。違反任一條 = 拆掉這個 repo 存在的意義。
看到使用者請求觸發任一條時：**先拒絕、解釋、提替代方案**，不要悄悄加進去。

## 規則 1：**No backend. Ever.**

→ 整個站維持靜態（GitHub Pages 即可 host）。

**違反的徵兆**：
- 任何 `fetch('/api/...')`、`fetch('https://api...')` 到自家伺服器
- 加入 Node.js server-side code、Express、Next.js API routes
- 任何要持久化到自家 DB／需要使用者帳號的功能

**正解**：
- 永久化用 `localStorage` 或 URL hash（`src/permalink.js` 用 lz-string 壓 markdown 到 URL）
- 需要伺服器的功能 → **不屬於這個 repo**，建議放到姊妹專案 `code/article-to-mindmap`（CLI + 未來 web pipeline）

**拒絕模板**：
> 這個功能需要伺服器（理由：XXX）。本 repo 鐵則是「no backend」—— 它要永遠維持
> GitHub Pages 上的靜態網站。建議的替代：(1) 改成純前端方案（用 localStorage / URL 編碼），
> 或 (2) 把這功能放到 `code/article-to-mindmap` 那邊做。

## 規則 2：**No telemetry, no analytics.**

→ 隱私是產品。

**違反的徵兆**：
- Google Analytics、Plausible、Mixpanel、PostHog、Sentry 等任何 tracking SDK
- 第三方 CDN script tag（即使「只是」字型）—— 因為會在使用者瀏覽器留 IP/header 紀錄
- 主動上報 `fetch('https://...', {body: usageData})`
- 任何形式的「使用統計」、「錯誤上報到雲端」

**正解**：
- Debug 用 `console.log` / `console.error`，使用者自己看
- 字型／lib 全部 **bundle** 進 dist，不從 CDN 載

> 例外（已記錄）：KaTeX 在 standalone HTML 下載產物裡是 CDN 載入（為了壓檔案大小）。
> 那是「使用者自己下載走的 HTML」，不是主站的隱私問題 —— 主站本身仍然 zero CDN。

**拒絕模板**：
> 加 [analytics 名稱] 違反規則 2「no telemetry」。本 repo 連 hit count 都不收。
> 若你想知道使用量，建議改用 GitHub 的 traffic insights（Settings → Insights → Traffic），
> 它是 server-side 統計，使用者瀏覽器零負擔。

## 規則 3：**No AI / LLM dependencies.**

→ 純渲染。這個 repo 跟任何 LLM 零關係。

**違反的徵兆**：
- 加入 `@anthropic-ai/sdk`、`openai`、`@google/generative-ai`、`groq-sdk` 等
- 在前端呼叫任何 AI API（即使是「只是為了潤稿」）
- 預設用 AI 補全 Markdown、自動生成心智圖等

**正解**：
- AI 自動化的功能線完全留給姊妹專案 `code/article-to-mindmap`（CLI 已分階段規劃 Phase 3 加 AI pipeline）
- 在 markmap-studio 內 AI 永遠是「外部步驟」：使用者用 Claude 對話拿到 markmap MD，**手動貼進**這個編輯器，渲染。

**拒絕模板**：
> 在這個 repo 加 LLM SDK 違反規則 3「no AI/LLM dependencies」。整個 repo 的存在意義就是
> 「分離渲染與 AI」，讓它可以保持 zero LLM 相依、純前端可信。AI 自動化線請走
> `code/article-to-mindmap` —— 那個專案就是為這類功能規劃的。

## 三規則的「為什麼」

這不是潔癖，是工程槓桿：

- **No backend** → 維護成本接近 0、可永久免費 host、無 server 危險點
- **No telemetry** → 隱私可作為產品差異點、不必處理 GDPR/Cookie consent
- **No AI** → 不會因 API key／費用／rate limit 而炸；保持工具屬性而非服務屬性

三者合起來：**這個 repo 可以 5 年不維護仍然能跑**。任何違反其中之一的改動，都會把這個性質拿掉。