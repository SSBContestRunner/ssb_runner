# 不同 Contest 下我方 Exchange 与 Station 配置技术方案

> 状态：草案，待评审
> 背景：当前无论选择哪个比赛，操作员（我方 station）发出的 exchange 恒为 "59 + QSO 序号"，即 CQ WPX 的 "`59 #`" 形态，与所选比赛规则不符。
> 目标：按 contest 类型让 station 配置随之变化（CQ Zone / ITU Zone / Power / Prefecture / State 等），并据此生成正确的我方 exchange。
>
> **实施状态**：阶段 A + B 已落地。`flutter analyze` 仅剩历史 info（CI 以 `--no-fatal-infos` 放行），`flutter test` 79/79 通过。
> 已落地：station exchange 模型 / 五比赛 plan / 运行时接线 / 设置页动态字段 / RUN 硬门槛 / cty `cqz` 解析 + schema v3 / 默认值派生（`BI1QJQ` → CQ Zone 24）。
> 未做（见 §14）：ARRL W/VE（L0）、我方 exchange 记录（D6-A）、规则版本字段（不采纳）、入站真实化（阶段 C）。

---

## 1. 结论摘要

- **根因不是 UI 未刷新，而是运行期的"我方 exchange"被硬编码为 QSO 序号。**
  `ContestOperationEventHandler._obtainHisExchange()` 直接返回 `count + 1`，与当前 `ContestType` 无关；而 `ContestType` 契约里根本没有"我方发送什么"的概念。
- **附带缺陷：serial 中心主义的补零。** `audio_play_type.dart` 把所有纯数字 exchange 一律 `padLeft(3, "0")`，CQ/ITU Zone 与 JIDX 都道府县会被读成 3 位数（zone 5 → "005"）。
- **修复方向与你的意见一致：station 配置按 contest 变化。** 新增一层"我方 exchange 规格（plan）"：由 `ContestDefinition` 声明、`AppSettings` 按 contest 持久化、`ContestType` 在运行期构造。
- **取值优先级（本次调整）：显式配置 > 可派生默认值；取不到则必须手填，开赛前强制校验。** 用户在 Station 里填了什么就以什么为准；字段为空且能从呼号/DXCC 取到数据时自动填入默认（例如 `BI1QJQ` → CQ Zone 24）；取不到（如 ITU Zone，素材无 `ituz`）就留空并视为必填，**station config 未完全填好不允许开始比赛**。
- 影响面集中在 `lib/contest_type/`、`lib/contest_run/new/`、`lib/settings/app_settings.dart`、`lib/ui/main_settings/`；不推翻现有 `ContestType` / `ExchangeManager` / 状态机结构。

---

## 2. 现状与证据（代码核对）

### 2.1 现象复现路径

1. F2（EXCH）、F5（分号 hisCallAndMyExchange）、或在呼号已输入时按提交，触发我方 exchange 播放；
2. 播放路径最终都调用 `_obtainHisExchange()`（`contest_operation_event_handler.dart:222-232`）→ `count + 1`（当前 run 的 QSO 条数 + 1）；
3. 该值经 `SubmitCallAndHisExchange.hisExchange` → 状态机放进 `ReportMyExchange.myExchange`（`single_call_run_state_machine.dart:58-73`）→ `PlayCallExchange(isMe: true)`；
4. 音频 = 呼号 + `EXCH.wav` + 数字朗读（`payload_to_audio.dart:9-15`、`contest_state_change_handler.dart:204-242`）。

因此无论 CQ WW / IARU / ARRL / JIDX，发出的都是 WPX 的 "59 + 序号"。

### 2.2 证据清单

| # | 位置 | 事实 | 影响 |
|---|---|---|---|
| E1 | `contest_run/new/contest_operation_event_handler.dart:222-232` | `_obtainHisExchange()` 返回 `count + 1`，方法名与实际语义（我方）相反 | 我方 exchange 恒为序号 |
| E2 | `contest_operation_event_handler.dart:199-220` | `hisExchange: await _obtainHisExchange()` 被当作我方 exchange 传给 `ReportMyExchange` | 与 contest 类型解耦 |
| E3 | `state_machine/.../single_call_run_state_machine.dart:51-73` | `myExchange` 直接来自事件，状态机不感知 contest | 无扩展点 |
| E4 | `audio/payload_to_audio.dart:9-15` | 我方 RST 固定 `EXCH.wav`，对方固定 `ROGER_YOU_ARE_59.wav` | RST 59 本身没问题 |
| E5 | `state_machine/.../audio_play_type.dart:45-54` | 纯数字 exchange 一律补零到 3 位 | Zone/Prefecture 读数错误 |
| E6 | `contest_type/contest_definition.dart:12-22` | `ContestDefinition` 只有 id/name/exchangeLabel/scoringNotice/create | 无 station exchange 规格 |
| E7 | `contest_type/contest_type.dart:4-8` | `ContestType` 只有 allowExchangeRegex / scoreCalculator / exchangeManager | 无"我方发送"契约 |
| E8 | `contest_definition.dart:46/66/92/109/130` | `exchangeLabel` 只是展示字符串（"59 #" / "59 Zone" …） | 不影响运行行为 |
| E9 | `ui/main_settings/main_settings.dart:99/106` | exchangeLabel 只在设置页只读显示 | 切比赛只改了文案 |
| E10 | `settings/app_settings.dart:27-30` | 只有全局 `stationCallsign` | 无按 contest 区分的 station 参数 |
| E11 | `dxcc/dxcc_manager.dart:126-175` | `parseDxccXml` 只解析 call/adif/cont，忽略 cty 里的 `cqz` | CQ Zone 无法自动派生 |
| E12 | `assets/dxcc/cty.xml.gz` | 含 `cqz`（32233 条），**完全不含 `ituz`** | ITU Zone 只能手配或换素材 |
| E13 | `contest_type/contest_definition.dart:180-189` | `_NumericExchangeManager` 生成"对方"exchange（1..max） | 对方侧已是数字，但与我方 station 无关 |

### 2.3 结论

- 缺的是三样东西：**（1）我方 exchange 的领域契约；（2）按 contest 变化的 station 配置与持久化；（3）按 contest/字段决定的位数格式化。**
- 对方（入站台）的 exchange 生成已按 contest 参数化（E13），本方案以我方为主，同时为对方侧预留对称扩展（第 6.10 节）。

---

## 3. 目标与非目标

### 3.1 目标

