# SSB Runner v0.3.0 UI 重构技术方案（A · Console）

> 状态：布局、字体与设置分组已确认；晴空配色待视觉验收
> 决策日期：2026-10-31
> 修订日期：2026-10-31（三轮评审：§1.4、§1.5 共 8 项调整；§1.6 配色重做）
> 决策：主界面采用原型 A「Console 平衡式」；配色采用 v2「晴空」令牌；原型 B/C 不进入生产实现
> 布局基线：[原型 A](../../prototypes/ui-rework/a-console.html) · [方案索引](../../prototypes/ui-rework/index.html) · [无阶段提示变体](../../prototypes/ui-rework/a-console.html?difficulty=standard)
> 配色基线：[原型 A v2 · 晴空配色](../../prototypes/ui-rework/a-console-v2.html) · [v2 颜色令牌](../../prototypes/ui-rework/assets/palette-v2.css) · [深色预览](../../prototypes/ui-rework/a-console-v2.html?theme=dark)
> 范围：桌面端主界面、字体与数据排版、设置分组、计时与成绩、功能键操作区、比赛名称与 CQ WPX 序号展示口径
> 不在范围：训练状态机、计分算法、音频生成算法、数据库结构

---

## 1. 决策记录

### 1.1 结论

采用原型 A 的信息结构与布局：

- 顶栏只保留品牌、比赛上下文和全局入口；
- 主区域为「日志 + 操作台」左列、「本次练习 + 比赛规则」右列；
- 设置从固定 370px 侧栏改为按需打开的 4 分类侧边抽屉；比赛与电台合并为同一页；
- F1–F12 从 3×4 键盘阵列改为单行动作区，完整键位放入键盘速查对话框；
- 计时、进度、总分和三项统计合并进右侧卡片，已验证总分作为主视觉；
- 拉丁字母与数字以现有 Iosevka 为主字体，中文回退系统 CJK；数据文本启用 tabular figures；
- 配色以品牌蓝 `#0059BA` 为锚点：浅色改为近白卡片 + 浅蓝页面，辅色用青蓝，深色用深海蓝而非炭灰；三级色改为琥珀，仅作小面积暖色引导；废弃旧原型的灰紫表面、板岩灰辅色与紫色三级色；
- 交换信息输入不提供实时匹配/正确性反馈，更正答案只在提交后的日志行显示；
- 运行控制只保留开始/停止，不引入暂停；
- 比赛名称统一使用不含 SSB 后缀的正式名称；
- CQ WPX 发送序号由通联计数自动生成，不可配置、不补零，规则文案去掉「3 位」。

### 1.2 选择理由

| 维度 | A 方案表现 |
| --- | --- |
| 信息优先级 | 日志仍是训练现场的主信息，输入、成绩、规则同时可见 |
| 改动风险 | 组件边界与现有代码基本一一对应，业务 Cubit/Stream 可原样复用 |
| 操作连续性 | 保留「看日志 → 输入 → 发送」的现有工作流，不需要切换主视图 |
| 四个原问题的覆盖 | 设置抽屉、动作单行、成绩压缩和 MD3 组件体系同时解决 |
| 后续扩展 | 右侧卡片可继续容纳复盘、会话统计，不需要改动主网格 |

B「Focus」需要改变主导航并弱化日志常驻；C「Ribbon」以全宽日志为主，会牺牲输入区与成绩区的并列关系。两者保留在 `prototypes/ui-rework/` 作为设计存档，不进入 v0.3.0 生产实现。

### 1.3 实施边界

- 原型只作为视觉与交互基线，生产实现必须使用 Flutter/Material 3 组件，不嵌入 HTML。
- 布局、字体与设置分组已在 §1.4、§1.5 确认，可作为实施基线；配色按 §1.6 输出 v2 原型，待视觉验收。§11 仅保留尚未确认的扩展项。
- 现有键盘映射、训练状态机、计分算法和会话复盘不因 UI 重构而改变；仅按 §1.4、§1.5、§1.6 / §6.1 调整字体策略、设置分组、配色、比赛名称与 CQ WPX 序号展示口径。

### 1.4 评审细节调整（2026-10-31）

| # | 评审反馈 | 结论 | 落地位置 |
| --- | --- | --- | --- |
| 1 | 交换信息不能显示「已匹配」 | 编辑过程中不显示任何匹配/正确性反馈；提交后只在日志中显示更正答案 | §5.3、§5.2 |
| 2 | 更正信息要显示正确答案 | 日志更正列直接渲染现有 `QsoResult.corrections`（正确呼号、正确交换信息、`DUPE`），不再用数量徽章代替 | §5.2 |
| 3 | 训练只有开始和停止，没有暂停 | 不增加暂停；文案统一为「开始训练 / 停止训练」「计时中 · 随时可停止」，停止后保留本次数据 | §5.4、§7 |
| 4 | 阶段提示只有入门难度显示 | 入门显示完整阶段行；标准/进阶整行隐藏、不保留占位；难度在运行中锁定，不产生运行中布局跳动 | §5.3、§4.2 |
| 5 | 比赛名不显示 SSB 后缀 | 顶栏、成绩卡、设置和规则入口统一使用 `ContestDefinition.name`（CQ WPX / CQ WW / ARRL DX / IARU HF / JIDX） | §5.1、§5.5、§6 |
| 6 | CQ WPX 序号自动生成、不可配置、不一定三位 | 原型设置删除序号输入；生产设置不新增该字段（CQ WPX 的 `fields` 为空）；发送序号从 1 开始按 QSO 数递增、不补零；规则摘要与 ARB 去掉「3 位」；日志与输入示例使用原始序号 | §5.6、§6.1、§8.2 |

原型 A 已按以上 6 项更新；B/C 作为设计存档不修改，避免把存档原型误当成生产基线。

### 1.5 第二轮评审调整（2026-10-31）

| # | 评审反馈 | 结论 | 落地位置 |
| --- | --- | --- | --- |
| 1 | 原实现很多地方使用 mono，新版改成 sans-serif 不对 | 以现有 Iosevka（`qsoFontFamily`）作为拉丁字母/数字的主字体，中文和缺失字形回退系统 CJK；数据类文本统一 Iosevka + tabular figures，不再把系统 sans-serif 作为拉丁/数字主字体 | §4.3、§5.2、§5.4、§5.6 |
| 2 | 比赛和电台配置经常联动，合并为一个 Tab | 设置抽屉由 5 类改为 4 类：比赛与电台、训练、音频、系统；比赛与电台在同一页上下排列，切换比赛后站点交换字段即时更新 | §5.6、§6、§8.1 |

原型 A 已同步第二轮调整；B/C 存档不修改。

### 1.6 第三轮评审：配色重做（2026-10-31）

