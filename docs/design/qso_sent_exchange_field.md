# QSO 控制台「我方交换」只读字段技术方案

> 状态：已评审，D1–D8 决策已固化（2026-11-01），待实现
> 需求：在【呼号】【RST】之后增加只读的【我方交换】，与【对方交换】（原「交换信息」）并排；该字段不允许修改，只能在 **设置 › 比赛与电台 › 我的电台** 修改。
> 关联：[`contest_station_exchange.md`](./contest_station_exchange.md)（我方 exchange 的模型与来源）、[`ui_rework_a_console_design.md`](./ui_rework_a_console_design.md)（控制台布局）
> 原型：[`sent_exchange_field_prototype.html`](./sent_exchange_field_prototype.html)

---

## 1. 结论摘要

1. **这不是一个"新设置"，而是一个只读投影。** 我方 exchange 已经存在：
   `ContestDefinition.myExchangePlan`（比赛决定字段集）+ `StationExchangeConfig`（显式值/呼号派生）+ `buildMyExchange(qsoNumber)`（含序号与补零）。新字段只是把它显示出来，**不新增持久化、不改数据库、不改状态机、不改音频**。
2. **字段只显示 RST 之后的交换部分。** RST 已由独立的 `RST` 字段承担（固定 `59`）；`buildMyExchange` 返回的也正是「去掉 RST 的交换」（CQ WW 的 `05`、WPX 的 `001`、ARRL 的 `100`）。
3. **显示值与实际播报形态一致（含补零）**：设置里 CQ 分区填 `5`，字段显示 `05`，因为音频读的是 "zero five"。设置页（D4 已确定）再显示一次「发射内容：59 05」，把两种表示连起来。
4. **只读的实现方式**：非焦点、非输入、不可 Tab 停留；RST 与我方交换置灰，我方交换加锁图标 + 悬浮提示；待机时可点击锁图标深链到设置页对应字段（D5 已确定，运行中禁用）。
5. **N1MM 复核与最终布局**：序号类比赛（WPX）的 Entry 行是 `Call → Snt → SentNr → Rcv → Exch`，`SentNr` 就是我方交换；固定交换比赛（CQ WW）会隐藏 `SentNr`。**已决策：固定采用 `Call → RST → 我方交换 → 对方交换`；RST 与我方交换置灰、窄栏、不可聚焦，主要宽度留给呼号与对方交换。**
6. **决策已全部固化**：D1 A、D2 独立、D3 不冻结、D4 加预览、D5 加（运行中禁用）、D6 不写入且日志表头改「对方交换」、D7 固定四栏、D8 始终显示。见 §10。

---

## 2. 现状与证据

| # | 位置 | 事实 | 影响 |
|---|---|---|---|
| E1 | `lib/ui/main_page/qso_console.dart:334-390` | 输入区只有三个字段：呼号（可编辑）、RST（只读、`59` 靠 F 键填充）、交换信息（可编辑 = **对方**发来的交换） | 操作员看不到"我方发什么" |
| E2 | `qso_console.dart:358-388` | RST 只读并带 `auto` 后缀；交换框是 F 键（F2/F5）后的焦点落点 | 新字段不能抢焦点，否则会打断 F2→输入的流程 |
| E3 | `lib/contest_type/contest_type.dart:4-13` | `ContestType.buildMyExchange(int qsoNumber)` 已存在，返回**可直接朗读**的我方交换 | 显示值有唯一权威来源 |
| E4 | `lib/contest_type/station_exchange.dart:207-243` | 构造逻辑集中在 `StationExchangeBuilder`（plan + config + 呼号 + DXCC + 位数） | 无需在 UI 里重复一遍规则 |
| E5 | `lib/contest_run/new/contest_operation_event_handler.dart:300-312` | 实发值 = 本局 QSO 表**原始行数** + 1 → `buildMyExchange` | 序号口径必须与显示一致（见 R1） |
| E6 | `lib/settings/app_settings.dart:94-117` | 按 contest 持久化，写入时 `settingsRevision++` | UI 可用 `settingsRevision` 刷新预览 |
| E7 | `lib/ui/main_page/settings_sheet.dart:904-963`、`:371-396` | 我的电台：呼号 + 按 plan 动态字段；运行中整页禁用并提示 | 满足"只能在设置改"的约束，无需新编辑入口 |
| E8 | `lib/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart:21-42`、`qso_result.dart:5-25` | 列表按 runId watch 原始行，**含 DUPE 行** | 列表长度 = `_myExchange()` 的行数口径，可直接用 |
| E9 | `lib/ui/main_app/main_app.dart:156-160` | 窗口最小 1024×650 | 四字段必须能在 1024 宽下不换行 |
| E10 | `test/ui/qso_console_test.dart:217-255` | 控制台测试在 660/668/874 宽度渲染 | 新增字段后必须仍无溢出 |

