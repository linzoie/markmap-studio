// Self-contained HTML page that recreates the live mindmap. The two
// placeholders (__MARKMAP_TITLE__ and the JSON between the comment markers)
// are replaced at download time with the user's content.
//
// Same template the article-to-mindmap CLI uses. CDN-loaded so the file
// stays small (~6KB) but requires internet on first open.

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
</style>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/markmap-toolbar@0.18.12/dist/style.css">
</head>
<body>
<svg id="mindmap"></svg>
<script src="https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/markmap-view@0.18.12/dist/browser/index.js"></script>
<script src="https://cdn.jsdelivr.net/npm/markmap-toolbar@0.18.12/dist/index.js"></script>
<script>(()=>{setTimeout(()=>{const{markmap:S,mm:Q}=window,$=new S.Toolbar;$.attach(Q);const I=$.render();I.setAttribute("style","position:absolute;bottom:20px;right:20px"),document.body.append(I)})})()</script>
<script>((l,U,M,R)=>{const N=l();window.mm=N.Markmap.create("svg#mindmap",(U||N.deriveOptions)(R),M),window.matchMedia("(prefers-color-scheme: dark)").matches&&document.documentElement.classList.add("markmap-dark")})(()=>window.markmap,null,/*__MARKMAP_DATA__*/null/*__END__*/,null)</script>
</body>
</html>`;
