# SSB Runner：吸收 PR #27（可扩展比赛训练平台）实施计划

> 状态：草案，待评审
> 来源：https://github.com/SSBContestRunner/ssb_runner/pull/27
> 上游 commit：`be026fe`（分支 `feat/contest-training-platform`，作者 BI4APF-AC3QL）
> 调研基线：本地 `main @ 640a24b`（含 PR #28）
> 调研时间：2026-09-30
> 结论：**不整体合并，按模块挑拣吸收**
> 特别约定：**practice seed（练习种子）不做半成品**——阶段 4 仅占位，吸收全部完成后由**阶段 5**完整实现（统一随机源 + 双种子 + Drift 事件日志 + 重放引擎），验收标准见 §3 阶段 5.7

> 实施状态（单工作区落地，2026-09-30）：阶段 1、2、3、4（含 4A–4E）、A（§5 音频方案）、5、6 的代码改动均已落地；
> `flutter analyze` 仅剩 `lib/contest_run/score_manager.dart:7` 的历史 info（CI 以 `--no-fatal-infos` 放行），`flutter test` 全绿。
> 未执行的手工验收：真机听感调参（§5.7 第 5 步）、GUI 冒烟、平台 Debug 构建。
> 本次未按阶段拆分 commit，故不在此记录各阶段 commit hash。

---

## 1. 背景与结论

### 1.1 PR #27 概况

| 项 | 值 |
|---|---|
| 标题 | feat: add extensible contest training platform |
| 状态 | open，`mergeable_state: dirty`（有冲突） |
| base | `main @ e19f10b`（含 #24），落后本地 main 11 个 commit |
| head | `be026fe`，单 commit |
| 规模 | 33 文件，+1589 / −344 |
| 作者自测 | `flutter test` 17/17；Windows Debug 构建 + 启动冒烟 |

**为什么不能整体合并：** PR 的 base 落后于本地 main。main 在此之后新增了日志系统、CI、macOS 支持，并**重写了 `lib/audio/audio_player.dart`**（从直接操作 SoLoud 改为 `AudioEngine` / `AudioSegment` 队列 + 看门狗）。PR 对 `audio_player.dart` 的改动与之冲突，`app_settings.dart`、`options_setting.dart`、`main_settings.dart` 也都被 main 改过。`git diff main..be026fe` 显示 75 文件、−4028 行，其中绝大部分是 main 的领先内容，属于噪音。

### 1.2 吸收原则

1. **优先取纯函数与独立抽象**（零依赖、易测）：`mix_pcm.dart`、`training_profile.dart`、`session_review.dart`、`contest_definition.dart`。
2. **需要重做的只重做接线层**：`AudioPlayer` 的 PCM 注入点、`ContestManager` 的规则实例化。
3. **丢弃格式化噪音**：`exchange_manager.dart`、`score_data.dart`、`prefix_table.dart`、`qso_result_list.dart` 中的缩进改动不吸收。
4. **main 已有的不重复做**；main 仍然欠缺的顺带修掉。
5. 每个阶段独立可测、可单独成 PR。
6. **practice seed 最后做，且必须做完整。** 它与题目生成、交换生成、音标选择、音频效果四处耦合，只有在前述吸收全部落地后才能一次改对。阶段 4 只做占位重命名与注入，**不得**在其中宣称"种子可用"。

### 1.3 明确不吸收的内容

| 项 | 原因 |
|---|---|
| `main_settings.dart` 包 `SingleChildScrollView` | main 已有（`lib/ui/main_settings/main_settings.dart:43`） |
| PR 版 `audio_player.dart` 直接调用 `SoLoud.addAudioDataStream` | main 已重写为 `AudioEngine` 抽象，架构更优 |
| 各文件的纯格式化 diff | 污染 review |
| 上游 `contests.dart` 直接删除 `supportedContests`/`Contest` 类型 | 破坏性重命名，改为派生实现（见 3.2） |
| 上游"`Random(seed)` 即练习种子"的实现 | 不完整：题目还受三处未接种子、且含 `Random(DateTime.now())` 的随机源影响；改为阶段 5 完整实现 |

---

## 2. 现状核对（代码证据）

在本地 main 上逐项核对 PR 各改动的适用性：

| PR 改动 | main 现状 | 处理 |
|---|---|---|
| 规则注册表 `ContestRegistry` | `contest_manager.dart:63` 硬编码 `CqWpxContestType(...)`；`AppSettings.contestId` 已可读任意值，即**设置里换比赛不生效** | 吸收（P0-1） |
| `TrainingDifficulty` / `AudioTrainingEffects` | 不存在 | 吸收（P0-2） |
| Pile-up / S&P 状态机扩展 | `audio_play_type.dart` 无 `PlayPileup`；`WaitingSubmitCall` 无 pileup 字段 | 吸收，纯增量（P0-3） |
| `replaySeed` + 会话历史 + 复盘浮层 | 不存在 | 吸收，但需修正语义（P1-1） |
| 可定制 F1–F8 | `key_event_handler.dart:5` 仍是全局 `functionKeysMap`，`qso_operation_area.dart:366` 也是全局 map | 吸收（P1-2） |
| 窗口可缩放 + `setMinimumSize(1024, 650)` | `main_app.dart:195` 仍是 `setResizable(false)` | 吸收（P2-1） |
| `key_tips.dart` 改主题色 + `Semantics` | main 仍硬编码 `Colors.white`(21) / `Colors.black`(83, 94)，深色主题下不可用 | 吸收（P2-2） |
| `qso_operation_area` dispose 修复 | main **仍有 bug**：`_exchangeEditorController` 在 288、291 行 dispose 两次，`_exchangeFocusNode`(139) 从未 dispose | 吸收（P2-3） |
| `dxcc_loader_test` 合并用例 | main 仍在读 `assets/dxcc/cty.xml` | 吸收（P2-4） |
| `options_setting` 时长校验改 `clamp` | main 用 toastification 弹提示 | 可选（P2-5） |
| README training 段落 + 免责声明 | 不存在 | 吸收（P2-6） |
| 新增 UI 英文文案 | **无需改动**——本仓库 GUI 全部为英文，中文仅出现在代码注释与 docs/（已核实，见 §4.6） | 保持英文，禁止引入中文 UI 文案 |

---

## 3. 分阶段实施计划

### 阶段 1：独立小修（无架构风险，可立即做）

目标：先清掉与 PR 架构无关、且 main 确实存在的缺陷，单独一个 PR。

- [ ] **P2-3 修复 `qso_operation_area` 双重 dispose**
  - 文件：`lib/ui/bottom_panel/qso_operation_area.dart`
  - 把 291 行的 `_exchangeEditorController.dispose()` 改为 `_exchangeFocusNode.dispose()`。
  - 验收：`flutter analyze` 无告警；启动后设置页可正常进出。

- [ ] **P2-4 合并 dxcc 测试用例**
  - 文件：`test/dxcc_loader_test.dart`
  - 删除读取 `assets/dxcc/cty.xml` 的用例，把 `expect(parseDxccXml(xmlString), isNotEmpty)` 并入 gz 用例。
  - 验收：`flutter test test/dxcc_loader_test.dart` 通过。

- [ ] **P2-1 窗口可缩放 + 最小尺寸**
  - 文件：`lib/ui/main_app/main_app.dart:192-196`
  - `setResizable(false)` → `setResizable(true)`，并加 `await windowManager.setMinimumSize(const Size(1024, 650));`
  - 验收：手动拖动窗口，确认最小尺寸生效、布局不破。

- [ ] **P2-2 `key_tips.dart` 主题色 + 无障碍**
  - 文件：`lib/ui/main_page/key_tips.dart`
  - `Colors.white`(21) → `colorScheme.surface`；83、94 行的 `Colors.black` → 继承默认（去掉 color）。
  - 外层加 `Semantics(label: 'Keyboard reference dialog', container: true)`。
  - 验收：深色主题下浮层文字可读。

### 阶段 2：规则注册表（P0-1）

目标：让"设置里选择比赛"真正生效，消除 `contest_manager.dart` 的硬编码。

