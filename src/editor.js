// CodeMirror 6 markdown editor.
//
// Returns an object that lets main.js subscribe to changes and read/write
// content imperatively (for upload, sample, permalink hydration).

import { EditorView, basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { markdown } from '@codemirror/lang-markdown';
import { keymap } from '@codemirror/view';
import { indentWithTab } from '@codemirror/commands';

export function initEditor({ container, initialContent }) {
  const target = typeof container === 'string'
    ? document.querySelector(container)
    : container;

  let onChangeCb = () => {};
  let suppressChange = false;

  const view = new EditorView({
    state: EditorState.create({
      doc: initialContent ?? '',
      extensions: [
        basicSetup,
        markdown(),
        keymap.of([indentWithTab]),
        EditorView.lineWrapping,
        EditorView.updateListener.of((update) => {
          if (update.docChanged && !suppressChange) {
            onChangeCb(update.state.doc.toString());
          }
        }),
      ],
    }),
    parent: target,
  });

  return {
    onChange(cb) { onChangeCb = cb; },
    getContent() { return view.state.doc.toString(); },
    setContent(text, { silent = false } = {}) {
      suppressChange = silent;
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: text ?? '' },
      });
      suppressChange = false;
    },
    focus() { view.focus(); },
  };
}
