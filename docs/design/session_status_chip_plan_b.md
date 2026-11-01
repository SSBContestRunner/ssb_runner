# 会话卡片底部改造 · 方案 B（含 V2 就绪 chip）技术方案

## 1. 背景

训练会话卡片（`lib/ui/main_page/session_panel.dart`）底部当前纵向堆叠了三层：就绪横幅、开始按钮、说明文字。就绪时横幅仍占一整块绿色底，导致：

- 纵向信息过密，主操作（开始训练）被向上推移；
- 就绪横幅与「运行中」状态都使用 success 色系，语义不清晰。

已通过临时 HTML 原型对比 5 个方案，最终选定：

- **方案 B**：删除底部横幅，就绪信息并入标题栏右上角状态 chip；
- **V2 配色**：就绪 chip 使用主色容器（蓝底 + 勾），与「运行中」的绿色实底区分。

## 2. 目标与非目标

目标：

1. 底部区域只保留「开始/停止按钮 + 一行说明」，就绪态净高从 118px 降到 77px；
2. 状态 chip 在同一位置表达三种状态，颜色/图标/文案三重可区分；
3. 就绪时不再出现任何整块色带；
4. 校验逻辑仍只有 `checkSettingsReadiness` 一个来源。

非目标：

- 不改按钮尺寸、计时区、进度条、成绩区；
- 不改设置抽屉、问题清单弹窗的内容；
- 不新增暂停或其它运行控制。

## 3. 最终视觉规范

### 3.1 状态矩阵

| isRunning | issues | chip 状态 | 底色 | 前景 | 左侧标记 | 文案 key | 可点击 |
|---|---|---|---|---|---|---|---|
| true | 忽略（不评估） | running | `successContainer` | `onSuccessContainer` | 7px 实心圆点 | `sessionStatusRunning` | 否 |
| false | 0 | ready | `primaryContainer` | `primary` | `Icons.check_rounded` 14px | `sessionStatusReady` | 否 |
| false | >0 | pending | `errorContainer` | `onErrorContainer` | 7px 实心圆点 | `sessionStatusPending(count)` | 是，打开问题清单 |

补充约束：

- chip 尺寸不变：高 26、左右内边距 10、圆角 8、图标与文字间距 6、文字 `labelSmall`（12/17，w600，字距 0.5）。
- 圆圈点沿用现有 `_StatusChip` 的 7px 圆点实现；就绪态改为勾图标，形成「勾 / 点」的形态差异。
- 就绪态**不使用**任何 success 色，绿色仅保留给运行中；红色仅保留给待处理。
- 深色模式全部走 `ColorScheme` 角色，不写死颜色。`primaryContainer` 深色为 `#00498C`、`primary` 为 `#A7CCFF`。
- 就绪态的勾与文字用 `primary`（浅色 `#0059BA`、深色 `#A7CCFF`），不用 `onPrimaryContainer`：后者偏深，视觉上会被读成藏青而不是原型里的品牌蓝。
- 运行中不评估设置：即使运行期改了设置，chip 仍为运行中，避免中途打断（保持现有行为）。

### 3.2 底部区域

| 状态 | 结构 | 净高 | 合计（含 18px 内边距） |
|---|---|---|---|
| 就绪 | 按钮 52 + 8 + 说明 17 | 77 | 95 |
| 待处理 | 按钮 52 + 8 + 说明 17 | 77 | 95 |
| 运行中 | 按钮 52 + 8 + 说明 17 | 77 | 95 |

异常时不再补一条横幅：点击按钮时若仍有 issues，仍弹出 `showSettingsIssuesDialog`（现有行为保留），且 chip 也提供同一入口。

## 4. 组件与数据流改造

### 4.1 现状问题

- `_RunSection` 内部用 `BlocBuilder<_RunBtnCubit, bool>` + `ValueListenableBuilder` 计算 readiness；
- `_StatusChip` 只监听 `_RunBtnCubit`，完全不知道 readiness；
- 若在 `_StatusChip` 中再算一次，会出现两处独立计算，存在漂移风险。

### 4.2 改为单次计算、下发给两个子组件

`_SessionCard.build` 提升为唯一的计算点：

