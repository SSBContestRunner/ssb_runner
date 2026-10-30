# v0.2.1-alpha01 Pile-up 模式两个 Bug 的分析与修复方案

> 状态：仅分析，未改代码。待决策后实施。
> 版本：`0.2.1+201001`（`git 9489c67`，与 `main` 一致）
> 证据来源：`debug/ssb-runner-diagnostics-20261030-163002(1)/`（`diagnostic-summary.txt` + `logs/latest.log`）、用户提供的 QSO 结果表截图

---

## 0. 结论摘要

| # | 现象 | 根因 | 性质 |
|---|---|---|---|
| 1 | 「回答后的呼号还会在第二轮出来」 | 重放兜底生成器从种子第 1 题重新开始。本局实际是**被静默武装的重放**：一次性 `pendingReplayRunId` / `pendingQuestionSeed` 持久化在 prefs，跨一次 App 重启仍然生效，操作员下一次按 RUN 时无声地重放了一局 **0 QSO（日志仅 1 条 answer）** 的会话，于是 Q1 取自日志、Q2 落到兜底 = Q1 | 确定性 bug，可单测复现；触发条件隐蔽（跨进程的残留状态） |
| 2 | 「输错两位呼号，再按 F5，流程就卡住」 | `WaitingSubmitCall` 抄错后被 `NoPlay` 永久覆盖本轮音频，`Retry` 又复制这个坏值，导致全程静音、状态机无法推进 | 确定性 bug，日志可佐证 |

现象 2 只涉及 `lib/contest_run/`；现象 1 的正确性修复在 `lib/contest_run/` + `lib/training/`，另外需要动 prefs 生命周期与少量 UI（重放可见化），不动 DB schema。

---

## 1. 现象 1：下一题 pileup 里又出现刚通联的台

### 1.1 两行就是本局第 1、2 个 QSO（时间线对齐）

截图与 `logs/latest.log`（UTC）逐条对齐：

| 截图 | 日志事件 | 距离 RUN 的计时 |
|---|---|---|
| `00:00:31` | `QsoEnd` @ 08:25:49.213 | ≈ 31.7 s |
| `00:01:13` | `QsoEnd` @ 08:26:30.804 | ≈ 73.3 s |

- 计时起点（`contestTimer.start()`）在首题生成之前；用「App ready 08:25:14.214」与「首段音频 08:25:17.649」夹逼，RUN 约为 **08:25:17.5**。
- 局内只有两次 `QsoEnd → NextCall`（08:25:50.645 / 08:26:32.245）；35 条 `contest.state` 跃迁全部单发，没有重复管理器、没有重启记录。
- ⇒ 截图两行就是**本局第 1、2 个 QSO**，不是跨局混排。

### 1.2 两行完全相同的含义

