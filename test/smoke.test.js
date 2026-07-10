// Smoke test — offline, DOM-free, no vite. Run with:  node --test "test/*.test.js"
//
// Why not import src/renderer.js directly: it top-level imports
// markmap-view / markmap-toolbar and a CSS file, none of which load in
// plain Node. Instead we exercise the exact same transform path
// renderer.js uses (markmap-lib's Transformer), fed with the project's
// own SAMPLE_MD, plus the two pure data modules that ARE importable.
// This catches: dependency upgrades breaking transform output, sample.js
// rot, and accidental edits to the placeholders downloads.js relies on.

import { test } from "node:test";
import assert from "node:assert/strict";

import { Transformer } from "markmap-lib";
import { SAMPLE_MD } from "../src/sample.js";
import { STANDALONE_TEMPLATE } from "../src/standalone-template.js";

function countNodes(node) {
  if (!node) return 0;
  return 1 + (node.children ?? []).reduce((n, c) => n + countNodes(c), 0);
}

test("Transformer: minimal markdown produces a sane tree", () => {
  const { root } = new Transformer().transform("# Root\n\n## A\n\n- a1\n- a2\n\n## B\n");
  assert.ok(root && typeof root === "object", "root node exists");
  assert.equal(typeof root.content, "string");
  assert.ok(Array.isArray(root.children), "root.children is an array");
  // Root(#) -> A, B ; A -> a1, a2  => 5 nodes total
  assert.equal(countNodes(root), 5);
});

test("Transformer: SAMPLE_MD transforms to a non-empty tree with frontmatter", () => {
  assert.ok(typeof SAMPLE_MD === "string" && SAMPLE_MD.length > 100, "SAMPLE_MD is non-trivial");
  const { root, frontmatter } = new Transformer().transform(SAMPLE_MD);

  assert.ok(root.children.length >= 3, "sample has several top-level sections");
  assert.ok(countNodes(root) >= 20, "sample produces a rich tree");

  // renderer.js feeds frontmatter.markmap into deriveOptions — the YAML
  // block must survive parsing.
  assert.equal(frontmatter?.markmap?.colorFreezeLevel, 2);
  assert.equal(frontmatter?.markmap?.initialExpandLevel, 3);

  // structural sanity: every node carries string content
  (function walk(n) {
    assert.equal(typeof n.content, "string");
    (n.children ?? []).forEach(walk);
  })(root);
});

test("standalone template keeps the placeholders downloads.js replaces", () => {
  assert.ok(STANDALONE_TEMPLATE.includes("__MARKMAP_TITLE__"));
  assert.ok(STANDALONE_TEMPLATE.includes("/*__MARKMAP_DATA__*/null/*__END__*/"));
  assert.ok(STANDALONE_TEMPLATE.includes("/*__MARKMAP_OPTS__*/null/*__END_OPTS__*/"));
});
