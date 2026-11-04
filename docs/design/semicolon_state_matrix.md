# 分号键（`;` / `hisCallAndMyExchange`）状态矩阵技术方案

> 状态：已实施（2026-11-01）。
> 范围：Run / Pile-up 与 S&P。
> 关联文档：[`f5_his_call_state_matrix.md`](f5_his_call_state_matrix.md)（同类状态覆盖缺口）、[`function_keys_f1_f12_design.md`](function_keys_f1_f12_design.md)（键位模型）。

---

## 0. 结论摘要

| # | 问题 / 决策 | 结论 |
|---|---|---|
| 1 | 训练中按 `;` 无反应 | **状态矩阵漏写**：只在 `WaitingSubmitCall` / `WaitingSubmitMyExchange` 有分支，`HeRepeatCorrectCallAnswer` 等状态被整个吞掉 |
| 2 | 为什么日志里能看到 `operation event` 却没有任何 `onTransition` | 处理函数没有调用 `transition()`，比「事件被状态机拒绝」更彻底地静默 |
| 3 | 音频为什么会出现「发出去没人应答」 | `_playAudioByOperationEvent` 与状态派发解耦：只要 `_hisCall` 非空就播组合音频，与状态无关 |
| 4 | 修复方式 | 把音频与状态迁移合并成一次派发；`_handleHisCallAndMyExchange` 改为显式状态矩阵 |
| 5 | `;` 的键义 | **一次发射 = 他的呼号 + 我的序号**（PRD「播放 F5+F2 的语音」） |
| 6 | 键盘层为什么也可能吞键 | `_pressedKeys.length == 1` 把修饰键和漏掉的 KeyUp 一起算进去；在需要 Shift 打 `;` 的布局上必现 |

---

## 1. 根因

日志特征（`debug/ssb-runner-diagnostics-20261101-144619/logs/latest.log`）：`operation event event="hisCallAndMyExchange"` 之后既没有 `onTransition`，也没有 `dropped` 告警。

链路：`;` → [`key_event_handler.dart`](../../lib/contest_run/key_event_handler.dart) 发出 `OperationEvent.hisCallAndMyExchange` → [`contest_operation_event_handler.dart`](../../lib/contest_run/new/contest_operation_event_handler.dart)。

1. **状态覆盖缺口**：`_handleHisCallAndMyExchange` 只判断 `WaitingSubmitCall` 与 `WaitingSubmitMyExchange`。而 `HeRepeatCorrectCallAnswer` 的状态机本来就有 `SubmitCallAndHisExchange` handler，所以这是漏写，不是有意排除。
2. **音频与派发解耦**：`_playAudioByOperationEvent` 在所有状态下都会播「他的呼号 + 我的序号」；在 `ReportMyExchange` / `QsoEnd` 还会用 `isResetCurrentStream: true` 打断正在播的发射音频。
3. **复用 Enter 的输入启发式**：`;` 在 `WaitingSubmitCall` 里走 `_handleSubmit`，既继承了「呼号空 + 序号非空 → 完全没有动作」，也继承了「两框都填 → `SubmitMyExchange` 在该状态无 handler → dropped」。
4. **键盘层**：`_pressedKeys.length == 1` 会把 Shift / Ctrl / Cmd / Alt 计入；窗口失焦漏掉 KeyUp 后集合残留脏键，之后 `;`、Enter、Esc、空格一起失效。

---

## 2. 状态 × `;` 矩阵（实现即文档）

| 状态 | 行为 | 音频 |
|---|---|---|
| `WaitingSubmitCall` | 呼号非空 → `SubmitCallAndHisExchange`（`isOperateInput: false`） | 播「他的呼号 + 我的序号」 |
| `WaitingSubmitCall`（呼号为空） | `Retry()`：让对方重播 | 不播（避免空发射） |
| `HeRepeatCorrectCallAnswer` | 呼号非空 → `SubmitCallAndHisExchange`；空 → `Retry()` | 同左 |
| `WaitingSubmitMyExchange` | `Retry()`：让对方重播序号（既有行为） | 呼号非空时播组合音频 |
| `HeAskForExchange` | `Retry()`（等价 F5/F7） | 不播（他在要序号，组合音频会盖住他） |
| `ReportMyExchange` / `QsoEnd` / `SpQsoEnd` | 无动作，仅 debug 日志 | 不播 |
| `SpListeningCq` / `SpWaitingHisExchange` | 等价 Enter（S&P 两 Enter 模型） | 不播 |

