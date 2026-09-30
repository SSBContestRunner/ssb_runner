# SSB Runner 日志系统设计方案

> 状态：草案，待评审
> 调研范围：应用运行期日志缺失（"没有日志"）问题
> 适用范围：Windows / macOS / Linux 桌面端（移动端后续复用同一套抽象）

---

## 1. 背景与问题陈述

当前应用在用户侧出问题时，开发者拿不到任何可用于定位的日志：

- Windows release 用户侧，所有标准输出（`logger.*`、`print`）都被丢弃，不会落盘；
- 唯一的落盘通道只记录未处理的异常，不记录运行过程；
- 日志中也没有应用版本、OS 版本、架构、locale 等环境信息。

因此用户只能描述"打不开""没反应"，开发者无法远程定位。本方案的目标是补齐日志与诊断能力，使问题**即使无法本地复现，也能通过用户导出的日志定位**。

---

## 2. 现状分析（代码证据）

### 2.1 日志链路现状

当前日志由两条互不相干的链路组成：

**链路 A：全局 logger（不落盘）**

`lib/main.dart` 中：

~~~dart
final logger = Logger(printer: PrettyPrinter(methodCount: 5));
~~~

- 使用 `package:logger` 的默认 `ConsoleOutput`，最终走 Dart 的 `print`，即 **stdout**。
- 没有 level 设置、没有 tag、没有结构化字段、没有文件输出。
- 全仓库使用点仅 6 处，集中在音频播放与状态机。

**链路 B：Catcher2 文件处理器（只记异常）**

`lib/error_handling.dart` 中：

~~~dart
final appLogDirPath = '${await getAppDirectory()}/$dirLog';
final fileHandler = FileHandler(
  File(''),
  fileSupplier: (report) => _supplyLogFile(appLogDirPath),
  printLogs: true,
);
~~~

- 落盘位置：`%DOCUMENTS%/ssb_runner/log/yyyy-MM-dd.log`（`lib/common/dirs.dart`）。
- **只有被 Catcher2 捕获的未处理异常，或显式调用 `Catcher2.reportCheckedError` 的错误才会写入。**
- 正常业务流程、启动步骤、插件初始化过程完全没有记录。

### 2.2 Windows 上"没有日志"的机制（关键）

- `windows/runner/CMakeLists.txt` 中：

  ~~~cmake
  add_executable(${BINARY_NAME} WIN32 ...)
  ~~~

  子系统的 `WIN32` 表示 **GUI 应用，不分配控制台**。

- `windows/runner/main.cpp` 中：

  ~~~cpp
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  ~~~

  - 用户从资源管理器双击启动时，没有父控制台，`AttachConsole` 失败；非调试状态 `IsDebuggerPresent()` 为假。
  - 结果：**进程没有任何控制台**，stdout/stderr 写入被静默丢弃。

**结论：Windows release 用户侧，`logger.*`、`print`、Dart VM 的所有标准输出全部丢失。** 这是"没有日志"的直接原因。

### 2.3 Catcher2 的能力边界

- `third_party/catcher_2/lib/handlers/file_handler.dart` 每次 report 都执行 open -> append -> flush -> close，没有常开句柄、没有体积轮转、没有崩溃前上下文缓冲。
- Catcher2 已接管 `FlutterError.onError`、`PlatformDispatcher.instance.onError`、`Isolate.current.addErrorListener` 与 `runZonedGuarded`（见 `third_party/catcher_2/lib/core/catcher_2.dart`），这部分能力应保留复用。
- release 配置使用 `DialogReportMode`，出错即弹窗，在比赛场景下体验较差。
- **Catcher2 只能捕获"进程已经起来之后"的 Dart 异常**，更早阶段的失败不在其覆盖范围内。

### 2.4 其他缺口