- [ ] **2.1 新增 `lib/contest_type/contest_definition.dart`**
  - 从 PR `be026fe` 原样移植，含：
    - `abstract class ContestDefinition { id / name / exchangeLabel / scoringNotice / create({stationCallsign, dxccManager}) }`
    - `ContestRegistry.all` + `ContestRegistry.byId(id)`（缺失时回退首项）
    - 5 个模板：`CqWpxDefinition`、`CqWwSsbDefinition`、`ArrlDxDefinition`、`IaruHfDefinition`、`JidxSsbDefinition`
    - 私有基类 `_NumericContestDefinition` / `_NumericContestType` / `_NumericExchangeManager` / `_NumericScoreCalculator`
  - 注意：`ContestType` 接口（`lib/contest_type/contest_type.dart`）与 PR 一致，**无需改动**。
  - 注意：`_NumericScoreCalculator` 的 multiplier key 口径偏松（见 §7 风险），先按 PR 实现，由 §7 的免责声明兜底。

- [ ] **2.2 `contests.dart` 改为派生，保持兼容**
  - 文件：`lib/contest_run/contests.dart`
  - **不采用** PR 的"删除类型 + re-export"方案（会破坏 `app_settings.dart:6`、`main_settings.dart:6` 等引用）。
  - 改为单一数据源派生：
    - `supportedContests` = `ContestRegistry.all` 映射而来；
    - `supportedContestModes` = `TrainingMode.values` 映射而来（阶段 3 落地后）；
    - `Contest` / `ContestMode` 类型保留为兼容视图。
  - 验收：`grep -rn "supportedContests" lib` 的调用点无需改动即可编译。

- [ ] **2.3 `ContestManager` 使用注册表**
  - 文件：`lib/contest_run/new/contest_manager.dart`
  - `startContest()`：`ContestRegistry.byId(settings.contestId).create(stationCallsign:, dxccManager:)`
  - `_createContestRunningManager`：`scoreCalculator: contestType.scoreCalculator`（替换硬编码的 `WpxScoreCalculator`）
  - 删除 `contest_manager.dart:10-11` 的 `cq_wpx.dart` / `cq_wpx_score_calculator.dart` import。
  - 验收：`flutter analyze`；`cq_wpx` 目录仍被注册表引用。

- [ ] **2.4 `ContestSettingCubit` 泛型改为 `ContestDefinition`**
  - 文件：`lib/ui/main_settings/main_settings.dart`
  - `Cubit<Contest>` → `Cubit<ContestDefinition>`；`firstWhere(...)` → `ContestRegistry.byId(...)`；`state.exchange` → `state.exchangeLabel`。
  - 比赛名输入框可改为 `DropdownMenu<String>`（可选，PR 中的做法）。

- [ ] **2.5 新增单测**
  - 文件：`test/contest_definition_test.dart`
  - 断言：5 个 id 齐全、`byId('missing')` 回退 `CQ-WPX`、每个 definition 的 `create()` 返回非空且 `scoreCalculator` 可用。

- [ ] **验收（阶段 2）**：`flutter analyze` 干净；`flutter test` 全绿；手动在设置里切换比赛，确认界面交换格式与计分随之变化。

### 阶段 3：纯函数层（P0-2 / P0-3 地基）

目标：先落不依赖 UI 与运行时的纯逻辑，配套测试。

- [ ] **3.1 `lib/audio/mix_pcm.dart`（新增）**
  - 从 PR 原样移植 `mixPcm16(List<Uint8List>, {offsetSamples = 3600})`。
  - 语义：16-bit 单声道 PCM 叠加并按样本数取均值，避免削波。

- [ ] **3.2 `lib/training/training_profile.dart`（新增）**
  - `enum TrainingMode { run, searchAndPounce, pileup }`（含 id / label / description / `fromId`）
  - `enum TrainingDifficulty`：beginner(1.0, 0, 0, 0) / standard(1.08, 0.10, 0.05, 1) / advanced(1.18, 0.22, 0.16, 2)
  - `AudioTrainingProfile.fromDifficulty({difficulty, volume, seed})`
  - `AudioTrainingEffects.apply(pcm, profile)` + `_resample`
  - **保留注释**：输入/输出为 24 kHz 单声道 16-bit LE，与项目一致。

- [ ] **3.3 `lib/training/session_review.dart`（新增）**
  - `TrainingRunMetadata`、`TrainingRunReview`（`accuracy` / `duration` / `qsosPerHour` / `fromQsos` / `toJson` / `encode` / `decode`）。
  - 本阶段**只移植占位形态**：一个 `seed` 字段 + `encode/decode`。
  - 后续在**阶段 5**把种子扩展为 `questionSeed` / `audioSeed` 双种子，并补齐真正的确定性出题与历史重放（**阶段 5 不得省略**）。
  - 命名统一为 "Practice seed"，**禁止出现 "Replay seed"**。

- [ ] **3.4 新增单测 `test/training_platform_test.dart`**
  - 直接移植 PR 版（纯 Dart，无 Flutter 绑定）：
    - 注册表模板齐全
    - `mixPcm16([pcm, pcm]).length > pcm.length`
    - `AudioTrainingEffects.apply` 二次调用结果相同（确定性），advanced 变短（重采样）
    - `TrainingRunReview.fromQsos` 的 accuracy / 错误分类 / `decode(encode()) == 原值`
  - 补充 `mixPcm16` 边界：空列表返回空、单元素原样返回。

- [ ] **验收（阶段 3）**：`flutter test` 全绿，`flutter analyze` 干净（含新文件）。

### 阶段 4：运行时接线（P0-2 / P0-3 / P1-1 / P1-2）

#### 4A 音频训练效果（重新设计接入点，不照抄 PR）

- [ ] **4A.1 `AudioPlayer` 增加可选训练画像**
  - 文件：`lib/audio/audio_player.dart`
  - 新增 `AudioTrainingProfile? _trainingProfile` 与 `setTrainingProfile(profile)`。
  - 在 `addAudioData`（`audio_player.dart:59`）中：仅当 `!isMyAudio && profile != null` 时对 `pcmData` 执行 `AudioTrainingEffects.apply` 后再入队。
  - `startPlay()` / `stopPlay()` / `resetStream()` 时是否清空 profile：由 `ContestManager` 统一负责，避免"停止后仍变速"。
  - **注意**：`_defaultEstimateDuration`（`audio_player.dart:191`）按固定 24 kHz 估算，变速后看门狗余量偏保守，可接受；如出现误判再按 profile 修正。

- [ ] **4A.2 `ContestManager` 下发画像**
  - 在 `startContest()` 里：
    - `final profile = AudioTrainingProfile.fromDifficulty(difficulty:, volume: settings.audioVolume, seed: seed);`
    - `_audioPlayer.setTrainingProfile(profile);`
  - 在 `stopContest()` 里清理。

- [ ] **4A.3 `AppSettings` 新设置项**
  - `difficulty`（`_settingDifficulty`）
  - `audioVolume`（`_settingAudioVolume`，`clamp(0.2, 1.2)`）
  - `replaySeed` → 重命名为 `practiceSeed`（`_settingPracticeSeed`），保留 `int?` 语义
  - **注意**：此处仅做占位重命名与读写；双种子拆分、持久化与重放一律在**阶段 5**完成，阶段 4 不要提前引入 `Random(seed)` 之外的耦合
  - 常量命名沿用现有 `_settingXxx` 前缀约定。

#### 4B Pile-up / S&P

- [ ] **4B.1 `ContestAnswerGenerator` 支持种子与堆叠**
  - 文件：`lib/contest_run/new/contest_answer_generator.dart`
  - 构造参数新增 `mode` / `difficulty` / `seed`，内部 `Random(seed)`（替换 `Random()`）。
  - **临时形态**：阶段 5 会把此处的 `Random(seed)` 替换为 `SessionRandom`，并让交换/音标也走同一随机源。阶段 4 允许先这样接，但不得在其上继续加新的 `Random()`。
  - `pileupCount = mode == pileup ? max(2, difficulty.pileupCallers + 1) : 1`，去重挑选候选呼号。
  - `ContestAnswer` 增加 `pileupCallsigns` 与 `mode`，加 `isSearchAndPounce` getter。

