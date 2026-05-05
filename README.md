# Markmap Studio

> 貼上 Markdown，即時繪製可互動心智圖。完全在瀏覽器執行，不上傳任何內容。

## 功能

- **左右分割面板**：左邊 Markdown 編輯器（CodeMirror 6 語法高亮），右邊即時心智圖
- **下載**：互動 HTML（離線可開）／ SVG ／ PNG ／ JPG
- **上傳**：拖曳或點選 `.md` / `.markdown` / `.txt` 檔案載入
- **可分享連結**：把 Markdown 編碼進 URL hash，貼連結即可分享內容（不經任何伺服器）
- **深色模式**：跟隨系統 / 手動切換 / 記住偏好
- **零後端**：所有渲染都在你的瀏覽器，內容永遠不會傳到任何伺服器

## 線上版

部署至 GitHub Pages：[https://linzoie.github.io/markmap-studio/](https://linzoie.github.io/markmap-studio/)

## 本機開發

```bash
pnpm install
pnpm dev      # 開啟 http://localhost:5173/markmap-studio/
pnpm build    # 輸出靜態檔到 dist/
pnpm preview  # 本機預覽 build 後的成果
```

## 部署

`main` 分支推上去後，GitHub Actions 會自動 build 並部署到 GitHub Pages。

第一次使用前，請到 repo Settings → Pages → **Source** 選 `GitHub Actions`。

## 隱私

- 你貼上的 Markdown **永遠不會離開你的瀏覽器**。
- 「Share」功能把內容編碼到 URL hash 之後，連結是給你**自己**複製去傳的；URL hash 不會送到伺服器。
- 不收集任何使用紀錄、不放追蹤碼、不用 cookie。

## 專案結構

```
src/
  main.js                 入口，把所有模組串起來
  editor.js               CodeMirror 設定
  renderer.js             markmap 渲染與更新
  downloads.js            HTML / SVG / PNG / JPG 下載
  upload.js               檔案上傳
  permalink.js            URL hash 編碼／解碼
  splitter.js             可拖曳分割列
  theme.js                深色模式
  toast.js                通知
  sample.js               預設範例 Markdown
  standalone-template.js  下載 HTML 用的模板
  style.css               全部樣式
```
