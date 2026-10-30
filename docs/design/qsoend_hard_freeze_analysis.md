# `QsoEnd` 硬冻结：确认结论、修复方案与测试方案

> 状态：**已实施 L1–L3**，并新增 `test/contest_state_change_handler_test.dart`（8 个用例）。
> 来源：[pileup_mode_bug_analysis.md §2.3](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/docs/design/pileup_mode_bug_analysis.md) 的"附带发现"
> 基线：`fix/v0.2.1-alpha01`（`5ad6154`，§3.2 的静音死路已修）
> 证据：`debug/ssb-runner-diagnostics-20261030-163002(1)/logs/latest.log`、`debug/ssb-runner-diagnostics-20261021-140838/logs/latest.log`、`debug/latest.log`

---

## 0. 结论摘要

| 问题 | 结论 |
|---|---|
| §2.3 的 `QsoEnd` 硬冻结是否存在 | **存在**，是可复现的结构性缺陷；但现有 3 份诊断日志中**从未触发**（均一一配对走完） |
| 是否必然可达 | S&P 分支**必然可达**（第二次回车只校验序号，不校验呼号）；Run 模式为异步窗口竞态 |
| 修复原则 | 提交可以失败，状态机不能停：落库"尽力而为"，`NextCall` 无条件执行 |
| 改动范围 | 只动 `contest_run/new/` 的两个 handler，不改 DB schema、事件日志格式、状态机正常路径 |

---

## 1. 缺陷确认

### 1.1 代码路径

