// Five download targets:
//   1. MD    - the editor's raw Markdown
//   2. HTML  - self-contained interactive page (rendered from current MD)
//   3. SVG   - full mindmap as currently expanded (vector)
//   4. PNG   - full mindmap as currently expanded (raster)
//   5. JPG   - same as PNG but JPEG codec, white background
//
// "Full mindmap" means the entire visible tree at its current expansion
// state, NOT just whatever portion of it happens to fit in the preview
// pane viewport. We compute the inner content's bounding box, clone the
// SVG into an offscreen container at that exact size with viewBox set
// accordingly, then capture from the clone. Live preview is undisturbed.

import { Transformer } from 'markmap-lib';
import { toPng, toJpeg } from 'html-to-image';
import { STANDALONE_TEMPLATE } from './standalone-template.js';

const transformer = new Transformer();

// Padding around the content bbox so nothing touches the edge of the image.
const EXPORT_PADDING = 24;

// Raster (PNG/JPG) output cap. The exported image will fit inside this
// box while preserving aspect ratio. SVG export is uncapped because
// it's vector and downstream tools resize freely.
const MAX_RASTER_WIDTH  = 1920;
const MAX_RASTER_HEIGHT = 1080;

// HiDPI multiplier applied when there's headroom under the cap.
// Small mindmaps render at this many physical pixels per SVG unit;
// large ones scale down so the final output never exceeds the cap.
const HIDPI_RATIO = 2;

// Inline stylesheet embedded into the exported SVG so the file looks the
// same when opened standalone (without our app's CSS in scope).
const EXPORT_INLINE_CSS = `
  foreignObject img { max-width: 240px; max-height: 180px; height: auto; width: auto; display: inline-block; object-fit: contain; vertical-align: middle; }
  foreignObject pre { margin: 4px 0; padding: 6px 8px; background: #f7f7f8; border-radius: 4px; overflow: auto; font-size: 12px; }
  foreignObject code { font-family: ui-monospace, "Cascadia Code", Consolas, monospace; font-size: .9em; }
  foreignObject table { border-collapse: collapse; font-size: 12px; }
  foreignObject th, foreignObject td { border: 1px solid #e4e4e7; padding: 2px 6px; }
`;

export const downloads = {
  md(content) {
    const title = extractTitle(content) || 'Mindmap';
    saveBlob(new Blob([content ?? ''], { type: 'text/markdown;charset=utf-8' }), `${slug(title)}.md`);
    return title;
  },

  html(md) {
    const { root, frontmatter } = transformer.transform(md ?? '');
    const title = extractTitle(md) || 'Mindmap';
    const opts = frontmatter?.markmap ?? null;
    const html = STANDALONE_TEMPLATE
      .replace('__MARKMAP_TITLE__', escapeHtml(title))
      .replace('/*__MARKMAP_DATA__*/null/*__END__*/', JSON.stringify(root))
      .replace('/*__MARKMAP_OPTS__*/null/*__END_OPTS__*/', JSON.stringify(opts));
    saveBlob(new Blob([html], { type: 'text/html;charset=utf-8' }), `${slug(title)}.html`);
    return title;
  },

  svg(svgEl, title) {
    const handle = createExportClone(svgEl, { withInlineStyles: true });
    try {
      const xml = '<?xml version="1.0" encoding="UTF-8"?>\n' +
        new XMLSerializer().serializeToString(handle.clone);
      saveBlob(new Blob([xml], { type: 'image/svg+xml;charset=utf-8' }), `${slug(title)}.svg`);
    } finally {
      handle.dispose();
    }
  },

  async png(svgEl, title, opts = {}) {
    const dataUrl = await captureFull(svgEl, 'png', opts);
    saveDataUrl(dataUrl, `${slug(title)}.png`);
  },

  async jpg(svgEl, title, opts = {}) {
    const dataUrl = await captureFull(svgEl, 'jpg', opts);
    saveDataUrl(dataUrl, `${slug(title)}.jpg`);
  },
};

// --- full-view capture --------------------------------------------------