- `lib/ui/main_app/main_app.dart` 的初始化链：`SoLoud.init` 异常被 catch 后仅上报不处理；`loadDxcc()`、`loadCallsigns()`、`SharedPreferences` 完全无 try/catch。一旦失败，UI 永久停留在 loading 且无日志。
- 日志中没有应用版本、build 号、OS 版本、架构、locale、运行时环境等任何上下文信息，排障时无法还原用户现场。
- 没有面向用户的日志导出通道。
- 日志与数据库同放 `Documents/ssb_runner`，而 Windows 的 Documents 常被 OneDrive 重定向，属于高风险位置（历史上已因"根目录不存在"出过问题，见 commit `69058bd`）。

---

## 3. 目标与非目标

### 3.1 目标

| 编号 | 目标 | 验收标准 |
|---|---|---|
| G1 | 全生命周期落盘 | 从 `main()` 第一步到退出，所有关键路径均有文件日志 |
| G2 | 启动失败可定位 | 启动阶段编号埋点；失败时可知"死在哪一步、错误是什么" |
| G3 | 环境可复现 | 每个日志文件带 session header，含 OS / 版本 / 运行时环境信息 |
| G4 | 崩溃上下文完整 | 环形缓冲 dump 最近 N 条 + Catcher2 异常详情 |
| G5 | 用户可交付日志 | 一键导出 zip 或复制诊断摘要 |
| G6 | 体积性能可控 | 分级 + 轮转 + 去重 + 异步写，单文件与总量有上限 |
| G7 | 不泄露敏感信息 | 路径脱敏，调试日志可关闭 |

### 3.2 非目标

- 不做服务端日志聚合平台（P3 才考虑远程上报）。
- 不改动数据库目录与数据，避免迁移风险。
- 不追求全量 trace 级日志常开，性能与体积优先。

---

## 4. 总体架构

~~~
业务代码
   |  log.info('...', tag: 'audio.player', fields: {...})
   v
AppLogger (facade, 基于 package:logging)
   |-- ConsoleSink      -> 复用现有 logger.PrettyPrinter（仅 debug 构建）
   |-- FileSink         -> 单行结构化文本，异步队列 + 轮转      [核心]
   |-- RingBufferSink   -> 内存保留最后 N 条，Fatal/异常时 dump
   |-- Catcher2Bridge   -> Catcher2 捕获的异常写入同一条日志流
   '-- (P3) RemoteSink  -> Sentry / 自建上报
~~~

**分层职责：**

| 层 | 名称 | 职责 | 依赖 |
|---|---|---|---|
| L1 | BootstrapLogger | 在插件、UI、Catcher2 之前工作；记录日志系统自身是否可用；目录失败时逐级回退 | 仅 `dart:io` + `path` |
| L2 | AppLogger | 日常结构化日志：level / tag / fields | feature 无关 |
| L3 | CrashReporter | Catcher2 汇聚 + 环形缓冲 + 环境快照 + 导出 | L1 + L2 |

---

## 5. 详细设计

### 5.1 依赖与模块划分

**依赖选择：**

| 依赖 | 现状 | 决策 |
|---|---|---|
| `package:logging` | 已是 transitive（pubspec.lock） | 提为 direct，作为 facade 标准 |
| `package:logger` | direct main | 降级为 ConsoleSink 的格式化器 |
| `package:package_info_plus` | 已是 transitive | 提为 direct，取版本 / build number |
| `package:device_info_plus` | 已是 transitive | 提为 direct，取 OS 详情 |
| `package:path` | transitive | 提为 direct，路径拼接 |

选 `package:logging` 而非继续裸用 `package:logger` 的理由：支持 `Logger('audio.player')` 层级命名、level 过滤、`Zone` 集成，且是生态标准。现有调用点仅 6 处，迁移成本极低。

**模块划分：**

~~~
lib/logging/
  app_logger.dart          # facade、level、tag、fields、session header
  log_record.dart          # 记录模型与字段序列化
  log_session.dart         # 一次进程运行的环境快照
  boot_trace.dart          # 编号埋点、计时、异常隔离
  runtime_env_probe.dart   # 运行时原生库加载情况采集
  export.dart              # zip / 剪贴板导出
  sinks/
    console_sink.dart
    file_sink.dart
    ring_buffer_sink.dart
    catcher2_bridge.dart
