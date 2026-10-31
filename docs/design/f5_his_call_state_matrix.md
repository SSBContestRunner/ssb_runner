# F5（`<his>`）在各状态下的行为矩阵技术方案

> 状态：已按本文档实施（2026-10-31）。
> 分支：`feat/v0.3.0`
> 范围：Run / Pile-up 与 S&P 共用同一套 F5 语义。
> 关联文档：[`function_keys_f1_f12_design.md`](function_keys_f1_f12_design.md)（F1–F12 键位模型）、[`he_ask_for_exchange_stuck_analysis.md`](he_ask_for_exchange_stuck_analysis.md)（F5 进入 `HeAskForExchange` 的既有路径）。

---

## 0. 结论摘要

| # | 问题 / 决策 | 结论 |
|---|---|---|
| 1 | 「Your report is sent — type his serial」状态下 F5 无反应 | **漏写分支**，不是有意排除 |
| 2 | 修复方式 | 采用**状态矩阵**：在 `_handleHisCall` 中把「F5 在每种状态下做什么」显式列出，而不是继续累加 `if` |
| 3 | 该状态下 F5 的行为 | 与 F7（AGN）一致：`transition(Retry())`，对方重播序号 |
| 4 | S&P 是否同步 | **是**，`SpWaitingHisExchange` 纳入同一分支（`Retry` 重播「我方呼号 + 他的序号」） |
| 5 | F5 是否仍播「他的呼号」音频 | **保留**：F5 的键义仍是「发送他的呼号」，状态迁移在其后发生 |
| 6 | 是否用 `Retry` 兜底所有状态 | **否**：`QsoEnd` / `ReportMyExchange` / `SpQsoEnd` 没有 `Retry` handler，兜底只会产生 dropped 警告 |
| 7 | 状态提示文案 | 两个相关状态补 `F5/F7 repeats`，与 `HeRepeatCorrectCallAnswer` 的提示风格一致 |

---

## 1. 问题与根因

### 1.1 现象

`WaitingSubmitMyExchange`（提示文案「Your report is sent — type his serial, then Enter」）下按 F5：

- 只会听到「他的呼号」被播出（我方发射），随后没有任何状态迁移、没有对方重播；
- 期望：与 F7 相同，让来台重发他的序号。

日志特征：只有 `operation event event=hisCall`，没有后续 `onTransition`，也没有 `dropped: no handler` 警告——因为根本没有提交迁移，属于静默无操作。

### 1.2 链路

F5 → `OperationEvent.hisCall`：

1. 音频：`_playAudioByOperationEvent` 的 `hisCall` 分支播放抄到的呼号；
2. 业务：`_handleHisCall` 只覆盖 `WaitingSubmitCall` / `HeRepeatCorrectCallAnswer`（→ `SubmitCall`）与 `HeAskForExchange`（→ `Retry`），其余状态直接返回。

而 `Retry` 在 `WaitingSubmitMyExchange` 是**有 handler 的**：重建同类型状态并保留 `PlayExchange(isMe: false)`，即对方重播序号；`_setupRetryTimer` 对 `event is Retry` 不再补开 10 s 定时器，因此不会产生自动重播循环。

同一状态下分号键（`;` / `hisCallAndMyExchange`）反而有 `WaitingSubmitMyExchange → Retry` 分支，说明「该状态要求重发」在语义上早已被认可，F5 只是没接上。

### 1.3 改动历史（为什么漏了）

