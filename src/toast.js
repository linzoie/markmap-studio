// Minimal toast system. Single host element under document body,
// each toast is a div that fades in/out via CSS classes.

let host = null;

function getHost() {
  if (!host) host = document.getElementById('toast-host');
  return host;
}

export function showToast(message, { type = 'info', duration = 2200 } = {}) {
  const el = document.createElement('div');
  el.className = `toast toast-${type}`;
  el.textContent = message;
  getHost().appendChild(el);
  // Trigger transition next frame
  requestAnimationFrame(() => el.classList.add('show'));
  setTimeout(() => {
    el.classList.remove('show');
    setTimeout(() => el.remove(), 250);
  }, duration);
}
