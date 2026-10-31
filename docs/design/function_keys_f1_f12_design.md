# F1–F12 功能键全量支持与 F12 清空输入技术方案

> 状态：需求决策已于 2026-10-31 确认；默认键位按 N1MM 复核后修订（2026-10-31），尚未改代码。
> 分支：`fix/v0.2.1-alpha01`
> 关联文档：[`f1_abandon_round_design.md`](f1_abandon_round_design.md)（F1 放弃当前轮；F1 的“CQ + 中途放弃”双语义保持不变）。
> 范围：所有训练模式（Run、Pile-up、S&P）共用同一套 F1–F12 键位。

---

## 0. 结论摘要

| # | 需求 / 决策 | 结论 |
|---|---|---|
| 1 | 支持 F1–F12 全部功能键 | 键位模型由“动作 → 按键”改为“按键 → 动作 / Spare” |
| 2 | 默认键位对齐 N1MM | F1 CQ、F2 EXCH、F3 TU、F4 `<my>`、F5 `<his>`、F6 B4、F7 AGN、F8 NIL、F9 Spare、F10 Spare、F11 Spare、F12 Wipe |
| 3 | 现有默认键位有意保留 | F1 保留“CQ + QSO 中途放弃”双语义；F6 B4、F7 AGN、F8 NIL 保留现有默认位置（均已发布，用户已形成习惯） |
| 4 | 缺音频资源的 N1MM 消息暂缺省 | N1MM 的 `QRZ?`（F7）与 `Zone?`（F9）无对应动作与音频：F9 默认 Spare，F7 继续承载 AGN；补音频后再升级 |
| 5 | 无行为的按键显示为 `Fn Spare` | 按 F1–F12 固定顺序渲染全部 12 个键；无动作即显示 `Fn Spare` |
| 6 | 配置支持 F1–F12，并支持不配置行为（Spare） | 配置对话框改为逐键配置，每个键可选择动作或 Spare |
| 7 | F12 清空输入 | 新增 `OperationAction.wipe` / `OperationEvent.wipe`；只清输入，不改状态、不播音频、不记日志 |
| 8 | F1 放弃路径不再自动清空输入 | 移除 `_inputHandler.clear()`；残留输入由 F12 手动清空 |

---

## 1. 目标与范围

### 1.1 目标

- 键盘与界面都完整支持 F1–F12，不再只识别 F1–F8。
- 默认键位按 N1MM 的 SSB 功能键布局对齐，但保留已发布的现有习惯：F1 双语义、F6 B4、F7 AGN、F8 NIL。
- 没有配置动作的按键一律显示为 `Fn Spare`，并且按下后不产生任何行为。
- 配置界面按“键”配置：F1–F12 每个键都可选择某个 `OperationAction`，或选择 `Spare`。
- F12 作为“清空输入”的默认键，替代 F1 放弃路径原先的自动清空（见关联文档 §7.1 决策 A）。

### 1.2 不在范围内

- 不新增音频素材：因此不实现 N1MM 的 `QRZ?` 与 `Zone?` 两条默认消息；F9 默认 Spare，F7 继续绑定 AGN。
- 不实现 N1MM 的消息文本、宏、Run/S&P 双套消息文件；本应用仍是一套语义动作。
- 不支持 `Shift` / `Ctrl` / `Alt` + 功能键的组合键。
- 不重映射非功能键（Enter、Esc、Tab、Space、`;` 等保持现状）。
- 不修改状态机、混音算法、数据库结构或事件日志结构。

---

## 2. 现状

