# 首屏白屏技术方案：首帧零 IO（First-Frame Zero-IO）

> 状态：待评审
> 适用范围：桌面端 Dart 启动路径（Windows / macOS / Linux）
> 关联文档：[启动性能优化设计方案](./startup_performance_design.md) §4.4、[窗口几何技术方案](./window_geometry_design.md)
> 本文替代 `startup_performance_design.md` §4.4 末尾「不做拆日志」的结论；窗口显隐实现保持一致（透明度隐藏，不用 `hide()`）。

---

## 1. 问题定义

用户反馈：双击启动后先看到空窗/白屏，之后才出现 loading；Windows 上则表现为窗口迟迟不出现，像「点了没反应」。冷启动、首次安装、机械盘/网络盘、Windows Defender 实时扫描、macOS 首次校验时更明显。

本文只处理 **Dart 首帧之前的工作**，即从 `main()` 进入 到 第一帧可见 的等待：

- 要解决：这段路径上的 IO、平台通道和同步文件系统调用。
- 不解决：`main()` 之前的引擎启动、插件 DLL 加载、代码签名/安全软件扫描。这部分如果慢，Dart 侧无法消除，需要单独的原生启动画面或签名方案。
- 不改变：`application ready` 的总时长（音频、DXCC、通话记录加载），这部分由 [`startup_performance_design.md`](./startup_performance_design.md) 的其他项负责。

两个指标必须分开看：

| 指标 | 含义 | 本文目标 |
| --- | --- | --- |
| 首帧延迟 | `main()` 进入 → 第一帧可见 | 不随磁盘/杀毒软件变化，路径上无 IO |
| ready 时长 | `main()` 进入 → `application ready` | 不回归，允许与首帧并行 |

## 2. 现状与根因

### 2.1 当前调用链

