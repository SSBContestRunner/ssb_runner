# flutter test WARN 清零技术方案

> 状态：**已定稿，待实施**（2026-11-14 确认采用本文第 4 节方案 A + 5.5 局部抑制；本次只固化结论，不改代码）
> 触发：本地 `fvm flutter test` 全量运行，412 个测试全部通过，但输出里仍有 98 条 WARN 噪音，掩盖真正的问题信号。

## 0. 定稿结论

以下结论已确认，后续实施以此为准，不再重新选型：

1. **修复范围只限 69 条 `WARNING (drift)`**。29 条应用日志 WARN 全部是测试故意触发的失败/拒绝路径，保留原样，不降级、不删除。
2. **4 个「顺手多建实例」的文件采用方案 A**：文件级共享一个永不打开的 `AppDatabase` 单例，把实例数降到每个文件 1 个：
   - `test/contest_definition_test.dart`（41 条 → 0）
   - `test/ui/qso_console_test.dart`（18 条 → 0）
   - `test/settings/settings_readiness_test.dart`（5 条 → 0）
   - `test/station_exchange_test.dart`（4 条 → 0）
3. **`test/dxcc_manager_test.dart` 的 1 条采用 5.5 的局部抑制**：该用例必须同时存活两个实例，不属于噪音，不能靠共享消除；用 `dontWarnAboutMultipleDatabases` 临时打开并在 `addTearDown` 中恢复。
4. **明确否决**：方案 B（逐测试 `addTearDown(close)`）、方案 C（`test/flutter_test_config.dart` 全局关闭告警）、方案 D（改生产 API）。
5. **不引入新文件、不改 `lib/`**：全部改动落在既有 5 个测试文件内。
6. **验收口径**：`WARNING (drift)` 计数为 0；`flutter test` 全绿；应用日志 WARN 仍为 29 条；`flutter analyze` 无新增 issue。

## 1. 现象与口径

```
fvm flutter test
00:13 +412: All tests passed!
```

统计口径：`flutter test` 输出中 level 为 WARN 的行，共 98 条，分两类：

| 类别 | 条数 | 来源 | 性质 |
|---|---|---|---|
| `WARNING (drift)` | 69 | drift 运行时断言 | **需要修复**：测试进程内构造了多个 `AppDatabase` |
| 应用日志 `WARN` | 29 | `lib/` 中的 `log.warn` | **不需要修复**：测试故意触发失败/拒绝路径，用于断言 |

修复目标：`flutter test` 输出中 `WARNING (drift)` 归零；29 条应用日志保持原样（它们是测试断言证据，不是缺陷）。

## 2. 告警清单与定性

### 2.1 需要修复：drift 多实例告警（69 条）

告警原文：

```
WARNING (drift): It looks like you've created the database class AppDatabase
multiple times. When these two databases use the same QueryExecutor, race
conditions will occur and might corrupt the database.
```

按「第一次出现该告警的测试栈帧」归因，69 条分布如下：

| 测试文件 | 构造点 | 条数 | 该处是否真的共享 QueryExecutor |
|---|---|---|---|
| `test/contest_definition_test.dart` | `_FakeDxccManager` → `AppDatabase(_unusedExecutor())`（第 17 行） | 41 | 否，每次都是新的抛异常 `LazyDatabase` |
| `test/ui/qso_console_test.dart` | `_createHarness()` → `AppDatabase(LazyDatabase(...))`（第 1018 行） | 18 | 否，每个测试新建一个 |
| `test/settings/settings_readiness_test.dart` | `_FakeDxccManager`（第 18 行） | 5 | 否 |
| `test/station_exchange_test.dart` | `_FakeDxccManager`（第 10 行） | 4 | 否 |
| `test/dxcc_manager_test.dart` | 第 82 行为验证「已关闭的库」故意新建第二个实例 | 1 | 否，但两个实例同时存活是**有意为之** |

