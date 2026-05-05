// Comprehensive sample exercising every markmap-supported feature.
// Modeled after markmap.js.org/repl, in zh-Hant + English.
//
// Markmap rule of thumb: content under a heading only becomes a child
// NODE if it's wrapped in a list. Plain paragraphs collapse into the
// heading itself and disappear from the rendered tree. Hence every
// "leaf" demo here uses `-` list items.

export const SAMPLE_MD = `---
title: Markmap Studio
markmap:
  colorFreezeLevel: 2
  initialExpandLevel: 3
  maxWidth: 320
  duration: 350
---

# Markmap Studio

## 連結 / Links

- [Website](https://linzoie.github.io/markmap-studio/)
- [GitHub](https://github.com/linzoie/markmap-studio)
- [markmap 官方](https://markmap.js.org)

## 文字格式 / Formatting

### 行內樣式
- **粗體** ~~刪除線~~ *斜體* ==螢光標記==
- \`inline code\`
- [連結](https://katex.org/docs/supported.html)
- ![logo](https://markmap.js.org/favicon.png)

### 待辦清單
- [x] 完成的待辦項目
- [ ] 未完成的待辦項目
- [ ] 另一個未完成項目

## 程式碼 / Code

### JavaScript
- \`\`\`js
const greet = (name) => \`Hello, \${name}!\`;
console.log(greet('Markmap'));
\`\`\`

### Python
- \`\`\`python
def fib(n):
    return n if n < 2 else fib(n - 1) + fib(n - 2)
\`\`\`

## 表格 / Tables

### 範例
- | 產品 | 價格 |
  |------|-----:|
  | Apple | 4 |
  | Banana | 2 |
  | Cherry | 6 |

## 數學 / Math

### Inline math
- 愛因斯坦質能等價 $E = mc^2$
- 圓周率 $\\pi \\approx 3.14159$
- 二次公式 $x = {-b \\pm \\sqrt{b^2 - 4ac} \\over 2a}$

### Display math
- 高斯積分 $$\\int_{-\\infty}^{\\infty} e^{-x^2} \\, dx = \\sqrt{\\pi}$$
- 歐拉恆等式 $$e^{i\\pi} + 1 = 0$$

## Frontmatter 配置

### 常用選項
- \`colorFreezeLevel: 2\` — 從第 2 層開始繼承顏色
- \`initialExpandLevel: 3\` — 預設展開到第 3 層
- \`maxWidth: 320\` — 單節點文字最大寬度（px）
- \`duration: 350\` — 動畫時間（ms）

### 隱藏節點 <!-- markmap: fold -->
- 加 \`<!-- markmap: fold -->\` 在標題尾端
- 該節點預設收合（你看到這個分支被自動收起就是這個原因）

### 長文字示範
- 這是一段刻意寫得很長很長很長的文字，用來示範 \`maxWidth\` 設定如何讓單一節點的文字自動換行而不是擠在同一行讓畫面爆掉

## 隱私 / Privacy

### 完全本機運作
- 你貼的 Markdown **永遠不會**離開這個分頁
- 所有渲染、下載都在你的瀏覽器
- 分享連結把內容**壓縮編碼**進 URL，不經任何伺服器
`;