1. 我方 exchange 按 contest 规则生成：WPX=序号、CQ WW=CQ Zone、IARU=ITU Zone、ARRL DX=功率或州/省、JIDX=都道府县（JA）或 CQ Zone（非 JA）。
2. Station 配置随所选 contest 变化，按 contest 持久化，运行中不可修改；**取值以显式配置为主**，为空且可派生时填入默认值（如 CQ Zone）；**所有必填字段必须完全填好才允许开始比赛**。
3. 位数/朗读格式由 contest 与字段决定（序号 3 位、Zone/都道府县 2 位、功率原样）。
4. 可单测、可复现；与现有 `SessionRandom` / 事件日志 / 重放设计兼容。
5. 向后兼容：旧设置、旧会话历史、旧事件日志不崩溃。
6. 新增 UI 文案保持英文（仓库约定，见 `docs/design/pr27_training_platform_absorption.md` §4.6）。

### 3.2 非目标

- 不做 Cabrillo 官方计分；仍是单波段训练档案（README 免责声明不变）。
- 不做 IARU HQ / 特殊台（society abbreviation）。
- 本方案不重写状态机、不重做音频引擎。
- 州/省（字母）的本地化读音素材不在 P0 范围（见风险 R1）。

### 3.3 取值优先级、默认填入与开赛校验（本次调整）

1. **显式配置优先**：Station 中用户手动填写的值永远最高优先级，任何自动派生都不得覆盖。
2. **可派生则填默认**：字段无显式值时，若能从 station 呼号 + DXCC 取到数据，则自动填为默认值并生效。例：`BI1QJQ` 经 `extractPrefix` 得 `BI1`，回溯 cty 前缀 `BI`（adif 318）得 `cqz=24`，默认 CQ Zone = 24。
3. **取不到留空且必填**：两者都没有时字段留空（例如 ITU Zone，cty 素材无 `ituz`），并标记为必填。
4. **开赛前强制校验**：点 RUN 时必须**所有必填字段都有合法值**（显式或派生），否则阻止开始并提示第一个缺失/越界的字段；不允许带空值开赛，也不允许开赛后补填。
5. 派生默认值**不写入持久化配置**，只影响显示与运行取值；用户一旦编辑即成为显式值。这样改呼号后默认值会自动刷新，而用户填过的值不会被冲掉。

---

## 4. 规则对照表（我方视角）

> 比赛规则会随年度修订；下表用于建模，落地前需对照当期官方规则复核（第 11 节 D4）。

| Contest | 我方 station 发送 | 对方发送 | 我方需要的 station 配置 | 朗读位数 |
|---|---|---|---|---|
| CQ WPX SSB | 59 + 序号（3 位，从 001 起） | 59 + 序号 | 无（自动递增） | 序号 3 位 |
| CQ WW SSB | 59 + CQ Zone | 59 + CQ Zone | CQ Zone 1..40（可由呼号派生） | 2 位 |
| IARU HF | 59 + ITU Zone | 59 + ITU Zone | ITU Zone 1..90（手配） | 2 位 |
| ARRL DX SSB | DX 台：59 + 功率；W/VE：59 + 州/省 | 与对方身份相反 | 功率（DX）或州/省（W/VE） | 功率原样；州/省按字母 |
| JIDX SSB | JA 台：59 + 都道府县号码（01–50）；非 JA：59 + CQ Zone | 与对方身份相反 | 都道府县 01..50（JA）或 CQ Zone 1..40（非 JA，可派生） | 2 位 |

判定"我方身份"依据 station 呼号的 DXCC：
- JA：Japan=339、Ogasawara=192、Minami Torishima=177（复用 `audio/audio_loader.dart:9` 的 `_japan` 集合）。
- W/VE：United States=291、Canada=1（cty adif 编号）。

---

## 5. 总体设计

~~~
┌──────────────────────────────────────────────────────────────────┐
│ 声明层  ContestDefinition                                          │
│   myExchangePlan(callsign, dxcc) -> MyExchangePlan                 │
│     • fields: [StationExchangeField]  ← 设置页渲染 + 持久化键       │
│     • sendsSerial: bool               ← 仅 WPX 使用自动序号          │
└───────────────┬──────────────────────────────┬───────────────────┘
                │ 设置页 / RUN 校验              │ create() 注入
                ▼                                ▼
┌───────────────────────────┐      ┌───────────────────────────────┐
│ 持久化层  AppSettings       │      │ 运行层  ContestType            │
│  按 contestId 存 JSON       │─────▶│  buildMyExchange(qsoNumber)    │
│  StationExchangeConfig      │      │  formatExchangeForAudio(text)  │
└───────────────────────────┘      └───────────────┬───────────────┘
                                                    │
                                                    ▼
┌──────────────────────────────────────────────────────────────────┐
│ 接线层  ContestOperationEventHandler / ContestStateChangeHandler    │
│   我方发送：buildMyExchange(qsoNumber)                              │
│   音频朗读：按 contest 格式化后交给 CallsignPayload                  │
└──────────────────────────────────────────────────────────────────┘
~~~

设计要点：
- **单一数据源**：一个 contest 的 station 字段、默认值、朗读位数、我方 exchange 构造规则都集中在 `ContestDefinition` / `ContestType`，不再有散落的 `if (contestId == ...)`。
- **运行期构造**：`create()` 时把持久化配置解析成不可变的 plan + 值，运行中不再读设置。
- **播放期格式化**：去掉全局补零，格式化只按当前 contest 规则执行。

---

## 6. 详细设计

### 6.1 新值类型 `lib/contest_type/station_exchange.dart`（新增）

~~~dart
/// 一个由 station 配置提供的 exchange 字段。
class StationExchangeField {
  const StationExchangeField({
    required this.id,          // 持久化键：'cqZone' / 'ituZone' / 'power' / 'prefecture' / 'stateProvince'
    required this.label,       // UI 标签：'CQ Zone'
    this.numeric = true,
    this.min,
    this.max,
    this.audioDigits = 0,      // 朗读补零位数：0 原样；2 Zone/都道府县；3 序号
    this.helperText,
    this.derive,               // 可选默认值派生：呼号 + DXCC -> String?
  });

  final String id;
  final String label;
  final bool numeric;
  final int? min;
  final int? max;
  final int audioDigits;
  final String? helperText;
  final String? Function(String stationCallsign, DxccManager dxcc)? derive;
}

/// 取值解析：显式配置优先；为空时用 derive 派生；仍为空返回 null。
String? resolveExchangeValue(
  StationExchangeField field,
  StationExchangeConfig config,
  String stationCallsign,
  DxccManager dxcc,
) {
  final explicit = config[field.id]?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  return field.derive?.call(stationCallsign, dxcc);
}

/// 一个 contest（在给定 station 呼号下）我方发送内容的结构描述。
class MyExchangePlan {
  const MyExchangePlan({
    required this.fields,
    required this.sendsSerial,
    this.serialDigits = 3,
  });

