// Four download targets:
//   1. HTML  - self-contained interactive page (rendered from current MD)
//   2. SVG   - serialize the live SVG element
//   3. PNG   - rasterize the live SVG (current viewport)
//   4. JPG   - same as PNG but JPEG codec, white background
//
// Trigger: button click handlers wired in main.js.

import { Transformer } from 'markmap-lib';
import { toPng, toJpeg } from 'html-to-image';
import { STANDALONE_TEMPLATE } from './standalone-template.js';

const transformer = new Transformer();

export const downloads = {
  html(md) {
    const { root } = transformer.transform(md ?? '');
    const title = extractTitle(md) || 'Mindmap';
    const html = STANDALONE_TEMPLATE
      .replace('__MARKMAP_TITLE__', escapeHtml(title))
      .replace('/*__MARKMAP_DATA__*/null/*__END__*/', JSON.stringify(root));
    saveBlob(new Blob([html], { type: 'text/html;charset=utf-8' }), `${slug(title)}.html`);
    return title;
  },

  svg(svgEl, title) {
    const xml = '<?xml version="1.0" encoding="UTF-8"?>\n' + serializeSvg(svgEl);
    saveBlob(new Blob([xml], { type: 'image/svg+xml;charset=utf-8' }), `${slug(title)}.svg`);
  },

  async png(svgEl, title) {
    const dataUrl = await toPng(svgEl, pngOptions(svgEl));
    saveDataUrl(dataUrl, `${slug(title)}.png`);
  },

  async jpg(svgEl, title) {
    const dataUrl = await toJpeg(svgEl, { ...pngOptions(svgEl), quality: 0.95, backgroundColor: '#ffffff' });
    saveDataUrl(dataUrl, `${slug(title)}.jpg`);
  },
};

// --- helpers --------------------------------------------------------------

function pngOptions(svgEl) {
  const rect = svgEl.getBoundingClientRect();
  return {
    width: Math.max(1, Math.ceil(rect.width)),
    height: Math.max(1, Math.ceil(rect.height)),
    pixelRatio: 2,
    cacheBust: true,
    backgroundColor: getComputedBackground(svgEl),
  };
}

function getComputedBackground(el) {
  // Walk up looking for a non-transparent background; fall back to white.
  let node = el;
  while (node && node !== document.documentElement) {
    const bg = getComputedStyle(node).backgroundColor;
    if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
    node = node.parentElement;
  }
  return document.documentElement.classList.contains('dark') ? '#27272a' : '#ffffff';
}

function serializeSvg(svgEl) {
  // Clone so we can inline computed sizes without mutating the live SVG.
  const clone = svgEl.cloneNode(true);
  const rect = svgEl.getBoundingClientRect();
  if (!clone.getAttribute('width'))  clone.setAttribute('width',  Math.ceil(rect.width));
  if (!clone.getAttribute('height')) clone.setAttribute('height', Math.ceil(rect.height));
  if (!clone.getAttribute('xmlns'))  clone.setAttribute('xmlns',  'http://www.w3.org/2000/svg');
  return new XMLSerializer().serializeToString(clone);
}

function extractTitle(md) {
  const m = (md ?? '').match(/^\s*#\s+(.+?)\s*$/m);
  return m ? m[1].trim() : null;
}

function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function slug(s) {
  return (s || 'mindmap')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60) || 'mindmap';
}

function saveBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  triggerDownload(url, filename);
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function saveDataUrl(dataUrl, filename) {
  triggerDownload(dataUrl, filename);
}

function triggerDownload(href, filename) {
  const a = document.createElement('a');
  a.href = href;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
}