- [ ] **4B.2 状态机扩展（纯增量）**
  - `lib/contest_run/state_machine/single_call/audio_play_type.dart`：新增 `PlayPileup({calls})`、`PlaySearchAndPounce({call})`。
  - `single_call_run_state.dart`：`WaitingSubmitCall` 增加 `pileupCallsigns` / `isSearchAndPounce`，在构造函数中原样选取 `audioPlayType`（多人 → `PlayPileup`，S&P → `PlaySearchAndPounce`，否则 `PlayCall`），并同步 `copyWith`。
  - `single_call_run_event.dart`：`NextCall` / `NoCopy` / `WorkedBefore` 增加同名字段（默认空/false）。
  - `single_call_run_state_machine.dart`：对应 `WaitingSubmitCall(...)` 传入新字段；WorkedBefore 分支改用 `stateVal.copyWith(...)` 以保留 `audioPlayType`。

- [ ] **4B.3 `ContestStateChangeHandler` 播放分支**
  - 文件：`lib/contest_run/new/contest_state_change_handler.dart`
  - 在 `_playAudioByPlayType` 的 switch 中新增 `PlayPileup()` / `PlaySearchAndPounce()` 两个 case。
  - `PlayPileup`：`Future.wait` 加载各呼号音频 → `mixPcm16` → `_audioPlayer.addAudioData(mixed, isResetCurrentStream:, isMyAudio: false)`。
  - `PlaySearchAndPounce`：加载 `CQ.wav` + 对方呼号 → `concatUint8List` → 入队。
  - **核对**：`_audioLoader.loadAudio` / `concatUint8List` / `obtainAssetDir` 的现有签名（见 `contest_state_change_handler.dart:174-260`），保持与 `PlayCall` 分支一致。

- [ ] **4B.4 调用链透传**
  - `contest_running_manager.dart`：`ContestAnswerGenerator` 注入 `mode/difficulty/seed`；`WaitingSubmitCall` 构造传入 `pileupCallsigns` / `isSearchAndPounce`。
  - `contest_manager.dart`：`startContest()` 读取 `TrainingMode.fromId(settings.contestModeId)` 与 `settings.difficulty`，生成 seed，透传给 `ContestRunningManager`。

#### 4C 会话复盘（P1-1）

- [ ] **4C.1 `ContestManager` 复盘流**
  - 新增 `Stream<TrainingRunReview> reviewStream`、`_saveReview()`、`recentCurrentRunQsoTimes({limit = 6})`。
  - `stopContest()` 加早退保护（`if (!_isContestRunning) return;`），避免重复保存。
  - 复盘分数取自 `_activeContestType.scoreCalculator.calculateScore(qsos)`。

- [ ] **4C.2 `AppSettings` 会话历史**
  - `sessionHistory` getter / `saveSessionReview(review)`（保留最近 30 条，`_settingSessionHistory`）。

- [ ] **4C.3 `TrainingReviewOverlay`（新增）**
  - 文件：`lib/ui/main_page/training_review_overlay.dart`
  - 监听 `ContestManager.reviewStream`，展示 QSO 数 / 准确率 / 速率 / 分数 / 错误分类 / 练习种子。
  - 挂载点：`lib/ui/main_page/main_page.dart` 的 `Stack`（当前第 23 行的 children 列表）。
  - 文案沿用英文（`Session review` 等），无需翻译（见 §4.6）。

#### 4D 可定制 F1–F8（P1-2）

- [ ] **4D.1 `KeyEventHandler` 支持注入**
  - 文件：`lib/contest_run/key_event_handler.dart`
  - `functionKeysMap` → `defaultFunctionKeysMap`；构造增加 `KeyEventHandler({Map<LogicalKeyboardKey, OperationEvent>? functionKeys})`。
  - 替换内部 3 处（44、82、89 行）对全局 map 的引用。
  - 新增 `functionKeysFromSettings(AppSettings)` + `OperationAction` 映射。

- [ ] **4D.2 `OperationAction` 与 `AppSettings.binding`**
  - `enum OperationAction { cq, exchange, tu, myCall, hisCall, before, again, noCopy }`（含 id / label / defaultKey）。
  - `AppSettings.binding(action)` / `setBinding(action, key)`，key 前缀 `_settingKeyBindingPrefix`。

- [ ] **4D.3 UI 接线**
  - `contest_running_manager.dart`：`_keyEventManager` 改为 `late final` 并用 `functionKeysFromSettings(_contestDataManager.appSettings)` 构造。
  - `qso_operation_area.dart:366`：`_FunctionKeys` 改读 `functionKeysFromSettings(context.read<AppSettings>())`。
  - `options_setting.dart`：新增"自定义功能键"对话框（含"每个命令必须不同键"校验）。

- [ ] **4D.4 验收**：改键后，键盘按键、底部功能键盘按钮、KeyTips 三者一致。

#### 4E 设置页整体改造（合并 4A/4D）

- [ ] `options_setting.dart`：模式下拉（Run / S&P / Pile-up）、难度下拉、接收音量滑条、功能键对话框、会话历史入口。
- [ ] `options_setting.dart` 时长输入改为 `FilteringTextInputFormatter.digitsOnly` + `clamp(0, maxDurationInMinutesPerRun)`。
  - **取舍**：会丢失原来的 toast 提示；若要保留提示，则在 `clamp` 触发时补一个 SnackBar。
- [ ] 所有新增控件补 `Semantics`（label / value），并在比赛运行中 `enabled: false`。
- [ ] UI 文案一律使用英文，与本仓库既有 GUI 一致（见 §4.6）；不要引入中文 UI 字符串。

### 阶段 5：practice seed 完整实现（**吸收完成后必做，不可省略**；内部编号 5.x 均指本阶段）

> 定位说明：阶段 3.3 中移植的 `session_review.dart` 只带一个 `seed` 字段（占位）；阶段 4A/4B 只把该 seed 接给 `Random(seed)`。**这属于半成品，本阶段负责把它做成真正可用、可复现、可重放的练习种子能力。**
>
> 明确不作为：不做加密安全随机、不做云端同步。目标只有两个——**同一种子 → 完全相同的题目序列**；**任一历史会话可被完整重放**。

#### 5.1 为什么上游那版不能算实现（现状核查）

上游只是把 `Random(seed)` 用在 `ContestAnswerGenerator` 里，但题目实际由**多个互不知情的随机源**共同决定，且这些源全部没有接种子。全仓库审计结果：

| 随机源 | 位置 | 当前状态 | 影响 |
|---|---|---|---|
| 呼号选择 + pile-up 候选 | `contest_answer_generator.dart:12` | `final random = Random();`（**函数内新建**，连 PR 的 seed 也没接上） | 每次调用都不可复现 |
| 交换序号生成 | `lib/contest_type/cq_wpx/cq_wpx.dart:35` | `final _random = Random();` | 交换值不可复现；JIDX/IARU 等模板同样 |
| 音标类型（mixed 模式） | `lib/audio/audio_loader.dart:164` | `Random(DateTime.now().millisecondsSinceEpoch)` | **绝对不可复现**，且每次取字符都新建 |
| 运行 ID | `contest_run/new/contest_manager.dart:55` | `Uuid().v4()` | 仅作 DB 主键，不影响内容——**保留**，但需与种子解耦 |
| 音效噪声/QSB | 阶段 3.2 新增 | 用同一个 seed | 与题目共用一个种子，耦合过强 |

由此得出三个必须解决的问题：

1. **单一种子无法覆盖全部随机源** → 即使接上 seed，交换值和音标仍随机；
2. **共享单个 `Random` 实例的序列耦合** → 任何一处多抽/少抽一个数，后续题目全部错位（Dart 的 `Random(seed)` 是序列相关的）；
3. **没有记录，就没有重放** → 上游 `TrainingRunReview` 只存汇总（qsoCount/score/seed），没有单题序列，无法重放，也无法自证"同种子同序列"。

#### 5.2 统一随机源（消除序列耦合）

新增 `lib/training/session_random.dart`：

~~~dart
/// 会话内的唯一随机源。按域把种子派生出相互独立的子流，
/// 因此题目域多抽/少抽一个数，不会影响音频域或音标域。
class SessionRandom {
  SessionRandom._(this._callsign, this._exchange, this._phonic, this._audio, this.seed);

