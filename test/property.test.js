// Property / metamorphic tests for the markmap-lib transform path.
// Zero-dependency (no fast-check): a seeded PRNG fuzzes markdown inputs so
// the run is reproducible and needs no install (this repo's pnpm is sandboxed).
//
// IMPORTANT — these invariants were empirically verified against
// markmap-lib@0.18.12 before being written (2026-07-11). Two "obvious"
// invariants were REJECTED by measurement and are deliberately NOT here:
//   ✗ "node count == heading count"  — list items/paragraphs/tables also
//      become nodes (e.g. `# R\n- a\n- b` = 3 nodes, 1 heading).
//   ✗ "adding a `## H` always increases node count" — markmap restructures
//      the tree; `# R\n- a\n- b` + `## H` goes 3 -> 2 (count DROPS).
// Only relations that actually hold are asserted below. If a future
// markmap upgrade breaks one, that's the regression signal we want.

import { test } from "node:test";
import assert from "node:assert/strict";
import { Transformer } from "markmap-lib";

const tx = (md) => new Transformer().transform(md).root;
const countNodes = (n) => (n ? 1 + (n.children ?? []).reduce((a, c) => a + countNodes(c), 0) : 0);
const everyNode = (n, pred) => pred(n) && (n.children ?? []).every((c) => everyNode(c, pred));

// --- seeded deterministic markdown fuzzer (LCG) -----------------------------
function makeRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 0x100000000;
  };
}
const FRAGMENTS = [
  () => "# H1 heading",
  () => "## H2 heading",
  () => "### deep heading",
  () => "- list item",
  () => "  - nested item",
  () => "1. ordered item",
  () => "a plain paragraph of text",
  () => "> a blockquote line",
  () => "```js\nconst x = 1;\n```",
  () => "| a | b |\n|---|---|\n| 1 | 2 |",
  () => "**bold** and _italic_ and `code`",
  () => "😀 unicode 中文 heading",
  () => "[a link](https://example.com)",
  () => "", // blank line
];
function genMarkdown(rng, maxFrags = 12) {
  const n = 1 + Math.floor(rng() * maxFrags);
  const parts = [];
  for (let i = 0; i < n; i++) parts.push(FRAGMENTS[Math.floor(rng() * FRAGMENTS.length)]());
  return parts.join("\n\n");
}

const SEEDS = Array.from({ length: 40 }, (_, i) => (i + 1) * 2654435761);

// --- Property 1: determinism ------------------------------------------------
test("property: transform is deterministic (same input → identical tree)", () => {
  for (const seed of SEEDS) {
    const md = genMarkdown(makeRng(seed));
    const a = tx(md);
    const b = tx(md);
    assert.deepEqual(a, b, `non-deterministic for seed ${seed}`);
  }
});

// --- Property 2: totality + structure preservation --------------------------
test("property: every input yields a well-formed tree (no throw, string content, ≥1 node)", () => {
  const inputs = [
    ...SEEDS.map((s) => genMarkdown(makeRng(s))),
    "",
    "   ",
    "\n\n\n",
    "\t",
    "#".repeat(100),
    "- ".repeat(50),
    "```\nunclosed code fence",
    "| broken | table",
    "😀💩 emoji # heading",
  ];
  for (const md of inputs) {
    let root;
    assert.doesNotThrow(
      () => {
        root = tx(md);
      },
      `threw on ${JSON.stringify(md).slice(0, 40)}`,
    );
    assert.ok(root && typeof root === "object", "root exists");
    assert.ok(Array.isArray(root.children ?? []), "children is an array");
    assert.ok(countNodes(root) >= 1, "at least one node");
    assert.ok(
      everyNode(root, (n) => typeof n.content === "string"),
      `some node has non-string content for ${JSON.stringify(md).slice(0, 40)}`,
    );
  }
});

// --- Property 3: empty / whitespace-only input is a single string root ------
test("property: empty and whitespace-only input → single node, string content", () => {
  for (const md of ["", " ", "\n", "\t\t", "   \n  \n"]) {
    const root = tx(md);
    assert.equal(countNodes(root), 1, `expected single root for ${JSON.stringify(md)}`);
    assert.equal(typeof root.content, "string");
  }
});

// --- Regression anchors: exact counts locked against markmap-lib@0.18.12 ----
// (mirrors smoke.test.js's ==5 style; upgrades that shift these are flagged.)
test("regression: known structures keep their exact node counts", () => {
  assert.equal(countNodes(tx("# A\n# B\n# C\n")), 4, "3×H1 under a synthetic root");
  assert.equal(countNodes(tx("# R\n## A\n## B\n")), 3, "root + two H2 children");
  assert.equal(countNodes(tx("# R\n## A\n- a1\n- a2\n## B\n")), 5, "matches smoke.test invariant");
  assert.equal(countNodes(tx("plain text no heading")), 1, "prose collapses to one node");
});