```dart
class _SessionCard extends StatelessWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final settings = context.read<AppSettings>();
    final dxccManager = context.read<DxccManager>();
    final contest = context.watch<ContestSettingCubit>().state;
    final options = context.watch<TrainingOptionsCubit>().state;
    final isCompact = MediaQuery.sizeOf(context).height <= 700;

    return BlocBuilder<_RunBtnCubit, bool>(
      builder: (context, isRunning) {
        return ValueListenableBuilder<int>(
          valueListenable: settings.settingsRevision,
          builder: (context, _, _) {
            final issues = isRunning
                ? const <SettingsIssue>[]
                : checkSettingsReadiness(
                    settings: settings,
                    dxccManager: dxccManager,
                  );

            return Container(
              // 外观不变
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(child: /* 标题与副标题，不变 */),
                          _StatusChip(isRunning: isRunning, issues: issues),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: /* 计时、进度、成绩，不变 */),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: _RunSection(isRunning: isRunning, issues: issues),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
```

注意：

- 标题与副标题仍读 `ContestSettingCubit` / `TrainingOptionsCubit`，这两个 watch 保持在 `build` 开头，重建粒度不变；
- 计算只在 `settingsRevision` 变化或运行状态切换时触发，与现状一致；
- 原先 `_RunSection` 和 `_StatusChip` 内的 `BlocBuilder` 一并删除，避免同一帧内两条订阅。

### 4.3 `_StatusChip` 新签名

```dart
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isRunning, required this.issues});

  final bool isRunning;
  final List<SettingsIssue> issues;
  ...
}
```

内部：

```dart
final isPending = !isRunning && issues.isNotEmpty;
final background = isRunning
    ? semantic.successContainer
    : isPending
        ? scheme.errorContainer
        : scheme.primaryContainer;
final foreground = isRunning
    ? semantic.onSuccessContainer
    : isPending
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;
final label = isRunning
    ? l10n.sessionStatusRunning
    : isPending
        ? l10n.sessionStatusPending(issues.length)
        : l10n.sessionStatusReady;
```

- 就绪态左标记：`Icon(Icons.check_rounded, size: 14, color: foreground)`；
- 运行/待处理左标记：现有 7px 圆点；
- 待处理态整体包 `Semantics(button: true, label: l10n.readinessIncomplete(issues.length))` + `InkWell(onTap: () => showSettingsIssuesDialog(context, issues: issues))`，圆角 8，`Material(type: transparency)`；
- chip 容器加 `key: const Key('sessionStatusChip')`，供测试断言；
- 命中区域：视觉 26px 不变，外层给至少 40px 的垂直命中（`SizedBox(height: 40)` 包裹并居中），标题行高 56 可以容纳。

### 4.4 `_RunSection` 与 `_ReadinessBar`

- `_ReadinessBar` 整类删除；
- `_RunSection({required bool isRunning, required List<SettingsIssue> issues})` 只负责 `Column(button, 8, note)`；
- 按钮逻辑保持：`issues.isNotEmpty` → 弹窗，否则 `toggle()`。

## 5. 文案（l10n）

新增 2 个 key：

| key | en | zh / zh_Hans | zh_Hant | ja |
|---|---|---|---|---|
| `sessionStatusReady` | `Ready` | 已就绪 | 已就緒 | 準備完了 |
| `sessionStatusPending` | `{count, plural, =1{1 to fix} other{{count} to fix}}` | {count} 项待处理 | {count} 項待處理 | {count} 件未完了 |

`sessionStatusPending` 需在 `app_en.arb` 声明 `@sessionStatusPending` 的 `count`（`type: int`）。

删除 3 个不再使用的 key（5 个 arb 同步删除）：

| key | 原因 |
|---|---|
| `readinessReady` | 横幅删除后无引用 |
| `readinessReview` | 横幅右侧「查看」删除后无引用 |
| `sessionStatusIdle` | 未运行时 chip 一律显示「已就绪」或「N 项待处理」，不再有「已停止」 |

保留 `readinessIncomplete`：用于 chip 的 Semantics label 与弹窗引导语。

文案宽度约束：chip 文案不超过 6 个汉字 / 10 个拉丁字符；`N 项待处理` 在 N 最大约 6 时仍能放进标题行。

## 6. 交互与无障碍