结论：**没有任何一处真正共享同一个 `QueryExecutor`**，所以不存在 drift 所警告的数据损坏风险；这是「测试里大量构造、从不关闭」导致的误报。但它确实是资源管理问题，且污染全量测试输出，值得修。

### 2.2 不需要修复：应用日志 WARN（29 条）

| 消息 | 来源 | 触发测试 | 定性 |
|---|---|---|---|
| `function key bindings rejected` ×2 | [app_settings.dart](../../lib/settings/app_settings.dart#L245) | `test/function_keys_test.dart` | 断言非法绑定被拒 |
| `function key bindings repaired` ×3 | [app_settings.dart](../../lib/settings/app_settings.dart#L294) | `test/function_keys_test.dart` | 断言重复/非法键被自动修复 |
| `function key binding conflict during migration` ×3 | [app_settings.dart](../../lib/settings/app_settings.dart#L346) | `test/function_keys_test.dart` | 断言迁移期冲突修复 |
| `settings.replay action="rejected-running"` ×1 | [app_settings.dart](../../lib/settings/app_settings.dart#L458) | `test/settings/pending_replay_test.dart` | 断言运行中拒绝武装重放 |
| `setting write rejected while a replay is armed` ×3 | [app_settings.dart](../../lib/settings/app_settings.dart#L589) | `test/settings/settings_cubits_test.dart` | 断言重放武装后拒绝写设置 |
| `contest/mode/difficulty change rejected…` ×3 | [settings_cubits.dart](../../lib/ui/main_page/settings_cubits.dart#L55) | `test/settings/settings_cubits_test.dart` | 同上 |
| `audio voice could not be allocated` ×1 | [audio_player.dart](../../lib/audio/audio_player.dart#L344) | `test/audio/audio_player_test.dart` | 断言语音分配失败的降级路径 |
| `audio engine could not create a segment` ×2 | [audio_player.dart](../../lib/audio/audio_player.dart#L297) | `test/audio/audio_effects_test.dart` | 断言音频段创建失败的降级路径 |
| `replay snapshot is unknown…` ×2 | [run_plan_resolver.dart](../../lib/contest_run/new/run_plan_resolver.dart#L103) | `test/run_plan_resolver_test.dart` | 断言未知快照被拒 |
| `replay header does not match…` ×4 | [run_plan_resolver.dart](../../lib/contest_run/new/run_plan_resolver.dart#L154) | `test/run_plan_resolver_test.dart` ×3、`test/contest_state_change_handler_test.dart` ×1 | 断言赛制/模式/难度不一致被拒 |
| `QSO skipped: his call or exchange is empty` ×2 | [contest_state_change_handler.dart](../../lib/contest_run/new/contest_state_change_handler.dart#L621) | `test/contest_state_change_handler_test.dart` | 断言空呼号/交换不落库 |
| `Cannot start training with an empty callsign pool` ×1 | [contest_manager.dart](../../lib/contest_run/new/contest_manager.dart#L206) | `test/contest_state_change_handler_test.dart` | 断言空题池拒绝开始 |
| `audio asset missing, using fallback` ×1 | [payload_to_audio.dart](../../lib/audio/payload_to_audio.dart#L56) | `test/audio/accent_fallback_test.dart` | 测试名即「缺失口音片段回退到 Global」，**故意**用不存在的 `RU/Common/EXCH.wav` |
| `boot three` ×1 | 测试夹具日志 | `test/app_logger_buffer_test.dart` | 断言环形缓冲内容 |

这些行被打印说明对应分支确实被执行到了，属于测试有效性的证明。**不动代码、不改日志级别**。

## 3. 根因

drift 2.35.3 在 `GeneratedDatabase` 构造时做了一次全局实例计数：

- `_handleInstantiated()`：每个 `runtimeType` 第一次构造记为 1，之后每次构造 `+1`，`count > 1` 就打印告警（仅 debug）。
- `close()`：在 assert 里把计数 `-1`。

项目代码本身没有问题：`lib/ui/main_app/main_app.dart` 只在 `RepositoryProvider` 里创建一次。问题出在测试：

1. `_FakeDxccManager` 为了满足 `DxccManager({required AppDatabase database})` 的签名，每次实例化都 `new` 一个 `AppDatabase`，其 `LazyDatabase` 打开即抛异常，永远不会被打开，也就永远不会被 `close()`；
2. `qso_console_test` 的 `_createHarness()` 每个测试新建一个，同样不关闭；
3. 同一测试文件共享一个 isolate，计数只增不减，于是「第 2 个实例起」每个测试都告警。

对比：`test/ui/session_panel_end_confirm_test.dart`、`test/ui/settings_sheet_test.dart`、`test/ui/main_page_layout_test.dart`、`test/ui/training_review_overlay_test.dart` 已经采用「文件级 `_neverOpenedDatabase` 懒加载单例」的写法，因此这些文件 0 告警。**本次修复就是把剩下 4 个文件对齐到既有约定**。

## 4. 方案决策

| 方案 | 做法 | 优点 | 缺点 | 决策 |
|---|---|---|---|---|
| A. 文件级共享单实例 | 每个测试文件顶层 `final AppDatabase _xxx = AppDatabase(抛异常的 LazyDatabase)`，所有 fake/harness 复用 | 从根上把实例数降为 1；无全局开关；符合仓库既有约定 | 需要改 4 个文件的实例化点 | **采纳** |
| B. 逐测试 `addTearDown(close)` | 每次构造后注册关闭 | 保持「每测试独立实例」 | 5 个文件、几十处注册；`close()` 在 assert 里减计数，漏一处就继续告警 | 已否决（成本高、易回潮） |
| C. 全局关闭告警 | `test/flutter_test_config.dart` 设 `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` | 1 处改动、69 条全消 | 会连带屏蔽未来真正「两个实例共享同一 executor」的缺陷；把问题藏起来而不是修掉 | 已否决 |
| D. 改生产代码 | 让 `DxccManager.database` 可空或抽出查询接口 | — | 为测试便利改动生产 API，过度设计 | 已否决 |

方案 A 的边界处理：`test/dxcc_manager_test.dart:82` 的那 1 条不属于「顺手多建」，而是**测试意图**（验证「数据库已被关闭时 DXCC 仍能从内置数据解析」），不能通过共享实例消除，因此对该测试单独做局部抑制（见 5.5）。

## 5. 实施规格（已定稿）

### 5.1 `test/contest_definition_test.dart`（41 → 0）

```dart
// 新增：本文件所有 fake 共享一个永不打开的库
final AppDatabase _unusedDatabase = AppDatabase(_unusedExecutor());

class _FakeDxccManager extends DxccManager {
  _FakeDxccManager({this.dxccId = 0, this.cqZone = 24, this.ituZone})
    : super(database: _unusedDatabase); // 原来是 AppDatabase(_unusedExecutor())
  // ...
}
```

`_unusedExecutor()` 保持不变（打开即抛 `StateError`），共享后「误用数据库会立刻抛错」的保护语义不变。

### 5.2 `test/station_exchange_test.dart`（4 → 0）

```dart
final AppDatabase _unusedDatabase = AppDatabase(
  LazyDatabase(
    () async => throw StateError('The DXCC table must not be touched here.'),
  ),
);

class _FakeDxccManager extends DxccManager {
  _FakeDxccManager() : super(database: _unusedDatabase);
  // ...
}
```

### 5.3 `test/settings/settings_readiness_test.dart`（5 → 0）

与 5.2 完全相同：把 `_FakeDxccManager` 初始化列表里的 `AppDatabase(LazyDatabase(...))` 提为文件级 `final`，构造器改为 `super(database: _unusedDatabase)`。

### 5.4 `test/ui/qso_console_test.dart`（18 → 0）

```dart
// 命名沿用 test/ui/ 其他文件既有约定
final AppDatabase _neverOpenedDatabase = AppDatabase(
  LazyDatabase(() async => throw StateError('no db')),
);

Future<_Harness> _createHarness() async {
  // ...
  final database = _neverOpenedDatabase; // 原来是 AppDatabase(LazyDatabase(...))
  // ...
}
```

由于 opener 必抛，`AppDatabase` 始终不会被真正打开，跨测试共享不存在状态泄漏；生产代码也不会 `close()` 这个实例（已核对 `lib/` 内无 `AppDatabase.close()` 调用点）。

### 5.5 `test/dxcc_manager_test.dart`（1 → 0，局部抑制）

该测试要同时持有 setUp 里活着的 `db` 和新建的 `closed`，冲突无法靠共享实例消除。在测试体内局部打开 drift 开关，并在结束时恢复：

```dart
import 'package:drift/drift.dart' show driftRuntimeOptions; // 新增

test('an unusable database still resolves from bundled data', () async {
  // 两个实例同时存活是本测试的意图：第二个实例必须被关闭。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  final closed = AppDatabase(NativeDatabase.memory());
  await closed.close();
  // ... 原有断言不变
});
```

`driftRuntimeOptions` 是进程级全局变量，但 `flutter test` 每个测试文件独立 isolate，且同一文件内测试串行执行，`addTearDown` 恢复即可，不影响其他测试。

不采用的替代做法（不改全局开关）：先 `await db.close()`，再直接用 `db` 作为「不可用的库」。drift 的 `DelegatedDatabase.close()` 对已关闭实例是 no-op，重复关闭不会抛异常；但 `GeneratedDatabase.close()` 的计数会在 assert 里再减一次，可能变成负数，语义不够干净，因此定稿不采用。

### 5.6 明确不做

- 不新增 `test/flutter_test_config.dart` 全局开关（方案 C 已否决，见第 4 节）。
- 不改 `DxccManager` / `AppDatabase` 的生产 API（方案 D 已否决）。
- 不改 29 条应用日志的级别或文案，也不在测试里把它们降级成 debug。
- 不合并三个文件里重复的 `_FakeDxccManager`（与本次 WARN 无关，避免扩大改动面）。
- 本次只固化结论，不产生任何代码改动。

## 6. 验证

```
fvm flutter test 2>&1 | grep -c "WARNING (drift)"   # 期望：0
fvm flutter test                                    # 期望：All tests passed，且失败用例数为 0
fvm flutter analyze                                 # 期望：与改动前一致，无新增 issue
```

验收补充：

- 单独跑 5 个改动文件，各自 `WARNING (drift)` 计数为 0；
- 单独跑 `test/ui/qso_console_test.dart`，18 个 widget 测试仍全绿（确认共享实例不引起跨用例污染）；
- 全量输出的应用日志 WARN 仍应为 29 条，若数量变化说明误伤了有意保留的失败路径。

## 7. 风险与边界

| 风险 | 评估 |
|---|---|
| 共享实例导致测试间状态泄漏 | 极低：5 个共享的实例都是「打开即抛」的 `LazyDatabase`，从未真正打开，无连接、无事务、无缓存 |
| 未来有人在这些文件里改用真实内存库 | 需同时删掉共享单例，否则会出现「真库 + 抛异常库」并存；届时 drift 不会告警（因为只有一个真实例），单测会因为立即抛错而快速暴露 |
| 局部开关未恢复导致后续告警被吞 | 用 `addTearDown` 恢复，且仅在单测试内设置；文件内串行执行，无并发覆盖 |
| 生产行为受影响 | 无：改动全部在 `test/` 目录 |

## 8. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-14 | 完成 `flutter test` WARN 审计（69 + 29），输出初版方案 |
| 2026-11-14 | 定稿：采纳方案 A（4 个文件共享单实例）+ 5.5 局部抑制；否决 B/C/D；应用日志 WARN 保持原样。本次不改代码 |