**最小可用宽度核算**：1024 − 主区左右 padding 32 − 侧栏 14 − 侧栏 310 − 控制台内 padding 28 = **640px**；四栏 + 3×10 间距后可用 610px。

### 2.1 N1MM 复核（2026-11-01，修订）

> **修订说明**：初版只核对了 CQ WW（固定交换），误把"我方交换不在录入行"当成了通例。经补充核对序号类比赛（Entry 窗口主截图），N1MM 的行为是**按交换是否可变来决定是否显示 `SentNr`**。以下为修订后的结论。

**两类比赛的 Entry 行（均为 N1MM 手册截图核对）**

| 类型 | 示例 | Entry 行（从左到右） | 我方交换 |
|---|---|---|---|
| 可变交换（序号） | CQ WPX | `Call` → `Snt` → **`SentNr`** → `Rcv` → `Exch` | **显示在第 3 格**，随 QSO 递增 |
| 固定交换 | CQ WW | `Call` → `Snt` → `Rcv` → `CQ-Zone` | **隐藏**（交换在 Contest Setup 里固定，`SentNr` 不显示） |

证据：

- 序号比赛的 Entry 主截图（`https://n1mmwp.hamdocs.com/manual-windows/entry-window/` 顶部图）：标题从左到右为 `Snt`、`SentNr`、`Rcv`、`Exch`，`SentNr` 框内为 `0`；
- CQ WW 截图（`Setting up for a Contest` → "Trying It Out"）：只有 `Snt`（59）、`Rcv`（59）、`CQ-Zone`（8）三格，`SentNr` 被隐藏；
- 手册《The Info Window》："The sent exchange ... is shown in the title bar ... Example: Exch: 59 002"（Info 标题栏是第二处显示，不是唯一一处）；
- 手册 FAQ：改完已记录的 sent serial 后，"you'll see the **Sent Nr field** increment properly"（确认 Entry 行存在 Sent Nr 字段）；
- UDC 编辑器：Entry 字段帧文本顺序 `SntRpt SntNR RcvRpt NR`，与 WPX 截图的 4 个交换格一致。

**字段映射（本 App 的简化视角）**

| N1MM | 本 App | 说明 |
|---|---|---|
| `Snt`（发送 RST） | `RST` | 本 App 发送/接收恒为 59，合并为一格；N1MM 另有 `Rcv` |
| `SentNr`（发送交换） | **我方交换** | 序号比赛显示；固定交换比赛 N1MM 隐藏 |
| `Rcv`（接收 RST） | `RST`（同一格） | 合并 |
| `Exch`（接收交换） | **对方交换** | 日志里记录的就是这一项 |

**结论**：

1. N1MM 的顺序是 **发送 → 接收**：`Snt → SentNr → Rcv → Exch`。
2. 映射到本 App（RST 合并）后，正确顺序是 **`呼号 → RST → 我方交换 → 对方交换`**，本方案已按此定稿（§4.4）。
3. N1MM 只在交换可变时显示 `SentNr`；本 App 出于训练目的选择**始终显示**（D8 已确定），固定交换比赛也能看到将发送的值。
4. N1MM 把发送/接收 RST 分成两个框；本 App 两者恒为 `59`，合并为一个 RST 框。这是既有简化，不在本方案内拆开。

---

## 3. 目标与非目标

### 3.1 目标