~~~

### 5.2 日志级别与命名空间

**级别：**

| 级别 | 用途 | release 默认 | debug 默认 |
|---|---|---|---|
| `FINEST` (trace) | 逐字符/逐帧级细节 | off | off |
| `FINE` (debug) | 状态机跃迁、音频加载明细 | off | on |
| `INFO` | 启动步骤、用户动作、状态变更 | on | on |
| `WARNING` | 可恢复异常、回退、降级 | on | on |
| `SEVERE` (error) | 操作失败、功能不可用 | on | on |
| `SHOUT` (fatal) | 即将崩溃 / 启动失败 | on | on |

**命名空间（tag）约定：** 采用点分层级，便于过滤：

~~~
boot            启动序列
audio           音频加载与播放
audio.soloud    SoLoud 插件
db              drift / sqlite
ui              界面
contest         比赛状态机
io              文件与路径
env             运行环境采集
crash           异常捕获
~~~

**运行时开关：** 设置页新增"详细日志（排障）"，开启后本进程 level 降至 `FINE`，并持久化到 `SharedPreferences`（在 `lib/settings/app_settings.dart` 增加 `verboseLogging` 键，UI 挂在 `lib/ui/main_settings/options_setting.dart` 一层）。

### 5.3 日志格式

**主格式：单行 logfmt 风格**，人工 grep 友好、体积小、可正则解析。

~~~
2025-10-28T14:15:03.123Z INFO   boot     msg="env_probe done" ok=4 fail=0
2025-10-28T14:15:03.456Z INFO   audio    msg="soloud initialized" channels=mono durMs=412
2025-10-28T14:15:04.001Z SEVERE audio    msg="soloud init failed" err="..."
~~~

规则：

- 时间戳统一 **UTC ISO-8601 毫秒**（比赛本身以 UTC 计时，避免时区歧义）。
- 级别左对齐补空格，tag 左对齐补空格，便于肉眼扫描。
- `msg` 与所有字段值：含空格或特殊字符时用双引号包裹，内部的双引号与反斜杠需要转义。
- 异常单独成块，多行保留，块首仍写一条 `SEVERE` 单行摘要，便于 grep。
- 文件编码 UTF-8 无 BOM。

**可选的 JSONL 模式：** `--dart-define=LOG_JSON=true` 时每行输出 JSON 对象，供后续自动化分析。

### 5.4 目录解析与回退

**回退链：**

| 优先级 | 目录 | Windows 实际位置 |
|---|---|---|
| 1 | `getApplicationSupportDirectory()/log` | `%APPDATA%/.../log` |
| 2 | `getTemporaryDirectory()/ssb_runner/log` | `%TEMP%/ssb_runner/log` |
| 3 | `File(Platform.resolvedExecutable).parent/log` | 便携版兜底 |

要点：

- **只迁移日志目录**，`dirDb` 保持不变，规避数据库迁移。
- session header 中记录最终使用的目录与 `fallback_index`。
- 保留对旧 `Documents/ssb_runner/log` 的过期清理一个版本。
- **日志系统自身失败必须可见**：任何 IO 异常都写 ConsoleSink，并尝试降级到下一级目录，绝不允许静默失败。

### 5.5 Sinks

**FileSink（核心）**

- `IOSink` **常开**，不再每次 open/close。
- 写入策略：
  - 内存队列 + 单消费者异步落盘，避免阻塞 UI isolate；
  - `WARNING` 及以上立即 flush；
  - 其余每 1 秒或每 64 行 flush 一次；
  - `AppLifecycleListener.onExitRequested`、`AppLifecycleState.detached`、退出信号时强制 flush 并 close（复用 `lib/ui/main_app/main_app.dart` 已有的 `onExitRequested` 钩子）。
- 任何写入异常降级为 ConsoleSink 输出，不影响主流程。

**RingBufferSink**