| 层 | 现状 |
|---|---|
| 动作定义 | `OperationAction` 只有 8 个动作，各自带 `defaultKey`（F1–F8） |
| 默认键位 | F1 CQ、F2 EXCH、F3 TU、F4 `<my>`、F5 `<his>`、F6 B4、F7 AGN、F8 NIL |
| 持久化 | `AppSettings.binding(action)` 以“动作 → 按键”存储，设置项为 `setting_key_binding_<actionId>` |
| 键位解析 | `functionKeysFromSettings()` 遍历动作生成 `LogicalKeyboardKey → OperationEvent`；结果为空时回退默认表 |
| 键盘处理 | `KeyEventHandler` 只处理已绑定的功能键；`_isFunctionKeyPressed` 保证按住只触发一次 |
| F1 语义 | 普通状态发 CQ；QSO 进行中走 `_onAbandonRound`（见 `_isInFlightQso`） |
| 界面按键板 | `_FunctionKeys` 遍历绑定结果，只显示已绑定的按键；当前 8 个按钮，每行 4 个 |
| 配置对话框 | 每个动作一行，下拉框只提供 F1–F8；按“按键值唯一”校验 |
| 键盘速查 | 只展示 Tab、Shift+Tab、Space、`;`、Enter，未提及功能键 |
| 音频资源 | 只有 `AGN / BEFORE / CONTEST / CQ / EXCH / NO_COPY / NR / PORTABLE / TU_QRZ`，无独立 `QRZ`、`ZONE` |
| F12 | 当前完全未处理 |

现状的关键限制：**“哪些键存在”不是显式配置，而是由动作绑定反推出来**。因此无法表达“F9 存在但没有行为”，也无法让多个键保持 Spare 状态。

---

## 3. 方案设计

### 3.1 键位模型：改为按键为中心

新增 `FunctionKey` 枚举，作为 F1–F12 的唯一来源：

| 字段 | 含义 |
|---|---|
| `label` | `F1` … `F12` |
| `logicalKey` | `LogicalKeyboardKey.f1` … `f12` |
| `defaultAction` | 默认动作，可为 `null`（Spare） |

`OperationAction` 继续描述“行为”，新增 `wipe`（见 §3.4），并移除 `defaultKey`；默认键位改由 `FunctionKey.defaultAction` 表达，避免“动作”和“键位”两套来源。

运行期使用有序的 `FunctionKeyBinding` 列表：

```
FunctionKeyBinding { FunctionKey key; OperationAction? action; }
```

- `action == null` 即 Spare。
- 列表始终包含 12 项，顺序固定 F1 → F12；界面按此顺序渲染。
- 持久化时，Spare 存为字符串 `spare`，其余存 `OperationAction.id`。

选择“按键为中心”而不是继续“动作为中心”的原因：

- N1MM 的功能键消息按位置绑定，同一位置可以为空（Spare）；
- “无行为”是键位本身的属性，而不是某个动作的属性；
- 允许多个键同时为 Spare，不会产生“哪个动作拥有该键”的歧义。

F1 的双语义不通过额外动作表达：F1 的默认动作是 `cq`，`ContestOperationEventHandler._handleCq` 继续保留 `_isInFlightQso` 分支（QSO 进行中 → `onAbandonRound`，否则 → `Retry`）。这样“放弃当前轮”不需要成为可配置动作，也就不会出现“把 Abandon 配到别的键”的歧义。

### 3.2 默认映射（对齐 N1MM，保留两项习惯）

| 键 | 默认动作 | 显示 | 行为 | 与 N1MM SSB Run 的差异 |
|---|---|---|---|---|
| F1 | `cq` | `F1 CQ` | 发送 CQ；QSO 进行中时走放弃当前轮 | **有意保留**：N1MM F1 只发 CQ，本应用保留训练用的中途放弃 |
| F2 | `exchange` | `F2 EXCH` | 发送我方交换信息 | 一致 |
| F3 | `tu` | `F3 TU` | 发送 TU（音频 `TU_QRZ.wav`） | 仅文案差异：N1MM 为 TNX，本应用保留已发布的 TU |
| F4 | `myCall` | `F4 <my>` | 发送本站呼号 | 一致 |
| F5 | `hisCall` | `F5 <his>` | 发送对方呼号 | 一致（N1MM 默认消息体为空，本应用更主动） |
| F6 | `before` | `F6 B4` | 发送 BEFORE | **有意保留**：N1MM 为 Spare；已发布、用户已形成习惯 |
| F7 | `again` | `F7 AGN` | 发送 AGN 并重播当前轮（既有行为） | **有意保留**：N1MM 为 QRZ?，本应用保留已发布的 AGN 位置 |
| F8 | `noCopy` | `F8 NIL` | 发送 NO COPY | **有意保留**：N1MM 为 Agn?，本应用保留已发布的 NIL 位置 |
| F9 | `null` | `F9 Spare` | 无动作 | 暂缺 `Zone?` 音频，默认 Spare |
| F10 | `null` | `F10 Spare` | 无动作 | 一致 |
| F11 | `null` | `F11 Spare` | 无动作 | 一致 |
| F12 | `wipe` | `F12 Wipe` | 清空输入框 | 一致 |