| 提交 | 变更 | 对 F5 的影响 |
|---|---|---|
| `7227774`（初始） | `cq` / `agn` / `hisCall` 同组 → `transition(Retry())` | F5 与 AGN 完全同义，任何状态都重播 |
| `2d6fa9f`（v0.0.2，2025-08-01） | 提交信息含 “fix: f5 no action” 与 “feat: add f5 and f2 actions”；F5 拆成独立的 `_handleHisCall`，移出 Retry 分组 | 从「通用重播」改为「按状态派发」，**只写了 2 个状态**；该提交中 `WaitingSubmitMyExchange` 已存在且已有 `Retry` handler，但没写对应分支 |
| `efd9b8b`（0.2.0-alpha-02，2026-10-15） | 提交信息：“F5 only dispatched SubmitCall from WaitingSubmitCall … further F5 presses were ignored”，补 `HeRepeatCorrectCallAnswer` | 同类漏写，被报告后打补丁 |
| `a5dc46e`（2026-10-31） | F1 放弃轮次 | 与 F5 无关 |
| `19d9f0a`（2026-10-31） | F1–F12 键位模型、F12 wipe | 与 F5 无关 |

结论：F5 的语义改造（v0.0.2）留下了状态覆盖缺口，此后每次都是「按报告补一个状态」，`WaitingSubmitMyExchange` 与 S&P 的 `SpWaitingHisExchange` 从未被补过。因此定性为**漏写**。

---

## 2. 状态 × F5 矩阵

| 状态 | F5 行为 | 说明 |
|---|---|---|
| `WaitingSubmitCall` | `SubmitCall(call: _hisCall)` | 既有行为，不变 |
| `HeRepeatCorrectCallAnswer` | `SubmitCall(call: _hisCall)` | 既有行为，不变（完整抄对 → `HeAskForExchange`；前缀匹配 → 继续重播；偏差过大 → 回到等待提交） |
| `HeAskForExchange` | `Retry()` | 既有行为，不变（对方重播「我的呼号 + NR」） |
| `WaitingSubmitMyExchange` | `Retry()` | **新增**：对方重播序号，效果与 F7 一致 |
| `SpWaitingHisExchange` | `Retry()` | **新增**：对方重播「我方呼号 + 他的序号」，效果与 F7 一致 |
| `ReportMyExchange` / `QsoEnd` / `SpQsoEnd` | 无动作 | 这些状态没有 `Retry` handler，保持静默 |
| `SpListeningCq` | 无动作 | 不在本次范围（若要「他再叫一遍 CQ」，需单独评估） |

前置条件：`_hisCall` 为空时 F5 不产生任何状态迁移（保持「F5 = 发送他的呼号，没有可发的内容就不发」的键义）。`WaitingSubmitMyExchange` / `SpWaitingHisExchange` 下 `_hisCall` 仍保留着操作员抄到的呼号（`ContestInputHandler.clear()` 只在 `QsoEnd` 与 F12 wipe 时调用），因此正常流程可达。

---

## 3. 实现

改动点：`lib/contest_run/new/contest_operation_event_handler.dart` 的 `_handleHisCall`。

```dart
Future<void> _handleHisCall() async {
  await _waitAudioNotPlaying();

  if (_hisCall.isEmpty) {
    return;
  }

  switch (_stateMachine.currentState) {
    case WaitingSubmitCall():
    case HeRepeatCorrectCallAnswer():
      _stateMachine.transition(SubmitCall(call: _hisCall));
      break;
    case HeAskForExchange():
    case WaitingSubmitMyExchange():
    case SpWaitingHisExchange():
      transition(Retry());
      break;
    default:
      break;
  }
}
```

设计要点：

1. **显式矩阵**：状态覆盖一眼可见；新增状态时不会再被 `if` 链静默吞掉。
2. **复用 `Retry`**：不改状态机、不改音频层、不动混音与数据库；Run 与 S&P 两套状态机都已有对应的 `Retry` handler。
3. **`default` 保持静默**：不做“未处理状态一律 Retry”的兜底，避免在 `ReportMyExchange` / `QsoEnd` / `SpQsoEnd` 产生 dropped 事件日志噪声。
4. **音频顺序**：F5 仍先播「他的呼号」（`isResetCurrentStream: true`），`_waitAudioNotPlaying()` 等其播完后再 `Retry`；对方重播的序号音频在状态变化时排队播放（`isResetAudioStream: false`）。因此听感是「我喊他 → 他重发序号」，与 F7 的「AGN → 他重发序号」状态效果相同、前导音频不同。
5. **计时器**：`Retry` 不重新布置 10 s 超时（与 AGN 一致），不会出现无限自动重播。