`;` 与 Enter 的区别：Enter 是「提交我已抄到的内容」（按输入启发式派发），`;` 是「发射他的呼号 + 我的序号」，只走 `SubmitCallAndHisExchange`。

---

## 3. 实现要点

1. **派发前判定**：`handleOperationEvent` 对 `hisCallAndMyExchange` 直接进入 `_handleHisCallAndMyExchange`，音频在状态被接受后才播。
2. **状态矩阵**：`_handleHisCallAndMyExchange` 用 `switch` 列出全部状态，`sealed` 类型保证新增状态时编译期暴露缺口。
3. **回车漏洞**：`_handleSubmit` 按状态先分支：
   - `WaitingSubmitCall` / `HeRepeatCorrectCallAnswer` → 统一 `SubmitCallAndHisExchange`（两框都填也不再产生 dropped）；
   - `WaitingSubmitMyExchange` → 序号为空时 `Retry`，不再发无 handler 的 `SubmitCallAndHisExchange`；
   - `ReportMyExchange` / `QsoEnd` / `SpQsoEnd` → 记录 `submit ignored`，不静默。
4. **键盘层**：
   - 修饰键改读 `HardwareKeyboard.instance`（框架先更新按下状态再派发，不会因漏 KeyUp 而失步）；
   - `;` 允许 Shift（部分布局靠 Shift 打 `;`），并接受 `PhysicalKeyboardKey.semicolon` 兜底；
   - `KeyRepeatEvent` 不派发，长按只触发一次；
   - 窗口失焦（`didChangeAppLifecycleState` 非 resumed）时复位「功能键仍按住」闩锁；
   - 快捷键命中/被忽略都写 `key` tag 的 debug 日志。
5. **可观测性与提示**：
   - `handleOperationEvent` 返回 `bool`：`false` 仅表示「本阶段无动作」；
   - `ContestRunningManager.ignoredShortcutStream` 把这类按键交给界面；
   - 控制台对 `;` 弹一条 2 秒轻提示（`hintNothingToSend`，5 个语言），不再让按键看起来像坏了。

---

## 4. 验证

1. `test/key_event_handler_test.dart`：`;` / Enter / Esc / Space 派发、Shift 兼容、Ctrl/Cmd/Alt 抑制、物理键兜底、长按不重复派发、失焦复位后功能键不卡住。
2. `test/contest_state_change_handler_test.dart` 的「分号键」「回车提交的遗留黑洞」两组：每个状态的行为、音频加载次数、返回值（无动作时为 `false`），并断言所有迁移都是 `TransitionValid`（无 dropped）。
3. `test/ui/qso_console_test.dart` 的「分号键在该阶段无效时给出一条轻提示」：从运行中的 manager 的忽略流到控制台 toast 的整条链路。
4. 手工链路：推进到 `HeRepeatCorrectCallAnswer` → 按 `;` → 日志应为
   `operation event event="hisCallAndMyExchange"` → `onTransition: HeRepeatCorrectCallAnswer -> ReportMyExchange event=SubmitCallAndHisExchange`，且听到组合音频后对方应答。

---

## 5. 改动文件清单

| 文件 | 改动 |
|---|---|
| `lib/contest_run/key_event_handler.dart` | 修饰键判定、物理键兜底、长按不派发、失焦复位、快捷键日志 |
| `lib/contest_run/new/contest_operation_event_handler.dart` | `;` 状态矩阵与音频合并派发；返回值；`_handleSubmit` 回车缺口 |
| `lib/contest_run/new/contest_running_manager.dart` | 生命周期观察者；`ignoredShortcutStream` |
| `lib/ui/main_page/qso_console.dart` | 忽略流转发；`;` 被忽略时的轻提示 |
| `lib/l10n/app_*.arb` + `lib/l10n/generated/*` | `hintNothingToSend`（en / zh / zh_Hans / zh_Hant / ja） |
| `test/key_event_handler_test.dart` | 新增 |
| `test/contest_state_change_handler_test.dart` | 分号矩阵、回车回归、返回值断言 |
| `test/ui/qso_console_test.dart` | 轻提示链路用例 |
| `docs/design/semicolon_state_matrix.md` | 本文档 |