`Call` / `Exchange` 列存的是操作员输入（`qso.callsign` / `qso.exchange`），`Corrections` 只在 `callsign != callsignCorrect || exchange != exchangeCorrect` 时才有值（[qso_result_list_cubit.dart#L60-L75](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart#L60-L75)）。

- Corrections 为空 ⇒ 两行的**输入都精确等于答案**。
- 即第 2 题服务给操作员的 `currentCallAnswer` / `currentExchangeAnswer` 与第 1 题**逐字相同**，并且 pileup 里他也确实听到了同一个呼号，才会抄出同样的内容。

### 1.3 排除：实时出题路径不可能连续两题相同

用仓库真实资源复刻 `SessionRandom` + `ContestAnswerGenerator`（`assets/callsign/callsigns.txt`：46040 条，**逐一比对无重复字符串**；CQ WPX 序号 = `nextExchange(3000)`，与呼号流独立，见 [cq_wpx.dart#L54-L63](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_type/cq_wpx/cq_wpx.dart#L54-L63)）：

```
连续题对 3,000,000 对（1e6 个 seed × 4 题）
同呼号        82   次（期望 65.2）
同 exchange   945  次（期望 1000）
同时相同      0    次（期望 0.022）
```

- 每次 `generateAnswer()` 必然推进 `_callsign` / `_exchange` 子流（[contest_answer_generator.dart#L33-L59](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_answer_generator.dart#L33-L59)、[session_random.dart#L9-L51](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/training/session_random.dart#L9-L51)）。
- `ContestAnswerGenerator` / `SessionRandom` 在 `ContestRunningManager` 里都是 `late final`，每局只构造一次；`generateAnswer()` 全仓库只有两个调用点：开局 `_setupStateMachine`（[contest_running_manager.dart#L114-L170](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_running_manager.dart#L114-L170)）与每题结束 `_logQsoAndAdvance`（[contest_state_change_handler.dart#L459-L506](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L459-L506)）。

⇒ 实时出题不会、也不能重复。**重复只能来自「题目流被倒回」。**

### 1.4 唯一能把题目流倒回去的路径：重放兜底

[contest_manager.dart#L147-L160](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L147-L160)：

```dart
// Record first, recompute as a fallback: if the log runs out mid-replay,
// continue from the question seed instead of crashing (design §5.5).
final AnswerSource? replaySource = replayEvents.isEmpty
    ? null
    : ReplayAnswerSource.fromEvents(
        replayEvents,
        fallback: ContestAnswerGenerator(
          callsignLoader: _contestDataManager.callsignLoader,
          contestType: contestType,
          mode: mode,
          difficulty: difficulty,
          random: SessionRandom(questionSeed),   // ← 同一个 seed，但随机流处于"第 0 题"
        ),
      );
```

- `ReplayAnswerSource` 按顺序返回录制值，**一旦 `_index` 越界就切到 fallback**（[replay_answer_source.dart#L37-L48](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/training/replay_answer_source.dart#L37-L48)）。
- fallback 是**全新**的生成器：同一个 seed、随机流处于初始状态 → 它的第 1 题 = 本局第 1 题（呼号、序号、pileup 列表全部一致）。

复现（真实呼号池，seed=123456789，standard 难度）：

```
原始第 1 题                = KB7IQO/1127 pileup=[KB7IQO, KC4NAP, IZ5OQX]
重放：日志 1 条   Q1       = KB7IQO/1127 pileup=[KB7IQO, KC4NAP, IZ5OQX]
重放：日志耗尽   Q2       = KB7IQO/1127 pileup=[KB7IQO, KC4NAP, IZ5OQX]   ← 与 Q1 完全相同
修复：兜底先快进 1 题     Q2 = YP8T/825        Q3 = WA3KCP/520
实时同 seed 的 Q2 / Q3     = YP8T/825          WA3KCP/520   ← 修复后与实时序列逐题一致
```

日志长度决定重复出现在第几题（每局固定写 1 条初始 answer，之后每完成 1 个 QSO 再写 1 条：[contest_manager.dart#L68-L79](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L68-L79)、[#L243-L273](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L243-L273)）：

- 本局重复出现在**第 2 题** ⇒ 被重放的那一局日志只有 **1 条 answer**，即该局 **0 个 QSO**（只出过第 1 题）。
- 日志越长重复点越靠后（第 N+1 题），现象一样。

设计 §5.5 的原意是"日志用完后**接着**种子往下走"，实现却变成了"从头再来"，属于实现偏差。

另外有个自传播效应：本局也会把这两条相同的 answer 记进自己的日志；若再重放本局，重复会继续往后传。

### 1.5 关键反证：本局第 1 题不是「现场种子」生成的

`questionSeed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff`（[contest_manager.dart#L114-L129](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L114-L129)）。以 RUN ≈ 08:25:17.5 为基准，枚举 `[08:25:14, 08:25:18)` 内每个 µs 作为种子、用真实资源复刻生成器：

- **没有任何一个种子能产出 `4X6ZM / 2500`**（该 4 s 窗口的误报期望仅 ≈ 0.03 次）。
- 把窗口放宽到 `[08:20, 08:30)`（6 亿个 µs）：只有 5 个种子命中 `4X6ZM / 2500`（期望误报 ≈ 4.3，属纯巧合），命中时刻 08:20:19.79 / 08:24:40.12 / 08:26:17.75 / 08:28:15 / 08:28:49，**都不在启动窗口内**。

⇒ 本局 `questionSeed` 来自 `pendingQuestionSeed`（或 `lockQuestionSeed` 固定值），**不是现场生成**。而「种子被继承」+「同题重复」这两个条件，在代码里只有**重放**路径能同时满足（见 1.4）。

### 1.6 重放是被「静默武装」的

- 三个一次性 prefs：`pendingReplayRunId` / `pendingQuestionSeed` / `pendingAudioSeed`（[app_settings.dart#L117-L148](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/settings/app_settings.dart#L117-L148)）。它们**只在 `startContest()` 读取后清空**（[contest_manager.dart#L89-L90](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L89-L90)），App 启动与退出都不清理 ⇒ **可跨进程存活**。
- 只有两个入口会同时写这三个键（并顺带覆盖 `contestId` / `contestModeId` / `difficulty`）：
  - 复盘浮层的「Replay this session」按钮（[training_review_overlay.dart#L88-L130](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/training_review_overlay.dart#L88-L130)）；
  - 设置页「Past sessions」列表项（[options_setting.dart#L499-L563](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_settings/options_setting.dart#L499-L563)）。
- 同一份诊断日志里的**上一次运行**（10-28 16:44:36 启动，只按了 3 次 Retry，16:45:17 停止）**0 个 QSO** ⇒ 它的日志正好是 **1 条 answer**，与 1.4 的触发条件严丝合缝。
- 该局停止后复盘浮层弹出（`_saveReview` → `reviewStream`），App 直到 10-29 10:51 才 `deinit()`。若此刻点过「Replay this session」，prefs 就被武装并一直留到 10-30 08:25 那次启动；之后按 RUN，`startContest()` 读到 `pendingReplayRunId` 就**静默进入重放**：Q1 取日志第 1 条；完成 QSO 后日志耗尽 → 兜底重开 → Q2 = Q1。
- 这也解释了「用户确认不是重放」：他并没有在**本次会话**点过重放；武装发生在上一次结束时，而且按钮文案「Replay this session」很容易被理解为「再练一局」，界面上也没有任何「本局是重放」的常驻标识。

### 1.7 现场可验证项（诊断包不含 prefs / DB）

1. prefs：`%APPDATA%\com.ssbrunner\ssb_runner\shared_preferences.json` 的 `setting_pending_replay_run_id`（若已被消费则为空，此时看下一条）。
2. 会话历史（prefs 的 `setting_session_history`）：是否存在一条 **0 QSO、起始时间 10-28 16:44** 的记录——那正是被重放的那局（[sessionHistory 写入](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/settings/app_settings.dart#L99-L105)）。
3. DB `event_log_table`：本局（10-30 08:25）的 answer 行数应为 **2 且两条完全相同**——这是兜底重复的直接铁证。
4. 长期可诊断性：给开局与每次出题加日志（见 §3.1-E），这类问题一行日志即可定位。

### 1.8 附带发现

`stopContest()` 里的落库是 fire-and-forget（[contest_manager.dart#L236-L241](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L236-L241)）：

```dart
if (run != null && contestType != null) {
  _saveReview(run, contestType);      // 未 await
  _persistEventLog(run.runId);        // 未 await
  _eventLog.clear();
}
```

用户 STOP 后立刻点「Replay this session」可能读到空/不完整日志：空日志会退化成"重新计算"（同样静默），短日志则触发上面的重复。建议一并收紧，并禁止用 < 2 条 answer 的日志武装重放。

---

## 2. 现象 2：抄错呼号 + F5 → 流程卡住

### 2.1 日志时间线（`logs/latest.log`，UTC）

```
08:26:32.245  QsoEnd -> WaitingSubmitCall        (NextCall，第 2 题开始)
08:26:37.995  WaitingSubmitCall -> WaitingSubmitCall  event=SubmitCall   ← 抄错 2 位后按 F5
08:26:47.997  Retry（10s 定时器）
08:26:49.697  Retry（用户 F7/F1）
08:26:56.864 / 08:26:59.169  Retry
08:27:09 → 08:29:49  每 10.0 s 一次 Retry，共 17 次
08:29:58.861  Voice ended（退出时噪声床停止，handle=1）
08:29:59.501  PlayerStateNotification.stopped
```

关键点：08:26:43 之后**再没有任何音频片段结束事件**（除退出时的噪声床），说明这一题的音频彻底消失；状态机也没有再接受任何有效推进。

### 2.2 根因

1. [single_call_run_state_machine.dart#L84-L116](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L84-L116)
   `SubmitCall` 既不相等、也不算"该重复"时：

   ```dart
   return definition.transitionTo(state.copyWith(audioPlayType: NoPlay()));
   ```

   状态仍是 `WaitingSubmitCall`，但**存进 state 的 `audioPlayType` 被永久改成 `NoPlay`**。

2. [single_call_run_state_machine.dart#L32-L43](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L32-L43)
   `Retry` 用 `copyWith` 复制，`NoPlay` 被原样带走 → F1(CQ)、F7(AGN)、10 秒自动重试**全部静音**。

3. [contest_state_change_handler.dart#L407-L426](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L407-L426)
   `WaitingSubmitCall` 会一直重挂 10 秒 `Retry` 定时器，于是出现日志里"每 10 秒空转、无音频"的循环。

4. 同一条死路的另两个入口：
   - [single_call_run_state_machine.dart#L241-L251](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L241-L251) `CallsignInvalid` 显式 `NoPlay`；
   - [single_call_run_state_machine.dart#L148-L183](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L148-L183) `HeRepeatCorrectCallAnswer` 差异过大时也落到 `NoPlay`，并且**连 `pileupCallsigns` 都丢了**（构造时未传，回落成 `const []`，见 [single_call_run_state.dart#L5-L36](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state.dart#L5-L36)）。

> 对操作员的影响：抄错一次之后，这一题再也听不到呼号（无法靠 AGN 重听），也看不到任何反馈，只能凭记忆猜中正确呼号才能继续 —— 即"卡住"。

### 2.3 附带发现：`QsoEnd` 存在硬冻结

[contest_state_change_handler.dart#L459-L506](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L459-L506)：

```dart
final callsign = _inputHandler.hisCall;
final exchange = _inputHandler.exchange;
if (callsign.isEmpty || exchange.isEmpty) {
  return;            // ← 既没落库，也没有 NextCall
}
```

`QsoEnd` 只注册了 `NextCall` 一个处理器，且 `_setupRetryTimer` 不会为 `QsoEnd` 挂定时器（[#L407-L426](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L407-L426)）。因此一旦在这里提前返回，状态机将**永久停在 `QsoEnd`**，任何按键都无效。

（`handleToState(QsoEnd)` 在进入前要先 `await _playAudioByStateChange(...)` 加载音频，存在"进入后、读取前"输入被清空的窗口。）

---

## 3. 修复方案

### 3.1 现象 1（重放出题重复）

**A. 兜底生成器「续题」而不是「重开」（核心正确性）**

```dart
// contest_manager.dart, startContest()
final recordedAnswers =
    replayEvents.where((event) => event.type == 'answer').toList();
final fallback = ContestAnswerGenerator(
  callsignLoader: _contestDataManager.callsignLoader,
  contestType: contestType,
  mode: mode,
  difficulty: difficulty,
  random: SessionRandom(questionSeed),
);
// 日志已承载前 N 题；兜底必须从第 N+1 题继续，而不是从第 1 题重开（design §5.5）
for (var i = 0; i < recordedAnswers.length; i++) {
  fallback.generateAnswer();
}
final AnswerSource? replaySource = replayEvents.isEmpty
    ? null
    : ReplayAnswerSource.fromEvents(replayEvents, fallback: fallback);
```

更内聚的写法：给 `ReplayAnswerSource` 传 `fallbackFactory: (int skip) => ...`，由它在**首次越界**时按 `_answers.length` 自行快进，`ContestManager` 只负责装配。已用真实呼号池验证：修复后兜底的 Q2/Q3 与同 seed 实时序列逐题一致（见 §1.4）。

> 注意：快进的前提是「重放局的 mode / difficulty / 题意与当前一致」。两者都取自被重放局的 metadata，因此成立；若未来出题算法变更导致每题消耗的随机次数变化，日志条数快进会错位——这正是下面 B、C 要兜的底。

**B. 兜底分支的保险**：`ReplayAnswerSource` 在返回兜底答案前与"上一条已服务答案"比对，呼号 + 序号都相同则重抽（限 5 次）并 `warn`。只作用于**兜底**（`src=seed`），不改变已录制题目的重放保真度。

**C. 让重放「可见且不可静默」——本次 bug 的真正触发点**

1. 一次性 prefs 不跨进程：App 启动时清空 `pendingReplayRunId` / `pendingQuestionSeed` / `pendingAudioSeed`（或改成带"本进程启动时间戳"的 armed 标记，跨进程即失效）。
2. 开局强提示：`startContest()` 若有重放，`score area` 常驻显示 `REPLAY 源 <时间> · 已记录 N 题`；RUN 前弹确认框（"本局将重放 10-28 16:44 的会话，日志 1 题"）。
3. 文案与可用性：按钮改为「用此种子从第 1 题再练」，并在列表项上显示该局 QSO 数；**answer 条数 < 2 的会话直接禁用重放**（0 QSO 的局重放必然从 Q1 重开，没有复现意义）。

**D. `stopContest` 落库可等待**：把 `_persistEventLog` 的 Future 保存起来，或让 `stopContest` 返回 `Future<void>` 并在「重放本局 / 关窗」前 await；同时只在落库成功后才把该局放进可重放列表。避免武装一个空/短日志。

**E. 诊断日志（强烈建议，成本极低）**

- 开局：`run started runId=… source=live|replay(answers=N) seed=… mode=… difficulty=…`
- 每次出题：`answer#k call=… exch=… pileup=[…] src=log|seed`

本次分析之所以绕远，正是因为现有日志只有状态跃迁、完全没有出题信息；加上这两行，同类问题一眼可判。

**F. 回归测试**（`test/replay_test.dart`）：

- 1 条日志 + 兜底 → 第 2 题 = 同 seed 实时的第 2 题，呼号 / 序号 / 堆叠均与第 1 题不同；
- 日志耗尽后连续取 N 题，与「同种子全新生成」从第 N+1 题起逐题一致；
- 兜底与上一条相同（构造极端 case）时的重抽行为；
- prefs 卫生：模拟启动后 `pendingReplayRunId` / `pendingQuestionSeed` 为空。

### 3.2 现象 2（静音死路）

**A. 不再用 `NoPlay` 覆盖整轮音频**：`Retry` 用"本轮默认音频"重建状态，而不是复制可能被改坏的 `audioPlayType`：

```dart
definition.on(Retry, (state, event) {
  final s = state as WaitingSubmitCall;
  return definition.transitionTo(WaitingSubmitCall(
    currentCallAnswer: s.currentCallAnswer,
    currentExchangeAnswer: s.currentExchangeAnswer,
    pileupCallsigns: s.pileupCallsigns,
  )); // 不传 audioPlayType，由构造器重新推导 PlayPileup / PlayCall
});
```

**B. 抄错要有反馈**：现实中喊错呼号，对方不会应答，会继续呼叫。所以
- `WaitingSubmitCall` 抄错且超出阈值 → 回到"重发"分支（继续重放呼号 / pileup），不再静音；
- `HeRepeatCorrectCallAnswer` 差异过大 → 留在重发状态（并补传 `pileupCallsigns`），不要掉到 `NoPlay`；
- `CallsignInvalid` → 同样回到"可重听"的 `WaitingSubmitCall`（默认音频）。

**C. `QsoEnd` 不再硬冻结**：输入为空时也照常推进到下一题；把"输入为空"的拦截放回事件入口（`_handleSubmit`）去挡。

**D. 回归测试**（`test/single_call_run_state_machine_test.dart`，当前没有覆盖 `WaitingSubmitCall` 的错误提交分支）：

- 抄错 2 位 → `SubmitCall` → 得到的仍是能产出 `PlayPileup` / `PlayCall` 的状态；
- 该状态下 `Retry` 必须产出 `PlayPileup` / `PlayCall`（不是 `NoPlay`）；
- `CallsignInvalid` 后的 `Retry` 同样有音频；
- `HeRepeatCorrectCallAnswer` 差异过大后保留 `pileupCallsigns`。

---

## 4. 影响面与风险

| 项 | 影响 |
|---|---|
| 重放保真度 | 修复 A 只影响"日志耗尽之后"的行为，已录制题目仍原样重放；B 只作用于兜底答案 |
| 一次性 prefs | 修复 C-1 会改变"跨进程重放"这一**未设计的功能**：正常产品语义是"下一次开始练习时重放"，跨重启残留属于缺陷，清掉不损失任何已文档化的能力 |
| UI 影响 | C-2/C-3 会新增 REPLAY 标识与确认框，并禁用 < 2 条 answer 的重放；需同步改文案与截图 |
| 记录优先原则 | 不变：`RecordingAnswerSource` 仍逐题记录，新旧日志格式不变，无 DB/JSON 变更 |
| 现象 2 的改动 | 只改状态机内"抄错/非法"分支的落点与音频选择，不动正常答对路径 |
| 其它模式 | S&P 状态机独立，不受影响；Run 模式共用同一状态机，但"抄错继续重发"对 Run 模式同样更真实 |
| 现有测试 | `test/single_call_run_state_machine_test.dart`、`test/replay_test.dart` 只增不删 |

---

## 5. 待决策项

1. 现象 1 的修法：
   - 方案 A：兜底快进（推荐，符合设计 §5.5，已用真实资源验证）
   - 方案 B：日志用完后直接结束本局（不重算），最省事但改变"可继续练习"的产品行为
2. 是否立刻清理跨进程的一次性 prefs（C-1）。**建议必须做**：只修 A 而不修 C，用户下次启动时 bug 仍会静默复现，且依然无法从日志判断。
3. 是否给每个兜底答案加"禁止与上一条相同"的重抽保险（B）。
4. 现象 2 中"抄错后对方继续呼叫"的具体落点：
   - 重放整个 pileup（更像真实 pileup，音更长）
   - 只重发目标呼号（与现有 `HeRepeatCorrectCallAnswer` 一致，改动最小）
5. 是否把 `stopContest` 的落库改为可等待（会改动调用方签名，涉及 UI）。
6. 实施顺序：建议先现象 2（副作用小、收益确定），再按 A → C → B → E 做现象 1；A 与 C 必须同批发布，否则用户侧仍可能见到同题重复。

---

## 6. 附录：关键代码位置

| 主题 | 位置 |
|---|---|
| 出题 / pileup 候选 | [contest_answer_generator.dart#L33-L59](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_answer_generator.dart#L33-L59) |
| 随机流 | [session_random.dart#L9-L51](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/training/session_random.dart#L9-L51) |
| 重放兜底 | [contest_manager.dart#L147-L160](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L147-L160) |
| 录制 / 重放源 | [replay_answer_source.dart#L37-L63](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/training/replay_answer_source.dart#L37-L63) |
| 事件日志落库 | [contest_manager.dart#L243-L273](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L243-L273) |
| 抄错 → NoPlay | [single_call_run_state_machine.dart#L84-L116](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L84-L116) |
| Retry 复制 | [single_call_run_state_machine.dart#L32-L43](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L32-L43) |
| 重发状态差异过大 | [single_call_run_state_machine.dart#L148-L183](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L148-L183) |
| CallsignInvalid | [single_call_run_state_machine.dart#L241-L251](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L241-L251) |
| 状态默认音频 | [single_call_run_state.dart#L5-L36](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/state_machine/single_call/single_call_run_state.dart#L5-L36) |
| 重试定时器 | [contest_state_change_handler.dart#L407-L426](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L407-L426) |
| QSO 落库与推进 | [contest_state_change_handler.dart#L459-L506](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L459-L506) |
| pileup 播放 | [contest_state_change_handler.dart#L360-L385](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_state_change_handler.dart#L360-L385) |
| F5 处理 | [contest_operation_event_handler.dart#L276-L293](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_operation_event_handler.dart#L276-L293) |
| 结果表校正列 | [qso_result_list_cubit.dart#L60-L75](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart#L60-L75) |
| 重放入口 | [training_review_overlay.dart#L113-L130](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_page/training_review_overlay.dart#L113-L130)、[options_setting.dart#L521-L541](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_settings/options_setting.dart#L521-L541) |
| 一次性 prefs（跨进程残留） | [app_settings.dart#L117-L148](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/settings/app_settings.dart#L117-L148) |
| prefs 消费 / 清空点 | [contest_manager.dart#L89-L90](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/contest_run/new/contest_manager.dart#L89-L90) |
| 会话历史写入（0 QSO 局会被记录） | [app_settings.dart#L99-L105](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/settings/app_settings.dart#L99-L105) |
