# 提取范围与汉化方案判断

## 已确认的游戏结构

- 游戏版本：`Lowmoor: An Adventurer's Chronicle`，桌面版本 1.4.0；包内游戏脚本版本字符串为 1.6.5。
- 技术栈：Electron。主包为 `resources/app.asar`，资源未压缩；Electron 桌面入口通过 `__dirname/game/index.html` 加载游戏。
- 这不是 Unity/Mono 游戏，未发现 BepInEx、Unity asset bundle 或托管程序集；本方案不需要 BepInEx。
- ASAR 已完整提取到 `source/app-asar/`，并生成 `inventory/asar-files.csv`、`inventory/asar-files.json`。
- 包内共 13 个文件：6 个游戏/图标资源，7 个桌面运行时脚本或元数据；`resources/app.asar.unpacked/` 仅为 Steamworks 原生运行库，不含可见文案。

## 玩家可见材料

1. `source/app-asar/game/index.html`：初始登记界面、菜单、面板标题、按钮、静态说明、帮助提示、无障碍标签。
2. `source/app-asar/game/lowmoor.js`：所有动态 UI、日志、事件、章节、角色/职业/种族/起源、技能、装备、宠物、雇佣兵、商店、成就、图鉴、音乐名称、补丁说明，以及隐藏 FYRBAL 小游戏文字。
3. `source/app-asar/game/lowmoor-boot.js`：启动时根据协议和本地设置添加的界面类名逻辑；若后续发现可见字符串，按清单处理。
4. `source/app-asar/main.js`：桌面窗口标题和少量外壳提示属于玩家可见文本；Electron 注释和 IPC 键不翻译。
5. `source/app-asar/preload.js`、`settings.js`、`steam.js`、`window.js`、`zoom.js`：只翻译实际显示给玩家的错误/状态文本，保留 API、存档键和 Steam token。

扫描器已输出 `translation/text-candidates.csv` 和同内容 JSON，共 7,248 条候选。候选故意包含动态字符串和技术字符串，翻译者必须依据 `review` 和上下文筛选；这比只抓 HTML 静态文本更不容易漏掉日志、事件和隐藏窗口。

图标 `assets/icon.ico`、`assets/icon.png` 没有发现玩家可读文字，不纳入图片重绘。CSS 没有文案，只有布局、颜色、字体和伪元素符号；不要改动类名或选择器。

## 语言入口与覆盖方式

未发现 `locale`、`i18n`、`navigator.language`、语言选择菜单或多语言资源表。`locales/zh-CN.pak` 是 Electron/Chromium 自带资源，不是游戏语言包。因此本游戏没有原生中文入口，正式补丁应直接覆盖默认英文文本。

Electron 入口从 `app.asar` 内部加载 `game/index.html`，无法仅靠在游戏根目录旁放置同名文件外挂覆盖。正式补丁采用方案 2：安装脚本备份原 `resources/app.asar`，从备份解包，按翻译清单改写文本，再重建 `app.asar`；卸载脚本恢复备份。补丁包不携带完整游戏封包。

## 字体判断

现有 CSS 字体栈为 `Tahoma, "MS Sans Serif", Geneva, sans-serif`，这些字体不能保证覆盖简体中文。若不补字体，中文很可能显示方块。已从 `09_SourceHanSansSC(1).zip` 提取 `SourceHanSansSC-Regular.otf` 和 `SourceHanSansSC-Bold.otf` 到 `fonts/`，并保留 SIL Open Font License 文本。`translation/font-injection-entry.json` 是待翻译完成后复制进主清单的 CSS 注入条目；它保留西文回退字体并避免修改 DOM/CSS 类名。

字体文件哈希（SHA-256）：Regular `F1D8611151880C6C336AABEAC4640EF434FA13CBFB1FFE82D0A71B2A5637256`；Bold `DF2B90F5BCC6D01DFC964CEC5F6D535D6B6AEBD26ED7FD79A9C1B3F2112FCB6B`。

## 安装器约定

- 正式 ZIP 以游戏根目录为释放目标，根目录放置 `安装汉化.cmd`、`卸载汉化.cmd`；两者自动定位旁边的 `chinese-patch`，不要求玩家填写路径或参数。
- `translation/patch-manifest.json` 已包含汉化替换；安装器仍会校验每条原文计数，任何计数不符都会停止。
- 安装前创建 `resources/app.asar.chinese-patch-backup`，重复安装始终从该备份重建，避免二次替换污染原文。
- 已完成清单级验证：JSON、JavaScript 注入脚本语法及每条替换的原文计数均通过；安装器会在用户机器上完成 ASAR 重建和字体显示验证。
