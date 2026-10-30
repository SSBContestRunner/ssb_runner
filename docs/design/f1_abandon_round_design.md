# F1 放弃当前 QSO 并开启下一轮（Run / Pile-up）技术方案

> 状态：方案已落盘，**待确认 §7 的三项决策**，尚未改代码。
> 分支：`fix/v0.2.1-alpha01`
> 模式范围：Run、Pile-up；S&P 不在范围内。

---

## 0. 结论摘要

| # | 需求 | 现状 | 结论 |
|---|---|---|---|
| 1 | QSO 进行中按 F1 = 放弃当前轮并开始下一轮 | 已实现（`AbandonQso` 事件） | 保留，仅调整取题方式 |
| 2 | 被放弃的台应继续留在 PILE-UP 池，但不再是主音频 | **未实现**：目标被永久移出池，新一轮列表不包含它 | 需改生成器 |
| 3 | F1 不再顺带重置输入框 | 当前 `abandonRound` 无条件 `_inputHandler.clear()` | 待确认（§7.1） |

---

## 1. 目标与范围

- QSO 进行中按 F1：放弃当前轮（不记日志），立即开始下一轮，让来台重新争抢回复机会。
- 被放弃的目标台：
  - 回到候选池，后续轮次仍可能被抽中为目标；
  - 在 PILE-UP 模式下继续“在呼叫”，但**不得是新主音频**。
- S&P 模式完全不动：F1 在 S&P 中仍走原有 Retry 语义。

术语对齐：

- **池** = `ContestAnswerGenerator._remainingCallsigns`（尚未作为目标抽出的呼号）
- **轮次呼号列表** = `ContestAnswer.pileupCallsigns`
- **主音约定** = `pileupCallsigns[0]` 是主音，`[1..]` 是干扰音（见 `PlayPileup` 混音实现）

---

## 2. 现状链路

1. F1 → `OperationEvent.cq` → 先播自己的 CQ 音频 → `_handleCq`
   - `lib/contest_run/key_event_handler.dart`：F1 映射
   - `lib/contest_run/new/contest_operation_event_handler.dart`：`_playAudioByOperationEvent` 先发声
2. QSO 进行中时 `_isInFlightQso` 为真，调用 `onAbandonRound`
   - 覆盖状态：`HeRepeatCorrectCallAnswer`、`HeAskForExchange`、`WaitingSubmitMyExchange`、`ReportMyExchange`
3. `abandonRound`（`lib/contest_run/new/contest_state_change_handler.dart`）：
   - 取消重试定时器
   - 等待音频播完（`_waitAudioNotPlaying`）
   - 校验状态未被推进（`identical(currentState, abandonedState)`）
   - `_inputHandler.clear()`
   - `_generateNextAnswer()` → `_stateMachine.transition(AbandonQso(...))`
4. 生成器（`lib/contest_run/new/contest_answer_generator.dart`）：
   - 用 swap-remove 抽取目标，目标**永久移出池**
   - `pileupCallsigns = [目标, 随机次要呼号...]`，次要呼号从池中抽取
5. 音频（`lib/contest_run/state_machine/single_call/single_call_run_state.dart`）：
   - `WaitingSubmitCall` 在列表长度 > 1 时使用 `PlayPileup`，否则 `PlayCall`
   - `PlayPileup` 混音（`contest_state_change_handler.dart`）以 `clips.first` 为主音

### 2.1 差距

| 差距 | 影响 |
|---|---|
| 目标被永久移出池 | 被放弃的台不会在后续轮次再出现，池被无效消耗 |
| 新一轮 `pileupCallsigns` 完全重新抽取 | 旧目标不在新一轮 PILE-UP 中，听不到他继续抢答 |
| `abandonRound` 无条件清空输入框 | 与真实操作不符（F1 不应顺带改动输入框） |

---

## 3. 方案设计

### 3.1 `AnswerSource` 契约变更

`generateAnswer()` 增加可选参数 `requeueCallsign`：

- 语义：把该呼号归还候选池；本轮若为 PILE-UP，则让它在混音里以非主音身份出现。
- `ContestAnswerGenerator`：实现归还 + 抽取 + 构建列表。
- `ReplayAnswerSource`：忽略该参数，按录制顺序返回（录制时列表已包含归还者）。
- `RecordingAnswerSource`：透传参数并照常录制。
- 测试替身（`_FixedAnswerSource` 等）：同步签名。

选择“参数”而非“先 requeue 再 generate”的独立方法，原因是**归还与抽题必须原子完成**，否则中间态可能让旧目标被抽为主音。

### 3.2 `ContestAnswerGenerator` 算法

固定顺序：

1. 归一化 `requeueCallsign`；为空则完全走现有逻辑。
2. 若池为空且存在 `requeueCallsign` → 按 §7.2 的策略处理。
3. 从池中正常抽取主目标。此时被放弃的呼号**尚未回到池**，因此不可能被抽为主音。
4. 构建 `pileupCallsigns`：
   - `TrainingMode.pileup`：`[主目标, 被放弃呼号, ...随机次要呼号]`，被放弃呼号固定在索引 ≥ 1；
   - `TrainingMode.run`：保持 `[主目标]`，本轮不混音；
   - 容量 = 池剩余 + 主目标 + 归还者；需去重并校验去重后长度。