  final List<StationExchangeField> fields;
  final bool sendsSerial;       // true = 自动序号，无需配置
  final int serialDigits;
}

/// 按 contest 持久化的 station exchange 取值。
class StationExchangeConfig {
  const StationExchangeConfig(this.values);
  const StationExchangeConfig.empty() : values = const {};

  final Map<String, String> values;

  String? operator [](String id) => values[id];

  Map<String, dynamic> toJson() => {'values': values};

  factory StationExchangeConfig.fromJson(Map<String, dynamic> json) =>
      StationExchangeConfig(
        Map<String, String>.from(
          (json['values'] as Map?)?.cast<String, String>() ?? const {},
        ),
      );
}
~~~

补充工具函数（同文件或 `contest_identity.dart`）：
- `bool isJapanDxcc(int id)` / `bool isWveDxcc(int id)`
- `String formatNumeric(String raw, int digits)`：digits=0 原样，否则按去前导零后补零。
- `String? validatePlan(MyExchangePlan, StationExchangeConfig)`：缺失/越界时返回英文错误。

### 6.2 `ContestDefinition` 契约扩展

~~~dart
abstract class ContestDefinition {
  String get id;
  String get name;
  String get exchangeLabel;       // 平台级格式描述，保留兼容
  String get scoringNotice;

  /// 给定 station 呼号，声明我方 exchange 需要哪些配置字段。
  /// ARRL/JIDX 会按 DXCC 切换字段集；其余比赛返回固定 plan。
  MyExchangePlan myExchangePlan({
    required String stationCallsign,
    required DxccManager dxccManager,
  });

  ContestType create({
    required String stationCallsign,
    required DxccManager dxccManager,
    required StationExchangeConfig stationExchange,   // 新增
  });
}
~~~

`exchangeLabel` 继续作为静态展示（例如 ARRL 写成 `"59 Power (DX) / 59 State (W/VE)"`），设置页的"Exchange"只读框展示 plan 摘要，不参与运行。

### 6.3 `ContestType` 契约扩展

~~~dart
abstract interface class ContestType {
  RegExp get allowExchangeRegex;
  ScoreCalculator get scoreCalculator;
  ExchangeManager get exchangeManager;

  /// 我方第 [qsoNumber] 个 QSO（1 起）发送的 exchange，已按本比赛位数朗读化。
  String buildMyExchange(int qsoNumber);

  /// 把入站 exchange 规范值转成朗读形态（补零位数按本比赛规则）。
  String formatExchangeForAudio(String exchange);
}
~~~

说明：`buildMyExchange` 直接返回"可朗读"的值（例如 WPX 的 `"024"`、CQ WW 的 `"05"`），因为该值不参与 QSO 记录与比较，仅用于发送播放；入站值仍保持"规范值（去前导零）+ 播放时格式化"以兼容 `processExchange` 的比较口径。

### 6.4 五个比赛的 plan 与构造

| Definition | myExchangePlan | buildMyExchange(qsoNumber) | formatExchangeForAudio |
|---|---|---|---|
| CqWpxDefinition | fields=[]；sendsSerial=true（3 位） | 序号补 3 位 | 补 3 位 |
| CqWwSsbDefinition | fields=[cqZone 1..40] | 配置/派生的 CQ Zone 补 2 位 | 补 2 位 |
| IaruHfDefinition | fields=[ituZone 1..90] | ITU Zone 补 2 位 | 补 2 位 |
| ArrlDxDefinition | callsign 属 W/VE → [stateProvince]；否则 [power] | 对应字段原样 | 数字原样；字母原样（见 R1） |
| JidxSsbDefinition | callsign 属 JA → [prefecture 1..50]；否则 [cqZone 1..40]（可派生） | 都道府县补 2 位 / CQ Zone 补 2 位 | 补 2 位；非 JA 为 CQ Zone |

`_NumericContestDefinition` / `_NumericContestType` 改造为接收一个 `MyExchangePlan` + `StationExchangeConfig` + callsign + dxcc，并持有一个共享的 `MyExchangeBuilder`：

~~~dart
class MyExchangeBuilder {
  const MyExchangeBuilder({
    required this.plan,
    required this.config,
    required this.stationCallsign,
    required this.dxccManager,
  });

  String build(int qsoNumber) {
    if (plan.sendsSerial) {
      return qsoNumber.toString().padLeft(plan.serialDigits, '0');
    }
    final parts = <String>[];
    for (final field in plan.fields) {
      final raw = config[field.id]?.trim() ?? '';
      if (raw.isEmpty) continue;          // 校验已保证非空
      parts.add(field.numeric ? _pad(raw, field.audioDigits) : raw);
    }
    return parts.join(' ');
  }
  ...
}
~~~

### 6.5 运行时接线（关键改动）

1. **`ContestManager.startContest()`**（`contest_manager.dart:130-133`）
   - 读取 `settings.stationExchangeConfig(definition.id)`；
   - 传入 `definition.create(stationCallsign:, dxccManager:, stationExchange:)`。
2. **`ContestRunningManager`**（`contest_running_manager.dart:57-74`）
   - 把 `_contestType` 注入 `ContestOperationEventHandler`。
3. **`ContestOperationEventHandler`**（`contest_operation_event_handler.dart:222-232`）
   - 删除 `_obtainHisExchange()` 的硬编码，改为：

~~~dart
Future<String> _myExchange() async {
  final done = await _appDatabase.qsoTable
      .count(where: (row) => row.runId.equals(_contestRunId))
      .getSingle();
  return _contestType.buildMyExchange(done + 1);
}
~~~

   - `_handleSubmit` / `_handleExchEvent` / `obtainMySentExchangeAudioData` / `obtainHisCallAndMyExchange` 全部改用 `_myExchange()`；
   - 同一 QSO 内可缓存该值，避免重复查库并保证 F2 与提交播放一致。
4. **`ContestStateChangeHandler._playAudioByPlayType`**（`contest_state_change_handler.dart:170-302`）
   - `PlayExchange` / `PlayCallExchange` 保留**原始** exchange 字段；
   - 播放时：`isMe == true` 直接用（build 已朗读化）；否则 `_contestType.formatExchangeForAudio(raw)`。
5. **`audio_play_type.dart`**（`:25-54`）
   - 删除 `exchangePadZerosIfNeeded` 的全局补 3 位；字段改为原始值 `exchangeToPlay` 或干脆改名 `exchange`。
   - `single_call_run_state_machine.dart:194-198 / 303-310` 相应改为传原始值。

不改动：`ExchangeManager.generateExchange` / `processExchange` 的接口与行为（E13 保持），入站 exchange 规范值仍是去前导零的数字。

### 6.6 持久化 `AppSettings`

