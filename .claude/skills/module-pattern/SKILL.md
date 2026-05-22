---
name: module-pattern
description: |
  Use this skill whenever editing any file under src/, adding a new module, or
  refactoring module boundaries — even if not explicitly asked. 規範 initX()
  慣例、模組不互 import、main.js 是唯一接線點、共用狀態集中 main.js。
allowed-tools: Read, Write, Edit, Grep, Glob
---

# markmap-studio：模組組裝慣例

這個 repo 是純 vanilla JS、沒有框架。維持小而清晰的關鍵是**嚴格的模組組裝紀律**。

## 核心慣例

1. **每個模組 export 一個 `initX(opts)` 函式**，做兩件事：
   - 註冊 DOM listeners
   - 回傳一個迷你 API（給 `main.js` 接線後續操作用）
2. **模組之間不互相 `import`**。任何模組只能 import：
   - 標準 lib（CodeMirror、markmap-*、html-to-image、d3 ...）
   - 同層的 CSS（`./style.css`）
   - **不准** `import { foo } from './otherModule.js'`
3. **`main.js` 是唯一的接線點**，是「唯一知道全部模組存在」的地方。
4. **共用可變狀態住在 `main.js`**，模組保持 pure。

→ 這個紀律讓任何模組可以被刪、被換、被獨立 debug，不會牽動其他模組。

## 真實典範（`src/main.js`）

```js
import { initEditor } from './editor.js';
import { initRenderer } from './renderer.js';
import { initSplitter } from './splitter.js';
// ...

const editor = initEditor({
  container: '#editor-pane',
  initialContent: initialMd,
});

const renderer = initRenderer({
  svg: '#mindmap',
  host: '#preview-pane',
});

initSplitter({
  splitter: '#splitter',
  host: '#app',
  onResize: () => renderer.fit(),   // ← 透過 main.js 把 splitter 跟 renderer 接起來
});
```

→ `splitter` 不知道 `renderer` 存在；`renderer` 也不知道 `splitter`。它們透過 `main.js` 注入的 callback 通訊。

## 加新模組的 6 步檢查清單

（這份清單也寫在主 CLAUDE.md「Adding a feature checklist」段，但這裡更具體）

1. **它真的屬於這個 repo 嗎？** 先看 `hard-constraints` skill：no backend / no AI / no telemetry。違反三者之一就**拒絕**。
2. 在 `src/` 開一個 `myFeature.js`，export `initMyFeature(opts)`，opts 用解構 + JSDoc 標註型別。
3. `main.js` 加 import + 呼叫 `initMyFeature({...})`，把它需要的 DOM 選擇器與 callback 傳進去。
4. 跑 `pnpm dev` 看 hot reload；確認沒打到 console error。
5. 跑 `pnpm build`（CI 也會跑）—— bundle 失敗就 push 不上去。
6. Commit；推上 main，GitHub Actions 自動 deploy 到 Pages。

## 反例

```js
// ❌ 模組互相 import
// src/upload.js
import { renderer } from './renderer.js';   // 不可以！繞回 main.js

// ✅ 正解：上層 main.js 注入 callback
// src/upload.js
export function initUpload({ input, onLoad }) {
  input.addEventListener('change', async (e) => {
    const text = await e.target.files[0].text();
    onLoad(text);   // 由 main.js 提供，回 main.js 處理
  });
}

// ❌ 共用狀態散落各模組
// src/theme.js  let currentTheme = 'light';   // 該住在 main.js

// ❌ 模組偷偷做副作用
export function initEditor() {
  document.title = '...';   // initX 應該只動 opts.container 與 listeners
}
```

## 為什麼這麼嚴

UI 小（12 模組），框架（React/Vue）的 ceremony 完全不划算。但小規模 vanilla JS 容易腐化成
「每個檔案都 import 隔壁三個檔案」的義大利麵 —— 嚴守 `initX(opts) + main.js 接線` 是
防止那個的最低成本方法。