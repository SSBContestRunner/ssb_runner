# 赛制 / 交换错配：根因分析与技术方案

> 状态：**已实施（2026-11-02，采用方案 A，§14 三项按推荐落地）**
> 来源：用户反馈的录屏——界面选择 CQ WW，实际发送与接收的都是 CQ WPX 交换
> 基线：`e4750e9`（A Console UI）
> 关联历史：`a1127c4`（contest-aware operator exchange，已修“所有赛制都发流水号”）
> 范围：设置 / 会话重放 / 开局链路 / 录像元数据 / 相关 UI 与测试；不涉及音频合成与状态机逻辑

---

## 0. 结论摘要

| # | 问题 | 结论 |
|---|---|---|
| 1 | 选 CQ WW 但收发 WPX 交换 | **旧版确实存在**（发送交换硬编码为流水号），已由 `a1127c4` 修复 |
| 2 | 历史会话重放后界面与实际赛制不一致 | **当前 HEAD 仍存在**（路径 A）；点一次历史即可复现 |
| 3 | 重放后再改赛制 | **当前 HEAD 仍存在**（路径 B）；无任何归属校验 |
| 4 | 修复原则 | 设置单一事实源 + UI 投影同步 + 带赛制的原子重放快照 + 开局解析器 + 录像头自证 |
| 5 | 改动边界 | 不改音频合成、不改状态机、不改 DB schema（录像头复用事件日志 payload） |
| 6 | 方案与决策 | 采用方案 A；§14 三项决策按推荐固化，不再保留备选分支 |

---

## 1. 现象与复现路径

### 1.1 录屏现象

- 界面（顶栏 / 设置里的比赛下拉 / 规则卡）显示 **CQ WW**；
- 实际开局后我方口头发送的是 **CQ WPX 的三位流水号**，对方来台也报流水号；
- 这与“选 CQ WW，实际收发 WPX”的描述一致。

### 1.2 路径 A：历史会话重放（最短复现，不需要改设置）

1. 当前赛制选择 CQ WW，顶栏确认显示 CQ WW；
2. 打开设置 → Past sessions → 点一条录制于 CQ WPX 的会话；
3. 关闭抽屉：顶栏与规则卡仍是 **CQ WW**，但 Console 的 Sent 预览变成 **001**；
4. 点击 RUN：实际按 **CQ WPX** 运行，双方收发流水号。

关键点：第 2 步的恢复动作直接写 `AppSettings.contestId`，而所有界面读的是 `ContestSettingCubit` 的内存快照；Cubit 从不重读，于是“界面事实源”和“开局事实源”分裂。

### 1.3 路径 B：重放后手动改赛制

1. 点历史会话（`pendingReplayRunId` 写入），此时 `settings.contestId` 被改成录像赛制；
2. 用户打开设置，把赛制改回 CQ WW（Cubit 与 settings 重新一致）；
3. 点击 RUN：`ContestType` 按 **CQ WW** 创建，但答案源仍是旧录像，交换值原样返回。

结果：我方发分区、对方发流水号；输入过滤、音频位数、复盘元数据全部按新赛制；本局还会以 CQ WW 名义写入历史，形成错配数据链。

### 1.4 已确认可见的矛盾点

| 观察点 | 读取源 | 恢复重放后会怎样 |
|---|---|---|
| 顶栏赛制名 | `ContestSettingCubit` | 保持旧赛制 |
| 规则卡 | `ContestSettingCubit` | 保持旧赛制 |
| 设置抽屉比赛下拉 | `ContestSettingCubit` | 保持旧赛制 |
| Console 的 Sent 预览（待机） | `AppSettings.contestId` | 变成录像赛制 |
| readiness / Start 的 blocker | `AppSettings.contestId` | 按录像赛制判断 |
| 本次开局实际赛制 | `AppSettings.contestId` | 录像赛制 |

即：一屏之内同时存在两套“当前赛制”。

---

## 2. 现状代码链路

### 2.1 设置与 UI 的读取关系