- 内存保留最后 200 条（可配置）。
- 触发 dump：出现 `SEVERE` / `SHOUT`，或 Catcher2 报告异常时，整段写入文件，前缀 `--- CONTEXT DUMP ---`。
- 目的：即使 release 级别是 INFO，也能看到崩溃前的 `FINE` 轨迹。

**ConsoleSink**

- 复用现有 `PrettyPrinter` 的彩色多行输出，仅 debug 构建启用。

**Catcher2Bridge**

- 将 Catcher2 的 `Report` 转换为一条 `SEVERE` 记录写入 FileSink，携带同一 session 的 `traceId`。
- 使异常与过程日志在同一文件内按时间交错，排障无需跨文件对时。

### 5.6 启动序列埋点

将 `lib/ui/main_app/main_app.dart` 的初始化链改造为编号埋点 + 异常隔离：

| 编号 | 埋点 | 关键字段 |
|---|---|---|
| 01 | process_start | pid / exe 路径 / cwd / args |
| 02 | platform | os / version / arch / dart version |
| 03 | log_dir_resolved | path / fallback_index |
| 04 | bindings_ready | - |
| 05 | error_handling_ready | - |
| 06 | env_probe | 运行时环境采集明细（见 5.8） |
| 07 | soloud_init | ok 或 err |
| 08 | window_ready | size |
| 09 | prefs_ready | - |
| 10 | dxcc_loaded | rows |
| 11 | callsign_loaded | rows |
| 12 | app_ready | 总耗时 |

统一包装：

~~~dart
await boot.step('10 dxcc_loaded', () => dxccManager.loadDxcc());
~~~

`boot.step` 内部负责计时、catch、记录 ok/fail，并把失败升级为**可呈现状态**：UI 不再永久转圈，而是展示"启动失败：DXCC 数据加载失败"并提供导出日志入口。

**补充：劫持 print。** 通过 `runZonedGuarded` 的 `ZoneSpecification.print`，把三方库与插件的 `print` 统一并入日志流，避免它们在 Windows 上同样成为黑洞。

### 5.7 环境快照（Session Header）

每个日志文件开头写一次（每进程一次）：

~~~
[SESSION] app=ssb_runner version=0.1.0+100000 build_sha=... mode=release
[SESSION] dart=... flutter=...
[SESSION] os=windows 10.0.19045 x64 processors=8
[SESSION] locale=zh_CN tz=Asia/Shanghai
[SESSION] exe=... cwd=... log_dir=... fallback_index=0
[SESSION] runtime_env=...
[SESSION] audio_devices=...
~~~

- build SHA 通过 `--dart-define=BUILD_SHA=...` 注入，避免依赖运行时。
- 版本号取自 `package_info_plus`。

### 5.8 运行时环境采集

在 `main()` 最前面、任何插件之前执行，作为环境快照的一部分记录运行时原生库的加载情况：

~~~dart
for (final name in candidates) {
  final path = p.join(exeDir.path, name);
  final exists = File(path).existsSync();
  String? loadErr;
  if (exists) {
    try {
      DynamicLibrary.open(path);
    } catch (e) {
      loadErr = '$e';
    }
  }
  log.info('native_dep', tag: 'env', fields: {
    'name': name, 'exists': exists, 'loadErr': loadErr,
  });
}
~~~

- `DynamicLibrary.open` 会走系统加载器，能拿到真实错误信息（如 Windows 的 126 = 模块找不到 / 依赖缺失），信息量远高于 `existsSync`。
- 同时记录 exe 同级目录的 **库文件名列表**，用于确认用户机器上的实际部署内容。
- **边界说明：** 该采集只能覆盖进程进入 Dart 之后的情况，更早阶段的失败不在覆盖范围内。

### 5.9 错误捕获集成

