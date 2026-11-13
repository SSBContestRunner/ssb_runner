# analyzer info 清零与 lint 收紧技术方案

> 状态：已实施（分支 `chore/v0.3.0-analyzer-infos`）
> 触发：[CI run 43484934462](https://github.com/SSBContestRunner/ssb_runner/actions/runs/43484934462) 的 `Analyze & Test` job 在 `flutter analyze --no-fatal-infos` 后报出 52 条 info。

## 1. 现象与定性

- 该 run 全部 job 为 `cancelled`（`main@5ecb4db` 的 push 被后续推送抢占），**不是 lint 导致的失败**。`--no-fatal-infos` 下 info 不计入退出码。
- 本地 `fvm flutter analyze` 与 CI 输出 1:1 一致：**52 条 info，0 error / 0 warning**。
- 分布：`prefer_initializing_formals` 51 条，`constant_identifier_names` 1 条（`CQ_WPX`）。

## 2. 根因

项目 SDK 已升至 Flutter 3.47.9（Dart 3.13.7，见 `.fvmrc`），Dart 3.13 引入了**私有命名形参**：构造器可以写 `Foo({this._field})`，且该形参对外暴露的名字会自动去掉前导下划线（调用方写 `field:`）。

在该能力落地之前，`Foo({X x}) : _x = x` 是唯一合法写法，`prefer_initializing_formals` 也就不会对它报警。SDK 升级后这条 lint 开始命中全部「参数名 = 字段名去掉下划线，且初始化列表里只做直赋」的构造器，属于**工具链升级带来的既有代码存量告警**，不是新引入的缺陷。

已验证的两个关键事实（用项目自带 SDK 编译验证）：

1. `Foo({this._y})` 合法，调用方必须写 `y:`；写 `_y:` 会报 `undefined_named_parameter`。
2. `const` 构造器、带 `super(...)` / `super.key` 的构造器均可使用私有命名形参。

## 3. 影响面

51 处全部满足「字段为 `final`、参数与字段名仅差前导下划线、初始化列表里是直赋」，逐文件分布：

| 文件 | 条数 |
|---|---|
| `lib/audio/audio_player.dart` | 1 |
| `lib/audio/qso_voice_replay_service.dart` | 3 |
| `lib/contest_run/new/contest_answer_generator.dart` | 5 |
| `lib/contest_run/new/contest_operation_event_handler.dart` | 6 |
| `lib/contest_run/new/contest_running_manager.dart` | 10 |
| `lib/contest_run/new/contest_state_change_handler.dart` | 9 |
| `lib/contest_type/contest_definition.dart`（`_NumericContestType`） | 1 |
| `lib/logging/boot_beat.dart` | 4 |
| `lib/state_machine/state_machine.dart` | 2 |
| `lib/ui/main_app/home_page.dart` | 1 |
| `lib/ui/main_app/main_app.dart`（`_MainAppCubit`） | 4 |
| `lib/ui/main_page/qso_console.dart`（2 个构造器） | 2 |
| `lib/ui/main_page/session_panel.dart` | 2 |
| `lib/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart` | 1 |

**不动**的形参（名字与字段不一致或带表达式，lint 本来就不报）：`AudioPlayer.engine`、`AudioPlayer.estimateDuration`、`ContestRunningManager.answerSource → _answerSourceOverride`、`ContestRunningManager.onAnswerGenerated/onAnswersExhausted`、`ContestStateChangeHandler.contestAnswerGenerator → _answerGenerator`、`StateMachine.initialState → currentState`。

## 4. 改法

### 4.1 构造器迁移

以 `AudioPlayer` 为例：

```dart
// before
AudioPlayer({
  AudioEngine? engine,
  Duration Function(int byteLength)? estimateDuration,
  Duration watchdogMargin = const Duration(seconds: 3),
}) : _engine = engine ?? SoLoudAudioEngine(),
     _estimateDuration = estimateDuration ?? _defaultEstimateDuration,
     _watchdogMargin = watchdogMargin;

// after
AudioPlayer({
  AudioEngine? engine,
  Duration Function(int byteLength)? estimateDuration,
  this._watchdogMargin = const Duration(seconds: 3),
}) : _engine = engine ?? SoLoudAudioEngine(),
     _estimateDuration = estimateDuration ?? _defaultEstimateDuration;
```

要点：

- 参数对外名称与改造前完全一致，**所有调用点零改动**。
- `required` / 默认值语义原样保留（如 `ContestStateChangeHandler.retryTimeout`、`BootBeat.interval`）。
- 私有命名形参不能与同名字段以外的形参重名；本次没有冲突项。
- 该写法依赖语言版本 ≥ 3.13，`pubspec.yaml` 已是 `sdk: ^3.13.0`，与 `.fvmrc` 一致，无需调整版本约束。

### 4.2 删除死常量 `CQ_WPX`

`lib/contest_run/score_manager.dart` 的 `const CQ_WPX = 'CQ-WPX';` 全仓库（含 `test/`）无任何引用，直接删除，不重命名为 `cqWpx`。

### 4.3 CI 收紧

`.github/workflows/ci.yml` 的 Analyze 步骤由 `flutter analyze --no-fatal-infos` 改为 `flutter analyze --fatal-infos`：清零后 info 重新变成门禁，避免同类存量再次无声堆积。同步更新文档中「以 `--no-fatal-infos` 放行历史 info」的过期描述。

## 5. 风险与验证

风险极低：改动只发生在构造器形参声明处，无运行时逻辑、无字段可空性/默认值变化、无调用点变化。唯一语义风险是「实参名是否变化」，已通过语言特性确认为不变。

验证口径：

```
fvm flutter analyze --fatal-infos   # 期望：0 issues
fvm flutter test                    # 期望：全绿
```

不需要额外做打包、多语言/字号、窗口尺寸验收。
