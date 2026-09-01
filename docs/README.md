# Lowmoor 简体中文汉化补丁

这是 Lowmoor 的简体中文汉化工程与发布目录。原始游戏没有语言选择入口，且桌面版从 `resources/app.asar` 内加载 HTML，因此补丁采用“备份原包、按清单重建 ASAR”的安装方式。原始源码保持不变，所有改写集中在 `translation/patch-manifest.json` 与运行时词库。

已完成：

- `source/app-asar/`：完整 ASAR 提取物。
- `inventory/asar-files.csv`、`inventory/asar-files.json`：封包文件清单。
- `translation/text-candidates.csv`、`translation/text-candidates.json`：当前从完整 ASAR 提取的 11,759 条静态/动态文本候选；候选包含技术字面量，需按审计规则筛选。
- `translation/dynamic-text-templates.json`：从 JavaScript 拼接表达式还原的 1,562 条动态消息模板，用于检查运行时最终可见文本，不可用片段数量代替完整消息覆盖率。
- `tools/Audit-Resource-Coverage.js`：独立确认 ASAR 中全部 HTML/JavaScript 文本资源均已进入候选清单；CSS 与 package 元数据列为非玩家文案资源。
- `docs/translation-constraints.md`：专业译者级别的语气、连续上下文、术语、词梗、占位符和审校约束。
- `tools/Apply-Asar-Patch.ps1`：无参数安装器调用的 ASAR 重建工具。
- `release-root/安装汉化.cmd`、`release-root/卸载汉化.cmd`：最终 ZIP 根目录脚本模板。
- `tools/Build-Patch-Zip.ps1`：只打包发布所需文件，排除源码和审计材料。
- `fonts/`：随补丁提供 Source Han Sans SC Regular/Bold 及许可证；清单已启用 CSS 字体注入。
- `translation/runtime-zh.js`：运行时中文词库，按玩家可见文本逐条翻译章节、地点、职业、技能、帮助和日志中的常用句子；动态消息模板必须使用完整句式或保留数值/HTML 的正则规则。
- `translation/runtime-zh-exact.js`：4,701 条完整句与短标签精确映射。
- 全量审计结果：静态可见残留 0、动态模板可见残留 0、格式违规 0、文本类资源覆盖 9/9。
- 发布验证：已在临时游戏副本中完成安装、重建 ASAR 内容检查与卸载；卸载后的封包 SHA-256 与原包一致。
- `tools/Benchmark-Runtime-Performance.js`：覆盖空白节点、已汉化节点、未知文本、Canvas 重绘缓存与 2,000 节点复杂面板的性能回归门禁。

## 性能修复

2026-09-01 修复了汉化运行时在军械库、技能树等复杂窗口中重复遍历全部正则和词表的问题。运行时现在使用空白/中文快速路径、预编译短语规则、常数时间单词查找、4,096 项结果缓存、DOM 节点缓存，以及 MutationObserver 新增子树去重。

同一台机器上的修复前后基准：空白或已汉化节点由约 2.5 毫秒/节点降至约 0.0003 毫秒/节点；2,000 文本节点的合成面板首次扫描约 54 毫秒，缓存后约 0.6 毫秒。实际 Electron 封包中连续打开 20 次，军械库中位响应 28.9 毫秒、最大 35.1 毫秒；技能树中位响应 5.3 毫秒、最大 23 毫秒。

## 汉化与安装说明

1. `translation/terminology.tsv` 已统一专名、系统名、稀有度和机制词。
2. `translation/patch-manifest.json` 已填入精确替换、上下文和计数；技术键、ID、URL、CSS、选择器和 API 均保持原样。
3. 安装器会将 `runtime-zh.js` 写入 ASAR 内的 `game/zh.js`，由唯一的运行时翻译层处理菜单、名称、职业、属性、帮助提示、图鉴、日志和战斗文本；页面不再注入重复的内联观察器。
4. 执行 `tools/Build-Patch-Zip.ps1` 生成 `Lowmoor-Chinese-Patch.zip`。将 ZIP 解压到游戏根目录后运行 `安装汉化.cmd`；需要恢复原版时运行 `卸载汉化.cmd`。

重新提取或更新候选表：

```powershell
.\tools\Extract-Asar.ps1 -ArchivePath ..\resources\app.asar -OutputDirectory .\source\app-asar
.\tools\Build-Material-Inventory.ps1 -ExtractedDirectory .\source\app-asar -OutputCsv .\inventory\asar-files.csv -OutputJson .\inventory\asar-files.json
.\tools\Extract-Text-Candidates.ps1 -SourceDirectory .\source\app-asar -OutputCsv .\translation\text-candidates.csv -OutputJson .\translation\text-candidates.json
node .\tools\Extract-Dynamic-Text-Templates.js
node .\tools\Audit-Dynamic-Templates.js
node .\tools\Audit-Visible-Translations.js
node .\tools\Audit-Translation-Format.js
node .\tools\Audit-Resource-Coverage.js
node .\tools\Benchmark-Runtime-Performance.js
```