  factory SessionRandom(int seed) => SessionRandom._(
    Random(_derive(seed, 'callsign')),
    Random(_derive(seed, 'exchange')),
    Random(_derive(seed, 'phonic')),
    Random(_derive(seed, 'audio')),
    seed,
  );

  final Random _callsign;
  final Random _exchange;
  final Random _phonic;
  final Random _audio;
  final int seed;

  int nextCallsignIndex(int length) => _callsign.nextInt(length);
  int nextExchange(int max) => _exchange.nextInt(max) + 1;
  int nextPhonicType(int max) => _phonic.nextInt(max);
  double nextAudioUnit() => _audio.nextDouble();

  static int _derive(int seed, String tag) => Object.hash(seed, tag).abs();
}
~~~

**接入点（必须全部改造，否则不算完成）：**

- [ ] `ContestAnswerGenerator`：删除内部 `Random()`，改注入 `SessionRandom`，呼号与 pile-up 候选都走 `nextCallsignIndex`；
- [ ] `ExchangeManager` 接口增加 `int get maxExchange` 或改签名，让 `generateExchange` 从 `SessionRandom.nextExchange` 取值；`_CqWpxExchangeManager`（`cq_wpx.dart:35`）与阶段 2 的 `_NumericExchangeManager` 都要改；
- [ ] `AudioLoader._obtainRandomPhonicType`（`audio_loader.dart:162-176`）：删除 `Random(DateTime.now()...)`，改为注入 `SessionRandom`，走 `nextPhonicType`；
- [ ] 音效噪声改走 `nextAudioUnit`（不再自己 `Random(seed ^ length)`）；
- [ ] 单元测试：同一 seed 构造两个 `SessionRandom`，连续抽取 100 次结果逐项相同；不同 seed 不同；**题目域抽取次数变化不影响音频域输出**（验证子流隔离）。

#### 5.3 种子模型：一局一个 + 双种子分离

- **一局一个**：`ContestManager.startContest()` 是唯一创建种子的地方，整局只创建一次并下发，禁止任何模块自行 `Random(seed)`。
- **双种子分离**：
  - `questionSeed`：决定题目序列（呼号、交换、pile-up 候选、音标）；
  - `audioSeed`：决定音效（噪声、QSB 相位、底床噪声生成）。
  - 理由：可以"同题不同噪"地练听力，也可以单独复现音频环境；避免改音效就破坏题目复现。
  - 默认：`audioSeed = questionSeed`，允许用户单独固定其一。
- **种子来源优先级**：显式设置 > 上次会话继承（重放）> `DateTime.now().microsecondsSinceEpoch & 0x7fffffff`。
- `Uuid().v4()` 继续生成 `runId`，仅作数据库标识，不进随机源。

#### 5.4 记录与持久化（没有记录就没有重放）

**必须从用户可见的设置项升级为可持久化数据。** 上游把 `TrainingRunReview` 以 JSON 塞进 `SharedPreferences` 列表（`AppSettings.sessionHistory`），存在三个硬伤：

1. 只有汇总，没有单题序列 → 无法重放；
2. 体积随会话增长，`SharedPreferences` 不适合；
3. 与 `QsoTable` 通过 `runId` 关联，但 JSON 里没有可靠的运行生命周期记录。

改为**读取已有 Drift 数据库**（QSO 记录本来就在 `AppDatabase.qsoTable` 里，与 review 依赖同一层 `drift`，无需引入新依赖）。

**新增表（`lib/db/table/event_log_table.dart`，并在 `app_database.dart:11` 的 `tables:` 注册）：**

~~~dart
class EventLogTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get runId => text()();
  IntColumn get elapsedMs => integer()();
  TextColumn get eventType => text()();   // answer / submit / nocopy / worked-before
  TextColumn get payload => text()();      // JSON: callsign / exchange / pileupCallsigns / mode
  IntColumn get createdAtUtc => integer()();
}
~~~

**数据模型（`lib/training/session_review.dart`）：**

~~~dart
class TrainingRunEvent {
  final int elapsedMs;
  final String type;
  final String callsign;
  final String exchange;
  final List<String> pileupCallsigns;
  final String modeId;
}

class TrainingRunLog {
  final TrainingRunMetadata metadata;
  final List<TrainingRunEvent> events;
  final TrainingRunReview review;
}
~~~

`TrainingRunMetadata` 增加：`questionSeed`、`audioSeed`、`appVersion`。

- [ ] `QsoTable` 只增不改（只加索引或元数据列，不动既有记录）；
- [ ] 保留 `AppSettings` 里最近若干条 review 摘要用于设置页快速展示，但**完整日志与 replay 数据一律进 Drift**；
- [ ] `TrainingRunReview.decode` 需对旧 JSON 做向后兼容（缺 `questionSeed` / `audioSeed` 时回退到旧 `seed`）。

#### 5.5 重放引擎

**重放数据源与被复现数据，以"记录的真实答案"为准，而不以"重新计算"为准。**

理由有两点：

1. 题目"消耗"与操作员行为耦合——`NoCopy` / `WorkedBefore` 会触发重新出题，"第 N 题"并非纯函数；
2. 生成算法未来可能调整，而历史日志必须永久可重放。

因此策略是**两级**：**记录优先，种子兜底**。

- [ ] 正常一局：`ContestRunningManager._setupStateMachine()` 每次生成 `ContestAnswer` 时，同步把事件写入 `ContestManager` 的日志队列（`elapsedMs` 取 `contestTimer` 已用时）；
- [ ] 重放一局：新增 `ReplayAnswerSource`（实现与 `ContestAnswerGenerator` 相同的取题接口），按记录顺序出题；题库不参与；
- [ ] 回退路径：若日志缺失，则用 `questionSeed` 重新计算，并给出提示；
- [ ] 结束一局时把事件批量落库（一次事务，避免逐题 IO）。

**重放的确定性边界（必须写进文档与测试）：**

- 完全可复现：题目序列、交换值、pile-up 候选、音效参数；
- 不可复现（受真实时间与人类输入影响，不纳入保证）：QSO 间隔与速率、操作员输入时序。

#### 5.6 UI 与设置（用户可见入口）

- [ ] 设置页新增 **Practice seed** 分组：显示当前种子、复制、粘贴自定义种子；
- [ ] 分开固定：`Lock question seed` / `Lock audio seed` 两个开关；
- [ ] 复盘浮层（`training_review_overlay.dart`）加 **Replay this session** 按钮，一键用该局种子重开；
- [ ] 若实现成本高，可先用最简形态：模态框展示 `questionSeed` + 复制按钮 + "Replay" 按钮；
- [ ] 文案统一为 `Practice seed`，**禁止再出现 `Replay seed`**（见 §4.6 第 5 条）。

#### 5.7 验收标准（本阶段的完成定义）

1. 同一 `questionSeed` 跑两次，**题目序列逐题相同**（呼号、交换、pile-up 候选、音标）；
2. 同一 `audioSeed` 跑两次，音效参数与底床噪声输出逐字节相同；
3. 修改 `audioSeed` 不影响题目序列；修改 `questionSeed` 不影响音频输出（子流隔离）；
4. 任一历史会话可被完整重放，且重放中不重新计算题目；
5. 旧版本（无种子字段）的历史记录可正常读取，不崩溃；
6. 自动化测试覆盖：子流隔离、跨会话复现、重放一致性、旧 JSON 兼容；
7. 文档说明重放的确定性与**不确定**边界（见 §3 阶段 5.5）。

### 阶段 6：文档与收尾

- [ ] **6.1 README**
  - 增加 "Training capabilities" 段落（规则模板、三种模式、难度档位、复盘指标、可定制 F1–F8）。
  - **必须保留免责声明**：这些模板是**单波段训练档案**，不是 Cabrillo 认证计分；正式多波段计分还需 event category / band / date / 当期规则版本。

- [ ] **6.2 本文件更新**：各阶段完成后勾选，并记录实际 commit。

- [ ] **6.3 全量验收**
  - `flutter analyze` 干净
  - `flutter test` 全绿（含新增测试）
  - 手动冒烟：设置比赛/模式/难度/音量 → 开始 → Run / S&P / Pile-up 各跑一轮 → 结束看复盘 → 改键后确认生效
  - 种子冒烟：固定 Practice seed 连跑两局，确认题目序列一致（阶段 5.7）
  - 至少一个平台 Debug 构建（Windows 或 macOS）启动通过

