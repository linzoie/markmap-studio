// Encodes the current Markdown into the URL hash so the link itself
// carries the content. Nothing leaves the browser; URL fragments are
// never sent to the server.

const PREFIX = '#md=';

export function readPermalink() {
  const hash = window.location.hash;
  if (!hash || !hash.startsWith(PREFIX)) return null;
  try {
    return decodeText(hash.slice(PREFIX.length));
  } catch {
    return null;
  }
}

export function updatePermalink(md) {
  const encoded = encodeText(md ?? '');
  const target = `${PREFIX}${encoded}`;
  // Use replaceState so we don't pollute history while typing.
  window.history.replaceState(null, '', target);
}

export function buildShareUrl(md) {
  const encoded = encodeText(md ?? '');
  const url = new URL(window.location.href);
  url.hash = `${PREFIX}${encoded}`;
  return url.toString();
}

// --- helpers --------------------------------------------------------------

// btoa only handles latin1; encode UTF-8 first.
function encodeText(text) {
  const bytes = new TextEncoder().encode(text);
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function decodeText(encoded) {
  const padded = encoded
    .replace(/-/g, '+')
    .replace(/_/g, '/')
    .padEnd(encoded.length + (4 - encoded.length % 4) % 4, '=');
  const bin = atob(padded);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}
