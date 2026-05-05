// Drag the divider to resize the editor / preview panes.
// Updates the grid-template-columns inline style on #app.

const STORAGE_KEY = 'markmap-studio.split';
const MIN_PCT = 15;
const MAX_PCT = 85;

export function initSplitter({ splitter, host, onResize }) {
  const handle = typeof splitter === 'string' ? document.querySelector(splitter) : splitter;
  const grid = typeof host === 'string' ? document.querySelector(host) : host;

  // Restore saved ratio (or default 50%)
  const saved = parseFloat(localStorage.getItem(STORAGE_KEY) ?? '50');
  applyPct(grid, isFinite(saved) ? saved : 50);

  let dragging = false;

  function onPointerDown(e) {
    dragging = true;
    handle.setPointerCapture(e.pointerId);
    handle.classList.add('dragging');
    document.body.classList.add('resizing');
    e.preventDefault();
  }

  function onPointerMove(e) {
    if (!dragging) return;
    const rect = grid.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const pct = Math.max(MIN_PCT, Math.min(MAX_PCT, (x / rect.width) * 100));
    applyPct(grid, pct);
    onResize?.();
  }

  function onPointerUp() {
    if (!dragging) return;
    dragging = false;
    handle.classList.remove('dragging');
    document.body.classList.remove('resizing');
    const cols = grid.style.gridTemplateColumns;
    const m = cols.match(/^([\d.]+)%/);
    if (m) localStorage.setItem(STORAGE_KEY, m[1]);
    onResize?.();
  }

  // Keyboard arrow support for accessibility
  function onKeyDown(e) {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    const cols = grid.style.gridTemplateColumns;
    const m = cols.match(/^([\d.]+)%/);
    const cur = m ? parseFloat(m[1]) : 50;
    const delta = e.key === 'ArrowLeft' ? -2 : 2;
    const pct = Math.max(MIN_PCT, Math.min(MAX_PCT, cur + delta));
    applyPct(grid, pct);
    localStorage.setItem(STORAGE_KEY, pct.toFixed(2));
    onResize?.();
    e.preventDefault();
  }

  handle.addEventListener('pointerdown', onPointerDown);
  handle.addEventListener('pointermove', onPointerMove);
  handle.addEventListener('pointerup', onPointerUp);
  handle.addEventListener('pointercancel', onPointerUp);
  handle.addEventListener('keydown', onKeyDown);
}

function applyPct(grid, pct) {
  grid.style.gridTemplateColumns = `${pct}% 6px 1fr`;
}
