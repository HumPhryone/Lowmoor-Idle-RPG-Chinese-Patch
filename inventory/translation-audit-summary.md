# 翻译审计摘要

审计脚本：`tools/Audit-Visible-Translations.js`

最近一次审计基于 `translation/text-candidates.json`（11,759 条候选），输出 `visible-residuals.jsonl`；动态拼接表达式另由 `translation/dynamic-text-templates.json`（1,562 条模板）和 `dynamic-visible-residuals.jsonl` 审计。技术键、IPC 名称、CSS/URL、版权链接和版本日期不属于玩家文案。

2026-09-01 全量结果：静态可见残留 0 条，动态模板可见残留 0 条，精确映射 4,701 条，格式违规 0 条；文本类资源覆盖 9/9。审计器已排除 URL、路径、CSS/HTML 属性片段、生成类名、内部选择器、版权署名和许可证链接。

已完成的重点范围：

- `game/lowmoor.js` 的 `ambient`、`travel`、`market`、`intro`、`lines`、`rider`/`riderPlain` 字段；这些字段包含所有楼层环境叙述、市场鉴定文本、战斗日志和装备说明。
- 技能/法术完整说明，以及事件公告的 `title`、`note`、`intro`、`live`、`done` 和 `lines`。
- FYRBAL Canvas 文本（通过 `fillText` 边界翻译），以及 HTML 的 About/许可段落（专名、作者和 URL 保留原文）。

长文本采用完整句映射，动态消息采用保留变量的句型规则；HTML 标签、插值、数值和快捷键均由格式审计检查。
动态模板不得仅以单个静态片段是否已进词库作为完成依据；必须以运行时组装后的完整文本或每个实际 DOM 文本节点为审计单位。
