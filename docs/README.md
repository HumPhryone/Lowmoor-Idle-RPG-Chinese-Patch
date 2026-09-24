# Lowmoor 简体中文润色补丁

适用：**Lowmoor Idle RPG: An Adventurer's Chronicle v1.7.2a**（Steam，2026-09-21 构建，包内版本号 v1.7.2c）

## 为什么重做

2026-09-14 起，游戏内置了多语言系统 `LowmoorI18n`（英 / 波 / 简中 / 德 / 巴葡 / 日），简体中文词表共 32,166 条，打包在 `game/lowmoor-boot.js` 里。旧补丁（2026-09-01，基于 v1.6.5）的做法是在运行时匹配**英文**原句，再替换成中文。游戏切到简体中文后，屏幕上已经是官方中文，旧补丁的规则一条都匹配不上；同时 v1.7.0 新增的“模组 III：最后的锚地”也不在旧词库里。所以旧补丁在新版本上已经失效。

新补丁改为**按词条键覆盖官方简体中文**：官方译文可用的就保留，只替换审校后确实需要修改的条目。

## 审校范围与结果

- 全部 32,166 条中，去掉语法变格副本、技术键和纯占位符后，剩下 12,268 组不重复的“英文→官方中文”对照，逐条对照英文并结合上下文审校。
- 最终覆盖 **1,699 个键**：
  - 约 1,560 条是修订；
  - 131 条是之前没有翻译的随机人名和兽名，现已音译或意译；
  - 7 条是 v1.7.2a 新增、官方尚未翻译的更新日志，现已补译。
- 逐条对照见 `translation/zh-changes.tsv`，列为：键、英文、官方译文、润色译文。

主要问题类型（括号内为代表例）：

| 类型 | 例 |
|---|---|
| 专名误译或前后不一 | Long Charter 官方作“大宪章”（易与 Magna Carta 混淆），改为“长宪章”；The Bottom 作“世界之底”，与“巨口之底”并存，统一为“巨口之底”；Undergate 在“深层之门”和“深门”之间混用；mimic 在“拟态怪”和“拟形怪”之间混用；Admiral 作“海军上将”，与“提督”并存 |
| 机制说明出错 | 漏掉“伤口未闭时”这个条件；把宠物按柜台价**付给玩家**译反了；“每次命中都生效”被译成有条件才触发；“may”（有几率）被译成必定触发 |
| 母题与设定被抹平 | 计数（count / tally）、名册（the Roll）、守封者（wardens）、债（debt）等贯穿主线的意象被译成泛泛的“数目”“荣誉名册”“守卫”；公会规章 charter 与玩家的技能宪章 charter 混为一谈 |
| 冷幽默和双关丢失 | “The statues in its lair were not carved.”原被直接解释成“都是曾经的猎物”；“the chest, which is not a chest”；The Cut Purse 改为“剪绺”；Dragonborn (Lapsed) 由“订阅失效”改为“资格失效”，与“吟游诗人（无执照）”“邪术师（条款待定）”的公文腔保持一致 |
| 残留英文和乱码 | 人名、兽名未翻译；Neris 被译成乱码“奈里英石过”；“Sons”“Holloway”等残留英文 |

术语规范见 `translation/terminology.tsv`，审校准则见 `docs/translation-constraints.md`。

## 安装（玩家）

1. 下载发布包 `Lowmoor-Chinese-Patch.zip`，解压到游戏根目录，即与 `Lowmoor.exe` 同级的目录（Steam 中右键游戏 →“管理”→“浏览本地文件”）。
2. 关闭游戏，双击 `安装汉化.cmd`。
3. 进入游戏，在首次启动的语言页或 **Options（选项）→ Language** 中选择 **简体中文**。

- **卸载**：双击 `卸载汉化.cmd`，或在 Steam 中“验证游戏文件的完整性”。
- **Steam 更新后**：更新会覆盖补丁，重新运行 `安装汉化.cmd` 即可。安装器会识别未打补丁的新封包，并自动刷新备份。
- **官方改过的词条**：每条润色都记录了对应官方原译的指纹。若官方原译已变化（通常意味着英文原文改了），该条会自动跳过，改用官方新译，不会用旧译文覆盖新内容，也不会触发游戏自带的占位符校验而导致无法启动。
- **注意**：若官方改动了 `lowmoor-boot.js` 中 zh-Hans 词表的开头或结尾结构，安装器会报“替换次数不符”并停止，不会改动游戏文件。

## 工作原理

- `translation/patch-manifest.json`（format_version 2）：
  - 在 `index.html` 中，先于 `lowmoor-boot.js` 加载 `zh-override.js`；
  - 在 `lowmoor-boot.js` 的 zh-Hans 词表外包一层 `__lowmoorZhMerge(...)`。
- `translation/zh-override.js`：记录 `key → [官方原译指纹, 润色译文]`。游戏注册 zh-Hans 之前，先把润色译文合并进官方词表，随后仍由游戏自己的 `registerLocale` 校验占位符和结构。
- `tools/Apply-Asar-Patch.ps1`：兼容 Windows PowerShell 5.1。
  - 以流式方式从备份重建 `app.asar`，其余文件逐字节原样复制；
  - 保留 `unpacked` 条目，即 steamworks.js 原生模块，保证成就和云存档正常；
  - 按 Chromium Pickle 规则对齐头部。
  - 旧版安装器会丢掉 `unpacked` 条目，并把 23MB 的文件整体装入 PowerShell 数组，新版已修正。

## 维护流程（开发者）

需要 Node.js 18+，以及 `npx @electron/asar`（用于解包）。

```powershell
# 1. 解包当前游戏（从备份或原版 app.asar）
npx @electron/asar extract "<游戏目录>\resources\app.asar" .\source\app-asar
# 2. 导出多语言词表
node .\tools\Extract-Locales.js .\source\app-asar .\locales.json
# 3. 编辑 translation\zh-revisions.json（key -> 润色译文；select/plural 词条保持官方的对象结构）
# 4. 生成 zh-override.js（自动检查键是否存在、占位符是否与官方一致）
node .\tools\Build-Override.js .\locales.json
# 5. 用游戏自身的 i18n 校验器验证
node .\tools\Validate-Patch.js .\source\app-asar
# 6. 打包发布
powershell -ExecutionPolicy Bypass -File .\tools\Build-Patch-Zip.ps1
```

## 旧版文件

以下文件属于 v1.6.5 时代的运行时英文替换方案，新补丁已不再使用，保留仅供参考，可以删除：

- `translation/` 下：`runtime-zh.js`、`runtime-zh-exact.js`、`dynamic-text-templates.json`、`text-candidates.*`、`font-injection-entry.json`；
- `inventory/` 目录；
- `tools/` 下的 `Audit-*`、`Extract-Text-*`、`Extract-Dynamic-*`、`Benchmark-*`、`Build-Material-Inventory.ps1`、`Extract-Asar.ps1`；
- `fonts/` 目录：官方中文依赖系统字体（微软雅黑等）即可正常显示。旧清单里的字体注入只声明了 `@font-face`，并没有应用到 `font-family`，实际从未生效。