1. 操作员在同一个控制台里能一眼看到「他要发什么」与「我要发什么」，减少把**我方交换**误填进「对方交换」的训练错误。
2. 该值按实际播报形态显示（含补零），并与发送时取值的规则一致；随比赛 / 呼号 / 设置 / QSO 数自动变化。
3. 只读：不可编辑、不抢焦点、不进入 Tab 序列；修改只能去设置页。
4. 零迁移：不新增 SharedPreferences 键、不改 Drift schema、不改 QSO 记录。
5. 支持 1024×650 最小窗口，不引入新的换行或溢出。

### 3.2 非目标

- 不把我方交换写进日志表 / 复盘 / 重放（沿用 `contest_station_exchange.md` §15 的 D6 决定）。
- 不改日志表结构；仅把表头文案「交换信息」改为「对方交换」。
- 不改音频、状态机、计分、`ExchangeManager`、`allowExchangeRegex`。
- 不做"每次 QSO 可改我方交换"（与需求冲突，会导致实发值与设置不一致）。
- 不改 RST 的语义（始终为 59）；只把它改为**常显 + 置灰**，不再依赖 F2 写入。

---

## 4. 交互设计

### 4.1 字段语义

| 项 | 取值 |
|---|---|
| 内容 | `buildMyExchange(qsoNumber)` 的返回值：RST 之后的交换（`05` / `001` / `100` / `TX` / `10`） |
| 形态 | **实际播报形态**，数字按比赛位数补零（`formatExchangeNumber`） |
| 来源 | 设置（显式值）> 呼号派生 > 序号自动生成 |
| 可编辑 | 否；`readOnly` + 不参与焦点 + 无输入法 |
| 变化时机 | 切比赛、改呼号、改 station 字段、每条 QSO 落库（WPX 序号） |

> 为什么不含 RST：控制台已有独立 RST 字段（`59`），`buildMyExchange` 本身也不含 RST；把 `59` 再拼一次会让同一行出现两个 `59`。若希望"完整一句话"，见决策 D2（原型可切换）。

### 4.2 各比赛显示对照

| Contest | plan | 设置来源 | 字段显示 | 备注 |
|---|---|---|---|---|
| CQ WPX SSB | 自动序号 | 无 | `001` → `002` … | 每条 QSO 落库后指向下一个序号（D3） |
| CQ WW SSB | `cqZone` 1..40 | 显式值 / 呼号 cqz | `05` / `24` | 填 `5` 显示 `05`（音频 zero-five） |
| IARU HF | `ituZone` 1..90 | 仅显式（素材无 ituz） | `08` | 未填时显示 `—`，且 RUN 被拦截 |
| ARRL DX SSB（DX 台） | `power` 1..1500 | 显式 | `100` | 原样，不补零 |
| ARRL DX SSB（W/VE 台） | `stateProvince` | 显式 | `TX` | 字母，逐字母朗读（既有 R1） |
| JIDX SSB（JA 台） | `prefecture` 01..50 | 显式 | `10` | 补两位 |
| JIDX SSB（非 JA 台） | `cqZone` 1..40 | 显式 / 呼号 cqz | `24` | 与 CQ WW 同源 |

### 4.3 标签命名（D1）

现有「交换信息」是一个中性词；一旦并排出现两个交换字段，方向必须由标签本身说清。

| 方案 | 中文 | English | 日本語 | 评价 |
|---|---|---|---|---|
| **A（已确定）** | 呼号 / RST / **对方交换** / **我方交换** | Call / RST / **Rcvd** / **Sent** | コールサイン / RST / **受信交換** / **送信交換** | 两个两字标签对称、无歧义；改动只是 ARB 值 |
| B（已否决） | 呼号 / RST / 交换信息 / 我方交换 | Call / RST / Exchange / Sent | … / 交換情報 / 送信交換 | 不动旧文案，但"交换信息"仍不指明方向 |
| C（已否决） | 呼号 / RST / 交换信息 / 我给对方的交换信息 | … / Exchange / My exchange | … | 最小宽度仍能显示，但视觉重量明显大于其它三栏，日文/英文更长 |

**D1 已确定 A。** 日志表头 `tableExchange` 同步改为「对方交换」（英文 `Rcvd`、日文 `受信交換`），因为它记录的就是收到的交换；这不是新增列，只是文案变更。

