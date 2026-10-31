# Run 模式 `HeAskForExchange` 卡死分析 与 交互决策

> 状态：分析完成，**决策已固化（见 §4）**，尚未改代码。
> 版本：`0.2.1+201001`，分支 `fix/v0.2.1-alpha01`
> 证据来源：`debug/ssb-runner-diagnostics-20261030-231729/`（`diagnostic-summary.txt` + `logs/latest.log`）
> 模式：Pile-up（Run），非 S&P

---

## 0. 结论摘要

| # | 现象 | 归因 | 性质 |
|---|---|---|---|
| 1 | 为什么进入「对方问我要号码（NR）」的状态 | 操作员在 `WaitingSubmitCall` 下按 F5(`<his>`)，且抄到的呼号与答案**完全相等** → 按设计进入 `HeAskForExchange`（对方确认收到我的呼号，要我报序号）。入场只播 `NR.wav`，界面无任何状态提示 | 设计路径 + 反馈缺失，不是状态机走错 |
| 2 | 按 F1(CQ) 后仍停在该状态 | F1 与 F7(AGN)、10 s 超时共用 `Retry` 事件；`HeAskForExchange.on(Retry)` 是**原地自环**（`copyWith(isPlayMyCall: true)`）。F1 的音频已先发出（CQ+我的呼号），随后排队的“我的呼号+NR”又播出来；且该状态没有任何出边（只有 F2 有效，Enter 被静默丢弃） | 确定性交互缺陷 |

---

## 1. 日志时间线（均为 UTC）

| 时间 | 事件 / 音频 | 说明 |
|---|---|---|
| 15:16:49.274 | `WaitingSubmitMyExchange → QsoEnd` | 上一轮完成 |
| 15:16:50.721 | `QsoEnd → WaitingSubmitCall` (`NextCall`) | 自动换题，新 pileup 开始播 |
| 15:16:52.9 / 55.3 / 57.6 | 音频结束 | pileup 播放，被后续操作打断 |
| **15:17:00.242** | 音频结束（自发音频） | = F5 发出的“他的呼号”播完 |
| **15:17:00.319** | `WaitingSubmitCall → HeAskForExchange` (`SubmitCall`) | 音频停止后 76 ms（`_waitAudioNotPlaying` 100 ms 轮询） |
| 15:17:03.996 | 音频结束 | 入场 `NR.wav` 播完（约 3.7 s） |
| **15:17:04.014** | `HeAskForExchange → HeAskForExchange` (`Retry`) | F1 |
| 15:17:09.265 / 15:17:15.874 | 同上 | F1（间隔 5.3 s / 6.6 s，人工） |
| **15:17:25.877** | 同上 | 15.874 + **10.000 s** = 超时定时器自动重试 |
| 15:17:19.486 / 22.216 | 两段音频结束 | 依次为「CQ+我的呼号」与「我的呼号+NR」，证明 F1 的音频副作用与自环重播叠加 |

该窗口内**没有 `to=null`**，即没有被丢弃的无效跃迁：只有 1 次 `SubmitCall` + 4 次 `Retry`。
现有日志不记录按键与输入内容，归因来自代码中的唯一产生点（见 §2、§3）。

---

## 2. 问题一：进入 `HeAskForExchange` 的路径

