# Layerly — Design Contract

单一真源声明：**值类 token 的唯一真源是 `design/prototype/shared.css`**（亮暗成对）；
本文件只记语义名、用途与决策，不复述值。改视觉语言先改这里（语义/不变式），
再同 commit 更新 shared.css 与各屏。界面实现以已落账的原型基线为准。

---

## Brief

**Layerly** — AI 原生 3D 打印工作台。一句话：从一个想法，到一件拿得起来的东西。

- **用户**：拥有拓竹（Bambu Lab）打印机的个人 3D 打印玩家；桌面三平台同等（macOS / Windows / Linux，glaze 线）。
- **核心主张**：一件作品的完整生命周期（需求 brief → 设计版本 → 模型 → 切片 → 打印 → 实物反馈）收在一个工作台里，旁边站着了解你的设备、耗材与打印历史的 AI 顾问。
- **治理不变式**：AI 提议，用户执行。打印派发、采购、删除归档必须经用户显式确认步；打印机 LAN-only 本地优先；API key 留在 backend，永不进 webview。
- **MVP（v1）**：工作台（项目/材料/历史）+ 拓竹设备接入 + AI 顾问对话。AI 建模链（Text-to-CAD、选形、三视图）放 v2——原型阶段一次性锁定其信息架构位置，界面上以「Design 流程占位态」表达。
- **品类叙事**：自定义品类「AI-native 3D printing workbench」，不提对标物。

## 设计原则（HIG 内核，平台无关）

1. **清晰优先**：一件作品现在处于生命周期的哪一步，任何界面 3 秒内可读——状态 pill 永远在场。
2. **内容至上**：主角是作品（模型、实物照片、记录），chrome（侧栏/工具条）退后；大面积中性底，色彩只用于状态与动作。
3. **直接操纵**：模型、材料槽位、进度都是可点对象；拖拽投放模型文件是首选录入方式。
4. **反馈及时**：打印进度按层回报（层积条）；AI 回复流式呈现；一切异步操作有进行态。
5. **防错一致**：破坏性动作（删除归档、清空清单）一律二次确认；打印派发走「打印包确认页」，不允许从列表行内一键静默发送。

## 视觉语言

- **气质**：工坊（workshop）——暖中性纸面底 + filament amber 主色（耗材的琥珀色）+ machine teal 辅助（设备的钢青色）。内容密集型工作台，**亮色为默认态**，暗色为完整成对主题。
- **母题「层」**：3D 打印的本质是层积。层积条纹进度条（`--layer-stripe`）、层数徽标、卡片分层投影——全家族共用 `shared.css` 的 `.layerbar` 与 `.layers-bg`。
- **字体**：系统栈（SF Pro / Segoe UI / PingFang SC / Microsoft YaHei）；一切尺寸、用量、耗时、克重用 `--mono` 等宽栈——数字是打印玩家的第一语言。
- **图标**：内联 SVG，1.5px 描边、16px 网格、圆角端点、无填充（filled 仅用于选中态导航）。

## Tokens（语义名 → 用途；值见 shared.css）

| 语义 | 用途 |
|---|---|
| `bg / surface / raised / line` | 页面底 / 卡片与面板 / 悬浮与嵌套面 / 描边 |
| `ink / mute / faint` | 主文本 / 次文本 / 弱化（时间戳、占位） |
| `accent / accent-soft` | 主色（amber）+ 其浅底；唯一品牌色，用于主动作、选中态、进行态 |
| `teal / teal-soft` | 辅助色（设备/连接语义）；设备在线、连接成功 |
| `ok / warn / err`（+ `*-soft`） | 语义状态：完成/成功、警告（材料不足、校验提示）、失败/错误 |
| `status-*`（idea/design/slicing/printing/done/failed） | 作品生命周期 pill 专用，映射到上述语义色 |
| `radius-*` | 窗口 12 / 卡片 10 / 控件 8 / pill 全圆 |
| `shadow-*` | 窗口大投影 / 卡片浮起 / 弹层 |
| `layer-stripe` | 层积条纹（进度、封面装饰） |

## 组件词汇（全家族唯一词汇，屏内禁止私有变体）

`window`（titlebar + body + sidebar + main + topbar）· `nav-item` · `btn`（primary/secondary/danger/ghost × small）· `pill`（状态）· `chip`（耗材，色点+类型）· `project-card`（封面/状态/版本/进度）· `layerbar`（层积进度）· `metric`（数值瓦片，mono）· `ams-slot`（AMS 槽位）· `timeline`（设计版本）· `chat`（user/advisor 气泡 + composer + 确认卡）· `table`（历史/清单行）· `empty`（空态）· `input / search / select` · `toggle`（主题切换，右上角固定）· `confirm-card`（AI 动作确认卡：内容+影响+显式确认按钮）