### 4.4 最终布局（2026-11-01 已确定）

固定采用 N1MM 的四栏顺序，不再提供其他布局：

```
┌──────────────┬────────┬─────────────┬──────────────┐
│    呼号      │  RST   │ 我方交换(锁)│   对方交换    │
│ flex 34      │   9    │     14      │      34       │
│ 可编辑       │ 置灰   │    置灰     │   可编辑      │
└──────────────┴────────┴─────────────┴──────────────┘
```

- 顺序：`Call → RST → 我方交换（SentNr）→ 对方交换（RcvdNr）`。
- **RST 与我方交换**：只读、不可聚焦、置灰（同上样式），不占主要宽度。
- **呼号与对方交换**：可编辑，合计约 **75%** 宽度。
- RST 不再保留 `自动` 后缀（太窄）；固定显示 `59`。
- 我方交换保留锁图标 + tooltip。
- 已否决："三栏 + 信息条"（只对应 N1MM 固定交换形态）、"我方在后"（方向相反）。

宽度核算（控制台内宽 640、间距 10×3）：

| 字段 | flex | 宽度 | 内容可用 | 适配 |
|---|---|---|---|---|
| 呼号 | 34 | 228 | 202 | 6–7 位呼号 |
| RST | 9 | 60 | 34 | `59` ≈ 26px |
| 我方交换 | 14 | 94 | 49（扣锁） | `003` ≈ 40px |
| 对方交换 | 34 | 228 | 202 | 分区 / 序号 / 功率 / 州省 |

1280 宽窗口（控制台内宽 842）：`303 / 80 / 125 / 303`。1024 最小窗口不换行。

> 若某些平台的字体度量更大，只需把 RST / 我方交换的内部水平 padding 从 13 降到 10，或字号降到 20；flex 比例不变。

### 4.5 只读的可感知性

1. **视觉**：**RST 与我方交换都使用置灰固定样式**（`surfaceContainerHighest` 填充 + 轻微斜纹、`onSurfaceVariant` 文字、浮动标签非 primary）；呼号与对方交换保持白底 + primary 浮动标签。
2. **锁图标**：我方交换 `suffixIcon` 放 14px 锁 + `Tooltip`：`固定值 · 在 设置 › 比赛与电台 › 我的电台 修改`；RST 太窄，不放后缀，靠灰底表达只读。
3. **RST 常显 59**：不再依赖 F2 写入；F2 仍把焦点交给对方交换框（`_fillRst()` 改为只跳焦点）。
4. **不可聚焦**：`FocusNode(canRequestFocus: false)` 或外层 `ExcludeFocus`；`onTap` 不聚焦键盘，避免与 F2/F5 的焦点链冲突。
5. **可访问**：`Semantics(label: '我方交换，只读，05')`；tooltip 同时是语义信息来源。
6. **深链（D5 已确定）**：待机时点击锁图标 → `showSettingsSheet(context, initialTab: SettingsTab.contestStation, focusFieldKey: SettingsFocusKeys.exchangeField(fieldId))`；运行中禁用点击，tooltip 改为「比赛进行中无法修改；停止后可改」。

### 4.6 空值 / 未配置

| 情况 | 显示 | 说明 |
|---|---|---|
| 运行中 | 不会为空 | RUN 门槛已保证（`settings_readiness.dart:12-87`） |
| 待机且字段缺失（如 IARU 未填 ITU） | `—` | tooltip 提示去设置；设置页已有红点/拦截 |
| 呼号为空 | `—`（可派生字段） | 同上 |
| WPX（`sendsSerial`） | 永不为空 | 恒为 3 位序号 |

### 4.7 序号时序（D3，已确定不冻结）

**最终口径（不冻结）**：字段恒等于 `buildMyExchange(本局原始行数 + 1)`，与发送时 `_myExchange()` 调用的表达式完全一致。

| 阶段 | 状态 | 显示 | 与实发值 |
|---|---|---|---|
| 待机（未开局） | 无 | `001`（下一局第 1 个；不沿用上一局列表长度） | — |
| 发送中 | `ReportMyExchange` | 本局行数 + 1 | 相同（尚未落库） |
| 等待对方交换 / 待提交 | `WaitingSubmitMyExchange`、`HeAskForExchange` 等 | 本局行数 + 1 | 相同（尚未落库） |
| 落库后的收尾 | `QsoEnd`、`SpQsoEnd` | 本局行数 + 1（下一个序号） | 刚发的是上一个；字段立即指向下一个 |

