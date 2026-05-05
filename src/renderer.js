// Wraps markmap-view + markmap-lib + markmap-toolbar.
// Exposes update(md), fit(), and accessors used by downloads.
//
// Beyond the basics:
//   - Reads YAML frontmatter `markmap:` block and feeds it into
//     deriveOptions, so settings like maxWidth / initialExpandLevel /
//     colorFreezeLevel actually take effect.
//   - After each layout, runs KaTeX `renderMathInElement` and
//     `Prism.highlightAllUnder` against the SVG's foreignObject nodes
//     so math/code render as expected.
//
// KaTeX & Prism are loaded via <script defer> tags in index.html.
// We tolerate them not being ready yet by polling briefly.

import { Transformer } from 'markmap-lib';
import { Markmap, deriveOptions } from 'markmap-view';
import { Toolbar } from 'markmap-toolbar';
import 'markmap-toolbar/dist/style.css';

const KATEX_DELIMITERS = [
  { left: '$$', right: '$$', display: true },
  { left: '$',  right: '$',  display: false },
];

// Walk the raw Markdown to extract the language hint of every fenced
// code block, in document order. We use this to recover language info
// that markmap's HTML→tree pipeline drops by the time it reaches the
// rendered <code> element.
function extractFencedLangs(md) {
  if (!md) return [];
  const langs = [];
  let inFence = false;
  let fenceMarker = null; // ``` or ~~~
  for (const line of md.split(/\r?\n/)) {
    const m = line.match(/^[ \t]*(```+|~~~+)\s*([^\s`~]*)/);
    if (!m) continue;
    if (!inFence) {
      inFence = true;
      fenceMarker = m[1][0]; // remember which marker opened it
      langs.push((m[2] || '').toLowerCase());
    } else if (m[1][0] === fenceMarker) {
      inFence = false;
      fenceMarker = null;
    }
  }
  return langs;
}

export function initRenderer({ svg, host }) {
  const svgEl = typeof svg === 'string' ? document.querySelector(svg) : svg;
  const hostEl = typeof host === 'string' ? document.querySelector(host) : host;
  const transformer = new Transformer();

  let mm = null;
  let lastRoot = null;
  let lastFrontmatter = null;
  let lastFencedLangs = [];
  let toolbarMounted = false;

  function update(md) {
    const { root, frontmatter } = transformer.transform(md ?? '');
    lastRoot = root;
    lastFencedLangs = extractFencedLangs(md);
    const newFrontmatter = JSON.stringify(frontmatter?.markmap ?? {});

    if (!mm || newFrontmatter !== lastFrontmatter) {
      // Frontmatter changed (or first run): rebuild the markmap so
      // options like initialExpandLevel actually re-apply.
      teardown();
      const opts = deriveOptions(frontmatter?.markmap ?? {});
      mm = Markmap.create(svgEl, opts, root);
      lastFrontmatter = newFrontmatter;
      mountToolbar();
    } else {
      mm.setData(root);
      mm.fit();
    }
    schedulePostProcess();
    return root;
  }

  function teardown() {
    if (mm) {
      try { mm.destroy(); } catch { /* older versions don't expose destroy */ }
      mm = null;
    }
    // Wipe SVG children — destroy() does not always clear them.
    while (svgEl.firstChild) svgEl.removeChild(svgEl.firstChild);
    if (toolbarMounted) {
      hostEl.querySelectorAll('.mm-toolbar').forEach((el) => el.remove());
      toolbarMounted = false;
    }
  }

  function mountToolbar() {
    if (toolbarMounted) return;
    const tb = new Toolbar();
    tb.attach(mm);
    const tbEl = tb.render();
    tbEl.classList.add('mm-toolbar');
    hostEl.appendChild(tbEl);
    toolbarMounted = true;
  }

  // markmap renders nodes asynchronously via d3 transitions, so the
  // DOM we want to post-process doesn't exist yet right after setData.
  // Run a few short retries.
  let postTimer = null;
  function schedulePostProcess() {
    clearTimeout(postTimer);
    let tries = 0;
    function tick() {
      runPostProcess();
      if (++tries < 6) postTimer = setTimeout(tick, 200);
    }
    postTimer = setTimeout(tick, 60);
  }

  function runPostProcess() {
    const fos = svgEl.querySelectorAll('foreignObject');
    if (!fos.length) return;

    // KaTeX — walk each foreignObject so $...$ blocks render in place
    if (window.renderMathInElement) {
      fos.forEach((fo) => {
        try {
          window.renderMathInElement(fo, {
            delimiters: KATEX_DELIMITERS,
            throwOnError: false,
            ignoredClasses: ['katex'],
          });
        } catch { /* per-node failure should not break the whole pass */ }
      });
    }

    // Prism — match each rendered <pre> with the corresponding fenced
    // code block from the source Markdown (lastFencedLangs is in
    // document order). This is the most reliable way to recover the
    // language since markmap strips the class server-side and we
    // can't easily monkey-patch its internal markdown-it.
    if (window.Prism && window.Prism.highlightElement) {
      const pres = svgEl.querySelectorAll('pre');
      let langIdx = 0;
      pres.forEach((pre) => {
        try {
          // Ensure there's a <code> child to highlight (markmap usually
          // wraps but we're defensive).
          let code = pre.querySelector('code');
          if (!code) {
            code = document.createElement('code');
            while (pre.firstChild) code.appendChild(pre.firstChild);
            pre.appendChild(code);
          }
          if (code.dataset.markmapPrismDone === '1') {
            langIdx += 1;
            return;
          }

          const lang = lastFencedLangs[langIdx] || pickLang(code) || pickLang(pre);
          langIdx += 1;
          if (!lang) return;

          const klass = `language-${lang}`;
          if (!code.className.includes(klass)) {
            code.className = (code.className + ' ' + klass).trim();
          }
          window.Prism.highlightElement(code);
          code.dataset.markmapPrismDone = '1';
        } catch { /* ignore single-block failures */ }
      });
    }
  }

  function fit() { mm?.fit(); }

  // Extract a language hint from an element's class or data-language.
  function pickLang(el) {
    if (!el) return null;
    if (el.dataset && el.dataset.language) return el.dataset.language;
    const m = (el.className || '').toString().match(/\blanguage-([\w+\-#]+)/);
    return m ? m[1] : null;
  }

  return {
    update,
    fit,
    getSvg: () => svgEl,
    getRoot: () => lastRoot,
    getMarkmap: () => mm,
  };
}