说明：

- 相对现状，默认键位没有位移：F1–F8 的动作、位置与显示文案全部保持，只新增 F9–F12。
- F6、F7、F8 是“占用了 N1MM 非空位”的三个键，属于已发布行为的延续；想完全对齐 N1MM 的用户可在配置里把 F6、F7 改为 Spare、把 F8 改为 AGN。
- `QRZ?` 与 `Zone?` 尚未实现：后续新增动作与音频后，只需把 F7/F9 的默认动作替换为新动作，键位模型与迁移逻辑无需再动。
- F1 的中途放弃语义见关联文档；S&P 中 F1 仍走既有 Retry 语义，不进入放弃分支。
- 所有模式（Run / Pile-up / S&P）共用上表；N1MM 的 Run/S&P 双套键位不在本次范围。

### 3.3 Spare 语义

- Spare 键不产生任何 `OperationEvent`，因此没有音频、没有状态机迁移、没有日志。
- 键盘仍把 F1–F12 全部视为功能键：
  - 按下 Spare 只更新“功能键按住”状态，不派发事件；
  - 松开后正常复位，保证后续按键不会被按住状态卡住。
- 界面显示固定文案 `Fn Spare`。
- Spare 键建议渲染为禁用态（`onPressed: null`），视觉上弱化，避免误以为可执行。

### 3.4 F12 Wipe（清空输入）

新增动作与事件：

- `OperationAction.wipe`：`id = 'wipe'`，`label = 'Wipe'`。
- `OperationEvent.wipe`：`btnText = 'Wipe'`。

处理链路：

1. `KeyEventHandler` 识别 F12 → 派发 `OperationEvent.wipe`。
2. `_playAudioByOperationEvent`：`wipe` 不加载、不播放任何音频。
3. `_handleOperationEventBusiness`：`wipe` → `_inputHandler.clear()`。
4. `ContestInputHandler.clear()` 已有能力：清空 `hisCall` / `exchange` / `isRstFilled`，并通过 `inputControlStream` 通知输入框刷新。

约束：

- **只清输入**：不迁移状态机、不放弃 QSO、不写数据库、不写操作日志、不停止正在播放的音频。
- 在任何状态、任何模式下都可使用。
- 若 QSO 进行中按 F12，当前轮继续，操作员可重新输入。
- 因为 `wipe` 是普通 `OperationAction`，用户可以把 Wipe 配到其他键，也可以把 F12 设为 Spare。

### 3.5 配置界面：逐键配置

把现有“每个动作选一个键”的对话框改为“每个键选一个动作”：

- 固定 12 行，依次为 F1–F12。
- 每行一个下拉框，选项为：
  - `Spare`（无动作）；
  - `CQ`、`EXCH`、`TU`、`<my>`、`<his>`、`B4`、`AGN`、`NIL`、`Wipe`。
- 校验规则：
  - 非 Spare 动作最多出现一次；出现重复时阻止保存，并复用现有 `functionKeysUnique` 提示；
  - 多个 Spare 合法。
- 对话框内容需要可滚动（12 行会超出当前高度），建议使用 `AlertDialog(scrollable: true)` 或限高滚动容器。
- 保存时把 12 个键位一次性写入设置；取消不落盘。
- 打开对话框时以当前实际绑定为准，而不是以默认表为准。