---

## 4. 能力边界厘清：底噪 / 衰落 / Pile-up

上游 PR 的标题描述（"noise, and fading"、"Pile-up exercises"）容易高估其实际能力。以下按代码逐项核实。

### 4.1 能力矩阵

| 能力 | 上游是否真的做了 | 代码依据 | 缺口 |
|---|---|---|---|
| 白噪声（信号内） | 是 | `AudioTrainingEffects.apply` 对每个采样加 `(rand*2-1)*32767*noiseAmount` | 噪声只覆盖 clip 自身时长 |
| **接收机底噪（静默期持续）** | **否** | 噪声在 `apply()` 内按 clip 循环生成；`AudioPlayer` 停止发声时无任何输出源 | 真实台在两次发射之间仍有持续嘶嘶声，这是训练"弱信号抄收"的核心 |
| 衰落（QSB） | 是（简化版） | `fade = 1 - fadingAmount*(0.5+0.5*sin(second*pi*2))`，即 1 Hz 正弦包络 | 相位每次从 0 重算，clip 之间不连续；无多径/快衰落 |
| 变速 | 是 | `_resample` 按 `playbackRate` 线性丢样 | 无抗混叠滤波；时长变化未反映到看门狗 |
| 音量 | 是 | `adjusted * profile.volume` | 仅作用于 clip |
| Pile-up 多台并发 | 是（裸混音） | `PlayPileup` → `mixPcm16(clips)` | 见 4.3，目标台被大幅衰减 |
| S&P 模式 | 是 | `PlaySearchAndPounce` → 拼接 `CQ.wav` + 对方呼号 | 无"逐个频点搜索"的节奏 |
| Run 模式 | 是 | 默认模式 | — |

### 4.2 底噪：上游做的是"信号上叠噪声"，不是"底噪"

上游 `apply()` 的核心循环（`lib/training/training_profile.dart`）：

~~~dart
for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
  final sample = data.getInt16(offset, Endian.little);
  final second = (offset / 2) / sampleRate;
  final fade = 1 - profile.fadingAmount * (0.5 + 0.5 * sin(second * pi * 2));
  final noise = (random.nextDouble() * 2 - 1) * 32767 * profile.noiseAmount;
  final adjusted = (sample * fade + noise) * profile.volume;
  data.setInt16(offset, adjusted.clamp(-32768, 32767).round(), Endian.little);
}
~~~

由此可确定三个结论：

1. **噪声的生存期 = clip 的时长。** 一次呼号音频约 0.4 s，噪声就只存在 0.4 s；clip 播完，输出立刻静音。
2. **静默期完全没有噪声。** 两次发射之间的间隔是"数字静音"，而真实电台是持续底噪 + 信号浮于其上。
3. **难度档位并未控制"有无底噪"**，只是控制噪声幅度：`beginner noiseAmount=0.0`、`standard=0.10`、`advanced=0.22`。用户感受不到"本底噪声"，只能感到"每个音都糊"。

**真正需要的是第二条独立音源**：一条循环播放的噪声底床（noise bed），在整局训练期间常驻，音量由难度决定，信号 clip 叠加在其上。这正是当前 main 的 `AudioEngine` 抽象可以优雅接纳的改动——底床位于 segment 队列**之外**，不参与队列时序。

### 4.3 Pile-up：结构对了，混音有缺陷

上游结构是合理的：

- `ContestAnswerGenerator`：`pileupCount = mode == pileup ? max(2, difficulty.pileupCallers + 1) : 1`，候选呼号去重挑选；
- `WaitingSubmitCall.audioPlayType`：`pileupCallsigns.length > 1` → `PlayPileup(calls)`；
- `ContestStateChangeHandler`：`Future.wait` 加载各台音频 → `mixPcm16` → **作为单个 segment 入队**。

最后一点很关键：当前 main 的 `AudioPlayer` 是**串行单段队列**（一次只有一个 voice），所以"多台重叠"只能靠预混音实现，不能靠多路 voice。上游选对了。

但混音实现有两个缺陷：

~~~dart
output[offset + sample] += source.getInt16(sample * 2, Endian.little);
...
data.setInt16(sample * 2, (output[sample] ~/ clips.length).clamp(-32768, 32767).toInt(), ...);
~~~

1. **目标台被衰减 `1/N`。** 3 台叠加后整体除以 3，**目标台的音量也被压低约 9.5 dB**。而训练目的是"从干扰中抄出目标台"，目标台反而变成最弱的那个。应改为**目标台保持 1.0 增益，仅对干扰台加权**（例如干扰 ×0.5），再做软限幅。
2. **`~/ clips.length` 在叠加峰值超过 32767 时会先截断再取整**，产生硬削波失真（`~/ ` 作用于已溢出的 int 累加值）。应改为浮点累加 + `tanh` 软限幅。

另外：`offsetSamples = 3600`（24 kHz 下 = 150 ms），而 US 呼号单字母约 0.375 s，因此 3 台几乎完全重叠——可听性偏难，建议把偏移做成难度参数（150 ms → 300 ms）。

---

### 4.4 上游的 UI 修改清单

对 PR 全部 33 个文件做逐行扫描后的结论：**UI 改动集中在 9 个文件**（`lib/ui/` 下 9 个 + `lib/settings/app_settings.dart` 提供状态），其中 `lib/ui/main_page/training_review_overlay.dart` 为新增文件。按性质归类如下。

#### (1) 新增 UI 能力

| 变更 | 文件 | 说明 |
|---|---|---|
| 赛后训练复盘浮层 | `lib/ui/main_page/training_review_overlay.dart`（**新增 115 行**） | 监听 `ContestManager.reviewStream`，以半透明遮罩 + 卡片展示 QSO 数 / Accuracy / Rate / Score / Call errors / Exchange errors，并显示 seed；外层 `Semantics(label: 'Training review', liveRegion: true)` |
| 功能键自定义对话框 | `options_setting.dart`（`_KeyBindingsDialog`） | 8 个 `DropdownButtonFormField`，每项 F1–F8；**含重复键校验**（"Each command needs a different function key."）后才写回设置 |
| 会话历史对话框 | `options_setting.dart`（`_SessionHistoryDialog`） | 展示 `AppSettings.sessionHistory`（保留最近 30 条） |
| 训练模式 / 难度下拉 | `options_setting.dart` | `DropdownMenu<TrainingMode>`、`DropdownMenu<TrainingDifficulty>` |
| 接收音量滑条 | `options_setting.dart` | `Slider` 0.2–1.2，10 档，`Semantics(value: 'N percent')` |
| "清除练习种子"按钮 | `options_setting.dart` | 条件渲染（仅 seed 非空时），清空后 SnackBar 提示 |

#### (2) 结构性重构

| 变更 | 文件 | 说明 |
|---|---|---|
| `OptionsSetting` 由 `StatefulWidget` → `StatelessWidget` | `options_setting.dart` | 原先靠 `TextEditingController` + `_updateState()` 手动同步输入框，改为 `_OptionsCubit` 单一状态源 + `_Options` 不可变模型（去掉 `copyWith`）。这是本 PR 最有价值的 UI 重构 |
| 时长输入校验方式改变 | `options_setting.dart` | 由"超限时弹 toastification 警告"改为 `FilteringTextInputFormatter.digitsOnly` + `clamp(0, maxDuration)`。**副作用：原有的超限提示消失** |
| 比赛选择由只读 `TextField` → `DropdownMenu<String>` | `main_settings.dart` | 配合注册表，实现多比赛切换 |
| `Cubit<Contest>` → `Cubit<ContestDefinition>` | `main_settings.dart` | `state.exchange` → `state.exchangeLabel` |
| 设置面板可滚动 | `main_settings.dart` | **main 已自行实现**（`main_settings.dart:43`，含解释性注释），此条无需吸收；main 还额外多了 Diagnostics 分区 |

#### (3) 交互与可用性修复

