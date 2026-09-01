#!/usr/bin/env node
// Release gate for the localization runtime's hot paths. It deliberately
// exercises whitespace, already translated text, cache misses, and a large
// newly-rendered panel without requiring Electron or a browser DOM.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const {performance} = require('perf_hooks');

const runtimePath = process.argv[2] || 'chinese-patch/translation/runtime-zh.js';
const exactPath = process.argv[3] || path.join(path.dirname(runtimePath), 'runtime-zh-exact.js');

function createHarness() {
  const document = {
    readyState: 'loading',
    addEventListener() {},
    createTreeWalker(root) {
      const nodes = [];
      const visit = node => {
        for (const child of node.childNodes || []) {
          if (child.nodeType === 3) nodes.push(child);
          else visit(child);
        }
      };
      visit(root);
      let index = 0;
      return {nextNode: () => nodes[index++] || null};
    }
  };
  const context = {
    document,
    Node: {TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11},
    NodeFilter: {SHOW_TEXT: 4}
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(exactPath, 'utf8'), context, {filename: exactPath});
  const runtime = fs.readFileSync(runtimePath, 'utf8').replace(
    '  if (document.readyState',
    '  globalThis.__lowmoorPerf = {translate, scan};\n  if (document.readyState'
  );
  vm.runInContext(runtime, context, {filename: runtimePath});
  if (!context.__lowmoorPerf) throw new Error('无法取得运行时性能入口');
  return context.__lowmoorPerf;
}

function timeCalls(label, count, callback) {
  const started = performance.now();
  for (let i = 0; i < count; i++) callback(i);
  const milliseconds = performance.now() - started;
  return {
    label,
    calls: count,
    milliseconds: Number(milliseconds.toFixed(3)),
    perCallMs: Number((milliseconds / count).toFixed(6))
  };
}

function makePanel(values) {
  const root = {
    nodeType: 1,
    tagName: 'DIV',
    childNodes: [],
    hasAttribute() { return false; },
    querySelectorAll() { return []; },
    contains(node) { return node === this || node.parentElement === this; }
  };
  root.childNodes = values.map(value => ({
    nodeType: 3,
    nodeValue: value,
    parentElement: root
  }));
  return root;
}

const direct = createHarness();
const results = [];
results.push(timeCalls('whitespace-fast-path', 10000, i => direct.translate(' '.repeat((i % 31) + 1))));
results.push(timeCalls('already-chinese-cold', 10000, i => direct.translate(`军械库${i}`)));
results.push(timeCalls('exact-translation-warm', 10000, () => direct.translate('Armoury')));
results.push(timeCalls('unknown-english-cold', 2000, i => direct.translate(`Unmapped sample label ${i}`)));
direct.translate('Repeated unmapped canvas label');
results.push(timeCalls('canvas-label-cache-hit', 10000, () => direct.translate('Repeated unmapped canvas label')));

// Use a fresh cache for a worst-case panel render. The mix approximates a
// complex menu: formatting whitespace, existing Chinese, exact labels, and a
// smaller number of previously unseen generated fragments.
const panelHarness = createHarness();
const panel = makePanel([
  ...Array.from({length: 800}, (_, i) => ' '.repeat((i % 31) + 1)),
  ...Array.from({length: 400}, (_, i) => `军械库${i}`),
  ...Array.from({length: 600}, () => 'Armoury'),
  ...Array.from({length: 200}, (_, i) => `Panel unmapped label ${i}`)
]);
const firstStarted = performance.now();
panelHarness.scan(panel);
const firstPanelMs = performance.now() - firstStarted;
const cachedStarted = performance.now();
panelHarness.scan(panel);
const cachedPanelMs = performance.now() - cachedStarted;

const report = {
  runtime: path.resolve(runtimePath),
  calls: results,
  panel: {
    textNodes: panel.childNodes.length,
    firstScanMs: Number(firstPanelMs.toFixed(3)),
    cachedScanMs: Number(cachedPanelMs.toFixed(3))
  }
};

const byLabel = Object.fromEntries(results.map(result => [result.label, result]));
const violations = [];
function limit(label, actual, maximum) {
  if (actual > maximum) violations.push({label, actual, maximum});
}
limit('whitespace per call', byLabel['whitespace-fast-path'].perCallMs, 0.01);
limit('Chinese per call', byLabel['already-chinese-cold'].perCallMs, 0.01);
limit('exact mapping per call', byLabel['exact-translation-warm'].perCallMs, 0.01);
limit('cold unknown English per call', byLabel['unknown-english-cold'].perCallMs, 1);
limit('cached canvas label per call', byLabel['canvas-label-cache-hit'].perCallMs, 0.01);
limit('2,000-node first panel scan', report.panel.firstScanMs, 500);
limit('2,000-node cached panel scan', report.panel.cachedScanMs, 30);
report.violations = violations;

console.log(JSON.stringify(report, null, 2));
process.exitCode = violations.length ? 1 : 0;