- **保留 Catcher2** 作为异常汇聚与 UI 呈现中枢，不重复设置 `FlutterError.onError` / `PlatformDispatcher.onError` / `Isolate` / zone（Catcher2 已接管）。
- 新增 LoggingHandler，把 `Report` 桥接到 FileSink（见 5.5）。
- 原 `FileHandler` 可保留以输出完整 crash block，但需确保与 FileSink **不写同一文件**、互不覆盖。
- release 的 `DialogReportMode` 替换为**错误页**：展示友好提示 + "导出日志" + "复制诊断信息"。
- `worker_manager` 动态 spawn 的 isolate 需单独挂 error listener，否则音频解码线程异常会丢失。

### 5.10 环形缓冲与崩溃 dump

见 5.5 RingBufferSink。此外：

- 崩溃安全依赖"常开 sink + 分级 flush + 生命周期钩子"三件套。
- 对原生崩溃（Windows access violation 等），进程内 Dart 代码无法收尾；这属于 P3 范围（可选接入 Crashpad / Sentry Native）。

### 5.11 轮转与保留

| 维度 | 策略 |
|---|---|
| 切分触发 | 按天 **或** 单文件 5 MB，先到先切 |
| 命名 | `app-YYYY-MM-DD.log`、`app-YYYY-MM-DD.1.log` |
| 保留 | 7 天 **且** 总量 <= 50 MB，双条件淘汰 |
| 字节预算 | 正常 release 使用一天 < 2 MB |

### 5.12 导出与上报

- **P2-a 导出 zip**：最近 N 个日志文件 + session header + DB schema 版本 + 设置快照（不含敏感值）打包，走系统另存/分享。
- **P2-b 复制诊断摘要**：把 header + 最近的 SEVERE 记录复制到剪贴板。社区沟通主用微信/QQ，粘贴文本摩擦最低，**建议先做这一档**。
- **P3 远程上报**：Sentry 或自建，需先明确隐私边界与默认开关。

### 5.13 脱敏

- 用户名路径脱敏：`/Users/<user>`、`C:\Users\<user>` -> `~`。
- 不记录设备序列号、MAC、剪贴板内容。
- 呼号属业务数据，可记录，但导出时在界面提示。

### 5.14 性能

- 落盘在独立单消费者队列，UI isolate 只做入队。
- 高频日志使用 `FINE`，并对相邻重复行折叠为 `(xN)`（状态机跃迁、音频播放是热点）。
- 日志格式化延迟到 sink 侧执行，避免调用点开销。

### 5.15 接口定义（草案）

~~~dart
enum LogLevel { trace, debug, info, warn, error, fatal }

class LogRecord {
  final DateTime timestampUtc;
  final LogLevel level;
  final String tag;
  final String message;
  final Map<String, Object?> fields;
  final Object? error;
  final StackTrace? stackTrace;
}

abstract class LogSink {
  Future<void> init(LogSession session);
  void write(LogRecord record);
  Future<void> flush();
  Future<void> dispose();
}

class BootTrace {
  Future<T> step<T>(String label, Future<T> Function() action);
}

class AppLogger {
  void trace(String msg, {String tag, Map<String, Object?> fields});
  void debug(String msg, {String tag, Map<String, Object?> fields});
  void info(String msg, {String tag, Map<String, Object?> fields});
  void warn(String msg, {String tag, Map<String, Object?> fields, Object? error});
  void error(String msg, {String tag, Map<String, Object?> fields, Object? error, StackTrace? stackTrace});
  void fatal(String msg, {String tag, Map<String, Object?> fields, Object? error, StackTrace? stackTrace});
}
~~~

---

## 6. 代码改动清单

| 文件 | 改动类型 | 说明 |
|---|---|---|
| `lib/logging/`（新增） | 新增 | facade / record / session / boot_trace / probe / export / sinks |
| `lib/main.dart` | 修改 | 先 init L1 日志，再 Catcher2；改用 runZonedGuarded 并劫持 print |
| `lib/error_handling.dart` | 修改 | Catcher2 Handler 桥接到 FileSink；release 换错误页 |
| `lib/common/dirs.dart` | 修改 | 新增 `getLogDirectory()` 回退链 |
| `lib/ui/main_app/main_app.dart` | 修改 | 加载链改为 `boot.step(...)`，失败进错误态 |
| `lib/settings/app_settings.dart` | 修改 | 新增 `verboseLogging` 开关 |
| `lib/ui/main_settings/options_setting.dart` | 修改 | 新增"详细日志""导出日志"UI |
| `pubspec.yaml` | 修改 | 显式声明 logging / package_info_plus / device_info_plus / path |
| `windows/runner/main.cpp` | 可选 | 原生 bootstrap 日志 / `--console` 参数 |