| 变更 | 文件 | 说明 |
|---|---|---|
| **窗口可缩放 + 最小尺寸 1024×650** | `main_app.dart` | `setResizable(false)` → `true`，并加 `setMinimumSize(Size(1024, 650))`。当前 main 仍锁死不可缩放（`main_app.dart:195`） |
| **修复 dispose 缺陷** | `qso_operation_area.dart` | 原代码 `_exchangeEditorController.dispose()` 被调用两次、`_exchangeFocusNode` 从未释放；改为释放 `_exchangeFocusNode`。main 仍存在该缺陷（`qso_operation_area.dart:288/291`） |
| 功能键按钮改为从设置读取 | `qso_operation_area.dart` | 全局常量 `functionKeysMap` → `functionKeysFromSettings(context.read<AppSettings>())`，使改键即时生效 |
| 信息按钮加 `Tooltip('Keyboard reference')`；功能键按钮加 `Tooltip('Send <key> <cmd>')` | `qso_operation_area.dart` | main 中 `lib/ui` 下**零 `Tooltip` 使用** |
| 主题色替换硬编码颜色 | `key_tips.dart` | 卡片 `Colors.white` → `colorScheme.surface`；`'+'` 与描述文字去掉 `Colors.black`。**main 仍是硬编码黑白**（`key_tips.dart:21/83/94`），深色主题下不可读 |
| `KeyTips` 外层加 `Semantics(label: 'Keyboard reference dialog')` | `key_tips.dart` | — |
| 速率显示改为滚动 5-QSO 速率 | `qso_speed_area.dart` | 原先把整局累计 QSO 数除以已用时长，开局阶段数值严重偏低；改为最近 6 个时间戳计算滚动速率，并在无 QSO 时显示 `--- QSOs/h`。配套 `ContestManager.recentCurrentRunQsoTimes()` |

#### (4) 无障碍（Accessibility）

上游是**一次性成体系地加 `Semantics`**，而当前 main 的 `lib/ui` 目录下 `Semantics(`、`Tooltip(`、`showDialog(` **全部为零**（已 grep 核实）：

| 位置 | Semantics |
|---|---|
| KeyTips 浮层 | `label: 'Keyboard reference dialog', container: true` |
| TrainingReviewOverlay | `label: 'Training review', liveRegion: true` |
| 比赛时长输入 | `label: 'Practice duration in minutes'` |
| 接收音量滑条 | `label: 'Incoming station audio volume', value: 'N percent'` |
| 各下拉菜单 | `label: <字段名>` |
| QSO 结果单元格 | `label: isCorrect ? data : '<data>, incorrect'` |

> 注：设置面板滚动在 main #28 中已独立实现；其余无障碍标注均未实现。

#### (5) 明确不属于 UI 改动的文件

PR 全部 33 个文件中，23 个非 UI 文件为音频、状态机、规则、设置模型、测试与格式化噪音（其中 `lib/` 下 20 个，另有 `test/training_platform_test.dart`、`test/dxcc_loader_test.dart`、`README.md`）。另需注意：**上游 PR 分支不含 `lib/ui/main_settings/diagnostics_setting.dart`**——该文件是本仓库 #28 新增的诊断面板，与 PR 无关，吸收时不要混淆。

### 4.5 结论：UI 层面值得吸收的内容排序

1. **必修（真实缺陷）**：`qso_operation_area` 双重 dispose、`key_tips` 硬编码黑白、窗口不可缩放。
2. **高价值重构**：`OptionsSetting` 的 Stateful → Stateless + Cubit 单一状态源（顺带把新增的难度/音量/模式控件挂上去）。
3. **高价值新增**：训练复盘浮层、功能键自定义对话框。
4. **中等价值**：`Semantics` 体系化补全、`Tooltip`、滚动 QSO 速率。
5. **需权衡**：时长超限提示被 `clamp` 取代——建议保留提示（clamp 触发时补 SnackBar）。

### 4.6 语言约定（重要纠正）

**经全仓库核实：本项目的 GUI 文案全部是英文，中文只出现在代码注释与 `docs/`。**

核实方式与结果：

- 对 `lib/**/*.dart` 全量扫描 CJK 字符，命中 23 行，**全部是注释**：
  - `lib/common/calculate_list_diff.dart:1-3`（算法说明）
  - `lib/audio/audio_loader.dart:7-49`（区域实体代码注释）
  - `lib/audio/wav_to_pcm.dart:11-49`（WAV 解析注释）
- 对 `lib/ui/` 全量提取字符串字面量，**无一条含中文**；实际文案为 `Contest` / `Options` / `Duration` / `Phonic Type` / `STOP` / `RUN` / `Callsign` / `Export logs` / `Copy diagnostics` / `Please set station callsign` 等——**包括错误提示与菜单项在内的全部用户可见文本都是英文**。
- `README.md` 无中文。
- `docs/` 下属文件为中文（`logging_system_design.md`、`logging-libraries.md`、`cicd-cross-platform.md`、`ssb_contest_runner_first_edition.md`，以及本文件）。

**因此：**

1. 上游 PR 新增的英文 UI 文案（`Session review`、`Training mode`、`Difficulty`、`Customize function keys` 等）**是正确且符合本仓库约定的**，不是缺陷；
2. 本计划早期草案中"上游英文文案与中文语境不一致、需要本地化"的判断**是错的**，已更正（见 §7 风险 5）；
3. 落地时新增 UI 文案应**一律使用英文**，并保持既有术语（`Duration`、`Phonic Type`、`Callsign`…）；
4. 代码注释可以继续使用中文，与现有风格一致；
5. 唯一需要改名的用户可见文案是上游的 `Replay seed` → `Practice seed`（完整实现见 §3 阶段 5）。

---

## 5. 技术方案（基于当前最新音频架构）

设计约束（来自当前 main 实现）：

- `AudioPlayer`（`lib/audio/audio_player.dart`）是**串行单段队列**，`addAudioData(pcm, {isResetCurrentStream, isMyAudio})` 入队，`_pump()` 一次只播一段；
- 播放完成由 `AudioSegment.finished` 驱动，另有看门狗 `_estimateDuration(pcm.lengthInBytes) + 3s`；
- 时长估算 `_defaultEstimateDuration` 固定按 24000 采样率、16-bit 单声道换算（`audio_player.dart:191`）；
- 引擎能力由 `AudioEngine` / `AudioSegment` 接口（`lib/audio/audio_engine.dart`）抽象，`SoLoudAudioEngine` 负责 `BufferingType.released` 的一次性 buffer stream；
- 所有语音资源为 **24 kHz / 16-bit / 单声道 WAV**（已核实 `CQ.wav`、`US/ICAO/A.wav`、`JP/Common/ROGER_YOU_ARE_59.wav`），经 `wav_to_pcm.dart` 去头后进队列；
- `assets/voice` 下**没有噪声素材**（仅 `Global/Common/CQ.wav`），且 voice 资源是 submodule。

### 5.1 分层设计

~~~
┌─────────────────────────────────────────────────────────────┐
│ 训练会话层  TrainingSessionProfile                            │
│   difficulty / qsbRate / noiseLevel / pileupCount / seed     │
└───────────────┬─────────────────────────────┬───────────────┘
                │ 每会话一次                    │ 每会话一次
                ▼                              ▼
┌───────────────────────────┐   ┌──────────────────────────────┐
│ 底噪层  NoiseBed           │   │ 信号层  AudioEffects          │
│  常驻循环音源，独立于队列    │   │  对每个 clip 施加：           │
│  start/stop/setLevel       │   │   resample / QSB / 音量      │
└───────────┬───────────────┘   └──────────────┬───────────────┘
            │                                   │
            ▼                                   ▼
┌─────────────────────────────────────────────────────────────┐
│ AudioEngine（现有抽象）                                       │
│  + startNoiseBed(pcm, {looping, volume}) / setNoiseBedVolume │
│  + stopNoiseBed()                                            │
│  （底床不进入 segment 队列，不影响时序与看门狗）                │
└─────────────────────────────────────────────────────────────┘
~~~

关键决策：**底噪不进 segment 队列，信号才进队列。** 理由是队列是串行且以"段结束"驱动状态机；如果底噪也进队列，会导致静默期被当成"正在播放入站音频"，`isPlaying()` / 看门狗 / 状态机时序全部失真。