`SubmitCall` 且 `submitCall == currentCallAnswer` 才进入该状态
（[single_call_run_state_machine.dart#L86-L100](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L86-L100)）。

`SubmitCall` 全仓库唯一产生点是 F5（`<his>`）
（[contest_operation_event_handler.dart#L278-L295](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L278-L295)）。
Enter 走的是 `SubmitCallAndHisExchange` / `SubmitMyExchange`
（[contest_operation_event_handler.dart#L235-L254](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L235-L254)），不会产生 `SubmitCall`。

入场音频只拼 `NR.wav`（`isPlayMyCall: false`）
（[contest_state_change_handler.dart#L188-L210](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L188-L210)），
因此操作员听到的只有 “NR（要号码）”。

结论：**这不是状态机走错**，而是“抄对呼号 + 按 F5”推进到了 QSO 中段；缺的是状态可见性与“下一步该按什么”的提示
（UI 完全不读 `currentState`，见 [contest_running_manager.dart#L121-L145](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_running_manager.dart#L121-L145) 的 `transitionListener`）。

另外两条路径的不对称：

| 路径 | 进入状态 | 是否自动补 RST / 聚焦 exchange | 出口 |
|---|---|---|---|
| Enter（只填呼号） | `ReportMyExchange` | 是（`isOperateInput: true`） | 自动推进 |
| F5（`<his>`） | `HeAskForExchange` / `HeRepeatCorrectCallAnswer` | 否 | 只有 F2 |

---

## 3. 问题二：F1 为什么“保持该状态”

三个根因叠加：

1. **语义混用**：F1(CQ) 与 F7(AGN) 都发 `Retry`
   （[contest_operation_event_handler.dart#L177-L182](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L177-L182)）。
2. **状态自环**：`HeAskForExchange.on(Retry)` 只做 `copyWith(isPlayMyCall: true)`，不离开状态
   （[single_call_run_state_machine.dart#L129-L151](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L129-L151)）。
3. **音频先于业务**：`handleOperationEvent` 先播音频再走状态机
   （[contest_operation_event_handler.dart#L55-L58](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L55-L58)、
   [#L60-L134](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L60-L134)），
   而该状态的重播不带 `isResetCurrentStream`，于是“CQ+我的呼号”之后**排队**播“我的呼号+NR”
   （队列语义见 [audio_player.dart#L168-L189](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/audio/audio_player.dart#L168-L189)）。
   按得越多，队列越长。

附加放大：

- **超时无限重挂**：该状态在重试名单内，每次 `Retry` 重新进入状态又挂 10 s 定时器
  （[contest_state_change_handler.dart#L428-L447](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L428-L447)）→ 无人操作也会**永久**每 10 秒播一遍。
- **Enter 静默失效**：该状态只注册 `Retry` 与 `SubmitHisExchange`。Enter 产生的两个事件都无处理器，
  被 [state_machine.dart#L34-L79](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/state_machine/state_machine.dart#L34-L79)
  **丢弃**（仅一条 `to=null` 的 INFO），用户侧零反馈。
- **输入不重置计时**：`onCallEdit` / `onExchangeEdit` 只是 setter，10 s 倒计时不会因“操作员正在打字”而重置。
- **无状态提示**：界面没有当前阶段/可用按键提示，也没有“放弃本轮”的入口。

---

## 4. 决策（固化）

### D1. F1(CQ) 在 `WaitingSubmitCall` 下保持“重放同一堆叠”

**保留现状**。理由：听抄训练中“没抄清，让同一批台再报一遍”是高频需求；在此状态换新题会破坏训练连续性。
“开始新一轮”的诉求只绑定到**已进入 QSO 中段**的状态。

### D2. 新增 `AbandonQso` 事件，只由 F1 在“在途 QSO 状态”触发

- 触发条件：当前状态为 `HeRepeatCorrectCallAnswer` / `HeAskForExchange` / `WaitingSubmitMyExchange` / `ReportMyExchange`。
- 语义：**放弃当前未提交的 QSO**（不落库、不计分、不影响连击），清空输入，生成新题，进入 `WaitingSubmitCall`。
- 落一条 INFO：`round abandoned`（带原因与前序状态），便于事后诊断。

### D3. 按键语义矩阵（决策表）

| 当前状态 | F1 (CQ) | F7 (AGN) | 10 s 超时 | Enter |
|---|---|---|---|---|
| `WaitingSubmitCall` | **重放同一堆叠**（保持现状） | 重放同一堆叠 | 重放（保持现状，无限循环） | 走现有提交逻辑 |
| `HeRepeatCorrectCallAnswer` | **放弃本轮 → 新题**（新增） | 重播他的正确呼号（保持） | 重播（仅一次，见 D4） | 走现有提交逻辑 |
| `HeAskForExchange` | **放弃本轮 → 新题**（新增） | 我的呼号+NR（保持） | 我的呼号+NR（仅一次，见 D4） | **新增**：exchange 非空 → `SubmitHisExchange`；为空 → `Retry` |
| `WaitingSubmitMyExchange` | **放弃本轮 → 新题**（新增） | 重播他的交换信息（保持） | 重播（仅一次，见 D4） | 保持现状 |
| `ReportMyExchange` | 放弃本轮 → 新题（窗口极短，低优先级） | — | — | — |
| `QsoEnd` / `SpQsoEnd` | 自动推进，不拦截 | — | — | — |

### D4. 在途状态的 10 s 超时只挂一次

`HeRepeatCorrectCallAnswer` / `HeAskForExchange` / `WaitingSubmitMyExchange` 首次静默 → 问候式重发一次；
重发后**不再重挂**定时器（对方“再问一遍”即可，不再无限自播）。
`WaitingSubmitCall` 的 10 s 循环 CQ 保持不变。

同时：输入框内容变化（`onCallEdit` / `onExchangeEdit`）时**取消并重置**当前超时计时，避免“正在打字被对方打断”。
（S&P 的 `SpListeningCq` / `SpWaitingHisExchange` 不改动，另案评估。）

### D5. `HeAskForExchange` 的重播音频使用 `isResetCurrentStream: true`

入场（`isPlayMyCall: false`）与重播（`isPlayMyCall: true`）都替换当前音频流，避免与 CQ / pileup 叠加排队，
使“按一次 = 听一次”可预期。

### D6. 可观测性

- 跃迁日志补充 payload：`call` / `exchange` / `submitCall` / `isPlayMyCall`。
- 操作事件（`cq` / `agn` / `hisCall` / `submit` / `exch` / `cancel`）各记一条 DEBUG，可直接区分 F1 / F5 / Enter。
- 无效跃迁由 INFO 提升为 WARN，文案标明 `dropped: no handler for <Event> in <State>`。

### D7. 界面可见性

- 增加一行“当前阶段 + 下一步按键”的提示（例：`对方要序号 → F2 发序号 / F1 放弃本轮叫 CQ`）。
- 提供显式的“放弃本轮”入口（按钮或快捷键，与 F1 的行为一致），避免操作员只能靠猜。

### 明确不做的事

- 不把 `HeAskForExchange.on(Retry)` 改成跳回 `WaitingSubmitCall` —— 否则 F7/AGN 与超时都会变成“丢半条 QSO 重开”。
- 不把 F1 统一改成“换新题” —— 见 D1。

---

## 5. 实施要点（尚未编码）

1. **事件层**：新增 `AbandonQso extends SingleCallRunEvent`。
2. **操作层**（`ContestOperationEventHandler`）：
   - 拆开 `case OperationEvent.cq` 与 `agn`；
   - 新增 `_handleCq()`：在途状态调 `onAbandonRound` 回调（由 `ContestRunningManager` 注入），否则 `transition(Retry())`；
   - `_handleSubmit()` 增加 `HeAskForExchange` 分支（D3）。
3. **状态变化层**（`ContestStateChangeHandler`）：
   - 新增 `abandonRound()`：`_inputHandler.clear()` → `generateAnswer()` → `transition(NextCall(...))`，不写 `qsoTable`；
   - `_setupRetryTimer()`：在途状态只挂一次；`WaitingSubmitCall` 保持；
   - `HeAskForExchange` 音频加 `isResetCurrentStream: true`。
4. **状态机**（`single_call_run_state_machine.dart`）：
   - `HeAskForExchange` 增加 `AbandonQso` / `NextCall` / `SubmitMyExchange` 出边；
   - `HeRepeatCorrectCallAnswer`、`WaitingSubmitMyExchange`、`ReportMyExchange` 增加 `AbandonQso` 出边。
5. **输入层**（`ContestInputHandler`）：`onCallEdit` / `onExchangeEdit` 触发“重置超时”回调。
6. **UI**：状态提示 + 放弃本轮入口。

> 实现顺序建议：2/3/4（核心可解卡）→ 5（防打断）→ 1 的日志补充 → 6 的界面提示。

---

## 6. 测试覆盖（仅列用例，未实现）

`test/single_call_run_state_machine_test.dart`

1. `HeAskForExchange` + `Retry` → 仍为 `HeAskForExchange`，`isPlayMyCall == true`（锁住既有语义，防回归）。
2. `HeAskForExchange` + `AbandonQso` → `WaitingSubmitCall`（新题呼号/序号/pileup）。
3. `HeAskForExchange` + `SubmitMyExchange` → `WaitingSubmitMyExchange`，`isOperateInput == true`。
4. `WaitingSubmitMyExchange` + `AbandonQso` → 新题 `WaitingSubmitCall`。
5. `HeRepeatCorrectCallAnswer` + `AbandonQso` → 新题 `WaitingSubmitCall`。
6. `WaitingSubmitCall` + `Retry` → 仍为重放同一 pileup（验证 D1 未被改坏）。

`test/contest_state_change_handler_test.dart`（复用现有 `_rig`）

7. `HeAskForExchange` 下发 `OperationEvent.cq` → `WaitingSubmitCall`、`rig.answers.calls == 1`、`qsoTable` 零新增、输入被清空。
8. `HeAskForExchange` 下填 exchange 后发 `OperationEvent.submit` → 进入 `WaitingSubmitMyExchange`（不再静默丢弃）。
9. 在途状态超时：首次重发后不再重挂（推进 fake timer 断言只有一次 `Retry`）。
10. 输入变化后超时被重置（断言不会在打字过程中触发 `Retry`）。
11. 既有 `QsoEnd` 落库/推进用例全部保持通过。

---

## 7. 遗留 / 待评估

- S&P 模式下 `SpListeningCq` / `SpWaitingHisExchange` 也共用 `Retry`，是否需要同样的“放弃本轮”语义，另案评估
（其 `NextCall` 处理器已存在但**无任何产生点**，属半成品）。
- `isOperateInput` 在 F5 路径为 `false`，导致后续 `WaitingSubmitMyExchange` 不自动补 RST/聚焦；
是否统一为 `true`，需要单独确认对评分与输入记录的影响。