## 不变式（违反即打回）

1. **状态 pill 永远在场**：任何出现作品的地方（卡片、详情头、历史行、AI 消息引用）都带生命周期 pill。
2. **确认边界可见**：凡触发打印/采购/删除的入口，视觉上必须是 `confirm-card` 或二次确认弹层；AI 消息里的动作建议只渲染为确认卡，不渲染为可直接执行的按钮。
3. **数字等宽**：一切尺寸（mm）、耗时（h/m）、克重（g）、层数用 mono。
4. **亮暗成对**：任何新色值必须同时给两主题；禁止用透明度黑补丁模拟暗色。
5. **零外部依赖**：不引外部字体/CDN/图片；图片位用内联 SVG 占位（模型=等距线框示意，实物=圆角矩形照片位）。
6. **AI 语境透明**：AI 气泡必须带角色标（Advisor / 任务小组），并显示其引用的项目上下文来源。

## 平台差异

- 机制因地制宜：macOS ⌘ 系快捷键 / Windows Ctrl 系；Linux 走 WebKitGTK 惯例；标题栏交通灯在 Windows/Linux 上由 glaze 宿主决定呈现，原型用 macOS 形态统一示意。
- 交互逻辑全平台统一：信息架构、术语、快捷键语义、确认流完全一致。
- 文件拖放、系统通知（打印完成）走各宿主能力，语义一致。

---

## Exit 条件（原型打磨完成的标准，写死不放松）

**关键屏清单（11 屏 + index 导航页）**：

1. `onboarding.html` — 首启：欢迎、设备连接（LAN 探测）、AI 配置（BYOK）、空项目引导
2. `dashboard.html` — 工作台总览：进行中项目、设备状态、最近打印、顾问入口
3. `projects.html` — 项目图册：卡片墙 + 生命周期过滤
4. `project.html` — 作品详情：brief、版本时间线、模型/实物、切片方案、打印记录、任务小组对话（全流程 IA 的核心屏）
5. `print-prep.html` — 打印包确认：材料映射（模型部件 ↔ AMS 槽位）、时间/用量估算、显式派发
6. `model-viewer.html` — 模型全屏预览：等距线框 + 视角/剖层控件（v2 AI 建模的三视图对比在此 IA 位置）
7. `devices.html` — 设备：打印机状态、AMS 槽位、当前任务层积进度
8. `history.html` — 打印历史：记录 + 实物反馈归档（成功/失败/教训）
9. `materials.html` — 材料库：库存、购物清单、采购记录
10. `advisor.html` — AI 顾问（跨项目）：对话 + 项目上下文引用 + 确认卡
11. `model-flow.html` 占位并入 `project.html` 的 Design 段（v2 建模链以禁用态+说明表达，不单独建屏）

**交互逻辑**：生命周期状态机（Idea → Design → Slicing → Printing → Done/Failed）在 projects/project/history 三屏表现一致；打印派发流 = print-prep 确认页唯一入口；AI 动作一律确认卡。

**HIG 清单**：五原则逐条过（状态可读 / 内容主角 / 直接操纵 / 反馈及时 / 防错一致）。

**用户满意**：用户在 OpenDesign 打磨后明确说「收」。


## 2026-11-15 · 原型交互补齐

入口为 prototype/dashboard.html。侧栏连接作品、设备、材料、历史、顾问。新建作品先呈现无模型空态，禁止直接打印；已有示例作品经过准备与确认后仅加入本地演示队列。模型层数与视角为 SVG 示意交互，不执行真实切片。

根级 index.html 只负责首次进入主界面；页面切换直接到目标界面，不再保留页面目录。原型运行脚本 prototype-runtime.js / prototype-flow.js 只表达浏览器内的交互合同；正式产品业务仍由既定引擎实现。真实设备、模型和发布服务均未连接。凭据演示不保存密钥，破坏性示例与派发保留确认和取消。

这些是可评审的增量改动，未替用户勾选满意度、HIG 最终验收或设计冻结条件。


## Prototype source checkpoint — 2026-11-15

`index.html` opens the primary prototype directly. Screen-directory launchers have been removed. All local scripts, styles and referenced assets needed by this checkpoint are versioned under this directory; OpenDesign metadata is excluded. This is an editable prototype checkpoint, not a claim that the native product or external services implement these interactions.
