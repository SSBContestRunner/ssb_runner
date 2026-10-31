# Contest 规则说明入口技术方案

> 状态：已确认，按本方案实施（决策项已按默认结论固化，见 §8.1）
> 背景：设置页只能看到每个比赛的 Exchange 格式串（如 `59 #`），新人无法从中判断“抄收什么、发什么”，需要额外查阅比赛规则。
> 目标：在 Settings 的 Contest 分区标题旁增加一个 `info` 图标，点击弹出该比赛的简要规则说明，覆盖 5 个已支持比赛。
> 范围：纯展示型改动，不参与运行逻辑、不改变状态机与比分计算。

---

## 1. 结论摘要

- 图标放在 **Contest 分区标题行右侧**（`SettingItem` 的标题区），而不是内容区，保持与其它三个分区一致的层级。
- 点击后用 `showDialog` 打开 `AlertDialog`，复用 [options_setting.dart](../../lib/ui/main_settings/options_setting.dart) 已有的设置类弹窗风格；**不复用** [key_tips.dart](../../lib/ui/main_page/key_tips.dart) 的 `MainPageCubit` + Stack 覆盖层，避免设置面板反向依赖主页面。
- 规则文案按比赛 id 存进 5 个 ARB 文件；`ContestDefinition` 增加英文兜底 `rulesSummary`，`DomainL10n` 增加 `contestRulesSummary(id, fallback)`，沿用 `contestExchangeLabel` 的既有模式。
- 改动集中在 `lib/ui/common/setting_item.dart`、`lib/ui/main_settings/`、`lib/contest_type/contest_definition.dart`、`lib/l10n/`，不触碰运行期。

---

## 2. 现状（代码核对）

| # | 位置 | 事实 |
|---|---|---|
| E1 | `lib/ui/main_settings/main_settings.dart:63-66` | Contest 分区为 `SettingItem(title: l10n.settingsContest, content: _ContestSettings())` |
| E2 | `lib/ui/common/setting_item.dart:3-7, 27-35` | `SettingItem` 只有 `title` + `content`，标题是单个 `Text`，无 trailing 位 |
| E3 | `lib/ui/main_settings/main_settings.dart:90-103` | `ContestSettingCubit` 持有当前 `ContestDefinition`，切换比赛时 `emit`，可直接作为弹窗数据源 |
| E4 | `lib/ui/main_settings/main_settings.dart:148-199` | Name 下拉与 Exchange 只读框已是 `BlocBuilder`，比赛进行中通过 `isEnabled` 禁用 |
| E5 | `lib/ui/main_settings/main_settings.dart:54-55` | 整个设置面板包在 `ExcludeFocus`（只影响键盘焦点，不拦截点击） |
| E6 | `lib/ui/main_settings/options_setting.dart:309-324, 347-360` | 现有设置弹窗统一用 `showDialog` + 私有 Widget，可作范式 |
| E7 | `lib/ui/main_page/key_tips.dart:6-79`、`main_page_cubit.dart:3-11` | 键盘速查是主页面 Stack 覆盖层，与设置面板无耦合通道 |
| E8 | `lib/ui/bottom_panel/qso_operation_area.dart:461-478` | 已有一个 `Icons.info_outlined` 的 `IconButton.filledTonal` + Tooltip |
| E9 | `lib/l10n/domain_l10n.dart:63-71` | `contestExchangeLabel(id, fallback)` 已按 contest id 解析 ARB 文案 |
| E10 | `lib/contest_type/contest_definition.dart:36-49` | `ContestRegistry.all` 固定 5 个 definition，id 稳定 |
| E11 | `l10n.yaml:1-12` | 模板为 `app_en.arb`，支持 en / zh / zh_Hans / zh_Hant / ja |

---

## 3. 目标与非目标

### 3.1 目标

1. 新人无需离开应用即可看到每个比赛“我方发什么、对方发什么、录入什么”。
2. 文案随语言本地化，未知比赛 id 有英文兜底，不出现空白。
3. 比赛进行中仍可查看规则（只读），不影响现有设置禁用逻辑。
4. 改动最小化，`SettingItem` 的新增参数对其它三个分区零影响。