**为什么选择不冻结**：

- `QsoEnd` 状态**不携带** `myExchange`（只有 `ReportMyExchange` / `SpQsoEnd` 携带），想覆盖运行模式的收尾窗口就必须在 UI 里记住"刚发出的值"，并处理停止/重开的清空；
- "下一个序号"本身是准确信息，字段语义是"我将要发的交换"，落库后前进一位是自然结果，也与 N1MM 的下一序号显示一致；
- 不冻结时实现是零状态耦合（§5.3 的代码里不需要读任何 `myExchange` 字段）。

**已否决（冻结）**：在 `ReportMyExchange` / `SpQsoEnd` 记住本 QSO 实发值、保留到下一轮开始，可避免收尾窗口里的提前跳号；但需要约 15 行 UI 记忆状态，而"下一个序号"本身就是准确信息。**D3 已定为不冻结**，接受落库后立即前进一位。

### 4.8 设置页「发射预览」（D4，已确定）

在 **我的电台** 的字段下方追加一条只读提示（不新增输入）：

```
发射内容：59 05
RST 固定 59；05 来自上方 CQ 分区
```

- WPX：`发射内容：59 001` +「序号随本局 QSO 数自动递增」。
- 未配置：`发射内容：未配置（请填写 ITU 分区）`。
- 作用：把"设置里填的 5"与"实际读出的 05"连起来，避免用户以为字段写错。
- **间距**：预览块与上方字段 / 序号提示保持 **16px**（MD3）；已修正原型中 CQ WPX 下预览与序号提示贴太紧的问题。

---

## 5. 技术方案

### 5.1 领域层：抽出纯函数（不改行为）

`station_exchange.dart` 里把构造逻辑提为顶层函数，`StationExchangeBuilder.buildMyExchange` 改为委托：

```dart
/// 我方第 [qsoNumber] 个 QSO 的交换（RST 之后），已按比赛位数朗读化。
String buildMyExchangeText({
  required MyExchangePlan plan,
  required StationExchangeConfig config,
  required String stationCallsign,
  required DxccManager dxccManager,
  required int qsoNumber,
}) {
  if (plan.sendsSerial) {
    return formatExchangeNumber(qsoNumber.toString(), plan.serialDigits);
  }
  final parts = <String>[];
  for (final field in plan.fields) {
    final value = resolveExchangeValue(field, config, stationCallsign, dxccManager);
    if (value == null || value.isEmpty) continue;
    parts.add(field.numeric ? formatExchangeNumber(value, field.audioDigits) : value);
  }
  return parts.join(' ');
}
```

`StationExchangeBuilder.buildMyExchange(n) => buildMyExchangeText(plan: plan, config: config, ...)`。
这样"实发值"与"显示值"共用同一段代码，不会各自漂移。

### 5.2 运行期入口：`ContestManager.myExchangeFor`

运行中必须用本局固化的 `ContestType`（设置快照），待机才用当前设置；两者都由 `ContestManager` 内部处理，UI 不需要新增 provider：

```dart
/// 我方第 [qsoNumber] 个 QSO 的交换。运行中取本局固化的 ContestType，
/// 待机时按当前比赛/呼号/设置预演下一局。
String myExchangeFor(int qsoNumber) {
  final active = _activeContestType;
  if (_isContestRunning && active != null) {
    return active.buildMyExchange(qsoNumber);
  }
  final settings = _contestDataManager.appSettings;
  final dxccManager = _contestDataManager.dxccManager;
  final definition = ContestRegistry.byId(settings.contestId);
  final plan = definition.myExchangePlan(
    stationCallsign: settings.stationCallsign,
    dxccManager: dxccManager,
  );
  return buildMyExchangeText(
    plan: plan,
    config: settings.stationExchangeConfig(definition.id),
    stationCallsign: settings.stationCallsign,
    dxccManager: dxccManager,
    qsoNumber: qsoNumber,
  );
}
```