---

## 7. 实施阶段

| 阶段 | 内容 | 估时 | 收益 |
|---|---|---|---|
| **P0** | FileSink + 启动埋点 + main 初始化顺序 + 目录回退 | 0.5 - 1 天 | 立刻有日志，可直接定位用户侧问题 |
| **P1** | 运行时环境采集 + 环境 header + 加载链异常隔离/错误页 | 0.5 - 1 天 | 启动失败可见、可诊断 |
| **P2** | 导出 zip/剪贴板 + 详细日志开关 + 轮转保留 + 脱敏 | 1 - 2 天 | 用户侧可交付日志，长期可维护 |
| **P3** | 远程上报 + 原生 bootstrap 日志 | 按需 | 主动发现线上问题 |

**建议先做 P0 + P1**：以最小改动解决"没有日志"与"启动失败无迹可查"。

---

## 8. 测试与验收

### 8.1 单元测试

- FileSink：轮转触发、保留淘汰、并发写入、flush 时机。
- 目录解析：回退链顺序与 `fallback_index`。
- 脱敏函数：Windows / macOS / 含空格与中文的用户名路径。
- logfmt 序列化：转义与解析往返一致。

### 8.2 故障注入

| 注入 | 预期 |
|---|---|
| 日志目录不可写 | 回退成功，header 标明 fallback_index |
| 删除某个运行时库 | boot trace 记录明确的 `native_dep` 加载失败条目 |
| `loadDxcc` 抛异常 | UI 进错误态，日志有 `SEVERE`，不再无限转圈 |
| 强制 `SEVERE` | 环形缓冲上下文被 dump |
| 杀进程 | 已 flush 的日志完整，无半行损坏 |

### 8.3 真机矩阵（关键）

| 维度 | 取值 |
|---|---|
| OS | Windows 10 / Windows 11 / macOS / Linux |
| 用户名 | 纯英文 / 中文 / 含空格 |
| Documents | 本地 / OneDrive 重定向 |
| 安装位置 | 系统盘 / 非系统盘 / 便携版 |

### 8.4 体积预算

连续运行 1 小时，release 日志 < 2 MB。

---

## 9. 风险与权衡

| 决策点 | 选择 | 理由 / 权衡 |
|---|---|---|
| 是否保留 Catcher2 | 保留 | 已接管全局错误钩子，重建不划算；降级为"错误汇聚 sink" |
| facade 选型 | `package:logging` | 生态标准、层级命名、level 过滤，且已是 transitive 依赖 |
| 主格式 | logfmt 单行文本 | 人工 grep 友好、体积小；JSONL 作为可选模式 |
| 日志目录 | Application Support | Windows Documents 受 OneDrive 影响，不适合放日志 |
| DB 目录 | 不动 | 避免数据迁移风险 |
| 常开 IOSink | 是 | 崩溃前尽量多落盘；代价是需要在生命周期钩子强制 flush |

---

## 10. 待决问题

1. 远程上报（P3）是否引入、默认是否开启、隐私政策如何表述。
2. 日志目录是否需要在界面上暴露（"打开日志文件夹"按钮）。
3. 便携版（未安装、直接运行 exe）场景下日志写到 exe 同级是否可接受。
4. 是否需要在 Windows 上提供 `--console` 启动参数以便现场调试。

---

## 12. 实现状态（方案 A）

> 落地日期：2026-09-30
> 范围：P0 + P1，并含 P2 的导出、开关与脱敏。

按方案 A 实现：复用 `package:logger` 的 `AdvancedFileOutput` / `MemoryOutput` / `MultiOutput`，未引入新的第三方包（`package_info_plus` 由 transitive 提升为 direct，版本未变）。