~~~dart
StationExchangeConfig stationExchangeConfig(String contestId) {
  final raw = _prefs.getString('$_settingStationExchangePrefix$contestId');
  if (raw == null || raw.isEmpty) return const StationExchangeConfig.empty();
  return StationExchangeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

void setStationExchangeConfig(String contestId, StationExchangeConfig config) {
  _prefs.setString(
    '$_settingStationExchangePrefix$contestId',
    jsonEncode(config.toJson()),
  );
}
~~~

- 常量：`const _settingStationExchangePrefix = 'setting_station_exchange_';`
- **只持久化显式值**；运行时取值统一走 `resolveExchangeValue`（显式 > 派生默认 > null）。
- 向后兼容：旧版本无该键 → 返回空配置。WPX 不受影响；CQ WW 与 JIDX 非 JA 的 CQ Zone 先尝试派生（如 `BI1QJQ` → 24）；IARU / ARRL / JIDX JA 的都道府县取不到才由 RUN 校验提示补齐。

### 6.7 设置页 UI（`ui/main_settings/main_settings.dart`）

现状：`_StationSettings` 只有一个 Callsign 输入框（`:168-241`）。

改造：
1. 新增 `_ContestStationCubit`，状态为 `(ContestDefinition definition, StationExchangeConfig config)`，作为 Contest + Station 两个分区的单一状态源；切换比赛时同步刷新 station 字段并写回 `AppSettings`。
2. `_StationSettings` 渲染：Callsign（既有）+ 按 `definition.myExchangePlan(callsign, dxcc)` 动态生成的字段输入框：
   - label 用 `field.label`；数字字段加 `FilteringTextInputFormatter.digitsOnly` 与 min/max 校验；
   - 输入框初值 = `resolveExchangeValue(...)`：有显式值用显式值，否则显示派生默认，helperText 标注 `Default from callsign`；
   - 用户编辑即写入 `AppSettings.setStationExchangeConfig`（成为显式值）；未编辑的派生默认不落盘，改呼号/切比赛时自动刷新；
   - 运行中 `enabled: false`（沿用 `MainSettingsCubit` 的 isContestRunning）；
   - 补 `Semantics(label: ...)`，英文 helperText。
3. "Exchange" 只读框展示 plan 摘要（例如 `"59 CQ Zone"`），实际值在 station 字段里。
4. 呼号失焦时刷新未编辑字段的派生默认；已显式填写的字段保持不变。

### 6.8 RUN 校验

`qso_speed_area.dart:155-165` `_checkSettingComplete()` 增加：

~~~dart
final definition = ContestRegistry.byId(_appSettings.contestId);
final plan = definition.myExchangePlan(
  stationCallsign: _appSettings.stationCallsign,
  dxccManager: _dxccManager,
);
final error = validatePlan(plan, _appSettings.stationExchangeConfig(definition.id));
if (error != null) return error;   // e.g. 'Please set ITU Zone before starting'
~~~

**强制门槛**：plan 中任一必填字段没有合法值（显式或派生）时，RUN 被拦截并 toast 提示第一个缺失字段，不允许开赛后再补。ITU Zone 就是典型情况：素材无默认，必须用户手填后才能 RUN。

校验顺序：先 station callsign（既有校验，且 ARRL/JIDX 需要呼号非空才能判定身份），再逐字段校验 plan。`validatePlan` 对每个必填字段执行 `resolveExchangeValue`，空值或越界即返回英文错误。

### 6.9 阶段 B：呼号派生默认值（配置优先）

数据来源已核实：cty 每条 prefix 带 `cqz`，例如 China(adif 318) 的 `BI` = `cqz 24`；`extractPrefix("BI1QJQ")` = `"BI1"`，回溯到 `BI` 得 24。因此 **CQ Zone 可自动填默认**；`ituz` 字段在素材中不存在（E12），**ITU Zone 无默认、必须由用户手填**。

实现：
- 扩展 `lib/db/table/prefix_table.dart`：新增可空 `cqz`（及预留 `ituz`）。
- `parseDxccXml`（`dxcc_manager.dart:168-175`）解析 `cqz` / `ituz`。
- `DxccManager` 增加 `findCallsignCqZone` / `findCallsignItuZone`（后者在当前素材下返回 null）。
- `CqWwSsbDefinition` 与 `JidxSsbDefinition` 非 JA 分支的 `cqZone` 字段挂 `derive: (call, dxcc) => dxcc.findCallsignCqZone(call)?.toString()`；因此 `BI1QJQ` 在 CQ WW 与 JIDX（非 JA）下默认都是 24。
- **Schema v3 迁移**：`app_database.dart` `_schemaVersion = 3`；`onUpgrade` 增加列后**清空 prefixTable**，否则 `loadDxcc` 见到已有行会提前返回、新列永远为空（`dxcc_manager.dart:74-79`）。
- 取值规则：显式 `cqZone` > 派生默认。ITU Zone 无默认，属必填项；未填满时 RUN 被拦截（见 6.8）。本次决定**不更新 cty 素材**、保持手填（D2）。

### 6.10 阶段 C：对方（入站）exchange 真实化（可选）

现状 `generateExchange(SessionRandom)` 不知道来台呼号，因此 CQ WW 的"对方 zone"其实是 1..40 随机值，而非对方真实 zone。

扩展：
~~~dart
String generateExchange(SessionRandom random, {required String callerCallsign});
~~~
- `ContestAnswerGenerator` 在抽出呼号后传入；
- CQ WW：优先用 `findCallsignCqZone(caller)`，缺失再随机；
- JIDX：JA 来台 → 都道府县（01–50），非 JA 来台 → 该台的 CQ Zone（优先从呼号派生）；
- ARRL：W/VE 来台 → 州/省，DX → 功率；
- 注意：这改变随机抽取序列，会改变 `questionSeed` 的可复现结果，需作为一次显式的种子语义升级（或只在新建会话生效）。

### 6.11 重放与日志

- 我方 exchange 目前不进 `QsoTable`、也不进 `TrainingRunEvent`，因此配置变更会影响重放时"我方发送什么"。
- 建议：在 `TrainingRunMetadata`（`training/session_review.dart`）快照 `stationCallsign` + `StationExchangeConfig`；旧记录缺字段时回退默认（与既有 `questionSeed` 兼容策略一致）。
- 若要求逐 QSO 精确重放我方发送，可在 `answer` 事件里加 `myExchange` 字段（向后兼容的 JSON 可选字段）。

### 6.12 兼容性清单

| 对象 | 处理 |
|---|---|
| 旧 SharedPreferences（无 station exchange 键） | 返回空配置；WPX 无感；其余 RUN 提示 |
| 旧 `sessionHistory` JSON | 不变；metadata 新字段可空 |
| 旧事件日志 / 重放 | 不变；入站 exchange 仍是已记录值 |
| DB schema v2 | 阶段 B 升 v3：加列 + 清空 prefix 以重载 |
| `contests.dart` 兼容视图 | 不变（`exchangeLabel` 仍为静态串） |
| `test/contest_definition_test.dart` | `create()` 新增参数需更新调用 |

---

## 7. 文件改动清单

| 文件 | 改动 | 阶段 |
|---|---|---|
| `lib/contest_type/station_exchange.dart` | **新增**：字段/plan/config/校验/格式工具 | A |
| `lib/contest_type/contest_definition.dart` | 五个 definition 增加 `myExchangePlan`；`create` 增参；`_NumericContestType` 接入 builder | A |
| `lib/contest_type/contest_type.dart` | 增加 `buildMyExchange` / `formatExchangeForAudio` | A |
| `lib/contest_type/cq_wpx/cq_wpx.dart` | 接入 contract | A |
| `lib/contest_run/new/contest_manager.dart` | `create` 传 stationExchange | A |
| `lib/contest_run/new/contest_running_manager.dart` | 向 operation handler 注入 contestType | A |
| `lib/contest_run/new/contest_operation_event_handler.dart` | 删除硬编码序号，改用 `buildMyExchange` | A |
| `lib/contest_run/new/contest_state_change_handler.dart` | 播放时按 contest 格式化 | A |
| `lib/contest_run/state_machine/single_call/audio_play_type.dart` | 去掉全局补 3 位 | A |
| `lib/contest_run/state_machine/single_call/single_call_run_state_machine.dart` | 传原始 exchange | A |
| `lib/settings/app_settings.dart` | 按 contest 存取 StationExchangeConfig | A |
| `lib/ui/main_settings/main_settings.dart` | Station 动态字段 + Contest/Station 单一 cubit | A |
| `lib/ui/bottom_panel/qso_speed_area.dart` | RUN 校验 station 字段 | A |
| `lib/db/table/prefix_table.dart` + `app_database.dart` + `dxcc_manager.dart` | cqz/ituz + schema v3 + `findCallsignCqZone`（默认值来源） | B（建议与 A 同批） |
| `lib/contest_run/new/contest_answer_generator.dart` + definitions | 入站 exchange 带呼号上下文 | C |
| `lib/training/session_review.dart` | metadata 快照 station 配置 | C |
| `test/station_exchange_test.dart`（新）、`test/contest_definition_test.dart` | 测试 | A/B |

---

## 8. 测试计划

### 8.1 单元测试（无需 Flutter 绑定）

- `station_exchange_test.dart`：
  - 每个 contest 的 plan：仅 WPX 为 `sendsSerial`；CQ WW 与 JIDX 非 JA 需 cqZone；IARU 需 ituZone；JIDX JA 需 prefecture；ARRL 分支；
  - `buildMyExchange(7)` 逐 contest 断言：WPX=`"007"`、CQ WW=`"05"`（配 5）、IARU=`"08"`、ARRL=`"100"`、JIDX JA=`"10"`、JIDX 非 JA=`"05"`（配 CQ Zone 5）；
  - **回归核心断言**：五个 contest 的 `buildMyExchange(1)` 不得全部等于 WPX 的序号形态；
  - **开赛门槛**：IARU 未填 `ituZone` 时 `validatePlan` 必须返回英文错误（阻止 RUN）；填好后返回 null（允许 RUN）；CQ WW 未填但可从 `BI1QJQ` 派生时视为已填、返回 null；越界返回错误；
  - **默认值优先级**：`cqZone` 无显式值时 `resolveExchangeValue` 对 `BI1QJQ` 返回 `"24"`（fake DXCC cqz=24）；显式配 `"23"` 时返回 `"23"`；不可派生且无显式时返回 null；
  - `StationExchangeConfig` JSON 往返一致，且只含显式值。
- 更新 `contest_definition_test.dart`：`create()` 传入 `StationExchangeConfig`；断言 `buildMyExchange` 非空且逐 contest 符合预期。
- 格式化：`formatExchangeForAudio` 对 zone/prefecture 补 2 位、serial（仅 WPX）补 3 位、power 原样。

### 8.2 组件/接线测试

- 用 fake `AudioEngine` / 空数据库驱动 `ContestOperationEventHandler`，断言：
  - CQ WW 会话中 `_myExchange()` 不等于 QSO 序号，而等于配置的 zone；
  - 第 2 个 QSO 时 CQ WW 的 exchange 不变（zone），WPX 的变为 `"002"`。
- `_playAudioByPlayType`：`isMe: true` 的 PCM 不二次补零；`isMe: false` 的 zone 值补 2 位。
- `_RunBtnCubit.toggleContestRunning()`：IARU 未填 ITU Zone 时不调用 `startContest` 且弹出英文错误；填好后正常调用。

### 8.3 回归/兼容

- 旧设置（无 station exchange 键）下 WPX 行为不变；
- 旧 `sessionHistory` / 事件日志可解码；
- schema v2→v3 迁移后 prefix 表能重新载入并带 cqz。

---

## 9. 分阶段实施与 PR 划分

| 阶段 | 内容 | 建议 PR | 依赖 |
|---|---|---|---|
| A | station exchange 模型 + 五比赛 + 接线 + 设置 UI + RUN 校验 + 测试（先支持显式配置） | `feat: contest-aware operator exchange` | 无 |
| B | cty cqz 解析 + `findCallsignCqZone` + schema v3 + 默认值填入（配置优先） | `feat: default station exchange from callsign` | A（建议同批交付） |
| C | 入站 exchange 真实化 + 字母州/省读音 + metadata 快照 | `feat: realistic received exchange` | A、B |

阶段 A 修复"总是 59 #"；阶段 B 落实"按比赛 + 可获取数据填入默认值（如 BI1QJQ → CQ Zone 24）"，并配合 6.8 的强制校验：取不到默认的字段（如 ITU Zone）必须手填，**填满才可开赛**；C 为可选真实度提升。

---

## 10. 风险与取舍

- **R1 州/省（字母）读音**：现有 `CallsignPayload` 会把 `TX` 读成 Tango X-ray，而非 "Texas"。P0 建议只支持 DX 侧的功率；W/VE 侧先接受字母拼读或暂不支持（见 D3）。
- **R2 ITU Zone 无自动来源**：cty 素材不含 `ituz`，按本次决定不更新素材、保持手填；ITU Zone 作为必填项，未填时 RUN 被拦截。
- **R3 功率表示**：ARRL 用瓦数还是 "KW" 需定义；建议存整数瓦，朗读用数字（100 → "one hundred" 形态取决于素材）。
- **R4 序号与规则的耦合**：WPX 序号从 001 起；删除/重做 QSO 时序号语义需明确（当前以 DB 条数为准，保持既有行为）。
- **R5 规则随年度变化**：JIDX exchange（JA 都道府县 / 非 JA CQ Zone）已按官方口径确认；ARRL 州/省口径等仍以当期规则为准，建模需留可配置点。
- **R6 种子可复现性**：阶段 C 改变随机抽取序列，会改变既有 `questionSeed` 结果；应显式版本化或仅对新会话生效。
- **R7 设置中途变更**：运行中字段 disabled，但外部直接改 prefs 不在防护范围；运行期 plan 已在 `create()` 固化。
- **R8 兼容视图**：`exchangeLabel` 仍是静态串，若未来要显示动态格式需统一到 plan 摘要，避免两套描述漂移。

---

## 11. 待确认决策

- **D1** 是否需要我按阶段 A 直接开始实现？（本文件目前只是方案）
- **D2（已确定）** IARU 的 ITU Zone：素材无 `ituz`、无默认 → **不填默认，必须用户手填**；开赛前校验拦截。
- **D3（已确定：L0）** ARRL DX 的 W/VE 州/省侧本次不做；L1/L2 方案保留在 §12，记入 §14 后续工作。
- **D4（已确定）** JIDX exchange 已确认（JA 都道府县 01–50；非 JA CQ Zone）；规则来源见 §13.3；**不采纳** `rulesUrl` / `ruleRevision` 机制。
- **D5（已确定）** 取值优先级：显式配置 > 可派生默认值；取不到则必填，**station config 未完全填好不允许开始比赛**。
- **D6（已确定：先不做）** 我方 exchange 的记录（metadata 快照 / 逐 QSO）本次不做；方案见 §15，记入 §14 后续工作。

---

## 12. 附录：D3 详述 —— ARRL DX 的 W/VE 州/省侧

> **决定（本次）**：采用 **L0**（不做 W/VE 州/省侧）。L1/L2 方案保留在本附录，并记入 §14 后续工作。

### 12.1 规则与两种身份

ARRL International DX Contest（SSB）exchange：

- **W/VE 台**：RST + 州/省（state/province）；
- **DX 台**：RST + 发射功率（power）。

规则以当期官方文件为准：<https://contests.arrl.org/ContestRules/DX-Rules.pdf>。

因此"W/VE 侧"在 App 里有**两个独立方向**，不要混为一谈：

| 方向 | 场景 | 影响 |
|---|---|---|
| (a) 我方是 W/VE | 操作员呼号属 US(adif 291)/Canada(1) | 我方发送的 exchange 是州/省字母，而不是功率 |
| (b) 对方是 W/VE | 入站台呼号属 US/Canada | 对方应发州/省字母，需要生成、输入、播放、校验 |

### 12.2 现状差距（代码证据）

- `ArrlDxDefinition` 目前继承 `_NumericContestDefinition`（`contest_definition.dart:85-100`），`maxExchange = 1500` → **所有**入站台（含 W/VE）都生成 1..1500 的数字，语义上把 W/VE 也当成 DX 功率；
- `_NumericContestType.allowExchangeRegex = RegExp("[0-9]")`（`contest_definition.dart:173`）→ Exchange 输入框**过滤掉字母**，操作员根本无法录入州/省；
- 我方 exchange 在本方案阶段 A 里，ARRL 计划固定为 `[power]`（§6.4），没有 W/VE 分支；
- 语音素材（`assets/voice`）：每个 accent 只有 `ICAO/`、`Location/`、`Alphabet/` 三类**逐字母**片段；`Global/`（我方口音）只有 `ICAO`；**没有任何州名/省名整词素材**（`find` 全库无 `texas/state/province`）。

入站池 W/VE 占比（用 cty 前缀表对本仓库 46,040 条呼号实测）：

| 实体 | adif | 数量 | 占比 |
|---|---|---|---|
| United States | 291 | 15,699 | 34.1% |
| Canada | 1 | 1,248 | 2.7% |
| **W/VE 合计** | | **16,947** | **36.8%** |

即在 ARRL DX 训练里，约 **37% 的入站 exchange 语义是错的**（该报州/省，却报了功率数字）。

### 12.3 三个支持级别

| 级别 | 内容 | 素材改动 | 改动量 | 真实度 |
|---|---|---|---|---|
| **L0** | 维持现状：W/VE 也发功率，我方只做功率 | 无 | 无 | ARRL 约 37% 来台 exchange 语义错误 |
| **L1** | 用 2 字母代码作为规范值，逐字母朗读 | **无**（复用现有片段） | 小 | 可接受；美式口语也常用字母 |
| **L2** | 州名/省名整词朗读（TEXAS.wav 等） | 需补 US 50+DC、Canada 13 的整词录音 | 大（素材工程） | 最接近真实 SSB 口语 |

**推荐 L1**：零素材改动即可同时覆盖 (a)(b) 两个方向；L2 作为后续音频真实度提升单独评估。

### 12.4 L1 的具体改动

1. **数据表**（新增，例如 `lib/contest_type/arrl_dx/regions.dart`）：
   - US：50 州 + DC（如 `TX`、`CA`、`DC`…）；
   - Canada：13 省/地区（如 `ON`、`QC`、`BC`…）；
   - 提供 `isValidRegion(String)` 与 `randomRegion(SessionRandom)`。
2. **我方为 W/VE**（方向 a）：
   - `ArrlDxDefinition.myExchangePlan` 按 station DXCC 分支：W/VE → `[stateProvince]`，否则 `[power]`；
   - `StationExchangeField(id: "stateProvince", label: "State/Province", numeric: false, audioDigits: 0)`；UI 建议用下拉选择，避免拼错；
   - 播放走 `CallsignPayload`：`Global/ICAO` 逐字母（TX → "Tango X-ray"）。
3. **对方为 W/VE**（方向 b，依赖阶段 C 的 caller-aware 接口）：
   - `generateExchange(random, callerCallsign)` 按 caller DXCC 分支：W/VE → 从州/省表随机，否则 → 功率；
   - `allowExchangeRegex` 放宽为 `[A-Za-z0-9]`（ARRL 专用），否则字母被过滤；
   - 提交时按当前题目的 exchange 类型做一次校验（州/省必须是合法 2 字母码，功率必须是数字），比单纯放宽正则更严谨；
   - 播放 `isMe: false` 时走 `formatExchangeForAudio` 原样，逐字母用**来台 accent 的 phonic**（`US/ICAO` 或 `US/Location`，取决于设置里的 Phonic Type）。
4. **比较与记录**：规范值统一大写 2 字母；`processExchange` 现有"去前导零"对字母无副作用，大写由 `UpperCaseTextFormatter` 保证；QSO 表/Cab corrections 列展示 2 字母不受影响。
5. **不做的事**：不改计分（ARRL `pointsFor` 恒 3，州/省不影响 multiplier 口径）；不改状态机。

### 12.5 局限与风险

- **州/省与来台呼号不完全对应**：cty 只给 DXCC 与 `cqz`，没有"呼号→州"映射。L1 只能从州/省表随机；US 呼号区号（W0–W9）也不能唯一定州。训练可接受，若要更真可在后续按区号加权。
- **听感不是整词**：L1 读 `TX` 为 "Tango X-ray" 而非 "Texas"；对抄收训练而言，字母码仍是有效练习（且 DX 台常这么发）。
- **随机序列变化**：方向 b 引入 caller-aware 抽取，会改变 `questionSeed` 的题目序列（与阶段 C 同一条，见 R6），需显式版本化。
- **正则放宽的副作用**：ARRL 输入框会接受字母，数字题里也能敲字母；通过提交时按题目类型校验即可，最坏也只是记一次错（训练无妨）。
- **素材清单**：L1 不改 `pubspec.yaml` / submodule；L2 则需要同时改 `assets` submodule、`pubspec.yaml`，并新增非逐字符的音频 payload 类型与 `AudioLoader` 分支。

### 12.6 L1 的测试点

- `ArrlDxDefinition.myExchangePlan(callsign: "W1AW")` → `[stateProvince]`；`("BI1QJQ")` → `[power]`；
- 我方 W/VE 配 `"TX"` → `buildMyExchange(3)` = `"TX"`，且 `validatePlan` 对非法值（如 `"ZZ"`）报错；
- 入站 W/VE（fake DXCC = 291）→ `generateExchange` 返回合法州/省码；DX → 数字功率；
- `allowExchangeRegex` 放行字母；
- 未配置 stateProvince 的我方 W/VE → RUN 被拦截（§6.8 门槛）。

---

## 13. 附录：D4 详述 —— JIDX exchange 规则与各比赛规则版本

### 13.1 D4 的两个部分

1. **规则确认**：JIDX 的 exchange（JA 与 非 JA 两类参加者）；
2. **版本治理**：五场比赛的官方规则来源、exchange 的稳定性；规则版本仅在本文档 §13.3 记录，不进入代码模型。

### 13.2 JIDX SSB exchange（已确认）

官方来源：JARL / JIDX 官方规则页。两类参加者的 exchange：

- **JA 台**：RS(T) + 都道府县号码（Prefecture number，01–50），两位。号码由电台所在地决定，**不能从呼号自动推出**；
- **非 JA 台**：RS(T) + CQ Zone number（**不是序号**）。

对本 App 的落点：

- **方向 (a) 我方**：
  - station 属 JA（DXCC 339 Japan / 192 Ogasawara / 177 Minami Torishima）→ 我方发都道府县，作为 station config 的 `prefecture` 字段手填，范围 01..50、朗读补 2 位；
  - station 非 JA（如 `BI1QJQ`）→ 我方发 CQ Zone，字段与 CQ WW 相同（可 `derive` 自呼号，如 `BI1QJQ` → 24），朗读补 2 位。
  - **JIDX 全程没有 serial**：`sendsSerial = false`。
- **方向 (b) 对方**（阶段 C）：
  - 来台属 JA → 生成都道府县（01..50）；
  - 来台非 JA → 生成**该台的 CQ Zone**（优先 `findCallsignCqZone(caller)`，缺失再随机 1..40）。
- **与早期假设的差异**：本方案初稿曾假设"非 JA 发序号"，已按官方口径更正为 **CQ Zone**；因此 JIDX 的 plan 从 `sendsSerial` 改为 `[prefecture]`（JA）或 `[cqZone]`（非 JA），`audioDigits` 均为 2。
- **都道府县范围**：按官方 01–50；本仓库没有都道府县编号表，需要内置一份 01..50 的合法值表（用于校验/生成）。
- **风险标注**：本环境网络受限，无法拉取 JIDX 官方 PDF 原文；以上按你提供的官方口径（JA: Prefecture number 01–50；Others: CQ Zone number）落地。

### 13.3 五场比赛的规则来源与版本敏感性

| Contest | 官方规则（来源） | 官方 exchange | 版本敏感点 |
|---|---|---|---|
| CQ WPX SSB | <https://cqwpx.com/> | RS(T) + 序号（001 起） | exchange 稳定；分数/系数规则年度可能调整 |
| CQ WW SSB | <https://cqww.com/> | RS(T) + CQ zone（1–40） | zone 表稳定；分类与得分规则调整 |
| IARU HF | <https://contests.arrl.org/> | RS(T) + ITU zone；IARU HQ 台加 society 缩写 | HQ 缩写随 member society 变动；本 App 不做 HQ |
| ARRL DX SSB | <https://contests.arrl.org/ContestRules/DX-Rules.pdf> | W/VE：RS(T) + 州/省；DX：RS(T) + 功率 | 州/省列表（含 DC）、功率表述 |
| JIDX SSB | JARL / JIDX 官方页 | JA：RST + 都道府县（01–50）；非 JA：RST + CQ Zone | 非 JA 为 CQ Zone，无 serial（见 13.2） |

总体判断：**exchange 格式多年稳定，真正随年度变动的是日期、分类、功率限制与计分细则**；而本 App 是训练档案、不做 Cabrillo 认证，所以规则版本对 exchange 生成的影响很小。规则来源在本文档 §13.3 维护，不进入代码模型（见 13.4）。

### 13.4 规则版本字段：不采纳（已决定）

曾评估给 `ContestDefinition` 增加 `rulesUrl` / `ruleRevision`、设置页展示、`TrainingRunMetadata` 快照、单测断言非空。**决定不采纳**，理由：

- 本 App 是单波段训练档案、不做 Cabrillo 认证，规则版本对 exchange 生成的影响本就很小（见 13.3）；
- 引入字段会增加契约面、设置页 UI 与迁移成本，收益有限；
- 规则来源已记录在 §13.3 的文档表格中，需要时在文档层面更新即可，无需进代码模型。

如果将来要做正式计分 / Cabrillo 日志导出，再重新评估这一机制。

### 13.5 D4 结论

- **JIDX exchange 已确认**：JA = RS(T) + 都道府县号码（01–50）；非 JA = RS(T) + CQ Zone number；**JIDX 全程没有 serial**；
- 规则版本字段（`rulesUrl` / `ruleRevision`）：**不采纳**（见 13.4）；D4 至此全部关闭。

---

## 14. 后续工作（本次不做）

| 项 | 来源 | 说明 |
|---|---|---|
| ARRL DX W/VE 州/省侧（L1 字母拼读） | D3 / §12.4 | 复用现有逐字母素材，零素材改动；覆盖"我方或对方为 W/VE" |
| ARRL DX 州名整词音频（L2） | D3 / §12.3 | 需补 US/Canada 整词录音 + submodule + 非逐字符音频 payload 分支 |
| 入站 exchange 真实化 | §6.10 阶段 C | caller-aware 生成（CQ zone / 州/省 / 都道府县） |
| 我方 exchange / station 配置的记录（D6） | D6 / §6.11 / §15 | 本次采用 A；后续推荐 B+C：TrainingRunMetadata 快照 stationCallsign + stationExchange，并在 QsoTable 增加 myExchange 列（随 schema v3 迁移） |
| cty 素材更新（ituz） | R2 / D2 | 若将来要自动派生 ITU Zone 才需要 |

---

## 15. 附录：D6 详述 —— 我方 exchange 的记录与重放精确度

> **决定（本次）**：采用 **A（先不记录）**。B / C / B+C 方案保留在本附录，并记入 §14 后续工作。

### 15.1 现状：重放机制记录了什么

- **题目（来台）逐条记录**：`contest_manager.dart:68-79` 的 `_recordAnswer` 把每条 answer 写入 `EventLogTable`；`contest_manager.dart:274-287` 的 `_loadEvents` 按 runId 读回；`training/replay_answer_source.dart` 优先回放记录，算法变化也照样重放（§5.5 的"记录优先"）。
- **TrainingRunMetadata**（`session_review.dart:5-31`）记录 runId / contestId / contestName / modeId / difficultyId / questionSeed / audioSeed / startedAt / appVersion；**没有 stationCallsign，也没有 station exchange 配置**。
- **QsoTable**（`db/table/qso_table.dart`）每行有 `stationCallsign`、his call / his exchange / correct answers；**没有"我方发送的 exchange"列**。
- **我方 exchange 在重放时是重新计算的**：`buildMyExchange(qsoNumber)` 的输入是"当前 stationCallsign + 当前 station exchange 配置 + 当前 run 的 QSO 计数 + contest 规则代码"。

### 15.2 因此存在这些不一致场景

| # | 场景 | 重放时我方 exchange 是否一致 |
|---|---|---|
| S1 | 重放前改了 station callsign | 不一致：我方 CQ / 呼号音频会变（呼号音频本来就没记录） |
| S2 | 重放前改了 station exchange 配置（CQ Zone / ITU Zone / Power / Prefecture） | 不一致 |
| S3 | 重放前改了 contest | 一致：`training_review_overlay._replay` 会把 contestId 设回去 |
| S4 | 代码里 `buildMyExchange` 的规则被修正 | 不一致 |
| S5 | WPX 序号随 QSO 数变化 | 只要完成的 QSO 数一致就一致；操作次数不同属"操作员行为"，本就不在重放保证范围（§5.5） |

结论：**S2 最现实**（用户重放前调了配置），**S4 是设计原则最在意的**（"历史日志必须永久可重放，即使生成算法调整"）。

### 15.3 四个落点选项

| 选项 | 存放 | 覆盖 | 成本 | 与 §5.5 "记录优先" |
|---|---|---|---|---|
| **A** 不记录（现状） | — | 都不覆盖 | 0 | 低 |
| **B** metadata 快照 | `TrainingRunMetadata` 增加 `stationCallsign` + `stationExchange`（显式值） | S1、S2；S4 不覆盖（仍重算） | 小 | 中 |
| **C** 逐 QSO 记录 | `QsoTable` 增加 `myExchange` 列（推荐）或 `EventLogTable` 增加 my-exchange 事件 | S1–S4 全覆盖 | 小到中 | 高 |
| **D** B + C | 两者 | 全覆盖，且能说明"这局的操作员与配置" | 中 | 高 |

### 15.4 推荐：B + C（QsoTable 列）

1. **B：metadata 快照**——最小修复 S2，同时让复盘/导出能说明"这一局操作员是谁、用了什么 station 配置"；
2. **C：`QsoTable` 增加 `myExchange`**——把"我方这一 QSO 发了什么"写进 QSO 记录：
   - 重放时按 runId + 顺序直接复用，无需重算，彻底覆盖 S4；
   - 未来做 Cabrillo 导出时，sent exchange 本来就是必需字段；
   - 与 §5.5"以记录的真实答案为准"原则一致；
   - schema 可与阶段 B 的 v3 迁移**合并成一次迁移**（cqz + myExchange）。
   - 若不想动 `QsoTable`，可退化为 `EventLogTable` 增加 my-exchange 事件（按 QSO 序号关联），覆盖能力相同，但查询/导出不如 QSO 列直观。

不建议只做 A。

### 15.5 接线清单（若采纳 B+C）

- `TrainingRunMetadata` 增加 `stationCallsign`、`stationExchange`（JSON 可选，decode 缺省为空；兼容旧记录，写法参考现有 legacy seed 的兜底）；
- `QsoTable` 增加 `myExchange`（TextColumn，可空/默认空串），并入 schema v3；
- `contest_manager.dart` 创建 metadata 时写入 stationCallsign + 配置；`_handleQsoEnd` 写 QSO 时带上我方 exchange；
- 重放路径：`training_review_overlay._replay` 除现有 pending* 外，补充 stationCallsign / stationExchange；或让 `ContestManager` 按 runId 从 sessionHistory 取 metadata；
- `startContest()` 在重放时用 metadata 快照构造 `ContestType`，而不是读当前设置；
- 重放时若存在逐 QSO 的 `myExchange`，**优先用记录值**，不再重算；
- 单测：先跑一局记录，再改当前 station 配置，重放后我方逐 QSO exchange 与原始记录一致；旧记录（无新字段）可解码不崩。

### 15.6 重放确定性边界（更新）

原 §5.5 边界：完全可复现 = 题目序列 / 交换 / 音效；不可复现 = QSO 间隔与速率、操作员输入时序。

若采纳 B+C，补充：**我方发送的 exchange 进入"完全可复现"**（前提是该局有完整逐 QSO 记录）；stationCallsign 音频与操作员行为仍不保证。

### 15.7 D6 结论

- **本次采用 A（先不记录）**：不加 `myExchange`、不做 metadata 快照，重放时我方 exchange 仍按当前配置与规则重算；
- 已知代价：S2（重放前改配置）与 S4（规则修正）下，重放的我方发送内容可能与原始局不一致；
- 后续若采纳，推荐顺序是 **B+C**（或只做 C 的 `QsoTable` 列）；方案保留在 §15.3–15.6。