### 5.2 底噪层实现

**素材来源（三选一，推荐 A）：**

- **A. 程序化生成（推荐，零素材依赖）**：用固定种子 PRNG 生成 2 s 带限噪声（简单一阶低通滤白噪声，模拟接收机音频通带 300–3000 Hz 的"沙沙"感），得到 96000 采样的 PCM，循环播放。优点：不动 submodule、时长可控、种子可复现。
- B. 新增 `assets/voice/Global/Common/NOISE.wav` 静态文件。缺点：要改 submodule 与资源清单。
- C. 白噪声实时流。缺点：需要持续喂 buffer，复杂度高，收益低。

**引擎接口扩展（`lib/audio/audio_engine.dart`）：**

~~~dart
abstract interface class AudioEngine {
  bool get isInitialized;
  AudioSegment? createSegment(Uint8List pcm);

  // 新增：常驻循环底床
  Future<void> startNoiseBed(Uint8List pcm, {double volume = 0.0});
  void setNoiseBedVolume(double volume);
  Future<void> stopNoiseBed();
}
~~~

`SoLoudAudioEngine` 里用一个 `BufferingType.released` 的 loop source 实现（`setDataIsEnded` + looping），与 segment 用同一个 `SoLoud` 实例但**独立的 `AudioSource` 与 `SoundHandle`**，因此不受 `_reset()` 影响。

**接线点：** `AudioPlayer.startPlay()` → `startNoiseBed(noisePcm, volume: profile.noiseLevel)`；`stopPlay()` → `stopNoiseBed()`；`setTrainingProfile()` 时若会话进行中则同步 `setNoiseBedVolume`。

**难度参数重新定义**（把"信号内噪声"与"接收机底噪"分离）：

| 档位 | 底噪 level（底床增益） | 信号内 SNR 噪声 | QSB 深度 | QSB 速率 | Pile-up 台数 |
|---|---|---|---|---|---|
| Beginner | 0.02 | 0.00 | 0.00 | — | 1 |
| Standard | 0.07 | 0.04 | 0.10 | 0.5 Hz | 2 |
| Advanced | 0.15 | 0.10 | 0.22 | 1.0 Hz | 3 |

底床增益需明显低于信号（信号峰值约 0.8 FS），避免掩蔽呼号。

### 5.3 信号效果层（把 PR 的纯函数层修好）

保留上游的分层（纯函数、可单测），修正以下四点：

1. **看门狗时长按效果后的 PCM 计算。** 当前 `_estimateDuration(segment.pcm.lengthInBytes)` 用的是**效果后**已入队的 PCM，只要效果在入队前完成，估算自动正确——但必须确保**先施加效果、再入队**，不能反过来。若做不到（例如想做流式效果），则需扩展 `_PendingSegment` 携带 `estimatedDuration`。
2. **QSB 相位跨 clip 连续。** 用一个会话级的相位累加器（`_phase` 随会话推进），而不是每个 clip 从 `sin(0)` 重新开始，否则每次发射都"从最响开始衰减"，听感虚假。相位由 seed 初始化。
3. **resample 用线性插值**替代最近邻丢样，避免 Advanced（1.18×）下的混叠噪声。代价可忽略（24 kHz 音频）。
4. **噪声与 QSB 分离开关**：底噪由底床负责后，`apply()` 内只保留"信号内 SNR 噪声"（幅度已下调），避免双重噪声叠加。

签名建议：

~~~dart
class AudioEffects {
  /// 确定性处理入站信号（不处理操作员自己的音频）。
  static Uint8List apply(
    Uint8List pcm, {
    required double playbackRate,
    required double snrNoise,       // 信号内噪声
    required double qsbDepth,       // 0..1
    required double qsbRate,        // Hz
    required double volume,
    required int seed,
    required double phaseOffset,    // 会话级相位，保证跨 clip 连续
  });
}
~~~

### 5.4 Pile-up 混音修正

**签名保持简单**，把"谁是目标"显式化：

~~~dart
/// 目标台保持满增益；干扰台按 interfererGain 衰减；tanh 软限幅防削波。
/// offsets 以采样为单位，逐台递增（默认 150 ms @24 kHz = 3600）。
Uint8List mixPileup(
  Uint8List target,
  List<Uint8List> interferers, {
  double interfererGain = 0.5,
  int offsetSamples = 3600,
});
~~~

要点：
- **目标台 1.0 增益**，只有干扰台被加权；
- 累加用 `Float64List`/int 累加后做 `tanh(x)` 软限幅再定标到 int16，**不做 `~/ N`**；
- 偏移量随难度变化（Beginner 不启用；Standard 300 ms；Advanced 150 ms）；
- 保留 upstream 的 `mixPcm16` 作为底层通用工具（或直接用修正版替换，注意其单测依赖 `mixPcm16([pcm,pcm]).length > pcm.length` 的语义）。

### 5.5 与训练会话的接线

```
ContestManager.startContest()
  ├─ difficulty = settings.difficulty            // 见 5.2 参数表
  ├─ seed       = settings.practiceSeed ?? now
  ├─ profile    = TrainingSessionProfile(...)
  ├─ audioPlayer.setTrainingProfile(profile)     // 会话级：底床 + 信号效果参数
  └─ ContestRunningManager(mode/difficulty/seed)
       ├─ ContestAnswerGenerator(seed, mode, difficulty)   // pileup 候选集
       └─ ContestStateChangeHandler
            ├─ PlayPileup            → mixPileup(target, interferers) → addAudioData(isMyAudio: false)
            ├─ PlaySearchAndPounce   → concat([CQ.wav, 对方呼号])     → addAudioData(isMyAudio: false)
            └─ 其他 Play*            → AudioEffects.apply(...)       → addAudioData
```

**不变式（必须写进测试）：** 任何标有 `isMyAudio: true` 的 segment **不得**经过 `AudioEffects`（操作员自己的 CQ 必须清晰）；当前 `addAudioData` 已有 `isMyAudio` 参数，天然可作为效果层的开关条件。

### 5.6 测试计划

新增 `test/audio/noise_bed_test.dart`、`test/audio/audio_effects_test.dart`、`test/audio/pileup_mix_test.dart`（沿用现有 `test/audio/` 结构，用 fake `AudioEngine` 断言调用）：

- [ ] 底床：`startPlay()` 调用 `startNoiseBed`，`stopPlay()` 调用 `stopNoiseBed`，音量与难度对应；
- [ ] 底床不进入 segment 队列：`startNoiseBed` 后 `isPlaying()` 仍为 `false`；
- [ ] 效果确定性：同 seed 同参数两次 `apply()` 结果逐字节相同；
- [ ] 相位连续：连续两段应用的 `phaseOffset` 接力，输出不出现每段重启；
- [ ] 看门狗：效果后 PCM 变短（1.18×）时，估算时长随之变短；
- [ ] 混音：目标台增益不被 `1/N` 衰减（用单频正弦断言目标峰值）；峰值不削波（无连续 ±32767 平台）；
- [ ] 不变式：`isMyAudio: true` 的 PCM 与未经处理的原 PCM 逐字节相同；
- [ ] 种子的确定性测试不在本节，统一见 §3 阶段 5.2 / 5.7（`SessionRandom` 子流隔离、跨会话复现、重放一致性）。

### 5.7 音频方案的落地步骤

1. `AudioEffects` + `mixPileup` 纯函数 + 单测（不依赖引擎，可立即做）；
2. `AudioEngine` 扩展接口 + `SoLoudAudioEngine` 实现 + fake 引擎上的 `AudioPlayer` 测试；
3. 噪声底床素材生成（程序化，零素材依赖）；
4. `ContestManager` / `AppSettings` / 设置页接线（难度、QSB、底噪、pileup 台数）；
5. 手动听感调参（底噪 level 与干扰台增益需实听确定）。

---

## 6. 任务与 PR 划分建议