async function captureFull(svgEl, format, { hd = false } = {}) {
  const handle = createExportClone(svgEl, { withInlineStyles: false });
  try {
    // Let the browser actually layout the cloned SVG before snapshotting.
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));

    // hd=true → no cap, just natural × HIDPI_RATIO (uncompressed sharp).
    // hd=false → fit inside MAX_RASTER_WIDTH × MAX_RASTER_HEIGHT.
    const { pixelRatio } = hd
      ? { pixelRatio: HIDPI_RATIO }
      : computeOutputSize(handle.width, handle.height);

    const fn = format === 'jpg' ? toJpeg : toPng;
    const opts = {
      width: handle.width,
      height: handle.height,
      pixelRatio,
      cacheBust: true,
      backgroundColor: format === 'jpg' ? '#ffffff' : getComputedBackground(svgEl),
    };
    if (format === 'jpg') opts.quality = hd ? 0.99 : 0.95;

    return await fn(handle.clone, opts);
  } finally {
    handle.dispose();
  }
}

/**
 * Decide the final raster output dimensions and the pixelRatio to feed
 * html-to-image. We start by aiming for HiDPI (natural × HIDPI_RATIO),
 * then scale that ideal down uniformly until both axes fit under the
 * configured cap. Aspect ratio is always preserved; we never scale up
 * beyond HIDPI_RATIO.
 */
function computeOutputSize(naturalW, naturalH) {
  const idealW = naturalW * HIDPI_RATIO;
  const idealH = naturalH * HIDPI_RATIO;
  const scale = Math.min(
    1,
    MAX_RASTER_WIDTH  / idealW,
    MAX_RASTER_HEIGHT / idealH,
  );
  return {
    pixelRatio: HIDPI_RATIO * scale,
    outW: Math.round(idealW * scale),
    outH: Math.round(idealH * scale),
  };
}

/**
 * Clone the live SVG into an offscreen container, sized to the full
 * content bounding box and with any d3 zoom/pan transform on the
 * content <g> reset so what we serialize matches what we measured.
 *
 * The clone keeps id="mindmap" so application CSS rules that target
 * #mindmap foreignObject ... still match (browsers permit duplicate
 * IDs for CSS matching purposes — they only break getElementById).
 */
function createExportClone(svgEl, { withInlineStyles }) {
  const inner = svgEl.querySelector('g');
  if (!inner) throw new Error('Mindmap has no content to export');

  // Bounding box in the SVG's user-space (independent of zoom transforms).
  const bbox = inner.getBBox();
  if (!bbox.width || !bbox.height) {
    throw new Error('Mindmap has no rendered geometry yet — wait for it to render and try again.');
  }
  const x = bbox.x - EXPORT_PADDING;
  const y = bbox.y - EXPORT_PADDING;
  const w = Math.max(1, Math.ceil(bbox.width + 2 * EXPORT_PADDING));
  const h = Math.max(1, Math.ceil(bbox.height + 2 * EXPORT_PADDING));

  const clone = svgEl.cloneNode(true);
  clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  clone.setAttribute('viewBox', `${x} ${y} ${w} ${h}`);
  clone.setAttribute('width', String(w));
  clone.setAttribute('height', String(h));
  clone.removeAttribute('style');

  // Drop the d3 zoom transform from the cloned content group so the
  // viewBox we computed actually contains everything.
  const cloneInner = clone.querySelector('g');
  if (cloneInner) cloneInner.removeAttribute('transform');

  if (withInlineStyles) {
    const style = document.createElementNS('http://www.w3.org/2000/svg', 'style');
    style.textContent = EXPORT_INLINE_CSS;
    clone.insertBefore(style, clone.firstChild);
  }

  // Hidden offscreen host. Position fixed avoids polluting layout flow.
  const container = document.createElement('div');
  container.setAttribute('aria-hidden', 'true');
  container.style.cssText = [
    'position: fixed',
    'left: -99999px',
    'top: 0',
    `width: ${w}px`,
    `height: ${h}px`,
    'pointer-events: none',
    'z-index: -1',
    'overflow: visible',
  ].join(';');
  container.appendChild(clone);
  document.body.appendChild(container);

  return {
    clone,
    container,
    width: w,
    height: h,
    dispose() { container.remove(); },
  };
}

// --- helpers --------------------------------------------------------------

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