---

## 4. 状态提示文案

`lib/ui/bottom_panel/qso_operation_area.dart` 的 `_phaseHint`：

| 状态 | 新文案 |
|---|---|
| `WaitingSubmitMyExchange` | `Your report is sent — type his serial, then Enter; F5/F7 repeats` |
| `SpWaitingHisExchange` | `He answered — copy his serial, then Enter; F5/F7 repeats` |

与 `HeRepeatCorrectCallAnswer` 的 `Call not copied — F5 to submit, F7 to repeat` 保持一致风格；提示仍为 `maxLines: 1` + ellipsis，长度与现有最长提示相当。

---

## 5. 边界与失败场景

| 场景 | 预期 |
|---|---|
| `WaitingSubmitMyExchange` 按 F5 | 我方播「他的呼号」→ 对方重播序号；状态仍为 `WaitingSubmitMyExchange`，已抄内容不清空 |
| `SpWaitingHisExchange` 按 F5 | 我方播「他的呼号」→ 对方重播「我方呼号 + 序号」；输入不清空 |
| 连续按 F5 | 与 AGN 相同：每次都是一次重播；10 s 定时器不会被重新布置 |
| `_hisCall` 为空（例如刚按过 F12） | 无音频、无迁移；需要重发时用 F7 |
| `QsoEnd` / `ReportMyExchange` / `SpQsoEnd` 按 F5 | 无动作，不产生 dropped 事件 |
| 按住 F5 不放 | 键盘层 `_isFunctionKeyPressed` 仍保证只触发一次 |
| 呼号抄错后按 F5（`HeRepeatCorrectCallAnswer`） | 既有分支不变 |
| 分号键 `;` | 既有 `WaitingSubmitMyExchange → Retry` 分支不变，与 F5 并存 |

---

## 6. 验证

1. 手工链路：推进到 `WaitingSubmitMyExchange` → 按 F5 → 日志应连续出现
   `operation event event=hisCall` → `onTransition: WaitingSubmitMyExchange -> WaitingSubmitMyExchange event=Retry`，并听到序号重播。
2. S&P：推进到 `SpWaitingHisExchange` → 按 F5 → 听到「我方呼号 + 序号」重播，状态不前进。
3. 回归：F5 在 `WaitingSubmitCall` / `HeRepeatCorrectCallAnswer` / `HeAskForExchange` 行为不变；F7 不变；`QsoEnd` / `ReportMyExchange` 按 F5 仍无动作且无 dropped 警告。
4. 状态机层已补回归断言：`WaitingSubmitMyExchange + Retry` 仍为 `WaitingSubmitMyExchange` 且 `audioPlayType` 为 `PlayExchange(isMe: false)`（见 `test/single_call_run_state_machine_test.dart`）。
5. `flutter analyze` 无告警。

---

## 7. 改动文件清单

| 文件 | 改动 |
|---|---|
| `lib/contest_run/new/contest_operation_event_handler.dart` | `_handleHisCall` 改为状态矩阵；新增 `WaitingSubmitMyExchange` / `SpWaitingHisExchange → Retry` |
| `lib/ui/bottom_panel/qso_operation_area.dart` | `WaitingSubmitMyExchange` / `SpWaitingHisExchange` 状态提示补 `F5/F7 repeats` |
| `test/single_call_run_state_machine_test.dart` | 新增 `WaitingSubmitMyExchange + Retry` 回归断言 |
| `docs/design/f5_his_call_state_matrix.md` | 本文档 |

不改：状态机、音频与混音、数据库结构、事件日志结构、键位配置与持久化。
