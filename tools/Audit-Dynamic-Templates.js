#!/usr/bin/env node
// Exercise reconstructed dynamic messages through the same translator used by
// the game, using the text-node boundaries produced by inline HTML.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const runtimePath = process.argv[2] || 'chinese-patch/translation/runtime-zh.js';
const templatesPath = process.argv[3] || 'chinese-patch/translation/dynamic-text-templates.json';
const outputPath = process.argv[4] || 'chinese-patch/inventory/dynamic-visible-residuals.jsonl';
const exactPath = process.argv[5] || path.join(path.dirname(runtimePath), 'runtime-zh-exact.js');
const runtime = fs.readFileSync(runtimePath, 'utf8')
  .replace('  if (document.readyState', '  globalThis.__lowmoorTranslate=translate; if (document.readyState');
const context = {
  document: {readyState: 'loading', addEventListener() {}},
  Node: {TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11},
  NodeFilter: {SHOW_TEXT: 4},
  console
};
vm.createContext(context);
if (fs.existsSync(exactPath)) vm.runInContext(fs.readFileSync(exactPath, 'utf8'), context, {filename: exactPath});
vm.runInContext(runtime, context, {filename: runtimePath});
const translate = context.__lowmoorTranslate;
if (typeof translate !== 'function') throw new Error('无法取得 runtime 翻译函数');

const allow = /^(Lowmoor|Steam|Discord|Windows|Linux|Mac|Macintosh|GNOME|FYRBAL|EXE|EGA|AdLib|Progress|LilChill|Eric|Mikoarc|Studio|Justin|Mariana|Jeff|Morgan|Remi|Harry|Thomas|Lorc|Delapouite|Skoll|DarkZaitzev|Caro|SRD|Creative|Commons|CC|BY|URL|HTTP|HTML|CSS|JavaScript|Electron|ASAR|XP|HP|MP|INT|WIS|CHA|STR|DEX|CON|CEST|F11|Ctrl|ESC|SPACE|S|v\d|D\d+|[IVXLCDM]+)$/i;
const technical = /^(?:[.#][a-z0-9_-]+|https?:|file:|data:|[a-z_$][a-z0-9_$.-]*$)/i;
const dynamicToken = /\{D\d+\}/g;
const translatableAttribute = /\b(?:data-help|data-helptitle|aria-label|placeholder|title)\s*=\s*(["'])(.*?)\1/gis;

function residualWords(text) {
  const visible = String(text).replace(/&(?:nbsp|thinsp|middot|minus|times);/gi, ' ');
  return (visible.match(/[A-Za-z][A-Za-z'-]{2,}/g) || []).filter(word => !allow.test(word));
}

function textNodes(template) {
  const nodes = [];
  for (const match of template.matchAll(translatableAttribute)) nodes.push(match[2]);
  const withoutTags = template.replace(/<[^>]*>/g, '\n');
  nodes.push(...withoutTags.split('\n'));
  return nodes
    .map(text => text.replace(dynamicToken, '7').replace(/&(?:nbsp|thinsp|middot|minus|times);/gi, ' ').trim())
    .filter(text => text && /[A-Za-z]{2,}/.test(text) && !technical.test(text));
}

function completeSample(template) {
  // Use values that do not create new English words. Replacing placeholders
  // before splitting avoids false samples such as `abilit7` from `ability`.
  return template.replace(dynamicToken, '7');
}

const templates = JSON.parse(fs.readFileSync(templatesPath, 'utf8'));
const out = [];
for (const item of templates) {
  const complete = completeSample(item.template);
  const samples = /<[^>]+>/.test(complete) ? textNodes(complete) : [complete];
  for (const sample of [...new Set(samples)]) {
    // Selector fragments, URLs and generated class/data values are not prose.
    if (technical.test(sample) || /\bdata-[\w-]+\s*=|\b(?:style|class|src|href|alt)\s*=/i.test(sample)) continue;
    if (/(?:^|\|)(?:assign:className|assign:transform|assign:font|call:fetch|property:authorization)(?:\||$)/i.test(item.context || '')) continue;
    if (/^(?:inset\(|input\[name=|popup=yes,|(?:hire|mod):\d+$|\d+\/bill$|\d+:\d+:(?:res|brk)$|\d+:pre$)/i.test(sample)) continue;
    const translated = translate(sample);
    const residual = [...new Set(residualWords(translated))];
    if (!residual.length) continue;
    out.push({
      id: item.id,
      line: item.line,
      context: item.context,
      template: item.template,
      sample,
      translated,
      residual
    });
  }
}
fs.writeFileSync(outputPath, out.map(item => JSON.stringify(item)).join('\n') + (out.length ? '\n' : ''), 'utf8');
console.log(`dynamic visible residuals: ${out.length}`);