| 阶段 | 建议 PR | 依赖 |
|---|---|---|
| 1 | `fix: minor UI and test defects` | 无，可立即做 |
| 2 | `feat: contest registry` | 无 |
| 3 | `feat: training profile pure layer` | 无（可与 2 并行） |
| 4A+4B | `feat: training modes and audio effects` | 3 |
| 4C | `feat: session review` | 2、3 |
| 4D+4E | `feat: settings and key bindings` | 2、4A |
| A1–A4 | `feat: receiver noise bed and pileup mixing`（技术方案见 §5.1–§5.4、落地顺序见 §5.7 前三步） | 3 |
| A5 | `feat: audio training settings`（§5.7 第 4 步） | A1–A4、4E |
| **P** | `feat: deterministic practice seed and session replay`（**完整实现**，见 §3 阶段 5） | 2、3、4、A 全部完成 |
| 6 | `docs: training capabilities` | 4、A、P |

> 说明：
> 1. `A1–A5` 对应 §5 的底噪 / Pile-up 音频方案，与本表 `4A+4B` 有重叠。**以 §5 为准实现音频部分**——4A/4B 只保留状态机与模式接线，DSP 与混音按 §5.2–§5.4 落地。
> 2. `P` 是 practice seed 的完整实现，**必须在吸收（含 A）全部完成后进行**，理由见 §3 阶段 5.1；它是唯一一个"吸收完之后才做"的独立阶段。

---

## 7. 风险与取舍

1. **音频效果与看门狗时长估算不一致**
   - 变速后 PCM 变短/变长，而 `_defaultEstimateDuration` 固定按 24000 采样率换算。
   - 影响：看门狗余量偏保守（Advanced 变速后估算偏长），不会卡死。
   - 约束：效果必须**在入队前**完成，`_estimateDuration` 用的是入队后的 PCM 长度，顺序反了就会失准（见 §5.3）。
   - 对比：底噪**走独立循环 source、不进队列**，因此不影响 `isPlaying()` 与看门狗（见 §5.1）。

2. **`_NumericScoreCalculator` 计分口径偏松**
   - multiplier 用 `exchange-${qso.exchangeCorrect}` 建 key，同一交换值在多波段下会被合并。
   - 影响：仅训练分数，非官方计分；由 README 免责声明兜底。若后续做正式计分，必须重写。

3. **practice seed：上游版本名不副实，已单列阶段 5 完整实现**
   - 上游称 "replay seed"，但只影响 `Random(seed)` 与音频效果，**不会重放历史 QSO**，也无法保证可复现。
   - 根因：题目由**三处各自新建、均未接种子**的随机源共同决定（`contest_answer_generator.dart:12`、`cq_wpx.dart:35`、`audio_loader.dart:164` 的 `Random(DateTime.now())`）。
   - 决策：**不在阶段 4 草率收尾**。阶段 4 只做占位重命名与注入；**阶段 5 负责完整实现**（统一 `SessionRandom`、双种子分离、Drift 事件日志、重放引擎、UI 入口），验收标准见 §3 阶段 5.7。
   - 风险若然：只把 seed 接给 `Random(seed)` 就宣称"可重放"，会造成**功能承诺与实际不符**，比不做更糟。

4. **`contests.dart` 兼容层**
   - 上游直接删除 `supportedContests`/`ContestMode`，会破坏现有引用。
   - 本计划改为派生实现，代价是短期内仍存在 `Contest` / `ContestDefinition` 两套模型；后续可再统一。

5. **术语一致性（原"本地化"条目已废弃）**
   - ~~上游新增 UI 文案为英文，与现有中文语境不一致~~ → **该前提错误**：本仓库 GUI 本来就是全英文，中文只出现在代码注释与 `docs/`（已核实，见 §4.6）。
   - 正确要求：新增 UI 文案**必须保持英文**，且术语与现有 GUI 一致（例如继续用 "Duration"、"Phonic Type"、"Callsign"）。
   - 另需把上游的 "Replay seed" 改为 "Practice seed"；其语义完整性由 §3 阶段 5 负责。

6. **底噪与信号的双重噪声叠加**
   - 若照搬上游 `apply()` 的噪声，同时在底床再放一条噪声，会出现"噪声叠噪声"，Advanced 档尤其浑浊。
   - 决策：底噪交给底床（常驻、跨静默期），`apply()` 内只保留幅度更低的"信号内 SNR 噪声"（见 §5.2 参数表）。

7. **底床可能掩盖呼号**
   - 底床增益过高会掩蔽弱信号，违背训练目的。初值取信号峰值的 2%–15%（§5.2 参数表）。
   - 缓解：底床音量可在设置页实时调节；上线前必须实听调参（§5.7 第 5 步）。

8. **Pile-up 偏移量与可听性**
   - 上游 150 ms 固定偏移、3 台几乎完全重叠，且目标台被 `1/N` 衰减，实际可听性差。
   - 缓解：目标台满增益 + 干扰台加权 + `tanh` 软限幅，偏移量按难度变化（§5.4）。

9. **底噪素材来源**
   - `assets/voice` 无噪声素材且为 submodule，新增文件需改 submodule 与资源清单。
   - 决策：优先程序化生成（固定种子 + 带限滤波），零素材依赖、可复现（见 §5.2）。

10. **上游未 rebase**
   - PR 停留在旧 base 且 `dirty`，不建议等待其合并；本计划的目标是自吸收，不依赖上游动作。

---

## 8. 附：上游改动文件清单与处置

（相对于 base `e19f10b`，+1589 / −344）

| 文件 | 处置 |
|---|---|
| `lib/contest_type/contest_definition.dart` | 吸收（阶段 2） |
| `lib/contest_run/contests.dart` | 改造后吸收（阶段 2.2） |
| `lib/ui/main_settings/main_settings.dart` | 部分吸收（阶段 2.4） |
| `lib/ui/main_settings/options_setting.dart` | 重做（阶段 4E） |
| `lib/training/training_profile.dart` | 吸收（阶段 3.2） |
| `lib/training/session_review.dart` | 吸收，改语义（阶段 3.3） |
| `lib/audio/mix_pcm.dart` | 吸收（阶段 3.1） |
| `lib/audio/audio_player.dart` | **重做**接入点（阶段 4A.1） |
| `lib/contest_run/new/contest_manager.dart` | 改造后吸收（阶段 2.3、4A.2、4B.4、4C.1） |
| `lib/contest_run/new/contest_running_manager.dart` | 改造后吸收（阶段 4B.4、4D.3） |
| `lib/contest_run/new/contest_answer_generator.dart` | 吸收；随机源在阶段 5 改为 `SessionRandom`（阶段 4B.1、5.2） |
| `lib/contest_run/new/contest_state_change_handler.dart` | 吸收（阶段 4B.3） |
| `lib/contest_run/state_machine/single_call/*` | 吸收（阶段 4B.2） |
| `lib/contest_run/key_event_handler.dart` | 吸收（阶段 4D.1） |
| `lib/settings/app_settings.dart` | 吸收；种子项在阶段 5 扩展为双种子 + Drift 持久化（阶段 4A.3、5.3、5.4） |
| `lib/ui/main_page/training_review_overlay.dart` | 吸收（英文文案）（阶段 4C.3、5.6） |
| `lib/ui/main_page/main_page.dart` | 吸收挂载点（阶段 4C.3） |
| `lib/ui/main_page/key_tips.dart` | 吸收颜色与 Semantics（阶段 1） |
| `lib/ui/main_app/main_app.dart` | 吸收窗口改动（阶段 1） |
| `lib/ui/bottom_panel/qso_operation_area.dart` | 吸收 dispose 修复 + 键位读取（阶段 1、4D.3） |
| `lib/ui/bottom_panel/qso_speed_area.dart` | 可选吸收滚动速率（阶段 4C 附带） |
| `lib/ui/qso_result_table/qso_result_list/qso_result_list.dart` | 仅 Semantics 部分可选 |
| `test/training_platform_test.dart` | 吸收（阶段 3.4） |
| `test/dxcc_loader_test.dart` | 吸收（阶段 1） |
| `lib/contest_run/data/score_data.dart` | 丢弃（纯格式化） |
| `lib/contest_type/exchange_manager.dart` | 丢弃（纯格式化） |
| `lib/contest_type/score_calculator.dart` | 丢弃（纯格式化） |
| `lib/db/table/prefix_table.dart` | 丢弃（纯格式化） |
| `lib/callsign/callsign_loader.dart` | 丢弃（纯格式化） |
| `README.md` | 吸收（阶段 6.1） |