### 3.6 持久化与旧配置迁移

新增设置项：

```
setting_function_key_F1  = 'cq' | 'exchange' | ... | 'wipe' | 'spare'
...
setting_function_key_F12
```

旧设置项 `setting_key_binding_<actionId>` 保留，仅用于迁移，不删除，便于回滚。

读取顺序：

1. 只要存在任意新的 `setting_function_key_*`，就以新设置为准；缺失的新键位按默认表补齐。
2. 否则若存在旧 `setting_key_binding_*`，执行一次迁移：
   - **以 §3.2 的新默认表为底**；
   - 对每个存过键值的旧动作，把它挪到该动作存储的键（即用户的自定义键位）；
   - 若该键已在新默认表中被别的动作占用，用户自定义优先，被挤出的动作置为 Spare，并记录警告日志；
   - 未存过键值的动作按 §3.2 默认表落位；
   - 迁移完成后写入 12 个新设置项。
3. 新旧设置都不存在（全新安装）→ 直接使用默认表。

关键约束：

- **全部 Spare 是合法状态**，不能像旧实现那样在“结果为空”时回退默认表；否则用户无法关闭所有功能键。
- 迁移必须幂等：重复读取不会反复改写，也不会覆盖新设置。
- 旧版本不可能把同一动作配到两个键（旧对话框已做唯一校验），冲突处理只作为脏数据兜底。
- 新旧默认表在 F1–F8 上完全一致，因此迁移不会产生“默认位移”；只有用户自定义过的动作才会改变键位。

### 3.7 事件流

```
KeyDown(Fn)
  → 识别为 FunctionKey
  → 查询 binding
      ├─ action == null → 结束（Spare）
      └─ action != null → OperationEvent
            ├─ cq 且 QSO 进行中 → 放弃当前轮（F1 既有分支）
            ├─ wipe → ContestInputHandler.clear()
            └─ 其余 → 既有处理器
KeyUp(Fn) → 复位功能键按住状态
```

- 保留现有 `_isFunctionKeyPressed` 单次触发保护：按住 F 键只触发一次，松开后才能再次触发。
- F1–F12 全部纳入“功能键按住”状态管理，包括 Spare 键。
- 键盘监听仍通过 `ServicesBinding.instance.keyboard.addHandler` 全局接收，因此输入框有焦点时 F12 也能清空。

---

## 4. 界面改动

### 4.1 功能键按键板

- 固定渲染 12 个按钮，顺序 F1 → F12。
- 沿用现有“每行 4 个、行高由父容器均分”的布局 → 变为 3 行 × 4 列。
- 按钮文案：`'${key.label} ${event?.btnText ?? 'Spare'}'`，例如 `F6 B4`、`F8 NIL`、`F9 Spare`、`F12 Wipe`。
- `Spare` 固定为英文，不翻译，保持与 N1MM 的显示一致；动作简称也继续使用现有英文缩写。
- Spare 按钮禁用，不可点击；可提供“F9 未配置动作”一类提示。
- 需要验证最小窗口尺寸下 12 个按钮不裁切、不溢出。
- F1 按钮沿用 `CQ` 文案；QSO 进行中按它仍走放弃轮（与键盘一致）。

### 4.2 键盘速查

- 在现有速查对话框增加一行：`F12` → 清空输入框。
- 新增本地化文案（如 `keyTipClearInput`）。
- 建议同时补一行 `Esc` → 停止发送（`_handleCancel` 已实现，与 N1MM 一致），说明“停发不等于放弃、也不清空输入”。
- 该行只作为提示；功能键的完整配置仍以按键板与配置对话框为准。

### 4.3 配置对话框

- 按 §3.5 改为 12 行逐键配置。
- 动作下拉框沿用现有简称；新增 `Wipe` 与 `Spare`，并保留 `NIL`、`B4` 作为可选动作。
- 保存前做“非 Spare 动作唯一”校验。
- 旧对话框的“每个命令需要使用不同的功能键”提示可继续复用，或改成“同一动作只能分配给一个功能键”。