原 A 原型虽然以 `#0059BA` 为 seed，但实际采用的是 MD3 默认派生的灰紫表面、板岩灰辅色和紫色三级色，层级对比弱、整体观感偏阴沉。本轮在不改动布局与组件规格的前提下重做调色盘，形成独立的 v2 原型。

| # | 评审反馈 | 结论 | 落地位置 |
| --- | --- | --- | --- |
| 1 | 旧 A 原型配色阴沉 | 重做「晴空」调色盘：品牌蓝作为 primary；近白卡片 + 浅蓝页面提升亮度；secondary 改青蓝、tertiary 改琥珀、success 改祖母绿；深色改深海蓝 | §4.3.1、[原型 v2](../../prototypes/ui-rework/a-console-v2.html) |
| 2 | 需要区分布局基线与配色基线 | 布局基线仍为原型 A；配色基线为 `a-console-v2.html`；v2 以 `palette-v2.css` 覆盖层实现，`proto.css`、旧 A 原型和 B/C 存档均不改动 | 文件头、§8.2 |
| 3 | 颜色必须可实施、可验收 | 提供浅/深两套完整 MD3 令牌与语义用法；生产按令牌显式构造 ColorScheme，不依赖 `fromSeed` 自动派生；关键组合按 WCAG AA 校验 | §4.3.1、§8.1、§9.1 |

调色盘方向：

- **亮度**：浅色页面 `#F4F8FE`、卡片 `#FBFDFF`/`#FFFFFF`，让日志和成绩成为近白主平面；旧版的 `#F9F9FF`/`#F3F3FA`/`#EDEDF4` 灰紫层级废弃。
- **色相**：primary 保持项目品牌蓝 `#0059BA`；secondary 由板岩灰改为青蓝（浅色 `#006B85`），用于 tonal 控件；tertiary 由紫改为琥珀（浅色 `#8A5200`），只做引导与成绩星标的小面积暖色。
- **深色**：表面改为深海蓝 `#0B1526`、卡片 `#111E32`，而不是旧版的中性炭灰；primary 提亮为 `#A7CCFF`。
- **可读性**：关键文本组合实测浅色最低 5.05:1、深色最低 6.59:1；原型在 1280×720、1024×650 下无溢出。

v2 原型通过覆盖 `:root` / `[data-theme="dark"]` 的颜色令牌实现，组件层只额外使用了三个语义落点：品牌标识（primary 实色）、入门阶段图标（tertiary-container）、设置行图标（primary-container）。旧 A 原型与 B/C 仍保留旧配色，作为历史存档，不参与新视觉评审。

---

## 2. 现状与问题

