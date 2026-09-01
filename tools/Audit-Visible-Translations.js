// Re-run the translation function against every extracted candidate and emit
// only strings that still contain likely player-facing English.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const runtimePath = process.argv[2] || 'chinese-patch/translation/runtime-zh.js';
const candidatesPath = process.argv[3] || 'chinese-patch/translation/text-candidates.json';
const outputPath = process.argv[4] || 'chinese-patch/inventory/visible-residuals.jsonl';
const exactPath = process.argv[5] || path.join(path.dirname(runtimePath), 'runtime-zh-exact.js');
const runtime = fs.readFileSync(runtimePath, 'utf8')
  .replace('  if (document.readyState', '  globalThis.__lowmoorTranslate=translate; if (document.readyState');
const context = {
  document: { readyState: 'loading', addEventListener() {} },
  Node: { TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11 },
  NodeFilter: { SHOW_TEXT: 4 },
  console
};
vm.createContext(context);
if (fs.existsSync(exactPath)) vm.runInContext(fs.readFileSync(exactPath, 'utf8'), context, { filename: exactPath });
vm.runInContext(runtime, context, { filename: runtimePath });
const translate = context.__lowmoorTranslate;
if (typeof translate !== 'function') throw new Error('无法取得 runtime 翻译函数');

const candidates = JSON.parse(fs.readFileSync(candidatesPath, 'utf8'));
const allow = /^(Lowmoor|Steam|Discord|Windows|Linux|Mac|Macintosh|GNOME|FYRBAL|EXE|EGA|AdLib|Progress|LilChill|itch|Eric|Mikoarc|Studio|Justin|Nichol|Mariana|Ruiz|Villarreal|Jeff|Preston|Morgan|Strauss|Remi|Harry|Thomas|Lorc|Delapouite|sbed|Skoll|DarkZaitzev|Caro|Asercion|SRD|Creative|Commons|CC|BY|URL|HTTP|HTML|CSS|JavaScript|Electron|ASAR|XP|HP|MP|INT|WIS|CHA|STR|DEX|CON|WIS|CEST|F11|Ctrl|ESC|SPACE|S|v\d|[IVXLCDM]+|\d{1,4}(?:st|nd|rd|th)?)$/i;
const technical = /^(node:|https?:|file:|[./\\]|[a-z_$][a-z0-9_$.-]*$|[A-Z_]{2,}$)/;
const codeLike = /(?:^|[;,])(?:function\b|const\s|let\s|var\s|return\b)|[\]}]\s*,\s*\{\s*(?:name|ambient|market|travel)\s*:/;
const dateOnly = /^\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}$/;
const runtimeOnlyFile = new Set(['main.js', 'preload.js', 'settings.js', 'steam.js', 'zoom.js']);
function residualWords(text) {
  const visibleText = text
    .replace(/\{[A-Za-z_$][\w$.-]*\}/g, ' ')
    .replace(/<[^>]*>/g, ' ');
  return (visibleText.match(/[A-Za-z][A-Za-z'-]{2,}/g) || []).filter(word => !allow.test(word));
}

const out = [];
for (const item of candidates) {
  if (!['game/index.html', 'game/lowmoor.js', 'main.js', 'window.js', 'preload.js', 'settings.js', 'steam.js', 'zoom.js'].includes(item.file)) continue;
  const source = String(item.text || '').trim()
    .replace(/\\([\\'"`])/g, '$1')
    .replace(/\\n/g, '\n');
  if (!source || technical.test(source) || dateOnly.test(source) || codeLike.test(source) ||
      /(?:^data:image|iVBORw0KGgo|base64|<svg|<path\b|currentColor|^M[0-9. -]+[a-z])/.test(source) ||
      !/[A-Za-z]{2,}/.test(source)) continue;
  // Preserve legal attribution and license wording verbatim; these are
  // player-accessible credits but are not localization targets.
  if (/^(?:&(?:minus|plus|times|middot|copy|trade|nbsp);|(?:This work includes material|The bestiary plates are the work|Colorful Monsters|Plates by |The Creative Commons licences are available|https?:\/\/))/i.test(source) ||
      /(?:SRD 5\.1|licensed under CC BY|released under CC0|Creative Commons|Wizards of the Coast|copyright|Progress Quest|LilChill Games|Eric Fredricksen|module covers|Holloway|game-icons\.net|creativecommons\.org)/i.test(source)) continue;
  if (source === 'use strict' || source === 'use asm') continue;
  // These candidates are JavaScript/HTML implementation fragments, not text
  // rendered to players. Keep full templates that contain prose, but discard
  // bare tags, selectors, attributes and generated class/data values.
  if (/^(?:<[^>]+>|["']?\s*(?:class|data-[\w-]+|style|src|href|alt|type|name|value|id)\s*=)/i.test(source)) continue;
  if (/^(?:[.#][\w-]+|(?:translateX|translateY|rotate|scale)\(|(?:seat|procs|fig|floater|pbar|lg-c)-?\w*)$/i.test(source)) continue;
  if (/(?:^|\|)(?:assign:className|assign:cssText|assign:font|call:querySelector|call:querySelectorAll)(?:\||$)/i.test(item.context || '')) continue;
  if (/^(?:["']?\s*>?<(?:a|div|button|img|input|span|tr)\b|["']?\s*(?:href|target|rel|class|data-[\w-]+|loading|style|src)\s*=|[a-z-]+\"><td>)/i.test(source)) continue;
  if (/^(?:lg-[\w-]+(?:\s+lg-[\w-]+)*)$/i.test(source)) continue;
  if (/^(?:img|src|alt|style|object-fit|contain|label|input|span|tr|td|div|button|aria-label|data-help(?:title|stats)?)$/i.test(source)) continue;
  if (/^(?:call|querySelector|querySelectorAll|closest|setAttribute|className|authorization|transform|property):/i.test(item.context || '') &&
      !/[A-Za-z]{2,}\s+[A-Za-z]{2,}/.test(source)) continue;
  // Shell diagnostics and IPC/API literals are not rendered by the game.
  // Keep the one desktop fullscreen prompt, which is explicitly player-facing.
  if (runtimeOnlyFile.has(item.file)) continue;
  // Very short identifiers are useful for the translation dictionary but are
  // not meaningful prose audit items unless they came from an HTML label.
  if (item.file === 'game/lowmoor.js' && source.length < 15 && !/\s/.test(source)) continue;
  const translated = translate(source);
  const words = residualWords(translated);
  if (words.length === 0) continue;
  out.push({ file: item.file, line: item.line, kind: item.kind, context: item.context || '', text: source, translated, residual: [...new Set(words)] });
}
fs.writeFileSync(outputPath, out.map(x => JSON.stringify(x)).join('\n') + (out.length ? '\n' : ''), 'utf8');
console.log(`visible residuals: ${out.length}`);
