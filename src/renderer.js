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

export function initRenderer({ svg, host }) {
  const svgEl = typeof svg === 'string' ? document.querySelector(svg) : svg;
  const hostEl = typeof host === 'string' ? document.querySelector(host) : host;
  const transformer = new Transformer();

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
    if (window.Prism && window.Prism.highlightAllUnder) {
      fos.forEach((fo) => window.Prism.highlightAllUnder(fo));
    }
  }

  function fit() { mm?.fit(); }

  return {
    update,
    fit,
    getSvg: () => svgEl,
    getRoot: () => lastRoot,
    getMarkmap: () => mm,
  };
}