[`main.dart`](../../lib/main.dart#L12-L41) 在 `Catcher2` 之前连续 `await` 了四步，而 `Catcher2` 内部才调用 `runApp`：

```text
main()
  WidgetsFlutterBinding.ensureInitialized()
  await bootstrapLogging()          // 平台通道 + 同步文件 IO
  await AppInfo.load()              // 平台通道（PackageInfo 第二次）
  await _hideWindowUntilFirstFrame()// 窗口透明度（此时才隐藏）
  await initErrorHandling()         // 无真实 IO，但仍是 await
  Catcher2(rootWidget: MainApp())   // 内部 runApp，首帧从这里才开始
```

### 2.2 首帧前的 IO 清单

| # | 工作 | 位置 | 类型 |
| --- | --- | --- | --- |
| 1 | `getApplicationSupportDirectory` / `getTemporaryDirectory` | [`log_paths.dart`](../../lib/logging/log_paths.dart#L22-L38) | 平台通道 ×2 |
| 2 | `existsSync` / `createSync` / `writeAsStringSync` / `deleteSync` | [`log_paths.dart`](../../lib/logging/log_paths.dart#L45-L72) | 同步 IO ×4 |
| 3 | `PackageInfo.fromPlatform()` 写会话头 | [`log_session.dart`](../../lib/logging/log_session.dart#L26-L54) | 平台通道 |
| 4 | 日志文件父目录检查与 sink 初始化 | logger `AdvancedFileOutput.init` | 同步 IO |
| 5 | 遍历可执行文件目录 `listSync` 并逐个判断类型 | [`logging_bootstrap.dart`](../../lib/logging/logging_bootstrap.dart#L59-L87) | 同步 IO，N 个文件 |
| 6 | `documentsPath()` + `appDataRoots()` + `describeDirectory` | [`logging_bootstrap.dart`](../../lib/logging/logging_bootstrap.dart#L95-L109)、[`dirs.dart`](../../lib/common/dirs.dart#L87-L101) | 平台通道 ×3 + 同步 IO ×9~12 |
| 7 | `AppInfo.load()` 第二次 `PackageInfo.fromPlatform()` | [`app_info.dart`](../../lib/common/app_info.dart#L13-L22) | 平台通道 |
| 8 | `window.opacity = 0` | [`main.dart`](../../lib/main.dart#L54-L66) | 原生 FFI，非 IO |

合计约 **7 次平台通道往返 + 20 次左右同步文件系统调用**。同步调用会直接占住 UI isolate；平台通道往返则让 `main()` 整体后移，`runApp` 和首帧一起被推后。

### 2.3 为什么表现为白屏

- **macOS**：`MainFlutterWindow` 来自 XIB，进程启动时窗口已经可见。透明度隐藏排在所有日志 IO 之后（[`main.dart`](../../lib/main.dart#L20)），因此整个日志初始化期间窗口是可见但无内容的空窗。
- **Windows**：runner 在首帧回调里才 `ShowWindow`（`windows/runner/flutter_window.cpp`），所以上面的 IO 时间直接表现为「窗口不出现」。
- **同步 IO**：`listSync` 遍历 exe 目录、`copySync` 迁移旧库、日志目录写探针都会阻塞 UI isolate。杀毒软件对每个被访问文件做实时扫描时，单次调用可能从微秒级放大到秒级。

### 2.4 必须区分的两个时间段

```text
[ 进程启动 ── 引擎/插件 DLL/AV扫描 ──> main() ] [ main() ── Dart IO ──> 首帧 ]
                                            本文改造范围
```

如果改造后日志显示 `main()` 本身就很晚才执行，剩余延迟不在 Dart 侧，需要原生启动画面或签名/信誉方案，不能继续在 Dart 里加启动代码。

## 3. 目标与验收

| 指标 | 基线 | 目标 |
| --- | --- | --- |
| 首帧前的文件系统调用 | ~20 次同步调用 | **0** |
| 首帧前等待的平台通道 | ~7 次 | **0**（Catcher2 内部异步 info 除外，见 §5.1） |
| macOS 空窗时长 | 等于日志初始化耗时 | **0**；窗口以透明度 0 存在，首帧完成即显示 splash |
| Windows 首帧 | 全部 IO 跑完才出现窗口 | 首帧即 splash，IO 在 splash 之后 |
| 首帧延迟与磁盘的关系 | 强相关 | 同一机器改造前后对比，差值应只来自引擎常量 |
| 首帧后 spinner 卡顿 | 存在同步 IO / 重计算 | profile 模式下无 > 32 ms 的单次 UI isolate 阻塞 |
| 日志完整性 | 首帧前日志落盘 | 首帧前日志以内存缓冲保存，首帧后按原时间戳回放，**不丢** |
| 回归 | — | `flutter analyze` / `flutter test` 全绿 |

验收以 AOT release 构建的 `BOOT` 日志为准，必须包含一次删除数据库目录后的冷启动，以及 Windows 首次安装（含安全软件实时防护）场景。

## 4. 设计原则

1. **首帧路径只允许内存操作**：`main()` 不读文件、不调 `path_provider`、不等 `PackageInfo`。
2. **IO 一律在首帧 post-frame 之后启动**：包括日志、prefs、数据库、DXCC、呼号表。
3. **首帧后也不允许同步 IO 阻塞 UI isolate**：同步文件 API 改异步或移入 isolate。
4. **日志不能因为延后而丢失**：首帧前使用内存缓冲，文件 sink 就绪后回放。
5. **不改变现有启动语义**：音频就绪仍是 `_Ready` 前提；数据库迁移、失败态、退出清理保持现状。

## 5. 总体设计

```text
main()（同步，无 IO）
  ├─ ensureInitialized
  ├─ 窗口透明度 = 0（原生 FFI）
  ├─ installLogger(AppLogger.buffered())     // 只写内存
  ├─ initErrorHandling()（同步）
  └─ Catcher2 → runApp
        │
        ▼
   第一帧：MaterialApp + _Loading（纯绘制，无资产 IO）
        │
        ├─ post-frame #1：_revealWindow()（显示 splash）
        └─ post-frame #2：_BootGate._start()
              ├─ bootstrapLoggingAfterFirstFrame()   // 文件日志 + 回放
              ├─ AppInfo（复用 PackageInfo）
              └─ _MainAppCubit.load()                // prefs / db / dxcc / callsign / audio
```

### 5.1 `main()` 收缩为同步内存启动

目标实现：

```dart
void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      boot.start(); // 启动计时，见 §6.6

      // 先隐藏窗口：纯原生 FFI，无 IO，且必须在任何 IO 之前。
      _hideWindowUntilFirstFrame();

      // 只写内存；文件 sink 在首帧后安装。
      installLogger(AppLogger.buffered());

      // 当前实现没有真实 IO，改为同步，避免无意义的 await。
      final (debugOptions, releaseOptions) = initErrorHandling();

      Catcher2(
        rootWidget: MainApp(),
        debugConfig: debugOptions,
        releaseConfig: releaseOptions,
      );
    },
    (error, stackTrace) { ... },
    zoneSpecification: appZoneSpecification(),
  );
}
```

要点：

- `_hideWindowUntilFirstFrame()` 提前到第一行。macOS 窗口在 runner 里已经可见，晚隐藏一毫秒就白一毫秒。
- `bootstrapLogging()` 不再在 `main()` 调用，整体移到首帧后。
- `AppInfo.load()` 不再在 `main()` 调用；版本信息在首帧后的日志阶段加载。
- `initErrorHandling()` 去掉 `async`（[`error_handling.dart`](../../lib/error_handling.dart#L20-L36) 无真实 IO），返回值由 `Future` 改为同步元组。
- `Catcher2` 构造本身只做 `runApp` 和错误钩子注册；它的 `_loadDeviceInfo()` / `_loadApplicationInfo()` 在 `runApp` 之后异步发起（已核对 `catcher_2-2.1.12` 源码），不阻塞首帧。这是唯一无法从外部延迟的通道调用，但不在关键路径上。

### 5.2 首帧内容

保留现有 `_Loading`（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L263-L272)）：`surface` 底色 + `CircularProgressIndicator`，纯绘制，无图片资产、无文件读取。

约束：

- 不在首帧路径放 `Image.asset` / `rootBundle.load` / 自定义字体测量。
- `MaterialApp` 的本地化 delegate 返回 `SynchronousFuture`，不会等待 IO，可保留。
- `AppTheme.light` / `AppTheme.dark` 的构造属于纯计算，不在本方案范围内；若实测首帧 build 超过 16 ms，再单独优化。

### 5.3 `_BootGate`：首帧后启动 IO

`_BootGate` 放在 `MultiRepositoryProvider` 之下、`BlocProvider` 之内，这样它既能 `context.read` 依赖，又不会在 `initState` 里直接做 IO：

```dart
BlocProvider(
  create: (context) =>
      _MainAppCubit(language: _language, themeMode: _themeMode), // 删除 ..load(...)
  child: _BootGate(
    child: BlocListener<_MainAppCubit, _AppState>(...),
  ),
)
```

```dart
class _BootGate extends StatefulWidget {
  const _BootGate({required this.child});
  final Widget child;

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  @override
  void initState() {
    super.initState();
    // initState 里只注册回调，不做任何 IO。
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    try {
      await bootstrapLoggingAfterFirstFrame();
    } catch (error, stackTrace) {
      // 文件日志不可用也必须继续启动；此条只进内存缓冲。
      log.error('logging bootstrap failed', tag: 'boot',
          error: error, stackTrace: stackTrace);
    }

    if (!mounted) {
      return;
    }

    await context.read<_MainAppCubit>().load(
      dxccManager: context.read(),
      callsignLoader: context.read(),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

顺序保证：

- `_MainAppState.initState` 先注册 `_revealWindow`，`_BootGate.initState` 后注册 `_start`；同一帧的 post-frame 回调按注册顺序执行，因此 **先显示 splash，再开始 IO**。
- `_MainAppCubit` 仍由 `BlocProvider` 懒创建；首帧 build 时 `BlocBuilder` 会读取并创建它，但不再在 `create` 里调用 `load`，所以首帧只渲染 `_Loading`。
- `load()` 内的步骤顺序保持不变（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L339-L408)），只是整体后移。

### 5.4 日志缓冲与回放

[`AppLogger`](../../lib/logging/app_logger.dart#L61-L122) 当前只有 `consoleOnly` 与 `fileBacked` 两种形态。新增第三种：

```dart
/// 首帧前使用：只写内存，不创建文件。
factory AppLogger.buffered({int bufferSize = 512}) {
  final filter = ProductionFilter()..level = _defaultLevel;
  final ring = MemoryOutput(bufferSize: bufferSize);
  final logger = Logger(
    filter: filter,
    output: MultiOutput(<LogOutput>[
      ring,
      if (!kReleaseMode) ConsoleOutput(),
    ]),
    printer: AppLogPrinter(),
  );
  return AppLogger._(logger, null, <LogFilter>[filter], ring, null);
}
```

首帧后升级为文件日志：

```dart
/// 创建文件 logger，等待 sink 就绪，再把首帧前的缓冲按原顺序写入。
static Future<AppLogger> restoreFileBacked({
  required String directory,
  required String header,
  required List<OutputEvent> pending,
}) async {
  final next = AppLogger.fileBacked(directory: directory, header: header);
  await next._primary.init; // Logger 构造时已触发 output.init()
  for (final event in pending) {
    next._file!.output(event); // 原始时间戳已在 event.lines 中
  }
  return next;
}
```

调用方：

```dart
Future<void> bootstrapLoggingAfterFirstFrame() async {
  final pending = log.bufferedEvents; // 取当前 ring 的快照
  final location = await resolveLogDirectory();
  final header = await buildSessionHeader(location: location);
  final next = await AppLogger.restoreFileBacked(
    directory: location.path,
    header: header.map((line) => '# $line').join('\n'),
    pending: pending,
  );
  installLogger(next);

  log.info('log sink upgraded', tag: 'boot', fields: <String, Object?>{
    'log_dir': redactPath(location.path),
    'fallback_index': location.fallbackIndex,
    'replayed': pending.length,
  });

  // 诊断探测不进入启动关键路径。
  unawaited(boot.step('runtime_env_probe', probeRuntimeEnvironment));
  unawaited(boot.step('storage_probe', probeStorageRoots));
}
```

设计约束：

- `AppLogPrinter` 使用事件自带的 UTC 时间（[`app_log_printer.dart`](../../lib/logging/app_log_printer.dart#L47-L49)），回放后时间线不会错乱。
- `AdvancedFileOutput` 在 `init()` 时写入会话头，因此先 `await next._primary.init` 再回放，文件结构是「会话头 → 首帧前日志 → 首帧后日志」。
- `log.flush()` 在文件 sink 安装前是空操作；此时进程退出本来也没有可写的文件，接受该窗口。
- 首帧前若进程直接崩溃，缓冲日志会随进程消失。该窗口只有首帧之前的几十毫秒；如需覆盖，只能在原生侧记录时间戳，不在本次范围。

### 5.5 首帧后 IO 管线

| 顺序 | 步骤 | 位置 | 执行方式 |
| --- | --- | --- | --- |
| 1 | 安装文件日志 + 回放 | §5.4 | await |
| 2 | `PackageInfo` + `AppInfo` | §5.6 | await，只调一次 |
| 3 | `SharedPreferencesWithCache.create` + `AppSettings` | `_MainAppCubit.load` | await，语言/主题立即生效 |
| 4 | `workerManager.init` | 同上 | await |
| 5 | `ensureDatabaseReady` | 同上 | await，文件 API 改异步 |
| 6 | `dxccManager.loadDxcc` | 同上 | await（数据库读在 drift 后台 isolate） |
| 7 | `callsignLoader.loadCallsigns` | 同上 | await |
| 8 | `_initAudio` | 同上 | 最先启动，最后 await（保持现状） |
| 9 | `runtime_env_probe` / `storage_probe` | §5.4 | **不 await，`_Ready` 之后完成即可** |

`_initAudio` 继续与 3~7 并行：它在 `load()` 一开始就启动，`_Ready` 前 `await audioReady`。原因不变——引擎未初始化时 `AudioPlayer` 会丢弃第一句语音。

### 5.6 `PackageInfo` 去重

现在 `buildSessionHeader` 与 `AppInfo.load` 各调用一次 `PackageInfo.fromPlatform()`。改为：

```dart
final packageInfo = await _tryPackageInfo();
final header = await buildSessionHeader(
  location: location,
  packageInfo: packageInfo,
);
AppInfo.apply(packageInfo); // 新方法，替代独立的 Future<void> load()
```

- 平台通道从 2 次降为 1 次。
- `AppInfo` 的公开读取方式不变，`display` 仍返回 `—` 兜底。
- 首帧的 `_Loading` 不展示版本号，因此首帧前读到 null 不影响观感。

### 5.7 同步 IO 异步化

| 位置 | 现状 | 目标 |
| --- | --- | --- |
| [`log_paths.resolveLogDirectory`](../../lib/logging/log_paths.dart#L45-L72) | `existsSync` / `createSync` / `writeAsStringSync` / `deleteSync` | `await exists()` / `await create(recursive: true)` / `await writeAsString()` / `await delete()` |
| [`dirs.prepareDirectory`](../../lib/common/dirs.dart#L64-L79) | 同上 | 同上 |
| [`_migrateLegacyDatabase`](../../lib/db/database_bootstrap.dart#L135-L165) | `existsSync` / `copySync` | `await exists()` / `await copy()` |
| [`probeRuntimeEnvironment`](../../lib/logging/logging_bootstrap.dart#L59-L87) | `existsSync` + `listSync` | 放到 `Isolate.run`，结果回主 isolate 写日志 |
| [`describeDirectory`](../../lib/common/dirs.dart#L87-L101) | `typeSync` / `resolveSymbolicLinksSync` | 改为异步版本，或与 `probeStorageRoots` 一起放 isolate |

说明：

- 异步文件 API 仍然走 Dart 的 IO 线程池，不会阻塞 UI isolate；同步 API 会。
- 旧库迁移的 `copySync` 可能是最大的单点卡顿（历史库可能几十 MB），必须改异步。
- `probeRuntimeEnvironment` 遍历 exe 目录时，每个条目都可能触发安全软件扫描，适合放 isolate 且不进入关键路径。

### 5.8 重计算是否移入 isolate

先测量，不预设结论：

| 工作 | 现状 | 结论 |
| --- | --- | --- |
| DXCC TSV 解析 | 4826 行约 5 ms（见 `startup_performance_design.md` §1） | **不移动**，低于 isolate 启动成本 |
| 呼号表拆分 | 70 807 行 / 432 KB | 先测；若单次 > 16 ms，再 `Isolate.run` 拆分 |
| DXCC 首次写库 | drift 后台 isolate + 单事务 | 已在后台，不需要额外处理 |

`worker_manager` 不因此新增使用点；呼号表若需要 isolate，用 `Isolate.run` 即可，避免绑定 worker_manager 生命周期。

### 5.9 窗口显隐

保持现有实现，仅调整顺序：

- `main()` 最前面：`WindowManager.instance.getCurrent()?.opacity = 0`。不用 `hide()`，否则 macOS runner 的 `applicationShouldTerminateAfterLastWindowClosed` 会退出进程。
- 首帧 post-frame：`_revealWindow()` 先配置最小尺寸/尺寸/居中，再 `opacity = 1`、`show()`、`focus()`（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L153-L207)）。
- `_revealWindow` 必须在 `_BootGate._start` 之前执行，保证用户看到的第一眼是 splash，而不是空窗。

### 5.10 首帧基准日志

在 [`BootTrace`](../../lib/logging/boot_trace.dart#L7-L41) 增加进程启动计时：

```dart
class BootTrace {
  final Stopwatch _sinceStart = Stopwatch()..start();

  void start() {} // 显式触碰，确保 top-level final 在此刻初始化

  int get elapsedMs => _sinceStart.elapsedMilliseconds;
}
```

- `main()` 中 `WidgetsFlutterBinding.ensureInitialized()` 之后立即调用 `boot.start()`。
- 首帧 post-frame、`_revealWindow()` 之后记录：

```dart
log.info('first frame visible', tag: 'boot', fields: <String, Object?>{
  'sinceMainMs': boot.elapsedMs,
});
```

- 该记录会进入内存缓冲，并在文件 sink 安装后回放，因此日志里能直接看到「首帧」与「第一条 IO」的先后关系。

## 6. 改造前后时序

改造前（时间随磁盘和安全软件放大）：

```text
进程启动
  └─ runApp 之前：通道 ×7 + 同步 IO ×20
       ├─ log_ready
       ├─ platform
       ├─ runtime_env_probe     listSync 整个 exe 目录
       ├─ storage_probe         多次 typeSync / resolveSymbolicLinksSync
       └─ AppInfo               第二次 PackageInfo
  └─ runApp → 首帧（此时窗口才显示）
       └─ prefs / db / dxcc / callsign / audio
```

改造后：

```text
进程启动
  └─ main()：binding + 窗口透明度 + 内存日志 + Catcher2（无 IO）
  └─ runApp → 首帧：_Loading splash（纯绘制）
       ├─ post-frame #1：_revealWindow()       窗口出现即 splash
       ├─ post-frame #2：first frame visible   记录 sinceMainMs
       └─ _BootGate._start()
            ├─ resolveLogDirectory + 安装 sink + 回放缓冲
            ├─ PackageInfo / AppInfo
            ├─ prefs / worker_manager / db / dxcc / callsign
            ├─ audio（并行启动，_Ready 前 await）
            └─ runtime_env_probe / storage_probe（不阻塞 ready）
```

预期：macOS 空窗消失；Windows 首帧即 splash；首帧延迟不再包含任何 Dart 侧 IO。`application ready` 总时长不回归。

## 7. 改动清单与实施顺序

### 7.1 P0：首帧零 IO（本文核心）

| 文件 | 改动 |
| --- | --- |
| [`lib/main.dart`](../../lib/main.dart) | 去掉 `bootstrapLogging` / `AppInfo.load` / `initErrorHandling` 的 await；窗口隐藏提前；安装 `AppLogger.buffered()`；记录启动计时 |
| [`lib/logging/app_logger.dart`](../../lib/logging/app_logger.dart) | 新增 `AppLogger.buffered()`、`restoreFileBacked()`、缓冲快照读取 |
| [`lib/logging/logging_bootstrap.dart`](../../lib/logging/logging_bootstrap.dart) | 拆为 `bootstrapLoggingAfterFirstFrame()`；探测改为不阻塞 |
| [`lib/logging/log_session.dart`](../../lib/logging/log_session.dart) | `buildSessionHeader` 接受外部传入的 `PackageInfo` |
| [`lib/common/app_info.dart`](../../lib/common/app_info.dart) | 新增 `apply(PackageInfo?)`，移除独立 `load()` 调用 |
| [`lib/error_handling.dart`](../../lib/error_handling.dart) | `initErrorHandling()` 去掉 `async` |
| [`lib/logging/boot_trace.dart`](../../lib/logging/boot_trace.dart) | 启动计时 + `start()` |
| [`lib/ui/main_app/main_app.dart`](../../lib/ui/main_app/main_app.dart) | 删除 `BlocProvider.create` 中的 `..load(...)`；新增 `_BootGate`；首帧日志 |

P0 完成后即可验收「首帧前 IO = 0」。

### 7.2 P1：首帧后 UI isolate 平滑

| 文件 | 改动 |
| --- | --- |
| [`lib/logging/log_paths.dart`](../../lib/logging/log_paths.dart) | 同步文件 API 改异步 |
| [`lib/common/dirs.dart`](../../lib/common/dirs.dart) | `prepareDirectory` 改异步；新增异步 `describeDirectory` |
| [`lib/db/database_bootstrap.dart`](../../lib/db/database_bootstrap.dart) | 旧库迁移改异步 |
| [`lib/logging/logging_bootstrap.dart`](../../lib/logging/logging_bootstrap.dart) | exe 目录遍历放 isolate |

### 7.3 P2：按实测决定

- 呼号表拆分若 > 16 ms，移入 `Isolate.run`。
- `AppTheme` 构造若导致首帧 build 超预算，再单独优化。
- 原生启动画面（Windows 首次安装、AV 扫描 `main()` 之前）另立方案。

每一批可独立提交、独立回滚。

## 8. 测试与验收

### 8.1 自动化

- 新增 `test/app_logger_buffer_test.dart`：
  - 首帧前写入 3 条不同级别的日志，`restoreFileBacked` 后读取文件，断言 3 条都在、顺序正确、时间戳保留。
  - 断言会话头在回放日志之前。
- 现有测试不受 P0 影响：`MainApp` 未在测试中直接 pump；`AppInfo` / `buildSessionHeader` 的签名变化需同步编译。
- `flutter analyze` / `flutter test` 全绿。

### 8.2 手工验收（release 构建）

1. 删除数据库目录后冷启动，检查 `latest.log`：
   - `first frame visible` 出现在第一条 `BOOT ... start` 之前；
   - `BOOT 01 log_ready start` 出现在 `first frame visible` 之后；
   - `runtime_env_probe` / `storage_probe` 出现在 `application ready` 附近或之后。
2. macOS：窗口出现的第一眼是 splash，不再有可见空窗。
3. Windows 首次安装（保持 Defender 实时防护）：窗口不再长时间不出现。
4. 首帧前日志完整性：`log sink upgraded` 的 `replayed` 字段大于 0，且文件里能看到 `first frame visible`。
5. 异常路径：
   - 日志目录不可写：退回到临时目录/可执行目录，启动不阻塞；
   - prefs 失败：仍进入 `_Failed` 失败态；
   - 音频设备缺失 / `SSB_RUNNER_DISABLE_AUDIO=1`：行为不变。
6. profile 模式下观察 splash 动画：无 > 32 ms 的单次 UI isolate 阻塞。
7. 退出：`flushLogs` 能写出首帧前的缓冲内容（升级后）。

### 8.3 建议的回归护栏（可选）

在 debug/profile 构建中加一个启动阶段标志：

```dart
enum StartupPhase { preFrame, booting, ready }
StartupPhase startupPhase = StartupPhase.preFrame;
```

在 `resolveLogDirectory`、`ensureDatabaseReady`、`probeRuntimeEnvironment`、`AppLogger.fileBacked` 入口加：

```dart
assert(startupPhase != StartupPhase.preFrame, 'IO started before first frame');
```

post-frame 回调里把 `startupPhase` 设为 `booting`。这样未来有人在 `main()` 里加 IO 会直接触发断言。测试需要在自己的 `setUp` 中把阶段设为 `ready`。是否落地由评审决定。

## 9. 风险与回滚

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 首帧前进程崩溃 | 缓冲日志丢失 | 窗口只有几十毫秒；Catcher2 仍会显示错误页。需要覆盖时在原生侧记时间戳 |
| 日志目录解析失败 | 无文件日志 | `resolveLogDirectory` 已有三级兜底；`_BootGate` 捕获异常后继续启动 |
| `_BootGate` 顺序错误 | 空窗或 IO 抢在首帧前 | 依赖 post-frame 注册顺序；用 `first frame visible` 日志验收 |
| `PackageInfo` 去重后为 null | UI 版本号显示 `—` | 已有兜底；版本信息只影响展示 |
| 旧库迁移改异步 | 迁移逻辑变化 | 只替换 API，不改顺序与回滚条件；补一条迁移测试 |
| 探针延后 | 诊断信息晚于 ready | 探针只做记录，不影响功能；失败不影响启动 |

回滚粒度：P0 涉及 8 个文件，可整体 revert；P1 每个文件独立；P2 未实施则无影响。

## 10. 非目标

- `main()` 之前的引擎/插件 DLL 加载、安全软件扫描、macOS Gatekeeper 校验。
- 缩短 `application ready` 总时长（DXCC 首次写库、音频初始化）。
- 原生启动画面（splash window）。如后续证明 Windows 首次安装的瓶颈在 `main()` 之前，再单独立项。
- 日志的远程上报、日志格式调整。

## 11. 决策记录

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| 只把 `bootstrapLogging` 改成 `unawaited` | 不采用 | 同步文件 API 仍会在 Future 恢复时阻塞 UI isolate，阻塞点不可控 |
| 只做原生 splash | 不采用 | 掩盖白屏，不减少首帧前的阻塞 |
| 把首帧前的 IO 全部并行化 | 不采用 | 缩短总时长但首帧仍在等 IO；且同步调用依旧阻塞 |
| 保留 `Catcher2` 在 `runApp` 之前 | 采用 | 构造本身无 IO；能尽早接管崩溃。其 device/application info 异步加载，不在关键路径 |
| 保留透明度隐藏而非 `hide()` | 采用 | macOS 上 `hide()` 会触发仅剩窗口关闭而退出进程（见 §5.9） |
| 诊断探针移出关键路径 | 采用 | 只服务排障，不影响功能，没必要让用户等 |
| DXCC 解析不移入 isolate | 采用 | 实测约 5 ms，低于 isolate 启动成本 |
