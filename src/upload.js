// File upload via hidden <input type="file"> triggered by a button.
// Reads as text and forwards to onLoad.

const TEXT_TYPES = /^(text\/|application\/json)/;
const TEXT_EXT = /\.(md|markdown|txt|text|mmd|mdx)$/i;

export function initUpload({ input, trigger, onLoad, onError }) {
  const inputEl = typeof input === 'string' ? document.querySelector(input) : input;
  const triggerEl = typeof trigger === 'string' ? document.querySelector(trigger) : trigger;

  triggerEl.addEventListener('click', () => inputEl.click());

  inputEl.addEventListener('change', async () => {
    const file = inputEl.files?.[0];
    if (!file) return;
    try {
      if (!isTextFile(file)) {
        throw new Error('只支援文字檔（.md / .markdown / .txt）');
      }
      const text = await file.text();
      onLoad?.(text, file.name);
    } catch (err) {
      onError?.(err);
    } finally {
      // reset so selecting the same file re-fires change
      inputEl.value = '';
    }
  });
}

function isTextFile(file) {
  if (!file) return false;
  if (file.type && TEXT_TYPES.test(file.type)) return true;
  if (TEXT_EXT.test(file.name)) return true;
  return false;
}