> 优点：控制台只依赖已经存在的 `ContestManager`；待机预览与"待机时点开始"完全一致；运行中与实发值同源。

### 5.3 UI 接线（`qso_console.dart`）

- 插入第 4 个 `_QsoField`（复用现有组件，增加 `focusable` / `suffixIcon` 参数），`flex: 22`，其余三个 flex 调整为 `26 / 10 / 26`。
- 数值计算放在字段自己的 builder 内（不触发整块控制台重建）：

```dart
final manager = context.read<ContestManager>();
final settings = context.read<AppSettings>();

ValueListenableBuilder<int>(
  valueListenable: settings.settingsRevision,       // 待机时改设置立即刷新
  builder: (_, _, _) => BlocBuilder<QsoConsoleCubit, SingleCallRunState?>(
    builder: (context, state) {
      final logged = state == null
          ? 0
          : context.watch<QsoRecordListCubit>().state.length;  // 原始行数（含 DUPE）
      final value = manager.myExchangeFor(logged + 1);
      return _QsoField(
        height: height,
        controller: ...,
        label: l10n.sentExchangeLabel,
        readOnly: true,
        focusable: false,
        suffixIcon: const _LockedIcon(),
        ...
      );
    },
  ),
)
```

要点：

- `state == null`（待机）时 `qsoNumber = 1`，**不要**用上一局列表长度。
- 运行中 `logged` 用 `QsoRecordListCubit` 的长度，与 `_myExchange()` 的 `qsoTable.count(runId)` 同为原始行数（含 DUPE），避免 WPX 序号偏移（R1）。
- 不读状态里的 `myExchange`（即 D3 已定口径：不冻结）。
- 空字符串统一渲染为 `—`。

### 5.4 文件改动清单

| 文件 | 改动 | 规模 |
|---|---|---|
| `lib/contest_type/station_exchange.dart` | 抽出 `buildMyExchangeText`；builder 委托 | ~20 行 |
| `lib/contest_run/new/contest_manager.dart` | 新增 `myExchangeFor(int)` | ~25 行 |
| `lib/ui/main_page/qso_console.dart` | 新增第 4 字段、RST 置灰常显 59、四栏 flex 34/9/14/34、序号取值 | ~75 行 |
| `lib/ui/main_page/settings_sheet.dart` | 新增发射预览 `_StationSentPreview`（D4） | ~40 行 |
| `lib/l10n/app_{en,zh,zh_Hans,zh_Hant,ja}.arb` | 复用 `exchangeFieldLabel` 与 `tableExchange`（值改为「对方交换」/ `Rcvd` / `受信交換`）；新增 `sentExchangeLabel`、`sentExchangeLockedTooltip`、`sentExchangeLockedRunningTooltip`、`sentExchangeNotSet`、`stationSentPreview` | 5 键 × 5 + 2 键取值 |
| `lib/l10n/generated/*` | `flutter gen-l10n` 重新生成 | 自动 |
| `test/station_exchange_test.dart` | `buildMyExchangeText` 各比赛断言 | ~30 行 |
| `test/ui/qso_console_test.dart` | 新增 `QsoRecordListCubit` provider；四字段/只读/序号断言 | ~40 行 |

**无 schema 迁移、无 SharedPreferences 新键、无音频与状态机改动。**

---

## 6. 备选方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **A（推荐）** | UI 投影 + `ContestManager.myExchangeFor` | 改动小；运行中与实发同源；无新 provider；待机也能预演；不依赖状态字段 | UI 需要看 `QsoRecordListCubit` 的列表长度 | ✅ |
| B | 新建 `MyExchangeCubit`，由状态变化 / DB 变更 / 设置变更推送 | 单一订阅点，未来可在多处复用 | 多一个 cubit 与生命周期；与 `QsoRecordListCubit` 的 DB watch 重复；收益低 | 不采纳 |
| C | 把"我方交换"作为第 6 列写进日志表 | 历史可见、便于复盘 | 现有列宽已满（84 + flex + 52 + flex + 132）；需要 `QsoTable` 加列 + 迁移 + 导出改动；与"只读参考"诉求无关 | 不采纳（D6 后续） |
| D | 做成可编辑输入框 | 灵活 | 与需求直接冲突；实发值会与设置漂移；破坏单一来源 | 排除 |