### 3.2 非目标

- 不展示完整官方规则、不计分公式明细、不链接外部网页。
- 不改变 `myExchangePlan`、`ExchangeManager`、`ScoreCalculator` 或状态机。
- 不做首次启动自动弹窗、不做 “不再提示” 的持久化开关。

---

## 4. UI 设计

> 以下为结构示意，字符宽度不严格对齐像素；实际由 Material 组件渲染。

### 4.1 整体位置

```
+---------------------------------------------------------------+
|  主页面                                                        |
|  +------------------------------------+  +-------------------+ |
|  |  QSO 记录表                        |  |  Settings 侧栏     | |
|  |                                    |  |  (370px)           | |
|  |                                    |  |  +-------------+   | |
|  |                                    |  |  | Contest (i) |   | |  <- 新增 (i)
|  |                                    |  |  +-------------+   | |
|  |                                    |  |  +-------------+   | |
|  |                                    |  |  | Station     |   | |
|  |                                    |  |  +-------------+   | |
|  |                                    |  |  +-------------+   | |
|  |                                    |  |  | Options     |   | |
|  |                                    |  |  +-------------+   | |
|  +------------------------------------+  +-------------------+ |
+---------------------------------------------------------------+
```

### 4.2 Contest 卡片：改前 / 改后

```
改前                                      改后
+--------------------------------+        +--------------------------------+
| Contest                        |        | Contest                  (i)   |
| [ Name                CQ WPX v]|        | [ Name                CQ WPX v]|
| [ Exchange              59 #  ]|        | [ Exchange              59 #  ]|
+--------------------------------+        +--------------------------------+
```

规格：

- `(i)` 为 32×32 `IconButton`，图标 `Icons.info_outlined`，与 [qso_operation_area.dart](../../lib/ui/bottom_panel/qso_operation_area.dart:461-478) 视觉一致。
- 带 `Tooltip`（“比赛规则 / Contest rules”），并设置 `Semantics` 标签，保证可读性。
- 标题行改为 `Row`：`Text(titleMedium)` + `Spacer()` + trailing；左右内边距沿用 `SettingItem` 的 14px。
- 其它分区不传 trailing，布局与渲染结果不变。

组件树变化：

```
SettingItem
└─ Column
   ├─ Row                      ← 新增（原为 Text）
   │  ├─ Text("Contest")
   │  ├─ Spacer
   │  └─ IconButton( (i) )
   └─ _ContestSettings
      ├─ DropdownMenu  (Name)
      └─ TextField     (Exchange, 只读)
```

### 4.3 弹窗

```
        +------------------------------------------+
        | CQ WPX 规则                              |
        |                                          |
        | 我方发送 ：59 + 序号（3 位）             |
        | 对方发送 ：呼号 + 序号                   |
        | 录入     ：呼号 + 序号，全部正确才计分    |
        |                                          |
        |                                  [关闭]  |
        +------------------------------------------+
        (背景：scrim 半透明遮罩，点击遮罩关闭)
```

- `AlertDialog`，`scrollable: true`，最大宽度约 420，`insetPadding` 约 24。
- 标题：带 `{contest}` placeholder 的 l10n key（如 “{contest} 规则 / {contest} Rules”）。
- 正文：每场比赛 3 行纯文本（我方发送 / 对方发送 / 录入提示），逐行 `Text` 渲染，长行自然换行。
- 关闭方式：底部 “关闭” 按钮、ESC、点击遮罩；**不设右上角 `X`**（减少一个无障碍标签与一整套 l10n 文案）。
- 弹窗内容在打开瞬间读取 `ContestSettingCubit` 的当前值，切换比赛后再次打开即显示新内容。

不同比赛的正文长度差异（同一布局，自动换行 / 滚动）：