| 问题 | 现状代码证据 | A 方案处理 |
| --- | --- | --- |
| 不符合 MD3 | [main_app.dart](../../lib/ui/main_app/main_app.dart#L199-L204) 只配置了 seed color；大量 4px 圆角、固定像素布局和自定义分隔线 | 建立统一 MD3 主题：color roles、type scale、shape、state layer、focus ring、tonal surface |
| F1–F12 占空间 | [bottom_panel.dart](../../lib/ui/bottom_panel/bottom_panel.dart#L12-L24) 固定 280px 高；[qso_operation_area.dart](../../lib/ui/bottom_panel/qso_operation_area.dart#L485-L530) 3 行 × 4 列 | 单行 38px 动作区，只展示已分配动作；完整键位与自定义移入键盘速查对话框 |
| 设置需要滚动 | [main_settings.dart](../../lib/ui/main_settings/main_settings.dart#L36-L88) 固定 370px 宽，4 个分组写在单个 `SingleChildScrollView`；[options_setting.dart](../../lib/ui/main_settings/options_setting.dart#L152-L364) 堆叠 8 项以上控件 | 480px 侧边抽屉 + 4 个分类 Tab；比赛与电台合并为一页，内容区独立滚动 |
| 成绩栏占空间 | [time_and_score_area.dart](../../lib/ui/bottom_panel/time_and_score/time_and_score_area.dart#L13-L27) 计时 54px；[score_area.dart](../../lib/ui/bottom_panel/time_and_score/score_area/score_area.dart#L17-L136) 用分隔线拼出原始分/验证分的 3×3 矩阵；另有 240px 速度卡 | 计时、进度、验证总分、原始分/更正、三项统计和运行按钮合入一张 360px 宽侧卡 |

当前窗口固定为 1280×720、最小 1024×650（[main_app.dart](../../lib/ui/main_app/main_app.dart#L150-L157)），这两个尺寸是本方案的主要验收场景。

---

## 3. 目标与验收标准

### 3.1 目标

1. 在 1280×720 和 1024×650 下，主页面不出现整页滚动或 RenderFlex overflow；只有 QSO 日志和设置内容允许内部滚动。
2. 设置抽屉打开后，四个分类在 480px 宽度内完整可见；比赛与电台同页，内容区可滚动，不需要为改电台信息切换 Tab。
3. 默认键位下，F1–F12 操作区在 1280×720 内保持单行；1024×650 允许折成两行。
4. 已验证总分是成绩区唯一主视觉；原始分、更正数和系数作为辅助信息，不再占据独立矩阵。
5. 现有键盘行为、训练状态机、计分算法和会话复盘完全保留；CQ WPX 序号展示口径按 §6.1 调整。
6. 视觉遵循 MD3：tonal surface、filled/tonal/outlined/text 按钮层级、完整焦点环、可读的对比度与 40px 以上点击目标。
7. 交换信息编辑期间不出现匹配/正确性提示；提交后日志的更正列显示正确答案。
8. 运行控制只有开始/停止；界面不出现「暂停」语义。
9. 阶段提示只在入门难度且运行中显示；标准/进阶下操作台不保留提示占位。
10. 比赛名不含 SSB 后缀；CQ WPX 发送序号不可配置、从 1 开始递增且不补零。
11. 拉丁字母和数字以现有 Iosevka 为主字体，中文回退系统 CJK；数据文本启用 tabular figures，不使用 sans-serif 承载数据。
12. 比赛与电台同页时，切换比赛/呼号后站点交换字段即时更新；运行中两个区块一起禁用。
13. 配色以品牌蓝为锚点，浅色近白卡片、深色深海蓝；语义色按 §4.3.1 使用，关键文字组合达到 WCAG AA。

### 3.2 验收清单

- [ ] `flutter analyze` 无新增问题，`flutter test` 全绿。
- [ ] 1280×720 / 1024×650 两种尺寸逐页截图检查，无溢出。
- [ ] 运行中打开设置：控件禁用、提示可见，停止后恢复可编辑。
- [ ] 自定义 F1–F12 后，动作区与键盘速查同步更新。
- [ ] Enter、Tab、Shift+Tab、Space、`;`、Esc 的现有行为不变。
- [ ] 中文（简/繁）、英文、日文文案均通过 ARB 生成本地化，不新增硬编码中文。
- [ ] 键盘速查、设置抽屉支持 Esc 关闭、焦点陷阱和焦点返回。
- [ ] 输入交换信息时不出现「已匹配」等实时反馈；提交后日志更正列显示正确答案。
- [ ] 运行按钮与提示只有开始/停止，无「暂停」文案。
- [ ] 标准/进阶难度下阶段行整行隐藏，1280×720 / 1024×650 无空白占位或溢出。
- [ ] 顶栏、成绩卡、设置中的比赛名均为「CQ WPX」等无 SSB 后缀名称。
- [ ] CQ WPX 设置无序号输入；发送序号从 1 开始递增、不补零，规则文案无「3 位」。
- [ ] 设置抽屉只有四个分类；比赛与电台同页，切换比赛/呼号后站点字段即时更新。
- [ ] 呼号、交换、UTC、计时、分数、速率、统计值等数据文本使用 Iosevka 与 tabular figures；中文正常回退。
- [ ] 浅色/深色按 §4.3.1 令牌实现；关键文字对比度 ≥ 4.5:1，图形与描边 ≥ 3:1。
- [ ] success 只出现在运行状态；tertiary 只用于入门阶段提示与成绩星标；error 只用于错误单元格与更正徽标。
- [ ] 组件内无硬编码颜色；旧版灰紫表面、板岩灰辅色和紫色三级色不再出现。

---

## 4. 布局规范

### 4.1 主结构

```text
┌──────────────────────────────────────────────────────────────┐
│ 顶栏 64：品牌 / 比赛上下文（无 SSB 后缀）   速查 主题 设置     │
├──────────────────────────────────────────────────────────────┤
│ 页面 padding 4 16 16                                         │
│ ┌ 左列 minmax(0, 1fr) ───────────────┐ ┌ 右列 360 ────────┐ │
│ │ QSO 记录（弹性高度，内部滚动）       │ │ 本次练习          │ │
│ │ 5 列：UTC / 呼号 / RST / 交换 / 更正 │ │ 计时 / 进度 / 分数 │ │
│ │                                     │ │ 统计 / 运行按钮    │ │
│ ├─────────────────────────────────────┤ ├──────────────────┤ │
│ │ QSO 操作台（按内容高度）             │ │ 比赛规则（自动高度）│ │
│ │ 阶段提示（仅入门）/ 3 输入框 / 动作行│ │                  │ │
│ └─────────────────────────────────────┘ └──────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 尺寸与断点

| 区域 | 1280×720 | 折叠规则 |
| --- | --- | --- |
| 顶栏 | 64px | 高度 ≤ 700 时降为 60px |
| 页面内边距 | 4 / 16 / 16（上/左右/下） | 固定 |
| 主网格 | `1fr` + 360px，间距 14px | ≤1180px：右列 332px；≤1060px：右列 310px |
| 日志表头 / 行 | 34px / 40px | 固定；行内文本单行省略 |
| 日志更正列 | 最小 108px | 显示正确答案，单行省略；替换旧的 58px 数量徽章列 |
| 阶段提示行 | 26–30px（仅入门、运行中） | 标准/进阶整行不构建；操作台高度随内容收缩，日志吸收剩余高度 |
| QSO 操作台 | padding 12/16/14；字段 64px | 高度 ≤700：padding 10/14/12；字段 58px |
| 动作按钮 | 38px 高 | ≤1060px 允许换行，最多两行 |
| 设置抽屉 | 宽度 `min(480, 94vw)`，4 个分类，全高 | 比赛与电台同页；内容区独立滚动 |
| 右侧卡片 | 上卡片填满剩余高度，下卡片按内容 | 间距 12px |

### 4.3 设计令牌

- **颜色**：以项目品牌蓝 `#0059BA` 为锚点，按 §4.3.1 的浅色/深色令牌显式构造 `ColorScheme`；不使用 `ColorScheme.fromSeed` 的默认派生结果（会重新生成灰紫表面、板岩灰与紫色辅色）。error 表达更正/错误；success 只用于运行状态，通过 `ThemeExtension` 提供，不冒充 MD3 标准角色。深色模式是否本期上线见 §11。
- **字体**：以现有 Iosevka（`qsoFontFamily`）作为拉丁字母/数字的主字体，中文及缺失字形回退系统 CJK；呼号、RST、交换信息、UTC、计时、分数、速率、统计数值、序号和规则数值一律使用 Iosevka + tabular figures。不再把系统 sans-serif 作为拉丁/数字的主字体；只有 Iosevka 缺字时才回退。
- **字号**：卡片标题 15/20 600；正文 14/20；辅助 12–13；呼号输入框静止标签 14、浮动标签 13；计时与总分等宽 42/34（紧凑高度时）；统计值 19。
- **形状**：卡片 16；抽屉 28（仅左侧圆角）；对话框 28；输入容器 12；按钮 16；badge 8。
- **间距**：4px 基础网格；常用 8/12/16/20/24。
- **层次**：优先表面色阶（surface-container-low / container / lowest）而不是阴影；抽屉使用 2 级阴影 + scrim。
- **焦点**：3px primary focus ring、2px offset；不为程序聚焦的抽屉/对话框容器绘制焦点环。

#### 4.3.1 晴空配色令牌

品牌与语义色（`success` 为自定义扩展，其余为 MD3 角色）：

| 角色 | 浅色 | 深色 | 主要用途 |
| --- | --- | --- | --- |
| primary | `#0059BA` | `#A7CCFF` | 主按钮、焦点环、进度、选中 Tab、当前日志行弱高亮 |
| on-primary | `#FFFFFF` | `#00315E` | primary 上的文字 |
| primary-container | `#D5E6FF` | `#00498C` | 品牌标识、设置行图标、tonal 强调 |
| on-primary-container | `#002A56` | `#D6E7FF` | 对应容器上的文字/图标 |
| inverse-primary | `#A3C9FF` | `#0059BA` | snackbar 图标与反色强调 |
| secondary | `#006B85` | `#6FD3ED` | 青蓝辅色，保留 MD3 角色 |
| on-secondary | `#FFFFFF` | `#00363F` | secondary 上的文字 |
| secondary-container | `#C6EAF5` | `#00515F` | 顶栏设置按钮、tonal chip |
| on-secondary-container | `#003441` | `#BFEDF7` | 对应容器上的文字 |
| tertiary | `#8A5200` | `#FFD08A` | 已验证总分星标（每卡一处） |
| on-tertiary | `#FFFFFF` | `#482A00` | tertiary 上的文字 |
| tertiary-container | `#FFE3B3` | `#653F00` | 入门阶段提示图标 |
| on-tertiary-container | `#2E1B00` | `#FFE3B3` | 对应容器上的图标 |
| error | `#BA1A1A` | `#FFB4AB` | 错误呼号/交换信息单元格 |
| on-error | `#FFFFFF` | `#690005` | error 上的文字 |
| error-container | `#FFDAD6` | `#93000A` | 更正徽标底色 |
| on-error-container | `#410002` | `#FFDAD6` | 对应容器上的文字 |
| success（自定义） | `#177D4B` | `#6FDFAC` | 运行状态前景与状态点 |
| on-success | `#FFFFFF` | `#003824` | success 上的文字 |
| success-container | `#C6F2DC` | `#0C4A32` | 运行状态 chip 底色 |
| on-success-container | `#00391F` | `#B0F5D0` | 运行状态 chip 文字 |

表面、文本与描边：

| 角色 | 浅色 | 深色 | 主要用途 |
| --- | --- | --- | --- |
| background / surface | `#F4F8FE` | `#0B1526` | 页面与顶栏底色 |
| on-background / on-surface | `#182030` | `#E4ECF9` | 主文本与数据默认色 |
| surface-variant | `#D6E2F0` | `#3C516E` | 备用变体底色 |
| on-surface-variant | `#4D5E73` | `#B6C7DD` | 辅助文字、标签、次要图标 |
| surface-container-lowest | `#FFFFFF` | `#070F1C` | 输入框、kbd、最高前景 |
| surface-container-low | `#FBFDFF` | `#111E32` | 日志卡、成绩卡、规则卡、设置抽屉 |
| surface-container | `#EAF1FA` | `#16253C` | QSO 操作台、只读字段、备注块 |
| surface-container-high | `#E1EAF6` | `#1E304A` | 对话框、次级容器 |
| surface-container-highest | `#D5E2F1` | `#273B58` | 动作按钮底、进度/开关轨道 |
| inverse-surface | `#2C3547` | `#E4ECF9` | snackbar 背景 |
| inverse-on-surface | `#EEF2FA` | `#24324A` | snackbar 文字 |
| outline | `#6C7E93` | `#8497AE` | 输入描边、可交互边界 |
| outline-variant | `#C3D2E2` | `#394C66` | 分隔线、非交互边框 |
| scrim | `rgba(4, 12, 26, 0.32)` | `rgba(0, 0, 0, 0.6)` | 抽屉/对话框遮罩 |

使用规则：

- 语义落点固定：primary 实色用于品牌标识与主操作；secondary-container 用于 tonal 控件；tertiary 只用于入门阶段提示与成绩星标；success 只用于运行状态；error 只用于错误单元格与更正徽标。不新增装饰性色彩。
- 表面层级固定为 surface（页面）→ low/lowest（卡片）→ container（操作台）→ highest（控件）；深色块不承载主信息。
- 阴影带蓝（浅色 `rgba(13, 42, 82, …)`），不使用纯黑大阴影；边界优先用 `outline-variant` 分隔，不叠加多重阴影。
- 组件不得硬编码色值，统一从 `Theme.of(context)` 与 `success` ThemeExtension 读取；浅色与深色共用同一套组件代码。
- 对比度实测（2026-10-31）：浅色 `on-surface-variant`/low 6.51:1、`primary`/low 6.56:1、`error`/low 6.34:1、success chip 10.68:1，正文最低 5.05:1；深色 `on-surface-variant`/low 9.72:1、`primary`/low 10.13:1、success chip 8.24:1，正文最低 6.59:1。
- 旧 A 原型、B/C 存档及 `proto.css` 保留旧配色不回写；v2 原型只在 `palette-v2.css` 覆盖令牌。

---

## 5. 组件规格与现有代码映射

### 5.1 顶栏（新增）

- 左侧：品牌标识、`SSB Runner` / 副标题、比赛名称、模式/难度/呼号元信息。
- 比赛名称直接使用 `ContestDefinition.name`（CQ WPX、CQ WW、ARRL DX、IARU HF、JIDX），不拼接 SSB 后缀，也不在 UI 中硬编码比赛名。
- 右侧：键盘速查、主题切换（是否本期上线见 §11）、设置。
- 比赛上下文来自现有 `AppSettings` 与 `ContestSettingCubit`，不新增业务状态。
- 品牌图标可复用 `img/logo_128.png`（需在 `pubspec.yaml` 声明）；不引入新图片资源。品牌标识底色使用 primary 实色、图标使用 on-primary，使蓝色品牌锚点在浅色/深色下都成立（原型 v2 已采用）。

### 5.2 QSO 记录（由 `QsoRecordTable` 演进）

- 保留 5 列：UTC / 呼号 / RST / 交换信息 / 更正；列宽改为 `74 / minmax(104, 1.05fr) / 52 / minmax(104, 1fr) / minmax(108, 0.85fr)`，呼号和交换信息吸收剩余宽度，更正列最小 108px 以容纳正确答案。
- 日志数据列（UTC、呼号、RST、交换信息、更正）使用 Iosevka + tabular figures；表头标签照常渲染，中文回退 CJK。
- 表头固定，行高 40px，日志区内部滚动并自动定位到最新记录；保留现有 `QsoRecordListCubit` 的数据库流和自动滚动行为。
- 头部右侧显示「N 条」与「M 处更正」；更正数由 `QsoResult.corrections.isNotEmpty` 的行数得出，不另建统计源。
- **更正列直接渲染现有 `QsoResult.corrections` 字符串**（正确呼号、正确交换信息、`DUPE`），不再用数量徽章代替；无更正显示「—」。这与现有生产行为一致，回归测试需覆盖。长文本单行省略。
- 仅错误的呼号/交换信息单元格使用 error 色，正确字段保持常规色，不能整行染红；最新行使用 primary-container 弱高亮；不再使用隔行底色。
- 日志与输入示例不使用固定 3 位序号；显示存储的原始交换信息（例如 CQ WPX 的 1、2、…、14）。保持现有文本省略和长呼号处理，不改变 `QsoResult` 的数据模型。

### 5.3 QSO 操作台（由 `QsoOperationArea` 演进）

- **交换信息不显示实时匹配**：编辑过程中不显示「已匹配」、成功色或任何正确性提示；只保留焦点、输入过滤和自动大写。正确性只在提交后由日志行与更正列反馈，避免训练时被 UI 提前告知答案。
- 阶段提示：仅入门难度且运行中显示；内容来自现有 `SingleCallRunState`，保留放弃本轮入口。图标底使用 tertiary-container，作为界面中唯一的暖色引导点。标准/进阶**整行不构建**（图标、阶段标题、提示和 Enter chip 一起隐藏），不保留空白占位；操作台高度随内容收缩，日志区吸收剩余高度。难度设置只在停止时可改，因此运行中不会因切换难度产生布局跳动。
- 输入区：呼号、RST、交换信息三个字段横向排列；呼号/交换信息可编辑，RST 只读并显示「自动」；保留自动大写、长度限制、输入过滤和焦点切换逻辑。
- 动作区：由 `functionKeysFromSettings` 动态生成，只展示非 Spare 的动作，按 F 键顺序排列；默认 9 个动作在 1280/1024 下均保持单行（1024 隐藏动作行末端的速查图标），自定义更多动作时允许换行。按钮点击与 F 键都映射到同一个 `OperationEvent`。
- 动作按钮不抢输入焦点：使用 `ExcludeFocus`/不可获取焦点的包装，保证点击发送后输入框仍保持编辑状态。
- 键盘速查入口在 1280 下同时保留在顶栏和动作行末端；≤1060 隐藏动作行末端的重复入口，顶栏入口始终保留，避免按键换行后只剩一个孤立图标。

### 5.4 本次练习 / 成绩卡（替换 `QsoSpeedArea` + `TimeAndScoreArea`）

- 复用 `ScoreAreaCubit`、`_QsoRecordSpeedCubit` 的滚动 5 条速率算法、`ContestTimer.elapseTimeStream` 和现有开始/停止校验逻辑。
- 内容顺序：状态 chip → 已用时间/剩余时间 → 进度条 → 已验证总分 → 原始分/更正数/系数 → QSO/系数/速率 → 运行按钮（开始/停止）→ 运行提示。
- 已验证总分标签的星标使用 tertiary 色，每张卡只出现一处暖色强调；运行状态 chip 使用 success-container，两者语义不互换。
- 已验证总分绑定 `verifiedScore.score`；原始分绑定 `rawScore.score`；系数绑定 `verifiedScore.multiple`；QSO 数绑定 `verifiedScore.count`；速率沿用滚动 5 条算法。
- 剩余时间 = `AppSettings.contestDuration` 分钟 - `ContestTimer.elapseTime`，进度按同一时长计算；比赛结束后收敛为 0。
- 运行控制只有开始/停止，不引入暂停：按钮文案「开始训练」/「停止训练」，运行中提示「计时中 · 随时可停止」，空闲「已停止 · 数据会保留」；不提供暂停按钮、暂停快捷键或「随时可暂停」文案。
- 计时、分数、速率、统计值和计时辅助行使用 Iosevka + tabular figures；中文说明回退 CJK。
- 开始/停止按钮沿用 `_RunBtnCubit` 的完整设置校验与 Toast 错误提示；运行状态和按钮文案由 `isContestRunningStream` 驱动。
- 停止后保留本次 QSO 数据和复盘入口；重新开始会创建新的 run（沿用现有 `startContest` 行为）。
- 不新增「成绩明细」弹窗；原始分和更正数已经在卡片内可见，若后续需要完整明细再复用原型 B 的结构（见 §11）。

### 5.5 比赛规则卡（新增）

- 常驻右列底部，显示三行摘要：你发送、对方发送、计分。
- CQ WPX 摘要为「你发送 59 + 序号 / 对方发送 呼号 + 序号 / 计分 呼号与序号都正确才得分」，不再写「3 位序号」；比赛名显示「CQ WPX」，不带 SSB 后缀。
- 规则数值（59 + 序号、呼号 + 序号）使用 Iosevka；说明句中文回退 CJK。
- 摘要来源为当前 `ContestDefinition` 和已有本地化文案；完整规则继续打开现有 `ContestRulesDialog`，不得硬编码某个比赛。
- 只做信息摘要，不复制规则正文。

### 5.6 设置侧边抽屉（替换固定 `MainSettings`）

- 入口：顶栏设置按钮；打开时覆盖页面，带 scrim、焦点陷阱、Esc 关闭，关闭后焦点返回设置按钮。
- 宽度 480px，右侧全高，左侧 28px 圆角；标题区固定，Tab 栏 48px 固定，内容区独立滚动。
- 四个分类：比赛与电台、训练、音频、系统（分组映射见 §6）。
- 比赛与电台合并页：上半部分为比赛名称、比赛交换格式和比赛规则入口；下半部分为「我的电台」呼号与发送交换信息。
- 切换比赛后，`myExchangePlan` 决定的下半部分字段立即更新：CQ WPX 无交换字段，仅只读序号说明；CQ WW 显示 CQ Zone；ARRL DX 按站点显示州/省或功率；IARU HF 显示 ITU Zone；JIDX 按站点显示都道府县或 CQ Zone。修改呼号时依赖呼号的派生字段也即时更新。
- 合并页内容独立滚动；不要求用户为改电台信息切换 Tab。
- 比赛名称下拉使用 `ContestDefinition.name`，不显示 SSB 后缀；比赛交换格式为只读展示，使用 Iosevka。
- CQ WPX 序号不写入设置、不持久化、不回退旧值；开始校验不要求序号字段。
- 使用 `TabBar` + `IndexedStack`（或保持状态的等价实现），切换分类不重建已有输入状态。
- 设置行图标使用 primary-container 底 + on-primary-container 图标，替换原来的中性灰底；只用于图标容器，不扩展到列表行背景。
- 运行中：比赛与电台两个区块一起禁用，保留查看；显示「比赛进行中无法修改设置，请先停止本次练习」提示。
- 所有现有 `TextEditingController`、Cubit 和对话框按分类迁移，不重写业务逻辑。

### 5.7 键盘速查对话框（替换 `KeyTips`）

- 由顶栏或动作行打开；展示 F1–F12 当前绑定、导航/提交快捷键和「自定义功能键」入口。
- 数据来自 `functionKeysFromSettings`，Spare 显示「未分配」；完整覆盖现有 `KeyTips` 的 7 条全局快捷键，不丢失 Tab、Shift+Tab、Space、`;`、Enter、F12、Esc。
- 使用 MD3 对话框，点击 scrim / Esc / 关闭按钮均可退出，焦点按对话框规则循环。
- 「自定义功能键」复用现有 `_KeyBindingsDialog` 逻辑，保存后动作区立即刷新。

---

## 6. 设置项重新分组

| 新分类 | 生产设置项 | 现有来源 |
| --- | --- | --- |
| 比赛与电台 | 比赛名称（`ContestDefinition.name`，无 SSB 后缀）、比赛交换格式（只读）、比赛规则入口；呼号、站点交换字段（按 `myExchangePlan` 动态生成；CQ WPX 无字段，仅只读序号说明） | `ContestSettingCubit`、`ContestRulesDialog`、`_StationCallsignCubit`、`_StationExchangeFieldInput` |
| 训练 | 训练模式、时长、难度、练习种子 | `OptionsSetting` 前半部分、`_PracticeSeedDialog` |
| 音频 | 音标类型、来台口音、来台音量 | `OptionsSetting` 后半部分 |
| 系统 | 语言、功能键、历史练习、详细日志、复制诊断、导出日志 | `OptionsSetting` 的语言/历史练习、`DiagnosticsSetting` |

迁移原则：

- 不改字段的存储 key、默认值和生效时机。
- 设置固定为四个分类；比赛与电台合并在同一页，切换比赛后站点字段即时更新，不要求用户切换 Tab。
- 比赛名称统一取 `ContestDefinition.name`，不在设置中新增带 SSB 后缀的名称。
- CQ WPX 不提供序号设置项，不读取/写入任何序号持久化值；原型中的序号输入不迁移。
- 训练进行中的禁用规则与现在一致；历史练习、诊断导出等只读操作保持可用。
- 设置侧栏原有的 `SettingItem` 视觉不再使用，提取为抽屉内的分组容器即可。
- 新增文案全部进入 5 个 ARB 文件（en / ja / zh / zh_Hans / zh_Hant）。

### 6.1 CQ WPX 序号口径

- **发送序号**：由本次练习的 QSO 计数自动生成，从 1 开始，第 N 个 QSO 发送 N；不可由用户配置，也不根据呼号推导。
- **不补零**：序号按其自然十进制显示和朗读（1、2、…、14），不强制三位（不补成 001）。涉及 `CqWpxDefinition.myExchangePlan` 的 `serialDigits`、`CqWpxContestType` 的 builder/audio digits 和 `StationExchangeBuilder.buildMyExchange` 的补零路径。
- **接收序号**：仍由训练模拟生成，操作员按听到的内容录入；日志显示存储的原始交换信息，不做 3 位补零。
- **文案**：`ContestDefinition.rulesSummary`、5 个 ARB 的 `contestRulesCqWpx`、比赛规则帮助文档统一改为「59 + 序号」，删除「3 位」。
- **兼容性**：历史 QSO/复盘按已存储的值展示，不强制迁移；新通联使用新格式。

---

## 7. 状态与交互约束

| 项目 | 约束 |
| --- | --- |
| 键盘输入 | 全局 F1–F12、Enter、Tab、Shift+Tab、Space、`;`、Esc 的现有处理链不变；动作按钮只是同事件的指针入口 |
| 输入焦点 | 打开设置抽屉前记录焦点；关闭后恢复；动作按钮、日志滚动不抢输入框焦点 |
| 交换反馈 | 编辑期间不显示匹配/正确性；仅保留焦点与格式过滤；提交后由日志更正列显示答案 |
| 运行控制 | 只有开始/停止；无暂停；停止保留数据，重新开始创建新 run |
| 阶段提示 | 仅入门且运行中构建；标准/进阶整行隐藏，不保留占位 |
| 比赛名称 | 统一取 `ContestDefinition.name`，无 SSB 后缀 |
| WPX 序号 | 自动递增、不可配置、不补零；日志、音频读法与规则文案一致 |
| 字体 | 拉丁字母/数字使用 Iosevka，中文与缺失字形回退 CJK；数据文本启用 tabular figures |
| 配色 | 颜色只取自 §4.3.1；success 仅运行状态，tertiary 仅阶段提示与成绩星标，error 仅更正/错误；组件不硬编码色值 |
| 设置联动 | 比赛与电台同页；切换比赛/呼号后站点字段即时更新，运行中两个区块一起禁用 |
| 运行锁 | 比赛与电台、训练、音频、功能键在运行中禁用；设置抽屉仍可查看 |
| 日志滚动 | 新 QSO 到达自动定位最新；表头与行布局适配 1024 宽度 |
| 计分口径 | 不改变 `ScoreManager`、`ScoreData` 和比赛类型计算器；UI 只负责展示 |
| 训练复盘 | 现有 `TrainingReviewOverlay` 保留，按 MD3 对话框样式重绘，不改变触发时机 |
| 主题 | 若本期落地深色模式，使用 `MaterialApp.theme/darkTheme/themeMode` 并持久化到 `AppSettings`；深色令牌见 §4.3.1，不把颜色硬编码进组件 |
| 性能 | 计时/分数/速率只重建对应的小组件；日志列表保持懒构建，避免每秒重建整页 |

---

## 8. 实施计划与文件影响

### 8.1 分阶段落地

| 阶段 | 内容 | 产出 |
| --- | --- | --- |
| P0 主题基座 | MD3 `ThemeData`（§4.3.1 浅/深令牌，显式构造 ColorScheme）、组件主题、success ThemeExtension、Iosevka 主字体与数据文本样式 | `lib/ui/theme/app_theme.dart`，接入 `main_app.dart` |
| P0b 序号与规则口径 | CQ WPX 发送序号从 1 递增、不补零；规则摘要/ARB/帮助文档去掉「3 位」；补格式化与音频单测 | `contest_definition.dart`、`cq_wpx.dart`、ARB、规则帮助文档、测试 |
| P1 页面骨架 | 顶栏、页面网格、响应式断点、右侧卡片占位 | `main_page.dart` + 顶栏/布局组件 |
| P2 日志与操作台 | 日志卡（更正列显示正确答案）、动作行、输入区（无实时匹配）、阶段提示仅入门、键盘速查 | 复用 `QsoRecordListCubit`、`QsoOperationArea` 逻辑 |
| P3 成绩侧卡 | 计时/进度/验证分/原始分/统计/开始停止按钮（无暂停） | 迁移 `ScoreAreaCubit`、速率 Cubit、`_RunBtnCubit` |
| P4 设置抽屉 | 4 分类（比赛与电台合并）、运行锁、比赛名无 SSB、WPX 序号只读说明、诊断与历史练习迁移 | 拆分 `main_settings`，新增设置抽屉 |
| P5 收尾 | 训练复盘重绘、主题（若确认）、l10n、测试、旧组件清理 | 全量回归 |

### 8.2 文件影响清单

**新增**

- `lib/ui/theme/app_theme.dart`：MD3 主题、§4.3.1 浅/深颜色令牌、语义色扩展、组件默认样式、Iosevka 主字体与数据文本（tabular figures）样式。
- `lib/ui/main_page/app_topbar.dart`：品牌与全局入口。
- `lib/ui/main_page/qso_log_panel.dart`：日志卡与头部统计。
- `lib/ui/main_page/qso_console.dart`：阶段提示、输入区、动作行。
- `lib/ui/main_page/session_panel.dart`：计时、进度、成绩、统计、运行按钮。
- `lib/ui/main_page/rules_card.dart`：规则摘要与完整规则入口。
- `lib/ui/main_page/settings_sheet.dart`：四分类设置抽屉；比赛与电台合并页。
- `lib/ui/main_page/key_reference_dialog.dart`：键盘速查。
- 对应 widget 测试：`test/ui/` 下的新布局、抽屉、动作行、成绩卡测试。
- `prototypes/ui-rework/a-console-v2.html`：A 布局 × 晴空配色原型，作为新配色基线。
- `prototypes/ui-rework/assets/palette-v2.css`：v2 颜色令牌覆盖层，仅作用于 v2 原型。

**修改**

- `lib/ui/main_page/main_page.dart`：改为顶栏 + 响应式主网格。
- `lib/ui/main_app/main_app.dart`：接入 §4.3.1 主题；若确认深色模式，增加 `darkTheme`/`themeMode`。
- `lib/ui/main_settings/main_settings.dart`：保留设置 Cubit，视图迁入抽屉；比赛与电台视图合并为一页。
- `lib/ui/main_settings/options_setting.dart`、`diagnostics_setting.dart`：拆分为训练/音频/系统面板。
- `lib/ui/qso_result_table/qso_record_table.dart`：按新日志卡规格重写视觉层，更正列显示正确答案、错误单元格逐列着色。
- `lib/ui/qso_result_table/qso_result_list/qso_result_row.dart`：调整列宽/省略与逐列 error 色；不改变 `QsoResult` 数据模型。
- `lib/contest_type/contest_definition.dart`：`CqWpxDefinition.myExchangePlan` 去掉固定 3 位；`rulesSummary` 删除「3-digit」。
- `lib/contest_type/cq_wpx/cq_wpx.dart`：发送序号 builder 与接收序号 audio 位数改为不补零。
- `lib/contest_type/station_exchange.dart`：确认 `serialDigits <= 0` 路径与注释；不影响其他比赛的字段格式化。
- `lib/l10n/app_*.arb`：`contestRulesCqWpx` 去掉「3 位」；新增电台序号只读说明；如需要新增开始/停止提示文案。
- `docs/design/contest_rules_help.md`、`docs/design/contest_station_exchange.md`：同步序号口径与规则文案，避免设计文档互相矛盾。
- `prototypes/ui-rework/a-console.html`、`assets/proto.css`、`assets/proto.js`：上一轮 A 原型基线（mono-first 字体、四分类设置），自本轮起冻结；旧配色只保留在存档中，不再回写。B/C 同样不修改。
- `prototypes/ui-rework/assets/Iosevka-Regular-sub.ttf`：原型自带的 Iosevka 子集，v2 原型继续复用，避免本地预览服务器根目录变化导致字体 404。

受影响测试：

- `test/ui/qso_result_table_test.dart`：更正列显示正确答案、长答案省略、错误单元格逐列着色。
- `test/ui/qso_operation_area_test.dart`：输入时不出现匹配提示；入门显示阶段行，标准/进阶不构建。
- `test/contest_definition_test.dart`：WPX `buildMyExchange(7)` 改为 `7`、`formatExchangeForAudio('7')` 改为 `7`。
- `test/station_exchange_test.dart`：保留通用补零函数测试，新增 WPX 不补零路径。
- `test/ui/main_settings_test.dart`、`options_setting_dialog_test.dart`：四个分类、比赛与电台同页、切换比赛/呼号后站点字段即时更新、比赛名无 SSB、WPX 无序号输入。
- 主题层增加数据文本样式断言（Iosevka + tabular figures）；既有 `key_tips_test.dart`、`qso_speed_area_test.dart` 随布局迁移更新。

**退役/替换**

- `lib/ui/bottom_panel/qso_speed_area.dart`：布局退役，速率 Cubit 迁出复用。
- `lib/ui/bottom_panel/time_and_score/time_and_score_area.dart`：布局退役，计时/成绩逻辑迁入 `session_panel.dart`。
- `lib/ui/main_page/key_tips.dart`：由 `key_reference_dialog.dart` 替代。
- `lib/ui/bottom_panel/bottom_panel.dart`：不再作为固定 280px 容器。

---

## 9. 验证方案

### 9.1 布局与视觉

- 1280×720、1024×650 各检查：浅色/深色（若实现）、空闲/运行中、日志为空/满屏、无设置/有设置。
- 无阶段提示变体：使用 `a-console.html?difficulty=standard` 或设置切到标准/进阶，确认阶段行隐藏后操作台上移、日志增长、无空白占位。
- 检查动作区单行与折行、长呼号省略、长本地化文案、分数位数增长（1,000 → 1,000,000）。
- 检查 1024 宽度下顶栏比赛元信息是否省略而不是溢出。
- 更正列：错误呼号/交换信息单元格使用 error 色，更正列显示正确值；长答案省略；1280/1024 都不溢出。
- 比赛名与序号：顶栏、成绩卡、设置、规则卡无 SSB 后缀；规则卡无「3 位」；日志与输入序号按原值显示（1、2、…、14）。
- 字体检查：呼号、交换、UTC、计时、分数、速率、统计值、规则数值应为 Iosevka；数字等宽对齐，中文回退正常，无缺字方块。
- 配色检查：浅色/深色按 v2 原型与 §4.3.1 逐项比对；关键文字 ≥ 4.5:1，图形与描边 ≥ 3:1；success 只出现在运行状态，tertiary 只在入门阶段提示与成绩星标，error 只在错误单元格与更正徽标。
- 检查旧灰紫表面、板岩灰辅色和紫色三级色是否残留；旧 A/B/C 存档不参与配色比对，评审应以 `a-console-v2.html` 为准。
- 设置抽屉、键盘速查、snackbar 分别在浅色/深色下检查文字与图标对比度。
- 设置抽屉为四个分类；比赛与电台同页内容独立滚动，1280/1024 无溢出。

### 9.2 交互

- F1–F12 全部快捷键、Tab 顺序、Shift+Tab、Space、`;`、Enter、Esc。
- 开始/停止校验失败提示、运行中设置锁、停止后恢复；界面无暂停入口或文案。
- 入门/标准/进阶切换（停止状态）：阶段行显隐与顶栏难度标签同步；运行中不能改难度。
- 输入交换信息：不出现「已匹配」等实时反馈；提交后日志更正列显示正确答案。
- 比赛与电台合并页：CQ WPX 无序号输入，只读说明可见；切换比赛/呼号后站点字段即时更新；运行中两个区块一起禁用。
- 自定义功能键保存后动作区、速查同步更新。
- 设置抽屉、键盘速查、完整规则、练习种子、历史练习、诊断复制/导出。
- 顶栏主题切换（若上线）：只替换令牌；运行中、更正、入门提示与焦点环的语义色保持一致，深色下抽屉/对话框/键盘速查均可读。
- 训练结束复盘浮层。

### 9.3 自动化

- `flutter analyze`。
- `flutter test`，重点更新 UI 组件测试与本地化测试。
- 如后续建立 golden 测试，以 1280×720 / 1024×650 两个尺寸作为基线。

---

## 10. 风险与对策

| 风险 | 影响 | 对策 |
| --- | --- | --- |
| 动作行固定高度与自定义 12 键冲突 | 1024 下溢出 | 允许折行；动作按钮高度固定 38，日志区吸收剩余高度；添加最大/最小尺寸测试 |
| 设置抽屉迁移导致 Cubit 重建 | 输入内容或焦点丢失 | 用 `IndexedStack` 保持各面板状态；在抽屉生命周期内维持 Cubit；关闭时销毁 |
| 运行中禁用逻辑遗漏 | 用户中途改配置导致行为不一致 | 统一从 `MainSettingsCubit` 读取运行状态，面板内的可编辑控件全部走同一开关 |
| 计分显示口径混淆 | 用户误读原始分/验证分 | 主数字固定为已验证总分；原始分和更正数只做辅助行，不并列成第二主数字 |
| 秒级计时刷新引起整页重建 | 性能下降、输入卡顿 | 只有计时/进度/速率局部 BlocBuilder；日志列表保持懒构建 |
| 删除旧组件影响测试/引用 | 编译失败或回归 | 先迁移逻辑再删 UI；按文件清单逐项替换并运行全量测试 |
| 深色模式范围膨胀 | 超出本次布局重构 | 主题支持作为 §11 待定项；未确认时不阻塞 P0–P5，但深色令牌已在 §4.3.1 备好 |
| 新配色在深色模式下层次或对比不足 | 可读性下降 | §4.3.1 深色令牌已按 AA 校验；上线前补 1280/1024 深色截图与对比度复核 |
| 评审误用旧原型作为配色基线 | 视觉结论反复 | v2 独立文件与样式层；文档标注配色基线；旧 A/B/C 明确为存档 |
| 近白卡片与浅蓝页面差异过弱 | 卡片边界模糊 | 使用 surface 层级 + `outline-variant` 分隔；以截图验收，必要时加深 `surface-container` |
| 序号不补零改变发送格式 | 旧练习/日志对照差异、音频读法变化 | 旧记录按存储值展示；新 run 从 1 开始；更新 `buildMyExchange`/audio 测试与 ARB |
| 更正列变宽挤压呼号/交换列 | 1024 宽度溢出 | 使用 `minmax` + 单行省略；增加 1024 宽度与长答案测试 |
| 标准/进阶隐藏阶段行 | 布局空洞或运行中跳动 | 整行不构建、日志吸收高度；难度运行中锁定；两尺寸截图验收 |
| 比赛名/规则文案残留 SSB 或「3 位」 | 文案自相矛盾 | 5 个 ARB、`rulesSummary`、规则帮助文档统一检查；l10n 测试 |
| 历史练习旧比赛名带 SSB | 历史列表与新名称不一致 | 按 `contestId` 归一化显示或保留原值，待 §11 确认 |
| Iosevka 缺字或字重不足 | 中文/特殊符号回退不一致，标题合成字重过粗 | 字体栈保留 CJK 回退；检查缺字；必要时补字体字重或调整字号/字重令牌 |
| 比赛与电台合并页过长 | 改呼号需要滚动，常用项被推低 | 比赛信息在前、电台信息在后；内容区独立滚动；常用项置顶；1024 高度验收 |
| 合并页联动遗漏 | 切换比赛后站点字段未更新 | 复用 `myExchangePlan` 单一来源；监听 `ContestSettingCubit` 与呼号变化；测试覆盖各比赛 |

---

## 11. 待补充的小细节

以下为仍需确认的扩展项；三轮评审意见已并入 §1.4、§1.5、§1.6，不再在此重复。

1. **主题切换**：v2 原型已提供浅色/深色两套令牌（§4.3.1），生产目前只有浅色主题。需要确认本期是否实现深色模式与其持久化策略；未确认时先落地浅色令牌，深色不阻塞 P0–P5。
2. **动作行展示策略**：默认 9 个动作在 1280/1024 下均可单行；若用户自定义 10–12 个动作，是否允许两行、是否需要「更多」折叠，待确认。
3. **比赛规则卡**：是否常驻右列；是否只在空闲时显示；是否需要在运行中弱化。原型的「查看」入口行为也需要确认是打开现有完整规则对话框还是跳转独立页面。
4. **日志附加信息**：A 的日志为 5 列（无前缀列）。如果实际训练需要快速判断系数，是否在「交换信息」后补充前缀列（C 方案的 6 列）；更正列加宽后需重新分配列宽，待确认。
5. **成绩辅助信息**：是否需要点击总分打开完整成绩明细；若需要，采用 B 的原始分/验证分对照结构。
6. **顶栏品牌**：使用现有 `img/logo_128.png`，还是使用 Material 图标占位；涉及 `pubspec.yaml` 资源声明。
7. **历史练习中的旧比赛名称**：历史 run 元数据可能保存了带 SSB 的旧名称；是否在列表中按 `contestId` 归一化显示，待确认。
8. **Iosevka 字重**：现有字体资源只有 400 字重，标题/强调字重由合成产生；是否补充 600 字重或调整字重令牌，待视觉验收。
9. **其他细节**：等待用户补充的视觉/交互调整清单。

---

## 12. 参考资料

- 布局原型：[A · Console](../../prototypes/ui-rework/a-console.html)、[A · Console（无阶段提示变体）](../../prototypes/ui-rework/a-console.html?difficulty=standard)、[B · Focus](../../prototypes/ui-rework/b-focus.html)、[C · Ribbon](../../prototypes/ui-rework/c-ribbon.html)
- 配色原型：[A v2 · 晴空配色](../../prototypes/ui-rework/a-console-v2.html)（[深色预览](../../prototypes/ui-rework/a-console-v2.html?theme=dark)）· [v2 颜色令牌](../../prototypes/ui-rework/assets/palette-v2.css)
- 方案索引与对比：[index.html](../../prototypes/ui-rework/index.html)
- 共享设计令牌：[proto.css](../../prototypes/ui-rework/assets/proto.css)（旧配色，存档基线）
- 共享交互脚本：[proto.js](../../prototypes/ui-rework/assets/proto.js)
- 现有功能键设计：[function_keys_f1_f12_design.md](function_keys_f1_f12_design.md)
- 现有比赛规则帮助：[contest_rules_help.md](contest_rules_help.md)
- 交换信息与序号设计：[contest_station_exchange.md](contest_station_exchange.md)