---

## 7. 边界与风险

| # | 风险 | 处理 |
|---|---|---|
| R1 | **序号口径**：`countCurrentRunQso()` 用 `uniqueQsos`，而实发值用原始行数；显示若用前者会在出现 DUPE 时偏移 | 显示必须用 `QsoRecordListCubit` 的原始长度；在代码处留注释指向 `_myExchange()`，两处口径一起改 |
| R2 | 设置快照 vs 当前设置 | 运行中直接取 `_activeContestType`，与实发完全一致；待机才读当前设置 |
| R3 | 运行中深链打开设置页会看到禁用态 | 若采纳 D5：运行中禁用点击（或打开后仍显示锁定说明，二者择一） |
| R4 | 最小窗口 1024 下四栏拥挤 | 按 §4.4 的 flex 分配；控制台测试增加 640 宽度用例，断言无 `RenderFlex` 溢出 |
| R5 | 5 种语言的标签长度不同（日文最长） | 标签固定为短词（≤4 字）；必要时 `TextOverflow.ellipsis` |
| R6 | 复盘/重放不记录我方交换（既有 D6 限制） | 不在本方案内解决；重放时显示的是"按当前设置会发什么"，与真实重放行为一致 |
| R7 | 只读但仍是 `TextField`，可能被 Tab 聚焦 | `canRequestFocus: false` + 测试断言（见 §8） |
| R8 | RST 改为常显 `59` 后，F2 的写入行为需同步调整，否则会与固定显示冲突 | `_fillRst()` 只保留"把焦点交给对方交换框"；语义仍是 `59`，控制台测试覆盖 |
| R9 | 落库后 WPX 序号立即前进一位（收尾窗口内与刚播报的值不同） | **D3 已确定为不冻结**，接受该行为；若以后要冻结，需在 UI 记住实发值 |

---

## 8. 测试计划

### 8.1 单元测试（`station_exchange_test.dart`）

- `buildMyExchangeText` 逐比赛断言：WPX `001`/`007`、CQ WW `05`、IARU `08`、ARRL(DX) `100`、ARRL(W/VE) `TX`、JIDX JA `10`、JIDX 非 JA `05`。
- 未配置且不可派生 → `''`（UI 层再映射为 `—`）。
- `StationExchangeBuilder.buildMyExchange` 与纯函数结果一致（回归）。

### 8.2 组件测试（`qso_console_test.dart`）

- 四个字段顺序为 **呼号 / RST / 我方交换 / 对方交换**；RST 与我方交换 `readOnly` 且不可聚焦；RST 常显 `59`、无后缀。
- 日志表头显示「对方交换」；控制台标签为「对方交换 / 我方交换」。
- 运行中点击我方交换不打开设置抽屉；待机点击打开并定位到对应字段。
- CQ WW + `cqZone=5` → 显示 `05`；切到 WPX → 显示 `001`。
- `QsoRecordListCubit` 追加一条后，WPX 显示 `002`。
- 待机时不沿用上一局列表（`qsoCount` 仍按 1）。
- 640 宽度渲染无溢出，且 RST `59`、我方交换 `003` 不被裁切（现有 660/668/874 用例保留）。
- WPX 落库后：字段从 `003` 立即变为 `004`（D3 已定：不冻结）。

测试夹具需新增 `BlocProvider<QsoRecordListCubit>`；该 cubit 在 `contestRunIdStream` 未发射前不会触发数据库，现有"DB 必抛"夹具可继续使用。

### 8.3 手工验收（4 场景）

1. CQ WW，`BI1QJQ` → 设置显示 CQ 分区 24 → 控制台 `24`；改成 `5` → `05`。
2. WPX，记录 2 条 QSO → 控制台 `003`；第 3 条落库后立即变 `004`（收尾窗口内也是 `004`）。
3. IARU 未填 ITU → `—`；设置页有红点；点开始被拦截。
4. 1024×650 最小窗口 + 中文/日文 + 浅/深主题 → 无换行、无溢出。

---

## 9. 实施步骤（建议 1 个 PR）

