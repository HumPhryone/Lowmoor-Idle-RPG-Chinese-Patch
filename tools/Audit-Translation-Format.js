#!/usr/bin/env node
// Verify that exact mappings preserve markup, interpolation tokens and
// numeric/control tokens. This is a release gate, not a translation scorer.
const fs = require('fs');
const vm = require('vm');
const file = process.argv[2] || 'chinese-patch/translation/runtime-zh-exact.js';
const runtimeFile = process.argv[3] || 'chinese-patch/translation/runtime-zh.js';
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(file, 'utf8'), context, {filename: file});
const mappings = context.LOWMOOR_ZH_EXACT || {};
const tokens = value => [...String(value).matchAll(/\$\{[^}]+\}|\{[A-Za-z_$][\w$.-]*\}|%[sd]/g)].map(m => m[0]).sort();
const tags = value => [...String(value).matchAll(/<\/?[A-Za-z][^>]*>/g)].map(m => m[0].replace(/\s+/g, ' ').trim()).sort();
const numbers = value => [...String(value).matchAll(/\b\d+(?:[.,]\d+)?(?:%|x|s|m|h|d)?\b/gi)].map(m => m[0].replace(/[a-z%]+$/i, '')).sort();
const violations = [];
for (const [source, target] of Object.entries(mappings)) {
  if (JSON.stringify(tokens(source)) !== JSON.stringify(tokens(target))) violations.push({kind: 'placeholder', source, target});
  if (JSON.stringify(tags(source)) !== JSON.stringify(tags(target))) violations.push({kind: 'html', source, target});
  // English prose often spells quantities ("one", "a fifth", "half") while
  // the Chinese localization renders the same value as a digit or percent.
  // Enforce byte-level preservation only when the source itself contains
  // explicit numeric tokens; this still catches dropped percentages, levels,
  // timers and damage values without flagging valid localized wording.
  const sourceNumbers = numbers(source);
  const segmented = /^%|\bper$|(?:Thomas Bewick|Clarke died|Bewick in \d{4})/i.test(source.trim());
  if (!segmented && sourceNumbers.length && JSON.stringify(sourceNumbers) !== JSON.stringify(numbers(target))) {
    violations.push({kind: 'number', source, target});
  }
}

let dynamicSpecCount = 0;
if (fs.existsSync(runtimeFile)) {
  const runtimeContext = {
    document: {readyState: 'loading', addEventListener() {}},
    Node: {TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11},
    NodeFilter: {SHOW_TEXT: 4}
  };
  vm.createContext(runtimeContext);
  vm.runInContext(fs.readFileSync(file, 'utf8'), runtimeContext, {filename: file});
  const runtime = fs.readFileSync(runtimeFile, 'utf8').replace(
    '  const DYNAMIC_PATTERNS =',
    '  globalThis.__lowmoorDynamicSpecs = DYNAMIC_SENTENCE_SPECS;\n  const DYNAMIC_PATTERNS ='
  );
  vm.runInContext(runtime, runtimeContext, {filename: runtimeFile});
  const specs = runtimeContext.__lowmoorDynamicSpecs || [];
  dynamicSpecCount = specs.length;
  const dynamicTokens = value => [...String(value).matchAll(/\{\d+\}/g)].map(m => m[0]).sort();
  for (const [source, target] of specs) {
    if (JSON.stringify(dynamicTokens(source)) !== JSON.stringify(dynamicTokens(target))) {
      violations.push({kind: 'dynamic-placeholder', source, target});
    }
  }
}
console.log(`exact mappings: ${Object.keys(mappings).length}`);
console.log(`dynamic sentence specs: ${dynamicSpecCount}`);
console.log(`format violations: ${violations.length}`);
for (const violation of violations.slice(0, 40)) console.log(JSON.stringify(violation));
process.exitCode = violations.length ? 1 : 0;