```
ARRL DX 规则
+------------------------------------------+
| 我方发送 ：W/VE -> 59 + 州/省            |
|            DX   -> 59 + 功率（瓦）        |
| 对方发送 ：按对方身份对应                 |
| 录入     ：呼号 + 州/省 或 功率           |
+------------------------------------------+
```

### 4.4 状态与交互

```
                  click (i)                Close / ESC / scrim
[ Contest 卡片 ] -----------------> [ AlertDialog ] -----------------> [ Contest 卡片 ]
                        打开时读当前 ContestSettingCubit 状态
```

```
状态                            标题 (i)          Name/Exchange 字段
------------------------------------------------------------------
未开始比赛                      可点击            可编辑
比赛进行中 (isContestRunning)    可点击（只读查看） 禁用/灰显
```

说明：`ExcludeFocus` 只排除键盘焦点，不拦截指针事件，因此比赛进行中图标仍可点击；字段禁用逻辑不变。

### 4.5 窄窗口与长文案

```
窗口宽度 >= 480                窗口宽度 < 480
+----------------------+       +------------------+
| 弹窗 420 宽居中       |       | 弹窗宽度 = 屏宽-32 |
|                      |       | 正文可滚动        |
+----------------------+       +------------------+
```

- 侧栏 370px 下标题为短词（Contest / Station / Options / Diagnostics），新增 32px 图标不会造成挤压。
- `AlertDialog` 已有宽度约束，但需确认 `insetPadding` 在最小窗口尺寸下不会溢出；必要时用 `ConstrainedBox` 限宽。

---

## 5. 数据与本地化

### 5.1 领域兜底

在 `ContestDefinition` 增加：

- `String get rulesSummary;`：英文一行式规则摘要，作为未知 id 的兜底；5 个 definition 各自返回固定英文串。
- 与 `exchangeLabel` / `scoringNotice` 同层，保持“领域对象只保留稳定 id + 英文兜底”的既有约定。

在 `DomainL10n` 增加：

- `String contestRulesSummary(String contestId, String fallback)`：按 id 映射到 ARB（`CQ-WPX` / `CQ-WW-SSB` / `ARRL-DX` / `IARU-HF` / `JIDX-SSB`），未命中返回 `fallback`。

### 5.2 ARB key 设计

只增加 3 类 key，避免 5 场比赛 × 3 行 × 5 语言的大量碎片：

| key | 用途 |
|---|---|
| `contestRulesTooltip` | 图标 Tooltip / 无障碍标签 |
| `contestRulesTitle` | 弹窗标题，placeholder `{contest}` |
| `contestRulesCqWpx` / `contestRulesCqWw` / `contestRulesArrlDx` / `contestRulesIaruHf` / `contestRulesJidx` | 每场比赛 3 行正文，用 `\n` 分隔 |

需要同步修改的 ARB：

- `lib/l10n/app_en.arb`（模板，需要写 `@` metadata 的 placeholder）
- `lib/l10n/app_zh.arb`
- `lib/l10n/app_zh_Hans.arb`
- `lib/l10n/app_zh_Hant.arb`
- `lib/l10n/app_ja.arb`

生成：

- 执行 `flutter gen-l10n`，产物在 `lib/l10n/generated/`。
- 检查 `build/l10n_untranslated.json` 为空，避免 CI 的未翻译告警。

### 5.3 文案内容（初稿）

| 比赛 | 我方发送 | 对方发送 | 录入提示 |
|---|---|---|---|
| CQ WPX | 59 + 3 位序号 | 呼号 + 序号 | 呼号 + 序号，全部正确才计分 |
| CQ WW | 59 + CQ 分区 | 呼号 + CQ 分区 | 呼号 + CQ 分区 |
| ARRL DX | W/VE：59 + 州/省；DX：59 + 功率 | 按对方身份对应 | 呼号 + 州/省 或 功率 |
| IARU HF | 59 + ITU 分区 | 呼号 + ITU 分区 | 呼号 + ITU 分区 |
| JIDX | JA：59 + 都道府县编号；非 JA：59 + CQ 分区 | 按对方身份对应 | 呼号 + 都道府县 或 CQ 分区 |

