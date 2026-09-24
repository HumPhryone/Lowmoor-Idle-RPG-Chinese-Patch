#!/usr/bin/env node
// 从游戏 lowmoor-boot.js 导出多语言词表（不执行 DOM 相关代码）。
// 用法：node tools/Extract-Locales.js <解包目录或 lowmoor-boot.js> [输出 locales.json]
'use strict';
const fs = require('fs');
const path = require('path');
let input = process.argv[2];
if (!input) { console.error('用法：node tools/Extract-Locales.js <app.asar 解包目录 | lowmoor-boot.js> [out.json]'); process.exit(2); }
if (fs.statSync(input).isDirectory()) input = path.join(input, 'game', 'lowmoor-boot.js');
const out = process.argv[3] || 'locales.json';
let s = fs.readFileSync(input, 'utf8');
const cut = s.indexOf(',LowmoorI18n.init()');
if (cut < 0) throw new Error('找不到 LowmoorI18n.init()，游戏结构可能已变化。');
s = s.slice(0, cut) + ';';
s = s.replace(/LowmoorI18n\.registerLocale\(/g, '__REG(').replace('LowmoorI18n.registerTerms(', '__TERMS(').replace('LowmoorI18n.registerRich(', '__RICH(');
const res = { locales: {}, terms: null };
globalThis.__REG = (meta, messages) => { res.locales[meta.code] = messages; };
globalThis.__TERMS = (...a) => { res.terms = a; };
globalThis.__RICH = () => {};
globalThis.window = globalThis;
globalThis.document = { documentElement: { classList: { add() {} } }, addEventListener() {} };
globalThis.location = { protocol: 'file:' };
globalThis.localStorage = { getItem() { return null; }, setItem() {} };
Object.defineProperty(globalThis, 'navigator', { value: { languages: ['en'], language: 'en' }, configurable: true });
(0, eval)(s);
fs.writeFileSync(out, JSON.stringify(res));
for (const [code, m] of Object.entries(res.locales)) console.log(code, Object.keys(m).length);
console.log('写入', out);