| 组件 | 读取方式 | 重同步机制 | 证据 |
|---|---|---|---|
| `ContestSettingCubit` | 构造时读一次 `appSettings.contestId` | **无** | [settings_cubits.dart#L32-L45](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/settings_cubits.dart#L32-L45) |
| `TrainingOptionsCubit` | 构造时读一次 mode/duration/difficulty/phonic/accent/volume | **无** | [settings_cubits.dart#L79-L90](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/settings_cubits.dart#L79-L90) |
| `StationCallsignCubit` | 构造时读一次，唯一写入口在它自己 | 无（目前没有外部写入口） | [settings_cubits.dart#L47-L58](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/settings_cubits.dart#L47-L58) |
| 顶栏 | `context.watch<ContestSettingCubit>()` | — | [app_topbar.dart#L22](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/app_topbar.dart#L22) |
| 规则卡 | `ContestSettingCubit` | — | [rules_card.dart#L15](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/rules_card.dart#L15) |
| Session 面板 | 展示用 Cubit；readiness 用 `AppSettings` | 仅 readiness 监听 revision | [session_panel.dart#L55-L73](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/session_panel.dart#L55-L73) |
| Sent 待机预览 | `ContestManager.myExchangeFor` → `settings.contestId` | 监听 revision | [contest_manager.dart#L374-L394](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L374-L394) |

`settingsRevision` 的监听者只有：顶栏设置徽标、SessionPanel、Sent 字段、设置抽屉里的 Station 预览、SettingsSheet 的部分状态——**没有任何 Cubit 重同步**。

### 2.2 恢复入口

| 入口 | 行为 | 证据 |
|---|---|---|
| 历史会话列表 | 逐字段写 `pendingQuestionSeed / pendingAudioSeed / pendingReplayRunId / contestId / contestModeId / difficulty`，然后关闭抽屉 | [settings_sheet.dart#L1519-L1541](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/settings_sheet.dart#L1519-L1541) |
| 复盘浮层“重放本局” | 同样的逐字段直写 | [training_review_overlay.dart#L136-L146](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/training_review_overlay.dart#L136-L146) |
| 历史行可用性 | 运行中**未禁用**（`_ListRow.enabled` 默认 true） | [settings_sheet.dart#L690-L698](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/settings_sheet.dart#L690-L698)、[settings_sheet.dart#L1274-L1281](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/settings_sheet.dart#L1274-L1281) |

`pendingReplayRunId` 是不带赛制的裸字符串：

- 读写：[app_settings.dart#L298-L308](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/settings/app_settings.dart#L298-L308)
- `difficulty` setter 不 bump revision：[app_settings.dart#L141-L149](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/settings/app_settings.dart#L141-L149)

### 2.3 开局链路

[contest_manager.dart#L98-L242](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L98-L242)：

1. 读取并**立刻清空** `pendingReplayRunId`（#L106-L107）；
2. 加载事件日志 `_loadEvents`（#L109-L125，失败时回退种子）；
3. `ContestRegistry.byId(settings.contestId)` → `definition`（#L128）；
4. `definition.create(...)` → `contestType`（#L147-L151）；
5. `_activeRun` 元数据用 `definition.id / definition.name`（#L155-L165）；
6. 空呼号池时 `return`（#L182-L191）——此时 `pendingReplayRunId` 已被吃掉；
7. 创建 `ContestRunningManager`，答案源为录像或生成器（#L224-L232）。

录像加载：[_loadEvents](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L335-L348)；回放：[ReplayAnswerSource](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/training/replay_answer_source.dart#L17-L39)。

### 2.4 录像与元数据

| 数据 | 内容 | 证据 |
|---|---|---|
| `eventLogTable` | 仅 `runId / elapsedMs / eventType / payload(JSON) / createdAtUtc` | [event_log_table.dart#L6-L17](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/db/table/event_log_table.dart#L6-L17) |
| `TrainingRunEvent` | 只有 callsign / exchange / pileup / modeId | [session_review.dart#L41-L82](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/training/session_review.dart#L41-L82) |
| `TrainingRunMetadata` | 含 contestId/contestName，但只存在 `sessionHistory` 的复盘里 | [session_review.dart#L6-L36](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/training/session_review.dart#L6-L36) |
| 历史容量 | 只保留最近 30 条 | [app_settings.dart#L254-L265](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/settings/app_settings.dart#L254-L265) |

录像本身无法自证赛制；历史条目被淘汰后更无据可查。

### 2.5 输入过滤与位数策略

| 行为 | 代码 | 说明 |
|---|---|---|
| 输入字符过滤 | [qso_console.dart#L715-L730](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/qso_console.dart#L715-L730) | 监听 `contestTypeStream`，用运行中 `ContestType.allowExchangeRegex` 过滤 |
| 赛制字符集 | [contest_definition.dart#L153](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_type/contest_definition.dart#L153)、[#L313-L314](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_type/contest_definition.dart#L313-L314) | ARRL 允许字母，其余只允许数字 |
| 音频补位 | [station_exchange.dart#L265-L273](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_type/station_exchange.dart#L265-L273) | 按赛制 `exchangeAudioDigits` 补零 |
| 落库去零 | [contest_definition.dart#L399-L400](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_type/contest_definition.dart#L399-L400)、[cq_wpx.dart#L65-L68](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_type/cq_wpx/cq_wpx.dart#L65-L68) | `^0+(?=.)` 去除前导零 |

---

## 3. 根因清单

| ID | 根因 | 层级 | 证据 | 严重度 |
|---|---|---|---|---|
| R1 | 设置与 UI Cubit 双事实源，Cubit 无重同步 | 状态管理 | `settings_cubits.dart` 全篇、全库仅 4 处 revision 监听 | P0 |
| R2 | 恢复入口直写 prefs，绕过 Cubit 写入口 | 状态管理 | 历史列表、复盘浮层 | P0 |
| R3 | `difficulty` 等 setter 不 bump revision | 状态管理 | `app_settings.dart#L141-L149` | P1 |
| R4 | 待重放只存 runId，不存赛制/模式/难度 | 数据模型 | `app_settings.dart#L298-L308` | P0 |
| R5 | 开局用当前 settings 建 ContestType，录像原样喂回 | 开局 | `contest_manager.dart#L128-L151`、`replay_answer_source.dart` | P0 |
| R6 | 运行中可打开并选择历史会话 | UI 约束 | `settings_sheet.dart#L690-L698` | P1 |
| R7 | 录像无赛制字段，无法自证归属 | 数据模型 | `event_log_table.dart`、`TrainingRunEvent` | P1 |
| R8 | 开局先清 pending，early return 会丢重放 | 开局 | `contest_manager.dart#L106-L107`、`#L182-L191` | P2 |
| R9 | readiness 与 UI 各自读不同源 | UI 一致性 | `settings_readiness.dart#L48-L53` vs `session_panel.dart#L55-L73` | P1 |
| R10 | `ContestRegistry.byId` 静默回落 WPX | 领域层 | `contest_definition.dart#L50-L53` | P2 |

---

## 4. 影响评估（含审计修正）

上一轮分析中“跨赛制重放每一题都会判错”的说法**过重**，需要修正：

- `_logQsoAndAdvance` 落库前会调用 `processExchange` 去前导零，`007 → 7`；
- 录制值是生成器输出（未补零），因此纯数字对纯数字的重放**通常仍判对**；
- 真正确定的破坏是：
  1. **我方发送语义错误**（流水号 vs 分区），即录屏现象；
  2. 对方交换内容不合赛制（WPX 的 `2500` 被当作 CQ 分区）；
  3. 音频位数按新赛制重算（`7` 念成 `07` 或 `007`），听到值与录制原值不一致；
  4. **ARRL 字母交换在数字赛制下无法输入**（输入框被 `allowExchangeRegex` 过滤），该局无法正常完成；
  5. 复盘/历史按新赛制落库，污染后续重放（可形成链式错配）；
  6. 同一屏内 readiness 与展示赛制互相矛盾。

---

## 5. 设计目标与不变量

- **I1 同源**：界面上展示的赛制/模式/难度，与 `startContest` 实际使用值同源。
- **I2 冻结**：一局开始后，运行中的赛制/模式/难度与开局前展示值一致。
- **I3 归属**：一次重放只能跑它自己录制的赛制；不匹配必须显式取消或明确提示，绝不静默混跑。
- **I4 原子**：待重放状态必须一次性写入（runId + 赛制 + 模式 + 难度 + 种子）。
- **I5 自证**：录像可凭持久化数据证明赛制归属，不依赖内存或 UI 状态。
- **I6 非破坏**：arm / cancel / 开局失败都不改写用户的普通设置；只有“重放校验通过且真正启动”才提交本次 RunPlan。
- **I7 来台唯一**：重放只复刻来台答案；我方发送交换始终由当前站台设置生成，不使用录像快照。

---

## 6. 方案选型

| 方案 | 描述 | 满足不变量 | 结论 |
|---|---|---|---|
| **A** | 设置唯一事实源 + Cubit 投影同步 + `PendingReplay` 原子快照 + 开局解析器 + 录像头校验 + armed 锁定/取消 | I1–I7 | **采用**；改动集中在设置、开局、UI 三处，不动音频与状态机 |
| B | 仅让 Cubit 监听 revision | I1、I2 | 不采用：只消除“界面骗人”，路径 B 仍在 |
| C | 开局一律按录像赛制，允许改设置但静默覆盖 | I1–I3 部分 | 不采用：用户意图被覆盖，违背 I6 |
| D | `ContestManager` 全面依赖注入 `RunSpec`，不再直接读 prefs | I1–I7 | 不采用：收益与 A 相近，改动面过大 |

本文档按方案 A 展开，所有设计细节均以“已定方案”表述，不再保留备选实现。

---

## 7. 详细设计

### 7.1 `PendingReplay` 值对象

建议位置：`lib/training/`（与 `session_review` 同层）或 `lib/settings/`。

字段：

| 字段 | 说明 |
|---|---|
| `runId` | 被重放的会话 id |
| `contestId` / `contestName` | 赛制（name 仅用于展示） |
| `modeId` / `difficultyId` | 重放时应复原的模式与难度 |
| `questionSeed` / `audioSeed` | 与现有 pending 种子一致的语义 |
| `armedAtUtc` | 展示“哪一局、何时” |

要求：

- `toJson / fromJson`，容忍未知字段；
- 缺字段时显式降级为 `unknown`，不猜；
- 它表达“下一局要重放什么”，不是“用户当前设置什么”。

### 7.2 `AppSettings` 改造

| 项 | 内容 |
|---|---|
| 新键 | `setting_pending_replay_v2`（JSON）；旧键 `setting_pending_replay_run_id` 保留只读兼容 |
| 新 API | `pendingReplay` getter；`armReplay(PendingReplay)`；`clearPendingReplay()`；`commitRunSpec(RunPlan)` |
| `armReplay` | **只写待重放快照**，不改写 `contestId / contestModeId / difficulty`；一次性写入全部字段并 **只 bump 一次** revision |
| 派生（待机） | `effectiveContestId / effectiveModeId / effectiveDifficultyId` = armed 时取 `PendingReplay`，否则取普通设置 |
| `commitRunSpec` | 仅在开局校验通过、真正启动前调用：一次操作内把 RunPlan 的赛制/模式/难度写入普通设置并清空待重放，只 bump 一次 |
| 补全 bump | `difficulty`、`incomingAccent`、`phonicType`（至少 `difficulty`，顶栏会展示） |
| 现有字段 | `pendingQuestionSeed / pendingAudioSeed` 保留（种子对话框仍单独使用）；重放时以 `PendingReplay` 内种子优先 |

关键语义：

- **arming 不产生副作用**：取消重放、开局失败都会让用户回到 arm 之前的设置；
- **成功启动才提交**：提交后普通设置即本次实际运行值，运行中 UI 读取设置与冻结值天然一致（满足 I2），无需额外的“运行中赛制”通道；
- `effective*` 只用于待机展示与 readiness，运行中一切以冻结的 `_activeContestType` 与该次 RunPlan 为准。

### 7.3 UI 投影同步

- `ContestSettingCubit`、`TrainingOptionsCubit`、`StationCallsignCubit`：
  - 构造时订阅 `settingsRevision`，`close()` 取消；
  - 回调中**只读 prefs 并 emit**，不回写，避免循环；
  - `ContestSettingCubit` 读 `effectiveContestId`，`TrainingOptionsCubit` 读 `effectiveModeId / effectiveDifficultyId` 与其余普通选项；
  - 用注册表 const 单例的 identity 比较，内容相同不重复 emit；
  - `TrainingOptionsCubit` 需同步 `durationController`：非聚焦时直接刷新文本，聚焦时保留编辑态（沿用现有失焦回填逻辑）。
- Cubit 写方法（`changeContest / setMode / setDifficulty`）：
  - **armed 时直接拒绝（no-op + 断言/日志）**，作为 UI 禁用之外的防御层；
  - 未 armed 时保持“写 prefs + emit”，不再负责清理 `pendingReplay`（锁定策略下不存在“改设置即取消”的分支）。

> 完成这一层后，任何“直接写 prefs”的入口都不会再让界面落后于实际值（路径 A 消失）；armed 时界面展示的是快照值，而不是尚未提交的普通设置。

### 7.4 恢复入口统一

- 历史列表与复盘浮层统一调用 `armReplay(PendingReplay.fromReview(review))`，不再逐字段写。
- `armReplay` **不修改普通设置**：arm 后顶栏/规则卡/Sent 预览通过 `effective*` 展示重放赛制；取消后自动回到 arm 前设置。
- 已 armed 时再选择另一条历史会话：**替换**当前快照即可（这是重放意图，不是设置修改），不需要先取消。
- 运行中禁用历史行，且禁止 arm：`_ListRow(enabled: !isRunning)`；`armReplay` 在 `isContestRunning` 时拒绝写入并记日志。
- 复盘浮层本身只在停止后出现，保持不变。
- 历史条目被淘汰但 `pendingReplay` 仍存在时：由录像头自证赛制；若无法自证则按 §7.5 的“重放中止”处理。

### 7.5 开局解析器 `RunPlanResolver`

纯函数/服务，输入 `settings`、`ContestRegistry`、`PendingReplay?`、`recordedHeader?`、`events`，输出：

| 输出字段 | 说明 |
|---|---|
| `contestId / definition` | 实际使用赛制 |
| `modeId / difficultyId` | 实际模式与难度 |
| `questionSeed / audioSeed` | 实际种子 |
| `replayRunId` | 非空表示本次为录像重放 |
| `source` | `pending`（重放）/ `settings`（普通开局或中止后的新局） |
| `abortedReason` | 中止重放的原因：`events_missing / header_mismatch / contest_unknown` |
| `warnings / errors` | 供 toast 与诊断 |

决策矩阵——**只有完全一致才重放；录像头只做校验，不做覆盖**：

| `pendingReplay` | 录像事件 | run-start 头 | 结果 |
|---|---|---|---|
| 无 | 任意 | 任意 | `source=settings`，普通开局 |
| 有 | 空 / 加载失败 | 任意 | **中止重放**：清 pending，`source=settings`，toast |
| 有 | 非空 | 存在且 contest / mode / difficulty 三项一致 | 重放，`source=pending` |
| 有 | 非空 | 存在但任一项不一致 | **中止重放**：清 pending，`source=settings`，toast + error 日志 |
| 有 | 非空 | 不存在（老录像） | 允许重放，`source=pending`，记 info |
| 有 | 任意 | 任意，但 `pending.contestId` 不在注册表 | 先查旧 id 别名；仍未知 → **中止重放**，`source=settings`，告警 |

补充规则：

- 中止重放时**不采用录像头的赛制**，也不强行改写用户设置（满足 I6）；
- 中止后按当前普通设置与种子开新局；`pendingReplay` 清空后 UI 自动回落到设置值；
- `source` 与 `abortedReason` 写入日志，并由开局结果带给 UI 弹 toast。

### 7.6 `ContestManager.startContest` 改造

时序（严格按序）：

1. 快照 `pendingReplay`（**不清空、不改设置**）；
2. 加载事件日志并解析 run-start 头；
3. `RunPlanResolver` 解析，得到 RunPlan 或 `abortedReason`；
4. **前置校验**：呼号池非空、赛制可解析、站台交换配置有效（armed 时按 effective 赛制）；失败则保留 pending 并返回 notices，不提交；
5. **提交**：调用一次 `commitRunSpec(RunPlan)`（内部完成“写普通设置 + 清空 pending”，单次 revision bump）；
6. 创建 `ContestType`、`_activeRun` 元数据、音频档位、计时器与 `ContestRunningManager`；
7. 把 `_activeRun / _activeContestType` 的赋值移到前置校验之后，避免半初始化状态（现状是 #L155-L166 早于空池检查 #L182-L191）。

失败与中止语义：

- 第 4 步失败：pending 保留、普通设置不动、`_isContestRunning` 仍为 false；返回值带 notice（修 R8）；
- 重放中止（`abortedReason` 非空）：清 pending，RunPlan 取 settings，按普通开局继续，返回值带 toast；
- 第 5 步之后不再有“可失败且应回滚”的步骤；DB / 音频异常沿用现有“尽力而为”策略，不回滚设置。

接口：

- `startContest` 返回 `RunStartResult { started, source, abortedReason, notices }`；
- `_RunButton`（[_RunButton](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/session_panel.dart#L623-L663)）根据 result 弹 toast；现有测试忽略返回值不受影响。

`myExchangeFor`（#L374-L394）：

- 运行中：用冻结的 `_activeContestType`；
- 待机：用 `effectiveContestId`，armed 时预览录像赛制；我方交换始终取**当前站台呼号与交换配置**（I7）。

### 7.7 录像头（run-start 事件）

- 开局创建 metadata 后，向 `eventLogTable` 插入一条 `eventType = 'run-start'`，payload 至少包含：
  `contestId / contestName / modeId / difficultyId / questionSeed / audioSeed / accentId / appVersion / replayOfRunId`。
- `ReplayAnswerSource.fromEvents` 已按 `type == 'answer'` 过滤，天然兼容。
- `_loadEvents` 解析头；无头老录像按 `PendingReplay`（其赛制来自 `sessionHistory[runId].metadata`）放行。
- 写入失败只降级告警，不阻塞开局。
- **零 schema 迁移**：payload 是 JSON；若未来需要强查询再考虑新建 `RunMetaTable`（schema v6），本期不做。

用途：**只做一致性校验**，不作为覆盖来源。`pendingReplay` 与头在 contest / mode / difficulty 任一项不一致时，按 §7.5 中止重放，而不是采用头里的值。

### 7.8 只读预览与 readiness 统一

- `checkSettingsReadiness` 改用 `effectiveContestId`；armed 时校验录像赛制的站台交换字段（例如 ARRL 需要 Power）。
- Sent 字段的“打开设置”入口（[qso_console.dart#L653-L673](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/qso_console.dart#L653-L673)）同样用 effective 定义定位字段。
- 我方发送交换始终由**当前站台呼号 + 当前站台交换配置**生成（决策 2）：重放录像只提供来台答案，不提供我方交换快照；armed 横幅需注明“重放仅复刻来台，我方按当前站台设置发送”。
- Session 面板继续用 Cubit 展示；§7.3 完成后两侧一致。

### 7.9 armed 状态交互（决策 1 固化）

采用**锁定 + 显式取消**，不使用“改赛制前确认”的分支：

| 场景 | 行为 |
|---|---|
| 历史 / 复盘 arm 后 | Session 面板显示“将重放：赛制 · 模式 · 难度 · 时间”与“取消重放”；顶栏/规则卡/Sent 预览按 `effective*` 展示 |
| 设置抽屉 | 比赛 / 模式 / 难度控件禁用；站台交换字段仍可编辑（readiness 需要） |
| 再选另一条历史会话 | 直接替换 armed 快照（属于重放意图） |
| 取消重放 | `clearPendingReplay()` + toast；普通设置未被改动，界面自动回到 arm 前的赛制/模式/难度 |
| 运行中 | 历史行禁用，`armReplay` 拒绝写入（pending 在成功启动时已清空） |
| 禁止行为 | 改赛制后仍沿用旧录像；静默合并两套赛制；arm 期间通过任何非 UI 入口改写赛制 |

核心原则：**绝不允许“改了赛制但仍偷偷用旧录像”**；取消是唯一出口。

### 7.10 日志

`Training started` 增加：

- `requestedContestId`、`effectiveContestId`、`planSource(pending/settings)`；
- `replayRunId`、`recordedContestId`、`recordedModeId`、`replayAbortedReason`；
- `committedContestId / committedModeId / committedDifficultyId`（本次提交给普通设置的值）。

事件：

- `settings.replay`：arm / replace / cancel 三种；
- `contest.replay.abort`：中止原因、pending 与头各自的赛制/模式/难度；
- 所有不一致用 warn/error，正常中止用 info。

### 7.11 `ContestRegistry.byId` 硬化

- 新增 `byIdOrNull`；持久化 id 的解析统一走 resolver；
- resolver 检测未知 id 并告警，可配置旧 id 别名表；
- 不在 UI 层依赖 WPX 默认回退。

---

## 8. 兼容与迁移

| 场景 | 处理 |
|---|---|
| 旧 `setting_pending_replay_run_id` | 读取时组装 `PendingReplay`：runId 用旧键，赛制/模式/难度从 `sessionHistory` 按 runId 查找；查不到标记 unknown，开局按 §7.5 **中止重放**并提示（不改普通设置） |
| 老录像无 run-start 头 | 允许重放：以 `PendingReplay` 的赛制/模式/难度为准（0.2.0 起复盘必存 contestId）；记 info |
| 历史 30 条淘汰 | 有头可自证即可重放；无头且 pending unknown 则中止 |
| 赛制 id 改名 | 别名映射 + 告警；仍未知则中止重放，不做隐式 WPX 回退 |
| 旧版本已改写普通设置 | 升级时保留原值；因旧实现 arm 已写过设置，“取消”无法回到更早选择，属一次性迁移代价，文档记录即可 |
| 数据损坏 / 未知 id | 中止重放 + 明确提示，不静默 |

不迁移 `event_log` 表，不改 schema 版本。

---

## 9. 文案清单（l10n）

需同步 `app_en.arb / app_zh_Hans.arb / app_zh_Hant.arb / app_ja.arb`（如 `app_zh.arb` 仍参与生成也补）：

- `replayArmedTitle`、`replayArmedDetail(contest, mode, difficulty, time)`
- `replayArmedStationHint`（“重放仅复刻来台，我方按当前站台设置发送”）
- `cancelReplay`、`replayCancelledToast`
- `replayLockedHint`
- `replayAbortedToast(contest)`（录像缺失 / 赛制冲突统一出口）
- `replayContestMismatchLog`（仅日志用，不必进 UI）
- `pastSessionsUnavailableWhileRunning`

---

## 10. 测试方案

### 10.1 单元

| 用例 | 断言 |
|---|---|
| `PendingReplay` JSON roundtrip | 字段无损；未知字段容忍 |
| 旧键兼容 | 仅有旧 `pendingReplayRunId` 时能组装；历史缺失时标记 unknown |
| `armReplay` | 只写 pending；普通 `contestId / contestModeId / difficulty` 不变；revision 只 +1 |
| `clearPendingReplay` | pending 清空；普通设置不变；revision +1 |
| `commitRunSpec` | 三个字段一次写入；revision +1 |
| `difficulty` 等 setter | revision 递增 |
| `RunPlanResolver` | 矩阵六种组合逐条断言：事件缺失/头缺失/头一致/头冲突/未知 id/无 pending；**冲突时中止而非采用头** |
| Cubit 同步 | 直接写 `settings.contestId / difficulty` 后两个 Cubit 均 emit；armed 时展示 `effective*`；重复 revision 不重复 emit |
| Cubit 防御 | armed 时 `changeContest / setMode / setDifficulty` 不写 prefs、不改状态 |

### 10.2 集成（复用内存 DB / 内存 prefs 夹具）

夹具：[contest_state_change_handler_test.dart#L48-L60](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/test/contest_state_change_handler_test.dart#L48-L60)。

| 用例 | 断言 |
|---|---|
| armed WPX（普通设置仍 CQ WW） | 待机 effective=WPX、Sent=`001`；启动成功后普通设置提交为 WPX、metadata `contestId`=WPX |
| 头冲突（pending WPX / header CQ WW） | 中止重放：pending 清除、普通设置保持 CQ WW、实际按 CQ WW 开新局、result 带 toast |
| armed 后取消 | pending 清除；普通设置与取消前完全一致 |
| armed ARRL + 当前站台 power=100 | 运行期 `allowExchangeRegex` 按 ARRL 可输入 `CA`；我方发送为当前站台配置的 `100`（决策 2） |
| 无头录像 + history 元数据 | 允许重放，按 pending 赛制 |
| 录像事件缺失 | 中止重放 + 清 pending + notice；普通设置不变 |
| 空呼号池导致启动失败 | pending 保留、普通设置不变（未提交） |
| 未知持久化赛制 id | 中止重放 + 告警，不静默 WPX |
| 同赛制重放 | 录制 `5` 在 CQ WW 下念 `05`，输入 `05` 判对 |

### 10.3 Widget

| 夹具 | 用例 |
|---|---|
| [_pumpMainPage](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/test/ui/main_page_layout_test.dart#L197) | CQ WW 显示下 arm WPX → 顶栏/规则卡/Sent 全部切到 WPX；启动后仍一致 |
| [_pumpSheet](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/test/ui/settings_sheet_test.dart#L498) | armed 时赛制/模式/难度禁用 + 横幅；取消后恢复可编辑且回到 arm 前赛制 |
| 同上 | armed 时再选另一条历史会话：替换快照，横幅信息更新 |
| 同上 | 运行中 Past sessions 行禁用（点击无副作用） |
| 同上 | 复盘浮层重放后 Cubit 与实际一致 |

### 10.4 手测

- 录屏原场景：CQ WW → 点 WPX 历史 → RUN（界面与收发全程 WPX）。
- arm 后点“取消重放”→ 界面回到 CQ WW、Sent 回到分区。
- arm 后杀进程重启 → RUN（验证待重放持久化与启动时提交）。
- 重放成功启动后再停止：普通设置即为录像赛制；改赛制再 RUN 无重放残留。
- 1024×650 / 1280×720，四语言横幅与 toast 不溢出。

---

## 11. 实施分期与验收

| 阶段 | 内容 | 验收标准 | 依赖 |
|---|---|---|---|
| **P0-1 同步层** | Cubit 订阅 revision；补 `difficulty` bump；运行中禁历史 | 所有展示/预览/readiness 都读 `effective*`；路径 A 消失 | 无 |
| **P0-2 重放快照** | `PendingReplay` + 非破坏 arm + 解析器 + armed 锁定/取消 + `commitRunSpec` | 决策 1 与决策 3 成立：不存在“改赛制仍用旧录像”；取消可回到原设置；只有成功启动才提交 | P0-1 |
| **P1 自证与提示** | run-start 头 + 一致性校验 + 中止/回退 + 日志 + toast | 决策 3：任何缺失/冲突都中止并可见提示，无静默回退 | P0-2 |
| **P2 硬化** | `byId` 别名/告警、l10n、设计文档与发布说明 | 旧数据兼容、四语言完整、手测矩阵通过 | P1 |

---

## 12. 风险与对策

| 风险 | 对策 |
|---|---|
| revision 监听引发重建风暴 | identity 比较；arm/commit 各只 bump 一次；监听回调不回写 |
| 成功启动后普通设置被提交为录像赛制 | 属预期行为（日志记录 committed 值）；取消/失败路径保证不写 |
| 提交与启动顺序出错导致“设置了但没跑起来” | 提交严格放在全部可失败前置校验之后（§7.6 第 5 步） |
| 锁定赛制降低可编辑性 | 显式“取消重放”入口 + 抽屉内说明 |
| 旧数据/旧键 | 兼容读取 + unknown 显式中止告警 |
| run-start 写入失败 | 降级为 pending/history 校验，不阻塞开局 |
| 历史 30 条淘汰 | 头部事件仍可校验；无头且 unknown 则中止 |
| `byId` 静默 WPX | 集中到 resolver 检测 + 日志 |

---

## 13. 明确不做

- 不做 PCM 级精确音频复刻（重放仍按文本重新合成）。
- 不把站台呼号、音量、种子锁等全部快照进录像（只还原影响答案与元数据的字段）。
- 不改计分/乘数规则，不改状态机。
- 不做云端同步/多设备。

---

## 14. 已固化决策（2026-11-02）

| # | 决策点 | 固化结论 | 落地位置 | 验收锚点 |
|---|---|---|---|---|
| 1 | armed 期间改赛制 | **锁定赛制 / 模式 / 难度 + 显式取消**；arm 不改普通设置；可选择另一历史会话替换快照；取消后回到 arm 前设置 | §7.2 / §7.3 / §7.4 / §7.9 | 集成：头冲突与取消；Widget：控件禁用与恢复 |
| 2 | 重放时的我方交换 | **始终使用当前站台呼号 + 当前交换配置**；录像只复刻来台答案；armed 横幅明确提示 | §7.6 / §7.8 | 集成：armed ARRL + power=100 → 我方发送 100 |
| 3 | 录像缺失 / 赛制冲突 | **放弃重放、清 pending、按当前设置开新局 + 明确 toast**；录像头只校验、不覆盖、不静默 | §7.5 / §7.6 / §7.7 | 集成：头冲突 / 事件缺失；日志事件 `contest.replay.abort` |

**不采用清单**（避免实现时再次分叉）：

- 改赛制前弹确认、确认后取消重放；
- 用录像快照完全复刻我方交换；
- 冲突时采用录像头的赛制、或静默覆盖用户设置；
- 中止重放但仍播放部分录像，或回退到“种子 + 旧录像混合”。

---

## 15. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-02 | 按推荐固化 §14 三项决策；新增 I6（非破坏）与 I7（来台唯一）；arm 改为非破坏，只有成功启动才 `commitRunSpec`；解析器由“优先级覆盖”改为“三项一致才重放” |
| 2026-11-02 | 按 §7 落地实现：`PendingReplay` / `RunPlanResolver` / `commitRunSpec`、Cubit 投影同步、run-start 头自证、armed 锁定与取消、五语言文案与单元/集成/Widget 测试 |

---

## 附录 A：受影响文件清单

| 文件 | 改动类型 | 风险 |
|---|---|---|
| `lib/settings/app_settings.dart` | `PendingReplay` 读写、`effective*`、`commitRunSpec`、补 bump | 中（持久化兼容） |
| `lib/training/session_review.dart` 或新文件 | `PendingReplay` 值对象与序列化 | 低 |
| `lib/ui/main_page/settings_cubits.dart` | 订阅 revision、读 `effective*`、armed 写保护 | 中（重建次数） |
| `lib/ui/main_page/settings_sheet.dart` | 历史 arm 入口、运行中禁用、armed 锁定/横幅/取消 | 中 |
| `lib/ui/main_page/training_review_overlay.dart` | 改用 `armReplay` | 低 |
| `lib/contest_run/new/contest_manager.dart` | `startContest` 解析/校验/提交、返回结果、待机预览 | 高（核心链路） |
| `lib/contest_run/new/run_plan_resolver.dart`（新） | 解析与一致性校验 | 中 |
| `lib/settings/settings_readiness.dart` | 使用 `effectiveContestId` | 低 |
| `lib/ui/main_page/qso_console.dart` | 待机预览/打开设置使用 effective 定义 | 低 |
| `lib/ui/main_page/session_panel.dart` | armed 横幅、取消按钮、Start 结果 toast | 中 |
| `lib/ui/main_page/app_topbar.dart` / `rules_card.dart` | 不变（依赖 Cubit 同步自动修正） | 低 |
| `lib/l10n/*.arb` + generated | 新文案 | 低 |
| `test/...` | 新增单元/集成/Widget 用例 | 低 |

## 附录 B：行为矩阵

| 场景 | 界面展示（顶栏/规则卡/下拉） | Sent 预览 | readiness | 实际开局 | 说明 |
|---|---|---|---|---|---|
| 空闲，选 CQ WW | CQ WW | 分区 | CQ WW | CQ WW | 一致 |
| arm WPX（普通设置仍 CQ WW） | WPX（effective） | 001 | WPX | WPX（成功后提交为 WPX） | arm 非破坏；取消即回 CQ WW |
| armed 时尝试改赛制 | 控件禁用 | — | — | — | 唯一出口是“取消重放” |
| 取消重放 | CQ WW（回到 arm 前） | 分区 | CQ WW | CQ WW | 普通设置从未被改写 |
| 重放成功启动后 | WPX（设置已提交） | 001 | 运行中不重算 | WPX | 停止后仍为 WPX |
| 重放中止（事件缺失 / 头冲突） | 回到普通设置 | 对应普通赛制 | 对应普通赛制 | 按普通设置开新局 | 清 pending + toast |
| 运行中 | 本次冻结赛制 | 冻结 | 不重算 | 冻结 | 历史入口禁用 |
