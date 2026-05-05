// Wraps markmap-view + markmap-lib + markmap-toolbar.
// Exposes update(md), fit(), and accessors used by downloads.

import { Transformer } from 'markmap-lib';
import { Markmap, deriveOptions } from 'markmap-view';
import { Toolbar } from 'markmap-toolbar';
import 'markmap-toolbar/dist/style.css';

export function initRenderer({ svg, host }) {
  const svgEl = typeof svg === 'string' ? document.querySelector(svg) : svg;
  const hostEl = typeof host === 'string' ? document.querySelector(host) : host;
  const transformer = new Transformer();

  let mm = null;
  let lastRoot = null;
  let toolbarMounted = false;

  function update(md) {
    const { root } = transformer.transform(md ?? '');
    lastRoot = root;
    if (!mm) {
      mm = Markmap.create(svgEl, deriveOptions({}), root);
      mountToolbar();
    } else {
      mm.setData(root);
      mm.fit();
    }
    return root;
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

  function fit() { mm?.fit(); }

  return {
    update,
    fit,
    getSvg: () => svgEl,
    getRoot: () => lastRoot,
    getMarkmap: () => mm,
  };
}
