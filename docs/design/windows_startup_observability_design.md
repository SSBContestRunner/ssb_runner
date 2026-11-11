# Windows 启动白屏可观测技术方案

> 状态：待评审
> 适用范围：Windows runner（原生时间线）+ 桌面端 Dart 启动链路（UI isolate 心跳信号）
> 关联文档：[首屏白屏技术方案](./first_frame_white_screen_design.md) §2.4、[启动性能优化设计方案](./startup_performance_design.md)
> 本文只解决「怎么让白屏可被定位」，不改窗口显示策略、不缩短启动耗时、不做自动恢复或自动杀进程。

---

## 1. 问题定义

用户反馈的 Windows「卡白屏」实际包含两类完全不同的故障，目前日志无法区分：

| 现象 | 可能卡住的线程/阶段 | 现有日志能否定位 |
| --- | --- | --- |
| 双击后长时间没窗口，任务管理器里有进程 | 平台线程：引擎和插件 DLL 加载、`FlutterViewController` 构造、`RegisterPlugins` | 否。`main()` 没执行，日志目录里没有本次会话文件 |
| 窗口出现但一直白屏/不刷新 | Dart UI isolate：`main()` 之后同步 IO、死锁、等待永不完成的 Future | 只能看到 `first frame visible` 缺失，无法判断卡在哪个 `BOOT` 步骤 |