5. 生成完成后，把 `requeueCallsign` 追加回池（仅一次），使其在**后续轮次**可再次成为主目标。
6. 保持不变式：
   - `pileupCallsigns` 无重复；
   - 索引 0 为主音；
   - 归还者 ≠ 索引 0；
   - 历史目标与当前轮不重叠（不传 `requeueCallsign` 时仍成立）。

### 3.3 `abandonRound` 改动

- 从当前 in-flight 状态取 `currentCallAnswer` 作为 `requeueCallsign`。
- 只在放弃路径传参；`QsoEnd` 正常推进逻辑不变。
- 保留三层保护：等待音频、状态同一性校验、异常时仍推进。
- 日志新增字段 `requeuedCallsign`，便于线上核对。
- 状态机事件 `AbandonQso` 与 `_abandonedRound` **无需改动**，已携带新的答案与呼号列表。

### 3.4 音频主/次不变式

- 不修改 `mixPileup`。
- 需要在代码注释中固化两条契约：
  - `pileupCallsigns[0]` = 主音；
  - `pileupCallsigns[1..]` = 干扰音。
- 当本轮只剩 1 个呼号时会退化为 `PlayCall`，属于预期降级。

### 3.5 回放与持久化

- 答案由 `RecordingAnswerSource` 录制，`pileupCallsigns` 已含归还者，回放可完整重现。
- 不改事件结构、不改数据库结构。

---

## 4. 边界与失败场景

| 场景 | 预期 |
|---|---|
| 池中只剩被放弃的呼号 | 按 §7.2 决策：结束本轮序列，或允许其降级为主音继续 |
| 连续按 F1 | 每次只显式归还当前目标；此前已回池的呼号正常参与随机抽取，不重复插入 |
| 呼号大小写/空格 | 统一 `normalizeCallsign` 后再比较与回池 |
| 音频仍在播放 | 沿用等待 → 状态若已推进则放弃本次 F1 |
| 输入框残留 | 见 §7.1 |
| 非 in-flight 状态按 F1 | 保持现有 `Retry()`（重播 CQ），不进入放弃逻辑 |
| Run 单人模式 | 归还回池，但本轮不加入混音列表 |
| S&P | 不触碰 |

---

## 5. 测试方案

### 5.1 生成器层

1. 传入 `requeueCallsign` 后：主目标 ≠ 被放弃呼号；列表包含该呼号且索引 ≥ 1；无重复。
2. 归还后可在后续轮次重新成为主目标（小池全量抽取验证）。
3. 小池 / 空池终止语义仍正确（保留现有“不无限循环”用例）。
4. Run 模式下归还者不进入本轮 `pileupCallsigns`。
5. 回放：录制的含归还者答案原样播放。

### 5.2 Handler 层

6. 四个 in-flight 状态下 F1 → 进入 `WaitingSubmitCall`，新目标 ≠ 旧目标；PILE-UP 模式下 `pileupCallsigns` 含旧目标。
7. F1 在非 in-flight 状态仍为原 Retry 行为。
8. 放弃时池耗尽 → `onAnswersExhausted` 仍被调用，状态机不冻结。
9. 输入框行为按 §7.1 的确认结果断言。

兼容性：现有 `test/replay_test.dart` 的“历史目标不再出现在 pileup”断言不会失败，因为该用例不传 `requeueCallsign`。

---

## 6. 改动文件清单

| 文件 | 改动 |
|---|---|
| `lib/contest_run/new/contest_answer_generator.dart` | `AnswerSource` 签名 + 归还/抽取/构建列表 |
| `lib/training/replay_answer_source.dart` | 实现新签名（忽略 / 透传） |
| `lib/contest_run/new/contest_state_change_handler.dart` | `abandonRound` 传 `requeueCallsign`；日志字段；输入框策略 |
| `lib/ui/bottom_panel/qso_operation_area.dart` | 可选：提示文案 |
| `test/replay_test.dart` | 生成器新用例 + 替身签名 |
| `test/contest_state_change_handler_test.dart` | 放弃路径用例 + 替身签名 |

不改状态机、不改混音算法、不改数据库结构。

---

## 7. 待确认决策

### 7.1 输入框是否在放弃后自动清空

- **A：保留**（不再调用 `clear()`）：贴近 N1MM“F1 不改输入框”的行为，但旧序列号会残留。
- **B：清空**：避免旧轮输入在下一轮被误提交。

结合最初反馈，倾向 **A**；若无法接受误提交风险则选 **B**。

### 7.2 池耗尽时的降级

- **A：结束本轮序列**（保证“旧目标不是主音”）
- **B：允许旧目标降级为主音继续**（保证训练不中断）
- 建议 **A**。

### 7.3 是否强制旧目标出现在本轮 PILE-UP 混音

- **A：强制**（固定塞入索引 ≥ 1，立刻还能听到他在抢答）——本方案默认。
- **B：仅回池**（后续轮次按概率出现，本轮不一定可闻）。
- 建议 **A**。
