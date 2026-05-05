// Light/dark theme toggle.
//
// - Honors prefers-color-scheme on first load.
// - Adds `dark` class on <html> for our CSS, plus `markmap-dark`
//   for the markmap-view runtime.
// - Persists choice in localStorage.

const STORAGE_KEY = 'markmap-studio.theme';

export function initTheme({ button }) {
  const btn = typeof button === 'string' ? document.querySelector(button) : button;

  apply(currentMode());
  btn?.addEventListener('click', toggle);

  // Follow system change unless user picked manually
  if (!localStorage.getItem(STORAGE_KEY)) {
    window.matchMedia('(prefers-color-scheme: dark)')
      .addEventListener('change', (e) => apply(e.matches ? 'dark' : 'light'));
  }
}

function currentMode() {
  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored === 'light' || stored === 'dark') return stored;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function apply(mode) {
  const root = document.documentElement;
  if (mode === 'dark') {
    root.classList.add('dark');
    root.classList.add('markmap-dark');
  } else {
    root.classList.remove('dark');
    root.classList.remove('markmap-dark');
  }
}

function toggle() {
  const next = document.documentElement.classList.contains('dark') ? 'light' : 'dark';
  localStorage.setItem(STORAGE_KEY, next);
  apply(next);
}
