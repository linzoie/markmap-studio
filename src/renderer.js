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

// Markmap-lib doesn't propagate the fenced-code language hint through
// to the rendered <code> element (probably stripped during the
// HTML → tree → render pipeline). We monkey-patch the markdown-it
// fence rule to explicitly inject `class="language-X"` AND a
// `data-language="X"` attribute so the post-process pass can recover
// the language even if classes get stripped downstream.
function patchFenceRenderer(transformer) {
  const md = transformer?.md;
  if (!md?.renderer?.rules) return;
  const origFence = md.renderer.rules.fence;
  md.renderer.rules.fence = function (tokens, idx, options, env, self) {
    const token = tokens[idx];
    const info = token.info ? String(token.info).trim() : '';
    const lang = info.split(/\s+/g)[0];
    if (lang) {
      const klass = `language-${lang}`;
      const existing = token.attrGet('class') || '';
      if (!existing.includes(klass)) {
        token.attrJoin('class', klass);
      }
      token.attrSet('data-language', lang);
    }
    return origFence
      ? origFence(tokens, idx, options, env, self)
      : self.renderToken(tokens, idx, options);
  };
}

export function initRenderer({ svg, host }) {
  const svgEl = typeof svg === 'string' ? document.querySelector(svg) : svg;
  const hostEl = typeof host === 'string' ? document.querySelector(host) : host;
  const transformer = new Transformer();
  patchFenceRenderer(transformer);

  let mm = null;
  let lastRoot = null;
  let lastFrontmatter = null;
  let toolbarMounted = false;

  function update(md) {
    const { root, frontmatter } = transformer.transform(md ?? '');
    lastRoot = root;
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

    // Prism — query every <code> in the SVG and recover the language
    // from either the class (`language-X`), data attribute, or the
    // parent <pre>. Then call highlightElement directly. This works
    // around: (a) markmap stripping the class during render, (b)
    // highlightAllUnder failing across the SVG namespace boundary.
    if (window.Prism && window.Prism.highlightElement) {
      const codes = svgEl.querySelectorAll('code');
      codes.forEach((code) => {
        try {
          if (code.dataset.markmapPrismDone === '1') return;

          let lang = pickLang(code) || pickLang(code.parentElement);
          if (!lang) return; // no language hint anywhere — leave it plain

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
