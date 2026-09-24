#!/usr/bin/env node
// 由 translation/zh-revisions.json（key -> 润色译文）生成 translation/zh-override.js。
// 每条附官方原译指纹：游戏更新后官方原译若变化，该条在运行时自动跳过。
// 用法：node tools/Build-Override.js <locales.json>
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const locales = JSON.parse(fs.readFileSync(process.argv[2] || 'locales.json', 'utf8')).locales;
const en = locales.en, off = locales['zh-Hans'];
const rev = JSON.parse(fs.readFileSync(path.join(root, 'translation', 'zh-revisions.json'), 'utf8'));
const fnv = s => { let h = 0x811c9dc5; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; } return h.toString(36); };
const PH = /\{[a-zA-Z][a-zA-Z0-9_]*(?::[a-zA-Z][a-zA-Z0-9_]*)?\}/g;
const leaves = (v, o = []) => { if (typeof v === 'string') o.push(v); else if (v && typeof v === 'object') for (const x of Object.values(v)) leaves(x, o); return o; };
const ph = v => [...new Set(leaves(v).flatMap(s => s.match(PH) || []))].sort().join(',');
const data = {}; const problems = [];
for (const k of Object.keys(rev).sort()) {
  if (!(k in en)) { problems.push('英文中已无此键：' + k); continue; }
  const ref = k in off ? off[k] : en[k];
  if (ph(ref) !== ph(rev[k])) { problems.push('占位符不一致：' + k); continue; }
  data[k] = [k in off ? fnv(JSON.stringify(off[k])) : '', rev[k]];
}
if (problems.length) { console.error(problems.join('\n')); process.exit(1); }
const tpl = fs.readFileSync(path.join(__dirname, 'zh-override.template.js'), 'utf8');
fs.writeFileSync(path.join(root, 'translation', 'zh-override.js'), tpl.replace('/*DATA*/{}', () => JSON.stringify(data)));
console.log('zh-override.js：', Object.keys(data).length, '条');