1. `station_exchange.dart` 抽出 `buildMyExchangeText` + 单测（行为不变）。
2. `ContestManager.myExchangeFor` + 单测（待机/运行两分支）。
3. `qso_console.dart` 第 4 字段 + 只读修饰 + flex 调整；更新控制台测试夹具。
4. 设置页发射预览（D4 已确定，保持 16px 间距）。
5. 5 个 ARB + `flutter gen-l10n` + `flutter analyze` / `flutter test`。

PR 标题建议：`feat: show sent exchange in the QSO console`

---

## 10. 决策记录（已全部确定）

| # | 决策 | 结论 | 备选（已否决） | 影响 |
|---|---|---|---|---|
| **D1** | 标签命名 | **A：对方交换 / 我方交换**（英文 Rcvd / Sent，日文 受信交換 / 送信交換） | B：保留「交换信息」；C：长标签 | 2 个 ARB 键 × 5 语言 + 日志表头文案 |
| **D2** | 是否把 RST 合进我方字段 | **独立**：固定 59、置灰、窄栏 | 并入显示 `59 05` | 与最终布局一致 |
| **D3** | WPX 序号时序 | **不冻结**：始终显示下一个 QSO 的序号，零状态耦合 | 收尾时冻结实发值（需 UI 记忆） | 收尾窗口会立即前进一位 |
| **D4** | 设置页「发射内容」预览 | **加**：`59 05`，与上方字段保持 16px（MD3） | 不加 | 多约 40 行 UI，帮助理解 `5` vs `05` |
| **D5** | 点击锁图标深链设置 | **加**：仅待机可点，运行中禁用并换 tooltip | 纯展示 | 需处理运行中禁用态 |
| **D6** | 是否写入 QSO 记录 | **不写入**；`QsoTable` 不加列 | 加 `myExchange` 列 + 迁移 | 与既有 D6 一致 |
| **D7** | 字段顺序与宽度 | **`Call → RST → 我方交换 → 对方交换`**；flex `34 / 9 / 14 / 34` | 三栏 + 信息条；我方在后 | 见 §4.4 |
| **D8** | 固定交换是否显示 | **始终显示**（随 D7 固定四栏） | 仅可变交换时显示（严格 N1MM） | 训练时也能看到将发送的固定值 |

> 附加文案变更（D1/D6 的落地）：日志表 `tableExchange` 由「交换信息」改为「对方交换」，不新增列。

---

## 11. 附：取值示例（同一时刻的四个字段）

| Contest | 呼号 | RST | 我方交换（只读） | 对方交换（录入） | 说明 |
|---|---|---|---|---|---|
| CQ WPX | `JA1ABC` | 59 | `003` | `012` | 第 3 条 QSO，序号自动 |
| CQ WW | `K1ABC` | 59 | `24` | `05` | 我方 CQ 分区 24 |
| IARU | `DL1ABC` | 59 | `08` | `28` | 我方 ITU 分区 8 |
| ARRL DX（DX 台） | `W1ABC` | 59 | `100` | `TX` | 我方功率 100 W |
| ARRL DX（W/VE 台） | `K1ABC` | 59 | `TX` | `100` | 我方州/省 |
| JIDX（JA 台） | `JA1ABC` | 59 | `10` | `24` | 我方都道府县 10 |
| JIDX（非 JA 台） | `K1ABC` | 59 | `24` | `10` | 我方 CQ 分区 24 |

---

## 12. 原型操作说明

打开 [`sent_exchange_field_prototype.html`](./sent_exchange_field_prototype.html)（本地直接双击，或 `python3 -m http.server` 后访问）：

- 顶部工具栏：切换 比赛 / 界面语言 / 主题 / QSO 状态；标签、布局、RST 与各项决策已固化，不再提供对照开关；
- 开关：仅保留「模拟未配置」（看 `—` 与设置页报错）；
- `记录 1 条 QSO`：在 WPX 下驱动序号递增（下一个值，不冻结）；待机时点击我方交换的锁图标打开设置抽屉，运行中禁用；
- 设置抽屉的「发射内容」预览始终显示，与上方字段保持 16px 间距（含 CQ WPX 的序号提示）。