[contest_state_change_handler.dart#L459-L506](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L459-L506)：

```dart
final callsign = _inputHandler.hisCall;
final exchange = _inputHandler.exchange;

if (callsign.isEmpty || exchange.isEmpty) {
  return;            // ← 既不落库，也不 NextCall
}
```

三条"提前返回"的死路，全部位于 `NextCall` 之前：

| 位置 | 条件 |
|---|---|
| [#L463-L468](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L463-L468) | 呼号或序号为空 |
| [#L482-L484](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L482-L484) | `insertReturningOrNull` 返回 null |
| 插入 / `_scoreManager.addQso` / `generateAnswer` 抛异常 | 未捕获（`handleToState` 的 try/catch 只包音频，见 [#L75-L87](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L75-L87)） |

### 1.2 为什么会永久冻结

1. [single_call_run_state_machine.dart#L318-L330](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L318-L330) 与 [search_and_pounce_run_state_machine.dart#L77-L87](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/search_and_pounce_run_state_machine.dart#L77-L87)：`QsoEnd` / `SpQsoEnd` 只注册了 `NextCall`。其它事件在 [state_machine.dart#L44-L49](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/state_machine/state_machine.dart#L44-L49) 走 `_notifyInvalidTransition`，状态原地不动，listener 对 invalid 直接 return（[contest_running_manager.dart#L120-L124](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_running_manager.dart#L120-L124)）。
2. [#L421-L424](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L421-L424)：`_setupRetryTimer` 对 `QsoEnd` / `ReportMyExchange` / `SpQsoEnd` 直接 `break`，并已 `cancel()` 掉上一状态挂的 10 秒重试。**一旦停在这里，连定时器都没有。**
3. Esc 只重置音频流，不动状态机（[contest_operation_event_handler.dart#L272-L274](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L272-L274)）。

结论：唯一的出路是 STOP 重开本局。

补充：`handleToState` 是**不 await 的 fire-and-forget** 调用（[contest_running_manager.dart#L126-L129](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_running_manager.dart#L126-L129)），所以上面第 3 条还会表现为未捕获异步错误（诊断包里会看到 `FATAL crash msg="Uncaught asynchronous error"`）。

### 1.3 可达性：必然 vs 竞态

| 触发方式 | 是否必然 | 依据 |
|---|---|---|
| S&P 第二次回车时 Call 框为空 | **必然** | [contest_operation_event_handler.dart#L218-L231](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L218-L231) 只校验 `_exchange`；`_logQsoAndAdvance` 却要求两者都非空。操作员扑上去后清空 Call 框是自然动作 |
| Run 模式在 `_playAudioByStateChange` 期间清空 Call/Exchange | 竞态 | 进入 `QsoEnd` 前两者必非空（[#L238-L241](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L238-L241)），但 `handleToState` 先 `await` 音频加载：`TU_QRZ` + 可能的更正呼号，[audio_loader.dart#L105-L117](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/audio/audio_loader.dart#L105-L117) 是逐字符 asset 读取的异步 I/O。这段时间文本框 `onChanged`（[qso_operation_area.dart#L230-L232](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/bottom_panel/qso_operation_area.dart#L230-L232)、[#L268-L272](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/bottom_panel/qso_operation_area.dart#L268-L272)）可把值改成空 |
| 落库 / 计分异常、`insertReturningOrNull` 返回 null | 必然 | 无兜底推进（`qso_table.dart` 无唯一约束，因此 null 分支概率极低，异常分支才是真实风险） |

> S&P 那条尤其需要注意：`_logQsoAndAdvance` 读取的 `hisCall` 在 S&P 里就是操作员抄到的来台呼号，`SpWaitingHisExchange` 阶段只剩序号要抄，清空 Call 框不会被任何地方拦住。

### 1.4 日志实证：从未实际发生

| 日志 | 进入 `QsoEnd` | `QsoEnd → NextCall` |
|---|---|---|
| `ssb-runner-diagnostics-20261030-163002(1)/logs/latest.log` | 24 | 24 |
| `ssb-runner-diagnostics-20261021-140838/logs/latest.log` | 133 | 133 |
| `debug/latest.log` | 17 | 16（差额为 grep 口径，逐条核对均配对） |

即：08:26 那次卡死属于 §2.2（`WaitingSubmitCall` 被 `NoPlay` 覆盖后全程静音），与 §2.3 无关。§2.3 是埋在代码里、尚未被踩到的坑。

---

## 2. 修复方案

原则：**提交可以失败，状态机不能停。**

### L1（必须）：落库尽力而为，`NextCall` 无条件执行

重排 `_logQsoAndAdvance` 的控制流，让它只有一个出口：

1. 先取到本次要提交的值（见 L2）；
2. 值为空 → `log.warn`（附 `runId`），**跳过 insert**，继续第 5 步；
3. 落库 + 计分放在 `try/catch` 内 → 失败 `log.error`，继续第 5 步；
4. `insertReturningOrNull` 为 null → `log.warn`，继续第 5 步；
5. 无条件执行：`_answerGenerator.generateAnswer()` → `_inputHandler.clear()` → `await _waitAudioNotPlaying()` → `transition(NextCall(...))`。

要点：

- `_inputHandler.clear()` 必须留在**无条件**分支。若跳过落库时不清空，旧文本会残留到下一题。
- 跳过落库不改变出题推进与事件日志：`RecordingAnswerSource` 仍按每题一次记录（[contest_running_manager.dart#L46-L56](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_running_manager.dart#L46-L56)），重放保真度不受影响。
- 空输入这条路径等价于"该 QSO 弃权不记录"，不再污染结果表（`Corrections` 列不会出现空呼号行）。

### L2（Run 模式，零成本）：从状态快照提交，不读活输入

`QsoEnd` 已经携带提交时的快照（[single_call_run_state.dart#L89-L107](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state.dart#L89-L107)）：

- 呼号 = `toState.correctedCall ?? toState.submitCall`；
- 序号 = `toState.submitExchange`。

正确性核对：`QsoEnd` 由 `WaitingSubmitMyExchange` 构建时，`submitCall` 取自**上一次**提交的呼号、`correctedCall` 才是本轮更正（[single_call_run_state_machine.dart#L281-L301](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L281-L301)）。而当前读的 `_inputHandler.hisCall` 在按下回车那一刻恒等于 `correctedCall ?? submitCall`，`exchange` 恒等于 `submitExchange`。所以这是**等价替换**，正常路径行为零变化，却彻底消除异步窗口竞态。

`SpQsoEnd` 不带操作员抄到的呼号，不建议为此扩字段/改事件，交给 L3 拦截。

### L3（S&P）：把空输入拦截放回事件入口

[contest_operation_event_handler.dart#L218-L231](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L218-L231) 的 `SpWaitingHisExchange` 分支，在 `_exchange.isEmpty` 之外补 `_hisCall.isEmpty → transition(Retry())`。

语义自洽：没抄到呼号就再听一遍（`Retry` 在该状态重放 `PlayCallExchange`），且不会伪造"完美抄收"（不能用 `currentCallAnswer` 顶替操作员的抄收，否则准确率虚高）。

### 可选：给 fire-and-forget 兜底

在 [contest_running_manager.dart#L126-L129](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_running_manager.dart#L126-L129) 的 `handleToState(...)` 调用补 `.catchError`，防止将来任何新异常点又变成静默冻结。L1 已覆盖当前唯一的异常面，此项属加固。

### 影响面

| 项 | 影响 |
|---|---|
| 正常 QSO 提交 | 行为不变（L2 等价替换，L1 只重排控制流） |
| 空输入 | 从"整局冻结"变为"跳过该条并继续" |
| S&P | 新增"回车但未抄呼号 → 重听"，与 N1MM 的 ESM 直觉一致 |
| DB / 事件日志 / 重放 | 无 schema、无 JSON 变更 |
| 其它状态 | `ReportMyExchange` 自身必定转移，不受影响 |

**实施顺序**：L1 → L2 → L3 → 测试。

---

## 3. 测试方案

现状：25 个测试文件里**没有任何** `ContestStateChangeHandler` 的测试；`test/single_call_run_state_machine_test.dart` 也覆盖不到这段（缺陷在 handler，不在状态机）。

新增 `test/contest_state_change_handler_test.dart`。所需依赖均已确认可在单测中搭建：

| 依赖 | 替身 |
|---|---|
| `AppDatabase` | `AppDatabase(NativeDatabase.memory())`（`dxcc_manager_test.dart` 已有先例） |
| `AppSettings` | `SharedPreferences.setMockInitialValues({})` + `SharedPreferencesWithCache`（`main_settings_test.dart` 同款） |
| `AudioLoader` | 子类 override `loadAudio` 返回固定 PCM；需要精确控制异步窗口时用 `Completer` 挂起 |
| `AudioPlayer` | `AudioPlayer(engine: _FakeEngine(isInitialized: false))`——`AudioEngine` 是接口（[audio_engine.dart#L32-L63](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/audio/audio_engine.dart#L32-L63)），未 start 时 `addAudioData` 直接丢弃，`isPlaying()` 恒 false |
| `DxccManager` | 真实实例 + 空前缀表（返回 -1，`QsoEnd` 音频不依赖它） |
| `ContestType` | `replay_test.dart` 的 `_FixedContestType` 同款 |
| `ScoreCalculator` | 返回 `ScoreData.initial()` / `Correct()` 的最小实现 |
| `AnswerSource` | 返回固定第 1/2 题的 fake，便于断言"只推进一题" |
| 状态机 | `initSingleCallRunStateMachine(initialState: QsoEnd(...))`，listener 收集 `TransitionValid` |

用例：

| # | 用例 | 断言 |
|---|---|---|
| 1 | 正常提交（输入完整） | DB 新增 1 条且 `callsign/callsignCorrect/exchange/exchangeCorrect` 正确；推进到 `WaitingSubmitCall`；输入被清空；`AnswerSource` 仅调用 1 次 |
| 2 | 异步窗口内被清空（复现 §2.3 竞态） | 让 fake `AudioLoader` 在 `loadAudio` 挂起，进入后 `inputHandler.clear()` 再放行。必须推进到 `WaitingSubmitCall`；L2 生效时该 QSO 仍按快照完整落库 |
| 3 | 一开始就为空 | 不落库、不抛异常、**仍推进**并清空输入（用 `expect(await ..., completes)` 兜住"不能永久挂起"） |
| 4 | 落库失败（`db.close()` 后调用） | 仍推进，异常不外泄（不应出现未捕获异步错误） |
| 5 | `SpQsoEnd` 镜像 | 输入完整 → 落库 1 条并推进到 `SpListeningCq`；Call 为空 → 不冻结 |
| 6 | 入口拦截（可选） | `SpWaitingHisExchange` 下 Call 空、Exchange 有值 → `submit` → 仍在 `SpWaitingHisExchange`，未进 `SpQsoEnd` |
| 7 | 回归 | `test/single_call_run_state_machine_test.dart`、`test/replay_test.dart` 不改动、必须继续通过（`QsoEnd` 不新增字段，现有 `_machineInSubmitExchangeState` 用例不受影响） |

验证命令：

```bash
flutter test test/contest_state_change_handler_test.dart
flutter test
```

---

## 4. 附录：关键代码位置

| 主题 | 位置 |
|---|---|
| `QsoEnd` 提交与推进 | [contest_state_change_handler.dart#L459-L506](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L459-L506) |
| 音频异常兜底 | [contest_state_change_handler.dart#L69-L109](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L69-L109) |
| 重试定时器 | [contest_state_change_handler.dart#L407-L426](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L407-L426) |
| Run 状态机 `QsoEnd` | [single_call_run_state_machine.dart#L318-L330](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L318-L330) |
| S&P 状态机 `SpQsoEnd` | [search_and_pounce_run_state_machine.dart#L77-L87](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/search_and_pounce_run_state_machine.dart#L77-L87) |
| `QsoEnd` 状态字段 | [single_call_run_state.dart#L89-L107](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state.dart#L89-L107) |
| 回车分发 | [contest_operation_event_handler.dart#L203-L253](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L203-L253) |
| 输入清空 | [contest_input_handler.dart#L42-L48](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_input_handler.dart#L42-L48) |
| 文本框回写 | [qso_operation_area.dart#L230-L232](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/bottom_panel/qso_operation_area.dart#L230-L232) |
| 转移监听（fire-and-forget） | [contest_running_manager.dart#L114-L141](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_running_manager.dart#L114-L141) |
| 音频加载（逐字符异步 I/O） | [audio_loader.dart#L105-L117](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/audio/audio_loader.dart#L105-L117) |
| QSO 表结构（无唯一约束） | [qso_table.dart](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/db/table/qso_table.dart) |
