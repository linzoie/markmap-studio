// Self-contained HTML page that recreates the live mindmap. Two
// placeholders are filled at download time:
//   __MARKMAP_TITLE__     <- escaped page title
//   /*__MARKMAP_DATA__*/  <- precomputed mindmap JSON
//
// Loads everything from jsDelivr CDN so the resulting .html stays tiny
// (~7KB). Requires internet on first open; subsequent opens cached.
//
// Addons loaded unconditionally:
//   - KaTeX  (math: $...$, $$...$$)
//   - Prism  (fenced code block syntax highlighting)
// Both fire after markmap finishes its first layout.

export const STANDALONE_TEMPLATE = `<!doctype html>
<html>
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<meta http-equiv="X-UA-Compatible" content="ie=edge" />
<title>__MARKMAP_TITLE__</title>
<style>
* { margin: 0; padding: 0; }
html {
  font-family: ui-sans-serif, system-ui, sans-serif, 'Apple Color Emoji',
    'Segoe UI Emoji', 'Segoe UI Symbol', 'Noto Color Emoji';
}
#mindmap { display: block; width: 100vw; height: 100vh; }
.markmap-dark { background: #27272a; color: white; }
.markmap-foreign pre { padding: 4px 8px; border-radius: 4px; background: #f6f8fa; overflow: auto; }
.markmap-dark .markmap-foreign pre { background: #1f1f23; color: #e4e4e7; }
.markmap-foreign code { font-family: ui-monospace, "Cascadia Code", Consolas, monospace; font-size: .9em; }
</style>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/markmap-toolbar@0.18.12/dist/style.css">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/themes/prism.min.css">
</head>
<body>
<svg id="mindmap"></svg>
<script src="https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/markmap-view@0.18.12/dist/browser/index.js"></script>
<script src="https://cdn.jsdelivr.net/npm/markmap-toolbar@0.18.12/dist/index.js"></script>
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-core.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-markup.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-css.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-clike.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-javascript.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-typescript.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-jsx.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-python.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-bash.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-json.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-yaml.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-markdown.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-sql.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-go.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-rust.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/prismjs@1.29.0/plugins/autoloader/prism-autoloader.min.js"></script>
<script>(()=>{setTimeout(()=>{const{markmap:S,mm:Q}=window,$=new S.Toolbar;$.attach(Q);const I=$.render();I.setAttribute("style","position:absolute;bottom:20px;right:20px"),document.body.append(I)})})()</script>
<script>((l,U,M,R)=>{const N=l();window.mm=N.Markmap.create("svg#mindmap",(U||N.deriveOptions)(R),M),window.matchMedia("(prefers-color-scheme: dark)").matches&&document.documentElement.classList.add("markmap-dark")})(()=>window.markmap,null,/*__MARKMAP_DATA__*/null/*__END__*/,/*__MARKMAP_OPTS__*/null/*__END_OPTS__*/)</script>
<script>
// After markmap renders its first frame, run KaTeX + Prism over the SVG's
// foreignObject contents. We retry a few times because markmap-view layouts
// asynchronously; collapse/expand re-renders DOM, so we hook those events too.
(function () {
  function process() {
    var nodes = document.querySelectorAll('.markmap-foreign, foreignObject');
    if (window.renderMathInElement) {
      nodes.forEach(function (n) {
        try {
          window.renderMathInElement(n, {
            delimiters: [
              { left: '$$', right: '$$', display: true },
              { left: '$',  right: '$',  display: false }
            ],
            ignoredClasses: ['katex'],
            throwOnError: false
          });
        } catch (e) { /* ignore per-node failures */ }
      });
    }
    if (window.Prism && Prism.highlightAllUnder) {
      nodes.forEach(function (n) { Prism.highlightAllUnder(n); });
    }
  }

  // initial pass after first paint, plus a few retries while markmap settles
  var tries = 0;
  var poll = setInterval(function () {
    process();
    if (++tries >= 6) clearInterval(poll); // 6 * 250ms = 1.5s
  }, 250);

  // also re-process when user clicks (likely expand/collapse)
  document.addEventListener('click', function () {
    setTimeout(process, 50);
    setTimeout(process, 250);
  }, true);
})();
</script>
</body>
</html>`;