---

## 5. 边界与失败场景

| 场景 | 预期 |
|---|---|
| 按下 F9–F11（默认 Spare） | 无事件、无音频、无状态变化；界面显示 `Fn Spare` |
| 按住功能键不放 | 只触发一次，松开后才能再次触发 |
| 所有 12 个键都设为 Spare | 合法；按键板全部显示 Spare；不得回退默认表 |
| 配置时把同一动作配到两个键 | 阻止保存并提示；Spare 可重复 |
| 旧配置迁移时动作冲突 | 用户自定义优先，被挤出者置为 Spare，并记录警告 |
| 新设置只写了一部分键位 | 缺失键位按默认表补齐，不视为全部 Spare |
| QSO 进行中按 F1 | 先播 CQ 音频，再放弃当前轮（既有行为，不改变） |
| QSO 进行中按 F12 | 只清空输入；当前轮继续，不放弃、不写日志、音频继续 |
| F1 放弃后按 F12 | 清掉上一轮残留输入；这正是 F1 文档决策 A 的配套操作 |
| 音频播放中按 F12 | 输入立即清空；音频不停止 |
| 输入框有焦点时按 F12 | 全局键盘处理，仍能清空；F12 不会作为文本输入 |
| Run / Pile-up / S&P | 使用同一套 F1–F12；F1 的既有模式语义不变 |
| 旧用户自定义过功能键 | 迁移后保持其自定义键位；未自定义的键按 §3.2 新默认 |
| 旧用户依赖默认 F7 AGN / F8 NIL | 默认位置不变，与旧版本完全一致 |
| 当前无动作可派发（全部 Spare） | `KeyEventHandler` 返回空事件映射是合法结果，不得回退默认 |

---

## 6. 测试方案

### 6.1 键盘层

1. F1–F12 按下均能被识别为功能键。
2. 已绑定动作的键派发正确 `OperationEvent`；Spare 键不派发。
3. F12 派发 `OperationEvent.wipe`。
4. 按住功能键只派发一次；松开后可再次派发。
5. 全部 Spare 时事件映射为空，且不触发默认回退。
6. F1 在 QSO 进行中仍进入放弃分支，非进行中仍为 `Retry`。

### 6.2 设置与迁移层

7. 全新配置 → 默认表正确（F1 CQ、F2 EXCH、F3 TU、F4 `<my>`、F5 `<his>`、F6 B4、F7 AGN、F8 NIL、F9–F11 Spare、F12 Wipe）。
8. 旧 `setting_key_binding_*` → 以新默认表为底叠加用户自定义；被挤出的动作置 Spare 并告警。
9. 全部设为 Spare → 保存后读取仍为全部 Spare。
10. 部分新键位存在 → 缺失键位按默认表补齐。
11. 迁移冲突脏数据 → 自定义优先，其余 Spare，并产生警告日志。
12. 迁移幂等：连续读取不会改写新设置。

### 6.3 Handler 层

13. `OperationEvent.wipe` 在 `WaitingSubmitCall`、`HeAskForExchange`、`WaitingSubmitMyExchange`、`ReportMyExchange` 以及 S&P 各状态下都只调用 `_inputHandler.clear()`。
14. `wipe` 不触发状态迁移、不播放音频、不写 QSO / 操作日志。
15. F1 放弃路径不调用 `_inputHandler.clear()`（与关联文档 §7.1 决策 A 一致）。
16. F12 清空后，下一次输入与提交按现有逻辑工作。

### 6.4 界面层

17. 功能键按键板固定显示 12 个按钮，顺序 F1–F12；F6 显示 `B4`、F8 显示 `NIL`，F9–F11 显示 `Spare`。
18. Spare 按钮显示 `Fn Spare` 且不可点击；最小窗口下无裁切。
19. 配置对话框显示 12 行，能选择 Spare / Wipe / NIL / B4；重复动作被阻止保存。
20. 键盘速查包含 F12 清空输入（以及 Esc 停止发送）提示。

