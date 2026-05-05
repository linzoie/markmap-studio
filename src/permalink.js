// Encodes the current Markdown into the URL hash so the link itself
// carries the content. Nothing leaves the browser; URL fragments are
// never sent to the server.
//
// Two encoding formats coexist:
//   #md1=...   lz-string compressed (default for new links)
//   #md=...    plain UTF-8 base64url (legacy; still readable for back-compat)
//
// lz-string typically shrinks Chinese Markdown by 50-70%.

import { compressToEncodedURIComponent, decompressFromEncodedURIComponent } from 'lz-string';

const KEY_COMPRESSED = '#md1=';
const KEY_LEGACY     = '#md=';

export function readPermalink() {
  const hash = window.location.hash;
  if (!hash) return null;

  if (hash.startsWith(KEY_COMPRESSED)) {
    const result = decompressFromEncodedURIComponent(hash.slice(KEY_COMPRESSED.length));
    return result || null;
  }

  if (hash.startsWith(KEY_LEGACY)) {
    try {
      return decodeLegacy(hash.slice(KEY_LEGACY.length));
    } catch {
      return null;
    }
  }

  return null;
}

export function updatePermalink(md) {
  const target = `${KEY_COMPRESSED}${compressToEncodedURIComponent(md ?? '')}`;
  // replaceState so we don't pollute history while typing
  window.history.replaceState(null, '', target);
}

export function buildShareUrl(md) {
  const url = new URL(window.location.href);
  url.hash = `${KEY_COMPRESSED}${compressToEncodedURIComponent(md ?? '')}`;
  return url.toString();
}

// --- legacy decoder (for any link minted before the lz-string switch) -----

function decodeLegacy(encoded) {
  const padded = encoded
    .replace(/-/g, '+')
    .replace(/_/g, '/')
    .padEnd(encoded.length + (4 - encoded.length % 4) % 4, '=');
  const bin = atob(padded);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}
