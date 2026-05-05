// Entry point. Wires all the small modules together. Modules don't talk
// to each other — main.js is the only place that knows about all of them.

import './style.css';

import { initEditor } from './editor.js';
import { initRenderer } from './renderer.js';
import { initSplitter } from './splitter.js';
import { initUpload } from './upload.js';
import { initTheme } from './theme.js';
import { showToast } from './toast.js';
import { downloads } from './downloads.js';
import { readPermalink, updatePermalink, buildShareUrl } from './permalink.js';
import { SAMPLE_MD } from './sample.js';

// --- bootstrap ------------------------------------------------------------

const initialMd = readPermalink() ?? SAMPLE_MD;

const editor = initEditor({
  container: '#editor-pane',
  initialContent: initialMd,
});

const renderer = initRenderer({
  svg: '#mindmap',
  host: '#preview-pane',
});

initTheme({ button: '#btn-theme' });

initSplitter({
  splitter: '#splitter',
  host: '#app',
  onResize: () => renderer.fit(),
});

initUpload({
  input: '#file-input',
  trigger: '#btn-upload',
  onLoad: (text, name) => {
    editor.setContent(text);
    showToast(`已載入 ${name}`, { type: 'ok' });
  },
  onError: (err) => showToast(err.message ?? '檔案讀取失敗', { type: 'err' }),
});

// First render
renderer.update(initialMd);

// --- live update with debouncing -----------------------------------------

let renderTimer = null;
let permalinkTimer = null;

editor.onChange((md) => {
  clearTimeout(renderTimer);
  renderTimer = setTimeout(() => {
    try {
      renderer.update(md);
    } catch (err) {
      console.error('[render]', err);
      showToast('Markmap 解析失敗（看一下 Markdown 結構）', { type: 'err' });
    }
  }, 250);

  clearTimeout(permalinkTimer);
  permalinkTimer = setTimeout(() => updatePermalink(md), 600);
});

// --- toolbar buttons ------------------------------------------------------

document.getElementById('btn-sample').addEventListener('click', () => {
  editor.setContent(SAMPLE_MD);
  showToast('已載入示範內容', { type: 'ok' });
});

document.getElementById('btn-copy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(editor.getContent());
    showToast('Markdown 已複製到剪貼簿', { type: 'ok' });
  } catch {
    showToast('複製失敗（瀏覽器拒絕剪貼簿存取）', { type: 'err' });
  }
});

document.getElementById('btn-share').addEventListener('click', async () => {
  const url = buildShareUrl(editor.getContent());
  try {
    await navigator.clipboard.writeText(url);
    showToast('分享連結已複製到剪貼簿', { type: 'ok' });
  } catch {
    // Fallback: prompt() lets the user copy manually
    window.prompt('複製這個連結來分享：', url);
  }
});

document.getElementById('btn-md').addEventListener('click', () => {
  try {
    const title = downloads.md(editor.getContent());
    showToast(`已下載 Markdown（${title}.md）`, { type: 'ok' });
  } catch (err) {
    console.error(err);
    showToast('下載 Markdown 失敗', { type: 'err' });
  }
});

document.getElementById('btn-html').addEventListener('click', () => {
  try {
    const title = downloads.html(editor.getContent());
    showToast(`已下載 HTML（${title}）`, { type: 'ok' });
  } catch (err) {
    console.error(err);
    showToast('下載 HTML 失敗', { type: 'err' });
  }
});

document.getElementById('btn-svg').addEventListener('click', () => {
  try {
    downloads.svg(renderer.getSvg(), getCurrentTitle());
    showToast('已下載 SVG', { type: 'ok' });
  } catch (err) {
    console.error(err);
    showToast('下載 SVG 失敗', { type: 'err' });
  }
});

document.getElementById('btn-png').addEventListener('click', async () => {
  try {
    await downloads.png(renderer.getSvg(), getCurrentTitle());
    showToast('已下載 PNG', { type: 'ok' });
  } catch (err) {
    console.error(err);
    showToast('下載 PNG 失敗', { type: 'err' });
  }
});

document.getElementById('btn-jpg').addEventListener('click', async () => {
  try {
    await downloads.jpg(renderer.getSvg(), getCurrentTitle());
    showToast('已下載 JPG', { type: 'ok' });
  } catch (err) {
    console.error(err);
    showToast('下載 JPG 失敗', { type: 'err' });
  }
});

function getCurrentTitle() {
  const m = editor.getContent().match(/^\s*#\s+(.+?)\s*$/m);
  return m ? m[1].trim() : 'mindmap';
}

// --- window resize triggers fit ------------------------------------------

let fitTimer = null;
window.addEventListener('resize', () => {
  clearTimeout(fitTimer);
  fitTimer = setTimeout(() => renderer.fit(), 150);
});