注意：文案与 `myExchangePlan` 是两份描述。若以后修改 ARRL/JIDX 的字段或位数，需同步更新 ARB；在 `rulesSummary` 上写注释说明。

---

## 6. 改动清单

| 文件 | 改动 |
|---|---|
| `lib/ui/common/setting_item.dart` | 新增可选 `titleTrailing`（默认 `null`），标题改为 `Row` |
| `lib/ui/main_settings/main_settings.dart` | Contest 分区传入规则按钮 widget；按钮 `watch(ContestSettingCubit)` 取当前比赛 |
| 新增 `lib/ui/main_settings/contest_rules_dialog.dart` | 公开 `ContestRulesDialog`，接收 `ContestDefinition` |
| `lib/contest_type/contest_definition.dart` | 5 处新增 `rulesSummary` 英文兜底 |
| `lib/l10n/domain_l10n.dart` | 新增 `contestRulesSummary(id, fallback)` |
| 5 个 ARB + 生成的 `app_localizations*.dart` | 新增文案 |
| `test/ui/main_settings_test.dart` | 新增弹窗打开 / 切换比赛 / 关闭的 widget 测试 |

不新增依赖，不改 `pubspec.yaml`。

---

## 7. 测试计划

- Widget（`test/ui/main_settings_test.dart`）：
  1. pump 设置面板 → 点击 `Key('contest-rules-button')` → 断言弹窗标题与当前比赛正文；
  2. 将 Name 下拉切到 CQ WPX → 再次点击 → 断言正文切换为 CQ WPX；
  3. 点击 “关闭” → 断言弹窗消失、无异常。
- 单元：遍历 `ContestRegistry.all`，断言 `rulesSummary` 非空，防止新增比赛漏写兜底。
- 回归：现有 “Contest and Exchange fill the panel width on separate rows”（`main_settings_test.dart:31-59`）应继续通过，验证 `SettingItem` 改动无副作用。
- 可点击性：比赛进行中（`isContestRunning = true`）时图标仍可点击，字段仍禁用。

测试细节：主页面底部面板已存在一个 `Icons.info_outlined`，全页面级测试不要用 `find.byIcon`，统一使用 `Key('contest-rules-button')`。

---

## 8. 风险与已确认结论

| # | 风险 | 处理 |
|---|---|---|
| R1 | 规则文案与运行逻辑漂移 | 文案仅描述交换，不写分数公式；在代码注释中标注同步点 |
| R2 | CJK 长文案在小窗口溢出 | `scrollable` + 限宽，必要时正文按行分包 |
| R3 | 两个 info 图标导致测试歧义 | 使用 `Key` 定位 |
| R4 | 新增 ARB key 漏翻译 | `flutter gen-l10n` + 检查 `l10n_untranslated.json` |
| R5 | `SettingItem` 改动影响其它分区 | `titleTrailing` 默认 `null`，不改默认布局 |

### 8.1 已确认结论（定稿）

| # | 决策点 | 结论 | 依据 |
|---|---|---|---|
| D1 | 比赛进行中是否允许查看规则 | **允许，只读** | `ExcludeFocus` 只影响键盘焦点，点击不受限；规则是解释性内容，查看无风险 |
| D2 | 弹窗是否包含 `scoringNotice` | **不包含** | 该字段当前仅英文且未本地化，混排会破坏 5 语言体验；后续本地化后再评估 |
| D3 | “我方发送” 一行是否由 `myExchangePlan` 动态生成 | **静态文案** | 规则说明面向新人，措辞需要自然语言；动态拼装会把 ARRL/JIDX 的身份分支引入 UI 层，收益不匹配复杂度 |
| D4 | 弹窗是否提供右上角 `X` | **不提供** | 底部“关闭”+ ESC + 遮罩点击已覆盖关闭路径，少一个 l10n 与无障碍标签 |
