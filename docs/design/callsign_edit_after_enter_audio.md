# 回车后再修改呼号的音频发送研究

> 状态：研究完成，未实施（2026-11-02）
> 分支：`fix/v0.2.1`
> 范围：Run / Pile-up 与 S&P；SSB 音频与状态流转；不涉及数据库、计分与复盘数据结构
> 关联：[`f5_his_call_state_matrix.md`](f5_his_call_state_matrix.md)、[`../release/0.2.0-alpha-02-zh.md`](../release/0.2.0-alpha-02-zh.md)

---

## 0. 结论摘要

| # | 结论 |
|---|---|
| 1 | 视频现象属实：按 Enter 后继续补全/修改呼号，我方发射音频不会带上新增部分 |
| 2 | 根因不是音频合成，而是 **Enter 事件在部分状态被静默丢弃**、**更正只在“已抄到序号再 Enter”时回读**、**进入等待序号状态时焦点被移到序号框** |
| 3 | 对方（runner）的音频始终使用完整呼号，PY 一定在对方音频里；缺的是我方发射 |
| 4 | 已播出的音频无法回溯修改；可行的是“下一次发射带上更正”或“发送前把输入合并进同一段音频” |
| 5 | 用户提出的“回车后继续往播放队列追加字母”**不能按原样实现**：报告音频是原子片段，追加字母会排在 RST/交换之后 |
| 6 | 可行落地方式：A 分段发射会话（最贴近原想法）、B 静默窗口 + 原子重建（推荐）、C 原子发送 + 更正重发（最小改动） |
| 7 | 推荐先做 **B + C**；只有“回车必须立即出声、后续输入必须实时延长音频”是硬需求时才做 A |

---

## 1. 现象与复现

用户反馈场景：

1. 输入 `BI4M`；
2. 按 Enter；
3. 继续输入 `PY`；
4. 播放出去的音频没有包含 `PY`。

以 Run 模式复现：

| 步骤 | 状态 | 当前行为 |
|---|---|---|
| 输入 `BI4M`，按 Enter | `WaitingSubmitCall` → `ReportMyExchange` | 播放“我方声音的 `BI4M` + 我的序号” |
| 对方回放 | `WaitingSubmitMyExchange` | 对方音频是完整的 `BI4MPY + 序号` |
| 补 `PY`，只改呼号 | 仍 `WaitingSubmitMyExchange` | 只更新 `ContestInputHandler`，不发射 |
| 再按 Enter（未填序号） | — | 兜底分支发出 `SubmitCallAndHisExchange`，该状态没有 handler → 静默丢弃，无音频、无状态迁移 |
| 若填了序号再 Enter | `QsoEnd` | 会先在签字前回读 `BI4MPY` |

所以“更正呼号”目前只在**已经抄到序号并再按 Enter**时才会发声；视频场景没有走到该路径。

S&P 模式下，对方呼号从未加入我方发射音频，签字阶段也没有更正回读，现象更直接。

---

## 2. 当前实现链路

### 2.1 Run 模式的发射链路

