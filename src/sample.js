// Comprehensive sample that exercises every feature the markmap-lib
// transformer supports, mirroring (and slightly extending) the canonical
// markmap.js.org/repl demo.
//
// What this demonstrates:
//   - YAML frontmatter with `markmap:` configuration
//   - Heading hierarchy (# ## ###)
//   - Inline formatting: **bold** ~~strikethrough~~ *italic* ==highlight==
//   - `inline code`, [links](url), images, reference-style links
//   - Task list items (- [x])
//   - KaTeX math: $\LaTeX$ inline + display
//   - Fenced code blocks with language hints
//   - GFM tables
//   - Long text wrapping (controlled by `maxWidth`)
//   - `<!-- markmap: fold -->` to collapse a node by default
//   - Multi-line content via HTML <br>

export const SAMPLE_MD = `---
title: Markmap Studio
markmap:
  colorFreezeLevel: 2
  initialExpandLevel: 2
  maxWidth: 320
  duration: 350
---

# Markmap Studio

## 連結 / Links

- [Website](https://linzoie.github.io/markmap-studio/)
- [GitHub](https://github.com/linzoie/markmap-studio)
- [markmap 官方](https://markmap.js.org)

## 功能 / Features

### 列表 / Lists

- **粗體**　~~刪除線~~　*斜體*　==螢光標記==
- \`inline code\`
- [x] 完成的待辦項目
- [ ] 未完成的待辦項目
- 數學公式：$x = {-b \\pm \\sqrt{b^2 - 4ac} \\over 2a}$ <!-- markmap: fold -->
  - [更多 KaTeX 範例](https://katex.org/docs/supported.html)
- 一段刻意寫得很長很長的文字，為了示範 \`maxWidth\` 設定如何讓單一節點的文字自動換行而不是擠在同一行
- 連結與圖片

### 區塊 / Blocks

\`\`\`js
// fenced code block
const greet = (name) => \`Hello, \${name}!\`;
console.log(greet('Markmap'));
\`\`\`

\`\`\`python
def fib(n):
    return n if n < 2 else fib(n-1) + fib(n-2)
\`\`\`

| 產品 | 價格 |
|------|-----:|
| Apple | 4 |
| Banana | 2 |
| Cherry | 6 |

![markmap logo](https://markmap.js.org/favicon.png)

## 數學 / Math

### Inline math

愛因斯坦質能等價：$E = mc^2$

### Display math

$$
\\int_{-\\infty}^{\\infty} e^{-x^2} \\, dx = \\sqrt{\\pi}
$$

## Frontmatter 配置

### 常用選項
- \`colorFreezeLevel: 2\` — 從第 2 層開始繼承顏色
- \`initialExpandLevel: 2\` — 預設展開到第 2 層
- \`maxWidth: 320\` — 單節點最大寬度（px）
- \`duration: 350\` — 動畫時間（ms）

### 隱藏節點
- 用 \`<!-- markmap: fold -->\` 註解讓節點預設收合

## 隱私 / Privacy

### 完全本機運作
- 你貼的 Markdown **永遠不會**離開這個分頁
- 所有渲染、下載都在你的瀏覽器
- 分享連結把內容**壓縮編碼**進 URL，不經任何伺服器
`;