### 6.5 回归

21. F1–F6 默认动作与既有交互不变（F1 双语义、F6 B4）。
22. F1–F8 的默认动作与位置完全不变；F9–F11 为 Spare、F12 为 Wipe。
23. S&P、Run、Pile-up 的现有状态机与音频行为不变。
24. 无关键（Enter、Esc、Tab、Space、`;`）行为不变。

---

## 7. 改动文件清单

| 文件 | 改动 |
|---|---|
| `lib/contest_run/key_event_handler.dart` | 新增 `FunctionKey` 与默认映射；补全 F1–F12；新增 `OperationEvent.wipe`；Spare 不派发事件 |
| `lib/settings/app_settings.dart` | 新增 `OperationAction.wipe`；键位读写改为按键为中心；旧配置迁移；全部 Spare 合法 |
| `lib/contest_run/new/contest_operation_event_handler.dart` | `wipe` 的音频分支（无音频）与业务分支（`_inputHandler.clear()`）；保留 `_handleCq` 的 F1 放弃分支 |
| `lib/ui/bottom_panel/qso_operation_area.dart` | 按 F1–F12 固定渲染 12 个按钮；Spare 文案与禁用态 |
| `lib/ui/main_settings/options_setting.dart` | 配置对话框改为逐键配置；12 行；Spare 选项；唯一性校验；滚动 |
| `lib/ui/main_page/key_tips.dart` | 增加 F12 清空输入提示（建议同时补 Esc 停止发送） |
| `lib/l10n/app_en.arb`、`app_zh.arb`、`app_zh_Hans.arb`、`app_zh_Hant.arb`、`app_ja.arb` | 新增清空输入提示与 Spare 提示文案（`Spare` 标签本身不翻译） |
| `test/` | 键盘、设置迁移、Handler、界面与回归用例 |

不改：状态机、混音算法、数据库结构、事件日志结构。

---

## 8. 实施顺序

1. 定义 `FunctionKey`、默认映射（含 F1 双语义、F6 B4）与 `OperationAction.wipe`。
2. 改造设置读写与旧配置迁移，保证“全部 Spare”不被默认表覆盖。
3. 改造 `KeyEventHandler`：识别 F1–F12、Spare 不派发、F12 派发 `wipe`。
4. 在操作事件处理器中实现 `wipe`（只清输入）。
5. 改造按键板、配置对话框、键盘速查与本地化。
6. 补齐测试并执行回归。

---

## 9. 决策记录（2026-10-31）

| 决策 | 结论 |
|---|---|
| 默认键位是否整体对齐 N1MM | **尽量对齐**：F2、F3、F4、F5、F10–F12 与 N1MM 一致；F1、F6、F7、F8 保留现有习惯；F9 因无音频暂为 Spare |
| F1 语义 | **保留 CQ + QSO 中途放弃**，不拆成独立键，也不做可配置的 Abandon 动作 |
| F6 默认动作 | **保留 B4**（已发布，用户已形成习惯），不随 N1MM 改为 Spare |
| F7 默认动作 | **保留 AGN**（已发布习惯），不随 N1MM 改为 QRZ? |
| F8 默认动作 | **保留 NIL**（已发布习惯），不随 N1MM 改为 Agn? |
| F3 显示文案 | **保留 TU**（已发布文案），不随 N1MM 改为 TNX；音频继续用 `TU_QRZ.wav` |
| 输入框是否在 F1 放弃后自动清空 | **A：不自动清空**；引入 F12 手动清空 |
| 池耗尽时的降级 | **B：允许旧目标降级为主音继续**（见关联文档） |
| 是否强制旧目标出现在本轮 PILE-UP | **A：强制，索引 ≥ 1**（见关联文档） |
| 功能键范围 | **F1–F12 全部支持** |
| 无行为按键显示 | **`Fn Spare`**，固定英文，不翻译 |
| 配置能力 | **逐键配置 F1–F12**，支持选择 Spare |
