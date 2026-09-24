#!/usr/bin/env node
// 用游戏自带的 LowmoorI18n.registerLocale 校验补丁：按清单改写 lowmoor-boot.js，
// 载入 zh-override.js 后执行注册（占位符或结构不符会直接抛错），并抽查渲染结果。
// 用法：node tools/Validate-Patch.js <app.asar 解包目录>
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const dir = process.argv[2];
if (!dir) { console.error('用法：node tools/Validate-Patch.js <app.asar 解包目录>'); process.exit(2); }
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'translation', 'patch-manifest.json'), 'utf8'));
const files = {};
for (const e of manifest.entries) {
  if (!(e.path in files)) files[e.path] = fs.readFileSync(path.join(dir, e.path), 'utf8');
  const c = files[e.path].split(e.old).length - 1;
  if (c !== (e.expected_count ?? 1)) throw new Error(`替换次数不符 ${e.path}：期望 ${e.expected_count}，实际 ${c}`);
  files[e.path] = files[e.path].split(e.old).join(e.new);
}
let s = files['game/lowmoor-boot.js'];
s = s.slice(0, s.indexOf(',LowmoorI18n.init()')) + ';';
globalThis.window = globalThis;
globalThis.document = { documentElement: { classList: { add() {} } }, addEventListener() {} };
globalThis.location = { protocol: 'file:' };
globalThis.localStorage = { getItem() { return null; }, setItem() {} };
Object.defineProperty(globalThis, 'navigator', { value: { languages: ['zh-CN'], language: 'zh-CN' }, configurable: true });
(0, eval)(fs.readFileSync(path.join(root, 'translation', 'zh-override.js'), 'utf8'));
(0, eval)(s);
const st = globalThis.__lowmoorZhPatch;
if (!st) throw new Error('合并函数未被调用：清单锚点可能失效。');
console.log(`合并：应用 ${st.applied} 条，跳过 ${st.skipped} 条（官方原译已变化或键已删除）`);
const I = globalThis.LowmoorI18n;
I.setLocale('zh-Hans');
for (const k of ['app.title', 'data.boot.config.and.version.notes.folk.dragonborn.lapsed']) console.log(' ', k, '=>', I.text(k));
console.log('校验通过');