- 待处理 chip 点击 → `showSettingsIssuesDialog`，与点击开始按钮完全一致；
- 就绪/运行中 chip 不可点击，不响应 hover 高亮（保持静态 chip 语义）；
- 待处理 chip 具备 `button` 语义与完整 label（「还有 N 项设置未完成」），读屏不会只念出数字；
- 键盘：chip 可 Tab 聚焦，Enter/Space 打开弹窗（`InkWell` 默认行为）；
- 颜色差异之外，文案与形态（勾 vs 圆点）同时区分三种状态，满足非纯色识别。

## 7. 测试计划

### 7.1 必须修改（`test/ui/main_page_layout_test.dart`）

- `fixing the gaps flips the bar to ready and clears the badge`
  - `find.text('2 settings need attention')` → `find.text('2 to fix')`
  - `find.text('Settings ready')` → `find.text('Ready')`
- `start shows a checklist that links into the settings drawer`
  - 同上替换，并补充：此时底部不再存在横幅文案（`find.text('2 to fix')` 只出现一次，位于 chip）。

### 7.2 新增用例

1. `pending chip opens the checklist without pressing start`：待处理态点击 chip → 弹出 `Cannot start yet` 与两条 issue；
2. `ready chip is not a button`：就绪态 chip 无 `button` 语义、点击无效；
3. `settings drawer badge and chip agree`：修复设置后，顶栏红点消失且 chip 变为 `Ready`（与现有断言合并即可）。

### 7.3 回归验证

- `flutter analyze`
- `flutter test test/ui/main_page_layout_test.dart`
- 全量 `flutter test`
- 手动：1280×720 与 1024×650 两种尺寸、浅/深主题、中英日繁体三种文案长度下标题行不溢出。

## 8. 实施步骤

1. l10n：5 个 arb 增加 2 个 key、删除 3 个 key → `flutter gen-l10n`；
2. `session_panel.dart`：提升 readiness 计算到 `_SessionCard`，改造 `_StatusChip`，删除 `_ReadinessBar`，精简 `_RunSection`；
3. 更新 `test/ui/main_page_layout_test.dart`，新增 7.2 用例；
4. 更新 `docs/design/ui_rework_a_console_design.md` §5.4 的状态 chip 描述（三态配色、底部只有按钮与说明）；
5. 按 7.3 验证。

## 9. 验收标准

- 就绪态：底部只有按钮与说明，整卡无绿色/红色色带；chip 为蓝底勾 + 「已就绪」；
- 待处理态：chip 为红底 + 「N 项待处理」，点击弹出清单，按钮点击行为不变；
- 运行态：chip 为绿底 + 圆点 + 「进行中」，底部无 readiness 元素；
- 三个状态在浅色与深色模式下都满足 WCAG AA（正文 12px 对比度 ≥ 4.5:1，实测 primaryContainer/primary 约 5.3:1，errorContainer/onErrorContainer 约 8:1）；
- 1024×650 与 1280×720 无溢出异常，中/英/日/繁体标题行不截断。

## 10. 风险与回滚

| 风险 | 影响 | 处理 |
|---|---|---|
| chip 文案变长挤压标题 | 1024 宽下副标题被压缩 | 文案上限 6 汉字；标题区已 `Expanded + ellipsis`；布局测试覆盖 1024 |
| 顶部与底部各自订阅同一 cubit 导致重复计算 | 每帧两次 readiness | 本方案已在 §4.2 合并为一次计算 |
| 删除 l10n key 后仍有残留引用 | 编译失败 | 先全局检索，再 `gen-l10n`，`flutter analyze` 兜底 |
| 运行期修改设置导致 chip 闪烁 | 状态来回跳 | 运行中直接返回 `const []`，不评估 |
| 待处理 chip 命中区域过小 | 鼠标/触屏点不中 | 外层 40px 命中区，视觉保持 26px |

回滚：本次仅改 1 个 UI 文件 + l10n + 测试，无可逆数据迁移；回滚即还原该文件与 arb 并重新 `gen-l10n`。

## 11. 参考

- 现有实现：`lib/ui/main_page/session_panel.dart`（`_StatusChip` / `_RunSection`）
- 校验来源：`lib/settings/settings_readiness.dart`