现有埋点（[boot_trace.dart](../../lib/logging/boot_trace.dart#L7-L51)、[logging_bootstrap.dart](../../lib/logging/logging_bootstrap.dart#L21-L79)）全部从 `main()` 开始，且文件 sink 在首帧之后才安装。**首帧之前发生的一切，磁盘上没有任何证据。**

## 2. 目标与非目标

### 2.1 目标

1. 把启动切成可对账的四段，每段都有毫秒级时间戳：

   ```text
   进程启动 ──> wWinMain ──> Dart main() ──> 首帧 ──> 窗口 Show
                (原生)         (Dart)        (Dart)     (原生)
   ```

2. 启动超时（默认 10 s 未 Show）时，原生侧主动落盘一条 `state=timeout` 记录，写明最后完成的阶段。
3. Dart UI isolate 在首帧前停摆超过 10 s 时，由原生看门狗线程落盘一条 `state=dart_stalled`，写明最后的启动阶段。
4. 正常启动只在窗口 Show 之后写一次约 200 字节的小文件；首帧路径不新增 IO、不新增平台通道、不新增 isolate。
5. 诊断摘要（用户复制/导出）自动带上启动时间线，不需要用户自己翻日志头。

### 2.2 非目标

- 不覆盖 `wWinMain` 之前的 exe/CRT/系统 DLL 搜索与安全软件首次扫描；那只能靠外部启动器或 ETW。
- 不自动重启、不自动关闭窗口、不弹错误对话框。
- 不做远程上报，不改日志格式。
- 不为 macOS/Linux 增加原生时间线；Dart 侧在缺少原生参数时静默降级。
- 默认不覆盖运行期卡顿，只覆盖到 `application ready`；运行期方案见 §10.3。

## 3. 方案总览

```text
wWinMain
  ├─ StartupTrace::Create()           记录 entry_utc / QPC 起点
  ├─ 写第一行 state=entry 到 %TEMP%\ssb_runner_boot\boot_<pid>.log
  ├─ 启动原生看门狗线程（10 s 无 Show / 10 s 无心跳则追加一条记录）
  ├─ 导出 ssb_boot_beat(phase, step)  供 Dart FFI 调用
  ├─ GetCommandLineArguments() + "--boot-trace-dir=<dir>"
  │      └─ set_dart_entrypoint_arguments
  ├─ FlutterWindow::OnCreate
  │     ├─ Mark(window_created / controller_created / plugins_registered)
  │     └─ SetNextFrameCallback → Mark(first_frame) → Show() → Write(state=shown)
  │
  ▼
Dart main(List<String> args)
  ├─ boot.start()                    记录 startedAtUtc
  ├─ 解析 --boot-trace-dir
  ├─ 启动 2 s 心跳 Timer（每次只写原生原子变量，不写盘、不打日志）
  ├─ 其余保持现状（内存日志、隐藏窗口、Catcher2）
  │
  ▼
first frame post-frame
  ├─ boot.markFirstFrame()
  ├─ log "first frame visible"（sinceMainMs / sinceProcessMs）
  │
  ▼
bootstrapLoggingAfterFirstFrame
  ├─ 安装文件 sink + 回放
  ├─ boot.step('boot_trace', readBootTrace)   读取原生文件
  ├─ log "boot timeline"（分段耗时 + 超时/停摆标记）
  └─ 删除临时文件
```

整个方案只有**一个临时文件、一个原生写线程**。心跳走 FFI 写入内存中的原子变量，正常路径不产生任何心跳日志，也不常驻额外 isolate。

## 4. 原生时间线（Windows runner）

### 4.1 新增 `windows/runner/startup_trace.{h,cpp}`

状态用 `shared_ptr` 持有，看门狗线程只引用它，不引用窗口对象，避免销毁竞态。

```cpp
enum class StartupPhase {
  kEntry,
  kWindowCreated,
  kControllerCreated,
  kPluginsRegistered,
  kFirstFrame,
  kShown,
};

class StartupTrace {
 public:
  static std::shared_ptr<StartupTrace> Create();  // 创建目录，记录 entry
  void Mark(StartupPhase phase);                  // 只写原子与 QPC，无 IO
  void Beat(int phase, int step);                 // Dart 心跳，只写原子
  void WriteSnapshot(const char* state);          // 追加一行

 private:
  void WatchdogMain();                            // 独立线程，250 ms 轮询
};
```

每个阶段只做两件事：`QueryPerformanceCounter` 取微秒差、`std::atomic` 存阶段枚举。**`Mark` 不写文件**，因此 `OnCreate`、插件注册、首帧回调都不会被磁盘或安全软件拖慢。

### 4.2 导出给 Dart 的心跳函数

```cpp
extern "C" __declspec(dllexport) void ssb_boot_beat(int phase, int step) {
  if (auto* trace = g_trace.load(std::memory_order_acquire)) {
    trace->Beat(phase, step);
  }
}
```

- `phase`：`0=preFrame`、`1=booting`、`2=firstFrame`、`3=ready`。
- `step`：`BootTrace` 当前步骤序号，0 表示还没进入任何 `BOOT` 步骤。
- 未初始化、已退出、非 Windows 构建时为空操作。
- 只有存在 `--boot-trace-dir` 参数时 Dart 才调用，macOS/Linux 不加载该符号。

### 4.3 文件格式

追加式单行 key=value，便于原生写、Dart 解析、人工看：

```text
trace=1 state=entry pid=12345 entry_utc_ms=1762836000123 elapsed_us=0 phase=entry
trace=1 state=dart_stalled pid=12345 entry_utc_ms=1762836000123 elapsed_us=11004312 phase=plugins_registered dart_phase=booting dart_step=05 dart_gap_ms=10020
trace=1 state=timeout pid=12345 entry_utc_ms=1762836000123 elapsed_us=10000231 phase=plugins_registered window_us=180022 controller_us=9210030 plugins_us=11004400
trace=1 state=shown pid=12345 entry_utc_ms=1762836000123 elapsed_us=12400310 phase=shown window_us=180022 controller_us=9210030 plugins_us=11004400 first_frame_us=12310010
```

规则：

- `elapsed_us` 与 `*_us` 一律相对 `entry`，来自 QPC，不受系统时间调整影响。
- `entry_utc_ms` 来自 `GetSystemTimePreciseAsFileTime`，只用于和 Dart 的 `DateTime.now()` 对齐。
- `state` 取值为 `entry / timeout / shown / dart_stalled`。一次启动可以先后出现多条，Dart 合并后按最后状态判断。
- `dart_phase=preFrame` 表示 `main()` 已进入但 `boot.start()` 之后的第一个心跳还没发出；`dart_phase=none` 表示整个进程从未收到过心跳（FFI 加载失败或 `main()` 未执行）。
- 每次写入用同一把 `std::mutex` 串行化，单行小于 512 字节。

### 4.4 原生看门狗

- 线程在 `wWinMain` 里、写 `entry` 之后启动，`std::thread` + `detach`，只持有 `shared_ptr<StartupTrace>`。
- 每 250 ms 检查一次，命中以下任一条件就追加记录：
  - `now - entry >= 10 s` 且尚未 `shown`：`state=timeout`。
  - 已收到过心跳，且 `now - lastBeat >= 10 s` 且尚未 `ready`：`state=dart_stalled`。
- 单进程最多写 3 条 `dart_stalled`（同一次停摆只写一条，收到新心跳后重新武装）。
- 收到 `phase=ready` 或 `shown` 后 60 s 仍未 `ready`，线程退出；不在应用整个生命周期内常驻。
- 超时阈值可通过环境变量 `SSB_RUNNER_BOOT_TIMEOUT_MS` 覆盖，便于支持人员现场复现。

### 4.5 埋点位置

| 位置 | 调用 | 说明 |
| --- | --- | --- |
| [main.cpp](../../windows/runner/main.cpp#L8-L33) `wWinMain` 开头 | `Create()` + `WriteSnapshot("entry")` | 记录进程进入 runner 的时间 |
| `window.Create(...)` 返回后 | `Mark(kWindowCreated)` | 区分窗口类注册/消息循环之前 |
| [flutter_window.cpp](../../windows/runner/flutter_window.cpp#L12-L40) `OnCreate` 构造 controller 之后 | `Mark(kControllerCreated)` | 这一段覆盖引擎加载与首帧调度器初始化 |
| `RegisterPlugins(...)` 之后 | `Mark(kPluginsRegistered)` | 插件 DLL 加载是 Defender 扫描的重点 |
| `SetNextFrameCallback` 内、`Show()` 之前 | `Mark(kFirstFrame)` | 引擎产出了第一帧 |
| `Show()` 之后 | `Mark(kShown)` + `WriteSnapshot("shown")` | 用户第一次能看到窗口 |

`FlutterWindow` 构造函数增加一个 `std::shared_ptr<StartupTrace>` 参数；`main.cpp` 已经自定义过窗口尺寸，继续在该文件接线。

### 4.6 构建接入

[runner/CMakeLists.txt](../../windows/runner/CMakeLists.txt#L9-L17) 的 `add_executable` 显式列出源文件，需要加入 `"startup_trace.cpp"`。导出符号使用 `__declspec(dllexport)`，不依赖 .def 文件。

## 5. Dart 侧读取与合并

### 5.1 启动参数

[main.cpp](../../windows/runner/main.cpp#L22-L25) 已把命令行参数传给 Dart，继续追加一项：

```cpp
arguments.push_back("--boot-trace-dir=" + Utf8FromUtf16(directory.c_str()));
```

Dart 入口改为 `void main(List<String> args)`，只识别 `--boot-trace-dir=` 前缀，其余参数保持原样传递。macOS/Linux 拿不到该参数，走降级分支。

### 5.2 新增 `lib/logging/boot_trace_reader.dart`

职责单一：定位文件、解析、删除。

```dart
class NativeBootTrace {
  final String? state;              // entry / timeout / shown / dart_stalled
  final int? entryUtcMs;
  final int? elapsedUs;             // 最后一条快照
  final Map<String, int> phasesUs;  // window/controller/plugins/first_frame
  final String? lastPhase;
  final bool timedOut;
  final bool dartStalled;
  final String? dartPhase;
  final int? dartStep;
  final int? dartGapMs;
}

Future<NativeBootTrace?> readBootTrace(String directory);
```

解析规则：

- 逐行按第一个 `=` 拆分，忽略无法识别的键（向前兼容）。
- 多行合并时 `state` 取最后一行的值；`timedOut` / `dartStalled` 为任意一行出现过对应状态。
- 各 `*_us` 取最大值（后写入的快照更完整）。
- 文件缺失、被占用、内容截断都只返回 `null` 或部分字段，**不抛异常**。

读取时机：文件 sink 安装并回放完成后，`await boot.step('boot_trace', ...)`。此时首帧已经发生，`shown` 行可能还差几毫秒；若读到 `state=entry/timeout/dart_stalled` 且没有 `shown`，挂一个一次性 1.5 s 的 `Timer` 重读，最多重试一次。

### 5.3 `BootTrace` 扩展

[boot_trace.dart](../../lib/logging/boot_trace.dart#L7-L51) 增加：

```dart
DateTime? _startedAtUtc;
DateTime? _firstFrameAtUtc;
String phase = 'preFrame';

void start() {
  _startedAtUtc ??= DateTime.now().toUtc();
}

void markFirstFrame() {
  _firstFrameAtUtc ??= DateTime.now().toUtc();
  phase = 'firstFrame';
}

int? get sinceProcessMs =>
    _startedAtUtc == null ? null : DateTime.now().toUtc().difference(_startedAtUtc!).inMilliseconds;
```

`phase` 由 `BootTrace.step` 在开始/结束时更新为 `booting` / `ready`，序号取 `_sequence`，供心跳一并上报。

### 5.4 日志输出

首帧日志补充进程维度字段：

```dart
log.info('first frame visible', tag: 'boot', fields: {
  'sinceProcessMs': boot.sinceProcessMs,
  'sinceMainMs': boot.elapsedMs,
});
```

读取结果输出一条聚合记录：

```dart
log.info('boot timeline', tag: 'boot', fields: {
  'process_to_main_ms': ...,
  'main_to_first_frame_ms': ...,
  'process_to_first_frame_ms': ...,
  'entry_to_shown_ms': ...,
  'window_us': ..., 'controller_us': ..., 'plugins_us': ...,
  'first_frame_us': ...,
  'native_timeout': false,
  'dart_stalled': false,
});
```

异常分支：

- `native_timeout=true`：额外写 `log.warn('native startup timeout', fields: {'last_phase': ...})`。
- `dart_stalled=true`：额外写 `log.warn('dart startup stalled', fields: {'phase': ..., 'step': ..., 'gap_ms': ...})`。
- 文件不存在：`log.info('boot trace unavailable', fields: {'reason': 'missing'})`，macOS/Linux 常态，级别不为 warn。

读取完成后删除自己 pid 的文件；删除失败只记 debug。

## 6. UI isolate 心跳信号

### 6.1 为什么需要独立观察者

Flutter 桌面端平台线程与 Dart UI isolate 是两个线程。Dart 侧死锁时平台线程仍然健康，原生看门狗只能看到「还没 Show」，看不到「Dart 已经跑到哪一步」。UI isolate 自己的 `Timer` 在停摆时也不会触发，因此必须由另一个线程观察心跳中断。

这个观察者放在原生看门狗线程里，而不是再开一个 Dart isolate：原生线程本来就要为 Show 超时存在，复用它看心跳不需要新增线程、新增 isolate 或新增文件。

### 6.2 实现

`lib/logging/boot_beat.dart`：

```dart
typedef BootBeatFn = void Function(int phase, int step);

BootBeatFn? loadBootBeat(DynamicLibrary process) {
  try {
    return process.lookupFunction<Void Function(Int32, Int32), void Function(int, int)>(
      'ssb_boot_beat',
    );
  } on ArgumentError {
    return null; // 符号不存在：非 Windows 或被裁剪
  }
}
```

- `main()` 里如果解析到 `--boot-trace-dir`，加载一次符号并调用一次 `beat(preFrame, 0)`，证明 `main()` 已执行。
- `Timer.periodic(const Duration(seconds: 2), ...)` 发送 `(phase, step)`；写入的是原生 `std::atomic<int64_t>` 与两个 `int`，没有序列化、没有文件、没有日志。
- `phase` 变为 `ready` 时发送最后一次心跳并取消 Timer，之后不再有任何心跳开销。
- FFI 加载失败只写一条 debug 日志（`boot beat unavailable`），不影响启动，也不回退到 isolate 方案。

心跳不产生日志：正常启动只有 `entry`、`shown` 两行临时记录，合并后落成一条 `boot timeline`。

### 6.3 开销与日志体量

| 项 | 正常启动 | 停摆时 |
| --- | --- | --- |
| 新增日志条数 | 1 条（`boot timeline`） | +1 条 warn |
| 临时文件 | 1 个，读取后删除 | 同左 |
| Dart isolate | 0（不新增） | 0 |
| UI 线程心跳频率 | 2 s 一次，`ready` 后停止 | 同左 |
| 单次心跳成本 | 一次 FFI 调用 + 三次原子写，纳秒级 | 同左 |
| 原生线程 | 1 个，`ready` 后退出 | 同左 |
| 写盘次数 | 2 次（entry、shown），均为一次性小文件 | +1 次（停摆记录） |
| 每进程停摆记录上限 | — | 3 条 |

因此不存在「都是心跳日志」的情况：心跳本身从不写日志，只有真正的停摆事件才落一行，且有条数上限。

## 7. 诊断摘要携带启动时间线

[log_export.dart](../../lib/logging/log_export.dart#L32-L64) 的 `diagnosticSummary` 目前只取 `latest.log` 最后 100 行，启动记录在文件最前面，正好被截掉。调整为：

1. 读取全部行后，先筛出 `boot / env / native` 标签的行（行格式见 [app_log_printer.dart](../../lib/logging/app_log_printer.dart#L47-L66)），最多 40 行；
2. 以 `--- startup ---` 段落放在会话头之后；
3. 再追加原有的 `last 100 lines`。

这样用户点「复制诊断摘要」时，`boot timeline`、超时/停摆记录一定在内，不需要再教用户去日志目录找文件头。

## 8. 测试与验收

### 8.1 自动化

| 用例 | 断言 |
| --- | --- |
| `boot_trace_reader_test.dart` 正常文件 | 解析出 `state=shown`、各阶段微秒值、`process_to_main_ms` 计算正确 |
| 只有 `entry` 行 | `state=entry`，缺 `shown` 不抛异常 |
| `timeout` + `shown` 两行 | `timedOut=true`，`elapsedUs` 取最后一行 |
| `dart_stalled` 行 | `dartStalled=true`，`dartPhase/dartStep/dartGapMs` 正确 |
| 未知键、乱序键、空文件 | 忽略或返回 null，不抛异常 |
| `BootBeat` 定时器 | 注入 fake `BootBeatFn`：2 s 触发、`ready` 后取消、`step` 随 `BOOT` 序号变化 |
| `diagnosticSummary` | 摘要包含 `--- startup ---` 与 `boot timeline`，且仍包含尾部日志 |

`flutter analyze` / `flutter test` 全绿。

### 8.2 手工验收（Windows release 构建）

1. 正常启动：`latest.log` 出现 `boot timeline`，`native_timeout=false`、`dart_stalled=false`；`%TEMP%\ssb_runner_boot\` 下本次 pid 文件被删除。
2. 模拟平台线程慢启动：设置 `SSB_RUNNER_BOOT_DELAY_MS=12000`（§8.3），确认 `state=timeout` 记录、`last_phase` 正确、日志出现 `native startup timeout`。
3. 模拟 Dart 启动停摆：设置 `SSB_RUNNER_TEST_BOOT_STALL_MS=8000`，在 `main()` 里同步忙等超过 10 s，确认原生侧写出 `dart_stalled`，且 `dart_step` 指向卡住前的最后一步。
4. macOS/Linux：启动日志无 warn，出现 `boot trace unavailable`（info）。
5. 首帧无回归：对比改造前后 `first frame visible` 的 `sinceMainMs`，差值应在个位数毫秒；profile 模式下无 > 32 ms 的单次阻塞。
6. 日志体量：正常冷启动 `latest.log` 只多 1 条 `boot timeline`，无周期性心跳记录。

### 8.3 测试钩子（仅测试用）

- 原生：`SSB_RUNNER_BOOT_DELAY_MS`，在 `OnCreate` 构造 controller 之前 `Sleep`，用于验证超时记录。
- Dart：`SSB_RUNNER_TEST_BOOT_STALL_MS`，在 `main()` 内同步忙等，用于验证原生侧对心跳中断的检测能力。

两个钩子只在读取到环境变量时生效，默认路径零影响；与现有 `SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER`、`SSB_RUNNER_TEST_EXIT_HANG`（[main_app.dart](../../lib/ui/main_app/main_app.dart#L83-L122)）保持同一风格。

## 9. 风险与回滚

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| `wWinMain` 开头的 `state=entry` 写盘本身被 Defender 扫描 | 极慢机器上给启动增加几毫秒 | 单次 200 字节写入；如实测有影响，可改为仅在看门狗超时时由线程补写，代价是失去「进程活着但从未进入 runner」的证据 |
| 导出符号在 release 构建被裁剪或查找失败 | 没有 Dart 心跳，`dart_stalled` 无法判定 | `__declspec(dllexport)` 显式导出；加载失败只写一条 debug；`timeout` 记录里带 `dart_phase=none` 表明「从未收到心跳」，仍可区分「Dart 没跑」与「Dart 跑了但慢」 |
| 入口参数被 Dart 层忽略 | 无原生时间线，只剩现有 Dart 埋点 | 解析失败只降级，不影响启动；日志记录 `reason=no-arg` |
| 心跳本身造成 UI 抖动 | 每 2 s 一次 FFI，理论纳秒级 | 验收项 5 要求 `sinceMainMs` 增量 ≤ 3 ms；若异常，优先怀疑其他改动 |
| 看门狗线程与窗口销毁竞态 | 退出时访问已释放对象 | 线程只持有 `shared_ptr<StartupTrace>`，不引用 `FlutterWindow`；`ready` 或超时后自行退出；进程结束时由系统回收 |
| 停摆记录刷屏 | 日志膨胀 | 每次停摆只写 1 条，收到新心跳后重新武装，单进程上限 3 条 |
| 两个进程同时写同一目录 | 文件名冲突 | 文件名带 pid，互不覆盖 |
| 临时文件泄漏 | `%TEMP%` 累积 | Dart 读取后删除；启动失败留下的文件由系统临时目录清理策略回收，单文件 < 1 KB |
| 日志泄露路径信息 | 隐私 | 目录与路径统一走 `redactPath`（[log_paths.dart](../../lib/logging/log_paths.dart#L115-L123)） |

回滚粒度：

- 原生时间线（§4、§5.1）一次提交，可整体 revert；
- Dart 读取与摘要（§5.2–§7）可独立 revert，原生文件残留无害；
- 心跳（§6）独立开关（无 `--boot-trace-dir` 即不加载），revert 后不影响其他两项。

## 10. 改动清单与实施顺序

### 10.1 P0：原生时间线 + Dart 合并

| 文件 | 改动 |
| --- | --- |
| `windows/runner/startup_trace.h/.cpp` | 新增：阶段标记、快照写入、看门狗线程、`ssb_boot_beat` 导出 |
| [windows/runner/CMakeLists.txt](../../windows/runner/CMakeLists.txt#L9-L17) | 加入 `startup_trace.cpp` |
| [windows/runner/main.cpp](../../windows/runner/main.cpp#L20-L33) | 创建 trace、追加 `--boot-trace-dir`、`Mark(kWindowCreated)` |
| [windows/runner/flutter_window.h](../../windows/runner/flutter_window.h#L12-L31) / [.cpp](../../windows/runner/flutter_window.cpp#L12-L40) | 注入 trace，标记 controller/plugins/first frame/shown |
| [lib/main.dart](../../lib/main.dart#L11-L49) | `main(List<String> args)`、解析参数、`boot.start()` 记录 UTC |
| `lib/logging/boot_trace_reader.dart` | 新增：解析、删除 |
| [lib/logging/boot_trace.dart](../../lib/logging/boot_trace.dart#L7-L51) | `startedAtUtc`、`markFirstFrame`、`phase`、`sinceProcessMs` |
| [lib/ui/main_app/main_app.dart](../../lib/ui/main_app/main_app.dart#L63-L70) | 首帧标记与日志字段 |
| [lib/logging/logging_bootstrap.dart](../../lib/logging/logging_bootstrap.dart#L40-L60) | sink 就绪后读取并输出 `boot timeline` |

P0 完成后即可回答「卡在进程→main、main→首帧、首帧→Show 的哪一段」。

### 10.2 P1：Dart 心跳信号

| 文件 | 改动 |
| --- | --- |
| `lib/logging/boot_beat.dart` | 新增：FFI 符号加载、2 s 心跳、`ready` 后取消 |
| [lib/main.dart](../../lib/main.dart#L11-L49) | 在 `Catcher2` 之前启动心跳 |
| [lib/logging/boot_trace.dart](../../lib/logging/boot_trace.dart#L7-L51) | `step` 同步更新 `phase` 与序号 |
| `windows/runner/startup_trace.cpp` | `Beat` + 看门狗判停摆 |

### 10.3 P2：诊断摘要与运行期

| 文件 | 改动 |
| --- | --- |
| [lib/logging/log_export.dart](../../lib/logging/log_export.dart#L32-L64) | 摘要前置 `--- startup ---` |
| `lib/logging/boot_beat.dart` | 运行期心跳（默认关闭）：不取消 Timer，间隔放宽到 5 s |
| `windows/runner/startup_trace.cpp` | 运行期不停看门狗，`dart_stalled` 上限沿用 3 条 |

运行期帧耗时采样（`addTimingsCallback` 只记录 > 32 ms 的帧）暂不纳入：它会产生持续日志量，且与本问题的排查路径不重合，等出现运行期卡顿反馈再单独立项。

## 11. 决策记录

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| 原生侧是否写日志文件 | 写 `%TEMP%` 下的独立小文件，不写应用日志目录 | 原生无法可靠复现 Dart 的日志目录三级兜底；临时目录恒定可写 |
| 是否只靠 Dart 看门狗 | 不采用 | `main()` 之前的阶段、以及平台线程阻塞，Dart 完全看不到 |
| 是否只靠原生看门狗 | 不采用 | 平台线程与 Dart UI 线程相互独立，原生看不到 Dart 卡在哪个 `BOOT` 步骤 |
| 心跳用独立 isolate 还是 FFI | **FFI** | 独立 isolate 要 spawn、要独立堆、要跨 isolate 序列化消息；FFI 只是三次原子写，正常路径零日志、零文件、零常驻 isolate |
| 心跳是否每条都写日志 | **否** | 只更新内存原子变量；仅在停摆时由原生线程写一条记录，单进程上限 3 条 |
| 心跳观察者是否常驻 | **否** | 复用 Show 超时看门狗线程，`ready` 后退出，不增加常驻线程 |
| 是否用 `OutputDebugString` / Windows 事件日志 | 不采用 | 普通用户拿不到，诊断包无法附带 |
| 是否把 `sinceProcessMs` 做成告警 | 只记录字段，不告警 | 慢机器基线差异大，误报会淹没真正的问题；超时由原生看门狗负责 |
| 是否自动结束卡死的进程 | 不做 | 观测方案不改变行为；卡死后的处置由用户决定 |
| 日志文件删除时机 | Dart 读取并写入 `latest.log` 之后删除 | 内容已经持久化，临时文件无保留价值 |