1. Enter 由全局键盘事件派发 `OperationEvent.submit`（[`key_event_handler.dart`](../../lib/contest_run/key_event_handler.dart)）。
2. `_handleSubmit` 根据当前状态与输入字段组合决定事件（[`contest_operation_event_handler.dart`](../../lib/contest_run/new/contest_operation_event_handler.dart#L234-L298)）。
3. `WaitingSubmitCall` 下只有呼号、没有序号时，发出 `SubmitCallAndHisExchange(call: 输入呼号)`（[`同文件`](../../lib/contest_run/new/contest_operation_event_handler.dart#L288-L295)）。
4. 状态机把它转成 `ReportMyExchange`，音频类型为 `PlayCallExchange(call: submitCall, exchange: myExchange, isMe: true)`（[`single_call_run_state_machine.dart`](../../lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L47-L70)）。
5. `PlayCallExchange` 把 **呼号 + RST/EXCH + 交换** 拼成一个 `pcmData` 后一次性入队（[`contest_state_change_handler.dart`](../../lib/contest_run/new/contest_state_change_handler.dart#L402-L445)）。
6. `_handleReportMyExchange` 等待音频播完，再延迟 500ms，然后无条件发出 `ReceiveExchange`（[`同文件`](../../lib/contest_run/new/contest_state_change_handler.dart#L548-L570)）。错呼号不退回重抄，而是进入序号阶段、按抄收原样落库，并在 log check 中判无效 + 2 倍 QSO 分值罚分。
7. `ReceiveExchange` 进入 `WaitingSubmitMyExchange`，此时 `submitCall` 仍是 Enter 时的快照。

### 2.2 S&P 链路

- 第一次 Enter：`SpPounce`，只发我方呼号（[`search_and_pounce_run_state_machine.dart`](../../lib/contest_run/state_machine/single_call/search_and_pounce_run_state_machine.dart#L49-L75)）。
- 第二次 Enter：`SpSubmitHisExchange`，只发我方交换并提交。
- `SpQsoEnd` 音频为我方交换 + TU，没有对方呼号回读（[`contest_state_change_handler.dart`](../../lib/contest_run/new/contest_state_change_handler.dart#L341-L359)、[`single_call_run_state.dart`](../../lib/contest_run/state_machine/single_call/single_call_run_state.dart#L186-L210)）。
- 对方呼号只用于日志，字段从实时输入读取。

### 2.3 关键事实

1. **音频是 Enter 时刻的快照**：`submitCall` 在事件生成时固定，后续编辑不会回写已入队的 PCM。
2. **报告音频是原子片段**：`PlayCallExchange` 先 `concatUint8List` 再入队，片段内顺序固定，无法中间插入。
3. **AudioPlayer 只能追加**：`addAudioData` 默认 `isResetCurrentStream: false`，新片段排在当前片段和待播队列之后（[`audio_player.dart`](../../lib/audio/audio_player.dart#L168-L189)）；没有公开的“插入/删除待播片段”能力。
4. **逐字母素材可独立加载**：`AudioLoader` 按字符拼接，可以对增量串单独生成 PCM（[`audio_loader.dart`](../../lib/audio/audio_loader.dart#L119-L136)）。
5. **进入等待序号状态时焦点跳转**：`WaitingSubmitMyExchange` / `SpWaitingHisExchange` 会触发 `fillRst`，把焦点移到序号框（[`contest_running_manager.dart`](../../lib/contest_run/new/contest_running_manager.dart#L156-L165)、[`qso_console.dart`](../../lib/ui/main_page/qso_console.dart#L313-L317)）。报告播放期间焦点仍在呼号框。
6. **CQ WPX 序号框只允许数字**：字母会被输入过滤器丢弃（[`cq_wpx.dart`](../../lib/contest_type/cq_wpx/cq_wpx.dart#L44)）。
7. **素材时长**：`B.wav` 约 0.497s、`M.wav` 约 0.400s；`BI4M` 的呼号段约 1.5–2s，视频中补 `PY` 通常能落在该窗口内。

---

## 3. 根因列表

### G1：Enter 在 `WaitingSubmitMyExchange` 下被静默丢弃

`_handleSubmit` 的兜底分支在“呼号非空、序号为空”时发出 `SubmitCallAndHisExchange`，但 `WaitingSubmitMyExchange` 只处理 `AbandonQso` / `Retry` / `SubmitMyExchange` / `NoCopy`（[`single_call_run_state_machine.dart`](../../lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L278-L332)），事件无 handler，日志出现 `dropped: no handler`，用户侧完全无反应。

`ReportMyExchange` 的过渡窗口同样会把该事件丢弃。

### G2：焦点被移到序号框，后续呼号输入可能落到错误字段

进入 `WaitingSubmitMyExchange` 后 `fillRst` 会把焦点移到序号框。若用户此时继续输入呼号：

- 字符进入序号框；
- CQ WPX 只接受数字，字母被过滤，表现为“输入了但什么都没发生”；
- 呼号字段没有变化，音频自然也不会包含新增部分。

### G3：更正回读只在 `SubmitMyExchange` 时发生

`QsoEnd` 的 `correctedCall` 只在 `SubmitMyExchange` 中比较“输入呼号 vs `submitCall`”后生成（[`single_call_run_state_machine.dart`](../../lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart#L297-L317)），音频在签字前回读（[`contest_state_change_handler.dart`](../../lib/contest_run/new/contest_state_change_handler.dart#L224-L248)）。

如果用户只补呼号、没有抄到序号，就不会走到该路径。

### G4：S&P 从不发射对方呼号

S&P 的设计是“发我方呼号 → 发我方交换”，对方呼号只用于日志，因此不存在“把 PY 发出去”的音频路径。

### G5：`submitCall` 基线与实际发射内容可能脱节

F5 / `;` 在 `WaitingSubmitMyExchange` 下只做 `Retry`，不更新已发送呼号基线，后续签字可能重复回读（[`contest_operation_event_handler.dart`](../../lib/contest_run/new/contest_operation_event_handler.dart#L340-L353)）。如果引入播放中追加，也会出现“音频已经是 BI4MPY、状态仍是 BI4M”的错位。

---

## 4. 期望语义

必须先定义“发送”：

| 方案 | Enter 后行为 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| A 更正即重发 | 呼号有变化时重发一次更正后的内容，再让对方重播 | 直接满足用户预期 | 多一次发射；需要更新已发送基线 | 推荐组合的一部分 |
| B 下次自然发射时补齐 | 只在签字/下一次报告时回读更正 | 最接近真实比赛 | 未抄序号时仍没有即时音频 | 作为兜底 |
| C 仅修复静默丢弃 + 提示 | Enter 不发音频，只提示/重听 | 风险最低 | 不满足“把 PY 发出去” | 过渡 |
| D 逐字符实时发射 | 每次按键都播音 | 直观 | 严重失真、碎片音频 | 不推荐 |

推荐：**A（轻量版）+ B（兜底）**。A 中“重读呼号”与“重发整份报告”是同一套事件设计下的强度差异，需产品确认。

---

## 5. 方案一：原子发送 + 更正重发（最小改动）

### 5.1 目标

按 Enter 后不改变已播放音频，只保证“下一次发射”能带上更正后的呼号。

### 5.2 设计要点

1. 把 `_handleSubmit` 末尾的兜底分支改为显式状态矩阵，覆盖 Run 与 S&P 的各个状态，杜绝静默丢弃。
2. `WaitingSubmitMyExchange` 下：
   - 呼号已变 + 无序号：播放更正呼号（复用 F5 的 `CallsignPayload` 音频，`isMyAudio: true`），或按产品选择重发“呼号 + 我方交换”；随后让对方重播序号。
   - 呼号未变 + 无序号：`Retry` 重听并给提示。
   - 呼号已变 + 有序号：保持现有 `SubmitMyExchange` → `QsoEnd` 回读。
   - 呼号空 + 有序号：提示呼号必填。
3. 新增 `MarkTransmittedCall(call)` 事件，在 `WaitingSubmitMyExchange` 中返回同状态并更新 `submitCall`，同时把 `audioPlayType` 设为 `PlayExchange(his exchange, isMe: false)`，让对方立即重播序号。
4. F5、`;`、Enter 更正分支统一走该事件，避免重复回读。
5. 事件不按 `Retry` 重新布置 10s 定时器，避免自动循环（[`contest_state_change_handler.dart`](../../lib/contest_run/new/contest_state_change_handler.dart#L508-L533)）。
6. 音频顺序：先等待当前音频播完，再发我方更正，再排队对方重播；不要截断对方正在发送的序号。
7. 异步捕获当前状态并做身份校验，防止连续 Enter 触发多次重发。

### 5.3 S&P

- 可选：`SpWaitingHisExchange` 记录 pounce 时的呼号，`SpQsoEnd` 增加 `correctedCall`，签字前回读更正呼号。
- 如果产品坚持 S&P 不发送对方呼号，则只修日志与提示，不新增音频。

### 5.4 风险

- 多一次发射，训练真实度有争议；
- 需要处理“签字二次回读”；
- 需要补齐 Run / S&P 的状态矩阵与测试。

---

## 6. 方案二：播放中追加（用户本轮想法）的可行性

用户设想：

1. 输入 `BI4M`；
2. Enter，音频队列放 `BI4M`；
3. 后续新增继续往队列塞内容；
4. 直到音频播放完，才状态流转。

### 6.1 逐条可行性

| 用户步骤 | 现有架构 | 结论 |
|---|---|---|
| 1 输入 `BI4M` | `onCallEdit` 实时更新输入 | 可行 |
| 2 回车把 `BI4M` 放队列 | `ReportMyExchange` 播放 `PlayCallExchange`，但它是 `呼号 + RST/EXCH + 交换` 的单段 PCM | 能播，但不是“只放 `BI4M`” |
| 3 后续新增继续塞队列 | `addAudioData` 可追加；`AudioLoader` 可单独生成增量串 | 追加的 `P/Y` 会排在整段报告之后：`BI4M ... 59 001 ... P Y`，不是 `BI4M P Y ... 59 001` |
| 4 播完才状态流转 | `_handleReportMyExchange` 已在等待 `isPlaying()` + 500ms | 追加音频会延长等待，但“队列为空”不是可靠的定稿信号；状态里的 `submitCall` 仍是 `BI4M` |

### 6.2 原样不可行的原因

1. **片段原子性**：PCM 生成后不可修改，只能追加新片段或重置重建；`AudioPlayer` 没有插入待播片段的能力。
2. **顺序错误**：报告音频把 RST/交换和呼号放在同一个片段里，追加字母必然落到交换之后。
3. **定稿信号缺失**：队列短暂为空时状态可能已推进；持续输入又会无限延长；需要静默窗口或显式定稿。
4. **状态/音频脱节**：`submitCall` 固定为 Enter 快照，会影响对方是否重复呼号、签字回读与日志一致性。
5. **编辑类型复杂**：退格、粘贴、中间替换无法“撤回已播字母”，需要重置重播或忽略策略。
6. **焦点窗口**：报告播放期间焦点仍在呼号框，这是可行的；但进入 `WaitingSubmitMyExchange` 后焦点跳到序号框，后续输入不再属于同一发射窗口。

### 6.3 落地变体 A：分段发射会话（最贴近原想法）

1. 把 `PlayCallExchange` 拆成“呼号段 + 尾段（RST/EXCH + 交换）”。
2. Enter 后先只入队呼号段并播放。
3. 呼号段播放期间，若输入是最长公共前缀的扩展，只把增量字母生成的片段追加在呼号段之后；尾段暂不入队。
4. 呼号段播完 + 300–500ms 静默后定稿：发出 `FinalizeReport(call)`，更新 `submitCall`，再入队尾段。
5. 尾段播完 → 对方音频 → 状态流转。
6. 需要额外处理：
   - 增量加载异步串行化，避免 P/Y 乱序；
   - 非追加编辑（退格/粘贴/中间修改）的重置或忽略策略；
   - 呼号段与尾段之间的静默窗口会误判 `isPlaying()` 为空，需要“发射会话”标志；
   - 噪声底在静默窗口可能释放，需要保持或占位；
   - 会话看门狗，防止永不流转；
   - 两阶段 `ReportMyExchange` 与 `FinalizeReport` 状态机支持；
   - 定稿后不得触发 `ReportMyExchange` 的 `isResetCurrentStream: true`（[`contest_state_change_handler.dart`](../../lib/contest_run/new/contest_state_change_handler.dart#L249-L258)），否则会截断呼号段。

**评价**：可行，但改动中到大，边界多；音频分段可能有缝隙；慢速输入会超窗；删除无法撤回已播内容。

### 6.4 落地变体 B：静默窗口 + 原子重建（推荐）

1. Enter 后不立即构建/播放报告，先等待一个很短的“输入静默窗口”（例如 300–400ms，按最后一次呼号编辑时间计算；如果 Enter 前已静默足够久，则立即发送）。
2. 窗口内继续输入只更新输入，不触发音频。
3. 窗口结束，用最终呼号一次性生成完整报告（呼号 + RST/交换 + 交换）并原子播放。
4. 现有 `_handleReportMyExchange` 的“音频播完再流转”直接复用。
5. 窗口关闭后的继续修改，走方案一的“更正重发”兜底。
6. 需要防重入：窗口期间再次 Enter、F5、F1 等事件要取消或忽略当前待发送。

**评价**：无插入/分段/顺序问题；退格、粘贴、输入法天然正确；`submitCall` 在发送时就是最终值；改动小。代价是报告最多延迟 0–400ms，且不是“回车立即听到 BI4M”。

---

## 7. 推荐

**推荐 B + 方案一（更正重发）组合。**

| 场景 | 行为 |
|---|---|
| Enter 后短窗口内继续补呼号 | 计入同一份原子报告，一次发出完整呼号 |
| 报告已开始播放后再修改 | 走更正重发/回读，不回溯已播放音频 |
| 已抄到序号再 Enter | 保持现有签字回读 |
| S&P | 只修日志与提示；是否回读需产品确认 |

只有在“回车必须立即出声、后续输入必须实时延长这段音频”是硬需求时，才做变体 A。

从训练真实度看，“边播边追加”并不是真实电台行为；B 的“发送前短暂合并输入”更自然，也不会把“没抄全就先发”变成一种被鼓励的交互。

---

## 8. 边界与风险

1. **重复发射**：更正重发可能多占一次发射时间，需产品接受。
2. **打断对方音频**：更正发送前应等待当前音频播完，不能截断对方序号。
3. **双重回读**：更新 `submitCall` 基线后，签字阶段不应再次回读。
4. **连续按键**：防抖 + 状态身份校验。
5. **焦点**：报告期间呼号框仍有焦点；进入等待序号状态后焦点跳转，后续输入不属于同一窗口。
6. **输入法/粘贴/退格**：B 天然正确；A 需要额外策略。
7. **音频空隙与噪声底**：A 分段后可能出现缝隙与底噪释放；B 无此问题。
8. **看门狗**：A 的发射会话需要最大时长保护。
9. **S&P**：默认不发射对方呼号，是否回读需单独决策。
10. **不改动项**：键位、数据库结构、计分、复盘种子与事件日志结构。

---

## 9. 验证计划

### 9.1 已完成的静态验证

- `PlayCallExchange` 为单段 PCM：已确认。
- `AudioPlayer` 追加语义：已确认。
- `AudioLoader` 可按增量串生成：已确认。
- 报告播放期间焦点仍在呼号框：已确认。
- 素材时长：`B.wav` 0.497s、`M.wav` 0.400s，`BI4M` 呼号段约 1.5–2s。

### 9.2 后续需验证

1. 用 fake audio engine 验证追加顺序，以及“队列短暂为空”时 `isPlaying()` 的行为。
2. 手工复现视频场景，确认日志中是否出现 `dropped: no handler for SubmitCallAndHisExchange in WaitingSubmitMyExchange`。
3. 检查 QSO 行：`call` 是否仍为 `BI4M`、`exchange` 是否为空或被过滤。
4. 模拟慢速输入、退格、粘贴、输入法组合，评估 A 的边界成本。
5. 验证增量字母异步加载是否可能晚于尾段入队（仅 A）。

---

## 10. 待确认问题

1. 更正重发是“只重读呼号”还是“重发整份呼号 + 交换”？
2. 是否接受方案 B 的报告最多延迟 0–400ms？
3. 定稿规则选哪种：静默窗口、呼号音频播完 + 宽限，还是第二次 Enter？
4. S&P 是否需要在签字前回读更正呼号？
5. 非追加编辑（退格/中间替换）在产品上期望“忽略已播内容”还是“重置重播”？

---

## 11. 未来实施清单（当前未实施）

| 优先级 | 改动 | 涉及文件 |
|---|---|---|
| P0 | 诊断日志字段：`hisCall`、`exchange`、当前状态、是否更正 | `contest_operation_event_handler.dart`、`contest_state_change_handler.dart` |
| P1 | Enter 显式状态矩阵，消除静默丢弃 | `contest_operation_event_handler.dart` |
| P1 | 更正重发 + `MarkTransmittedCall` 事件 | `contest_operation_event_handler.dart`、`single_call_run_event.dart`、`single_call_run_state_machine.dart` |
| P1 | 焦点策略：呼号未抄全时不自动跳到序号框 | `contest_running_manager.dart`、`qso_console.dart`、`contest_input_handler.dart` |
| P2 | 静默窗口 + 原子重建（方案 B） | `contest_operation_event_handler.dart`、`contest_input_handler.dart` |
| P2 | S&P 更正回读（可选） | `search_and_pounce_run_state_machine.dart`、`single_call_run_state.dart`、`contest_state_change_handler.dart` |
| P2 | 阶段提示与文案 | `qso_console.dart`、`lib/l10n/*.arb` |
| P2 | 测试：状态机、音频顺序、操作层、回归 | `test/single_call_run_state_machine_test.dart`、`test/contest_state_change_handler_test.dart`、新增操作层测试 |
| P3 | 方案 A 分段发射会话（仅硬需求时） | `contest_state_change_handler.dart`、`audio_player.dart`、状态机与会话协调层 |