### 12.1 已实现

| 设计项 | 实现位置 | 说明 |
|---|---|---|
| 目录回退链 | `lib/logging/log_paths.dart` | Application Support -> Temp -> exe 同级；用探针文件校验可写性；记录 fallback_index |
| 会话快照 | `lib/logging/log_session.dart` | 应用版本、Dart / OS / arch / locale / 时区 / 进程数与工作目录 |
| 日志格式 | `lib/logging/app_log_printer.dart` | 单行 logfmt + UTC ISO-8601 + 错误与堆栈缩进块 |
| facade / 级别 / 开关 | `lib/logging/app_logger.dart` | trace - fatal；`setVerbose` 运行时切换 |
| FileSink | `AdvancedFileOutput` | 5 MB 轮转、保留 10 份、缓冲写、warning 以上立即 flush、`fileHeader` 写 session header |
| RingBufferSink | `MemoryOutput` | 200 条环形缓冲；error / fatal 时 dump 进同一文件 |
| 启动埋点 | `lib/logging/boot_trace.dart` | `BOOT nn <label> start/ok/failed` + durMs |
| 环境采集 | `lib/logging/logging_bootstrap.dart` | 记录 exe 同级原生库清单 |
| Catcher2 桥接 | `lib/error_handling.dart` | 报告写入同一日志流；release 使用 `PageReportMode` |
| 启动链改造 | `lib/ui/main_app/main_app.dart` | 每步 `boot.step`；失败进错误页（复制诊断 / 导出日志） |
| 导出与摘要 | `lib/logging/log_export.dart` | zip 输出到 Documents；摘要复制到剪贴板 |
| 详细日志开关 | `lib/settings/app_settings.dart` + `lib/ui/main_settings/diagnostics_setting.dart` | 持久化并即时生效 |
| print 劫持 | `appZoneSpecification()` | 三方 `print` 纳入日志流，带防重入与防自捕获 |

### 12.2 与设计的偏差

1. **未使用 `LogfmtPrinter`**：它的输出只有 level 与 msg，不含时间戳、tag 与堆栈；改用自研 `AppLogPrinter`（约 60 行），格式与 5.3 一致。
2. **轮转仅按大小**：`AdvancedFileOutput` 不支持按天切分，5.11 的"按天或按大小"退化为 5 MB 单条件 + 保留 10 份。
3. **未保留 Catcher2 `FileHandler`**：异常与过程日志统一写入同一文件，避免两个文件对时。
4. **未纳入"打开日志目录"入口**：见第 10 节待决问题第 2 条。

### 12.3 关键修正

`package:logger` 的默认过滤器 `DevelopmentFilter` 基于 `assert`，在 release 构建下会丢弃**全部**日志。本次已显式改用 `ProductionFilter` 并按构建模式设置级别（release 为 INFO，debug 为 DEBUG）。这是"release 没有日志"的第二个成因——只解决 Windows 控制台问题并不足够。

### 12.4 验证

- 新增 `test/logging/`：printer 格式与转义、堆栈输出、日志文件枚举、诊断摘要、文件落盘与上下文 dump、路径脱敏。
- `flutter analyze` 无新增问题；`flutter test` 全绿。

---

## 附录 A：日志字段字典（核心字段）

| 字段 | 类型 | 说明 |
|---|---|---|
| `msg` | string | 人类可读摘要 |
| `tag` | string | 命名空间，见 5.2 |
| `err` | string | 异常 toString |
| `stack` | string | 仅在异常块中出现 |
| `durMs` | int | 步骤耗时 |
| `stage` | string | 启动埋点编号与名称 |
| `path` | string | 已脱敏路径 |
| `fallback_index` | int | 目录回退层级 |
| `rows` | int | 数据加载行数 |
| `traceId` | string | 进程级关联 ID |

## 附录 B：启动埋点清单

见 5.6 表格（01 - 12），失败时补记 `BOOT XX fatal stage=... err=...`。
