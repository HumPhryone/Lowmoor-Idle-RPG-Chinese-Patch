/* Lowmoor 简体中文润色补丁 — 覆盖官方 zh-Hans 词条
 * 基于游戏 v1.7.2a（2026-09-21）官方简体中文，逐条对照英文原文审校。
 * 结构：key -> [官方原译指纹, 润色译文]。游戏更新后若官方原译已变化（指纹不符），
 * 该条自动跳过，沿用官方新译，避免旧译文覆盖新内容或破坏占位符校验。
 */
(function () {
  'use strict';
  var O = /*DATA*/{};
  function fp(s) { var h = 0x811c9dc5; for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; } return h.toString(36); }
  function leaves(v, out) { if (typeof v === 'string') out.push(v); else if (v && typeof v === 'object') for (var x in v) leaves(v[x], out); return out; }
  function ph(v) { var set = {}; leaves(v, []).forEach(function (s) { (s.match(/\{[a-zA-Z][a-zA-Z0-9_]*(?::[a-zA-Z][a-zA-Z0-9_]*)?\}/g) || []).forEach(function (m) { set[m] = 1; }); }); return Object.keys(set).sort().join(','); }
  globalThis.__lowmoorZhMerge = function (base) {
    var applied = 0, skipped = 0, I = globalThis.LowmoorI18n;
    for (var k in O) {
      if (!Object.prototype.hasOwnProperty.call(O, k)) continue;
      var rec = O[k];
      if (Object.prototype.hasOwnProperty.call(base, k)) {
        var cur = base[k];
        if (fp(JSON.stringify(cur)) === rec[0] && ph(cur) === ph(rec[1])) { base[k] = rec[1]; applied++; } else skipped++;
      } else if (rec[0] === '' && typeof rec[1] === 'string' && I && typeof I.has === 'function' && I.has(k)) {
        base[k] = rec[1]; applied++;
      } else skipped++;
    }
    globalThis.__lowmoorZhPatch = { applied: applied, skipped: skipped };
    return base;
  };
})();
