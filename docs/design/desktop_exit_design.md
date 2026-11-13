# SSB Runner 桌面端退出流程技术方案（关闭窗口后进程残留）

> 状态：v2 修订（基于 2026-11-13 CI 故障的完整取证），待评审
> 适用范围：桌面端退出路径（Windows / macOS / Linux），重点是 Windows
> 不在范围：退出期间的业务数据落库策略、崩溃上报流程

---

## 0 修订摘要（v1 → v2）

v1 的"有界清理 + Dart 保底强杀"已落地并在多轮 Windows 冒烟中通过。2026-11-13 的 `v0.3.0-alpha05` 发布运行证明它**仍留有一个洞**：保底依赖 Dart 定时器，而新增的失败发生在 Dart VM 已经关闭之后。

| 维度 | v1 | v2 |
| --- | --- | --- |
| 根因认识 | 引擎在 `WM_DESTROY` 内同步析构时被阻塞 → 消息循环不退出 | 新增机制 B：退出时音频引擎处于**半初始化**状态 → `ExitProcess` 的 DLL 卸载阶段永久等待（§2.3） |
| 兜底位置 | Dart `Timer`（依赖 UI isolate 与 VM 存活） | 保留 Dart 定时器（只覆盖"清理卡死"），新增**原生看门狗**（覆盖 `ExitProcess` 卡死） |
| 音频收尾 | 用 `SoLoud.isInitialized` 判断是否 deinit | 用"初始化是否收敛"的追踪器决定；收敛后**一律**有界 `deinitAsync()`，不按状态跳过（§4.1 音频收尾硬约束）；只有两种确定状态才允许答复 `exit`（§4.1 不变量） |
| CI 覆盖 | 场景 3 只跑一次；失败无 dump；认为 CI 无音频设备 | 场景 3 延迟扫描 × 多轮；挂死先抓 minidump + 线程栈；已确认 CI 有音频端点且可稳定复现 |
| 启动成本 | 未评估 | 零新增启动期 IO / 线程：追踪器沿用现有 fire-and-forget 接入点，看门狗在 `Arm()` 内懒创建；约束与验收见 §4.1-5、§7-3 |
| 验收 | 10 s 内进程消失 | 增加"初始化在飞时关窗"必测项、线程数判据、退出 trace 阶段断言 |

---

## 1 背景与现场证据

### 1.1 用户侧反馈（v1）

| 证据 | 结论 |
| --- | --- |
| 本地 macOS（Debug / Release）关闭最后一个窗口，进程 1 s 内退出 | macOS 退出链路正常，问题集中在 Windows |
| 2025-08 曾用 `AppLifecycleListener.onExitRequested` 里调 `SoLoud.instance.deinit()` 修复过同类问题 | 该兜底不完整，用户侧仍能复现 |
| 上游 flutter_soloud issue #413 记录相同症状（Windows 关窗后进程留在后台） | 属桌面端原生音频析构与 Windows 进程退出时序的已知问题 |
| 用户诊断包显示 Windows 10、便携目录运行；启动失败/正常使用后关窗都会出现 | 与业务状态无关，只与退出路径有关 |

### 1.2 2026-11-13 CI 失败现场

运行 `43453412515`（分支 `v0.3.0-alpha05`，commit `171f7fd`），失败 job：`Smoke test (Windows)` 的 `Run Windows smoke test`，场景 3 `window close during startup`。

| 时刻（UTC） | 事件 |
| --- | --- |
| 15:44:42 | 启动进程 2044 |
| 15:44:43.672 | 首帧可见（`process_to_first_frame_ms=1003`） |
| 15:44:43.677~.693 | BOOT 01→09 依次开始，`storage_probe` / `soloud_init` / `db_ready` **均无 `ok`** |
| 15:44:43.708 | `exit requested`（关窗后 36 ms，`soloud_init` 只跑了约 20 ms） |
| +10 s | 日志再无任何一行；无 crash dump、无 WER 1000/1001 → **是挂死，不是崩溃** |
| 15:45:13 | 断言失败 `process 2044 still alive 10 s after WM_CLOSE`，随后被脚本强杀 |

排除回归：同一 commit 在 `main` 上的运行（`43453394654`）跳过了打包；20 分钟前的 `43449655097`（commit `e947ffa`）三个场景全过。`git diff e947ffa 171f7fd` 只有 `docs/release/*` 与 `pubspec.yaml` 版本号 → **不是功能回归，是时序竞态**。

同一次运行里场景 1（空闲关窗）与场景 2（注入清理卡死）均通过 → 关窗通路本身、Dart 保底在"引擎未开始析构"时有效。

---

## 2 根因分析

### 2.1 Windows 关闭时序（v1，仍然成立）

```
点击 X → WM_CLOSE
       → 引擎拦截（framework 已监听 flutter/platform）
       → 向 Dart 发送 System.requestAppExit
       → Dart 回调结束后答复 exit
       → 引擎重新 PostMessage(WM_CLOSE) → DefWindowProc 销毁窗口
       → WM_DESTROY → Win32Window::Destroy() → FlutterWindow::OnDestroy()
       → flutter_controller_ = nullptr（同步析构 FlutterEngine / Dart VM）
       → 之后才 PostQuitMessage(0) → 消息循环退出 → wWinMain 返回 → 进程结束
```

关键代码：[win32_window.cpp](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/win32_window.cpp#L202-L220)、[flutter_window.cpp](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/flutter_window.cpp#L76-L82)、[main.cpp](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/main.cpp#L45-L56)。

### 2.2 机制 A：退出清理无界 / UI isolate 被阻塞（v1 已修）

v1 的问题（清理没有超时、`deinit()` 同步阻塞 UI isolate、任一步抛错阻断后续）已由 [main_app.dart](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_app/main_app.dart#L120-L191) 的"有界清理 + Dart 保底强杀"覆盖，场景 2 即为该防线的回归测试。

**边界**：这条防线只在 Dart VM 仍然运行时有效。UI isolate 被阻塞、或 VM 已随引擎销毁而关闭时，`Timer` 不会执行。

### 2.3 机制 B：音频引擎半初始化 + `ExitProcess` 的 DLL 卸载（v2，本次取证结论）

取证分支 `ci/windows-exit-hang-forensics` 第一次 windows-only 运行即复现（`delay=0ms round 1`，run `43463159111` / job `132023572705`），并用三条独立时间线定位到挂死点。

**原生时间线**（`boot_<pid>.log`，pid 5220）：

| state | elapsed | 含义 |
| --- | --- | --- |
| `wm_close` | 1880 ms | WM_CLOSE 到达 |
| `destroy_begin` → `destroy_end` | 1887 → 1945 ms | **引擎析构只用了 58 ms，没有阻塞** |
| `loop_exit` | 1946 ms | 消息循环正常退出，`wWinMain` 返回 |

**Dart 退出时间线**（`exit_<pid>.log`）：`enter` → `logged` → `geometry_flushed` → `cleanup_done`，共 87 ms，**没有** `fallback_fired`。

**应用日志**：停在 `exit requested`，没有 `BOOT 06 soloud_init ok`、也没有 `SoLoud initialized` → 关窗时 `soloud_init` 仍在飞。由于 `SoLoud.isInitialized` 要求 `_nativeCallbacksInitialized`（初始化期间恒为 false），退出流程**跳过了 deinit**。

**挂死线程栈**（`hang_5220.dmp`，全进程只剩 1 个线程，`Wait / UserRequest`）：

```
ntdll!NtWaitForSingleObject
KERNELBASE!WaitForSingleObjectEx
flutter_soloud_plugin!...                  ← 13 层，无 PDB 只能显示最近导出符号
ntdll!LdrpCallInitRoutineInternal          ← DLL_PROCESS_DETACH
ntdll!LdrShutdownProcess
ntdll!RtlExitUserProcess
kernel32!ExitProcessImplementation
ucrtbase!common_exit
ssb_runner!...                             ← wWinMain 正常返回
```

因果链：

1. 窗口在首帧后 0~36 ms 被关闭，此时 `soloud_init` 已开始但未完成；`initEngine` 的设备打开在一个派生的 worker isolate 里执行（`Isolate.run(() => native.initEngine(...))`）。
2. 退出流程因为 `isInitialized == false` 跳过 deinit，答复 `exit`。
3. 引擎同步析构、窗口销毁、消息循环退出——这一段全部正常（58 ms）。
4. `wWinMain` 返回后进入 CRT `exit()` → `ExitProcess` → `LdrShutdownProcess`，逐个调用已加载 DLL 的 `DllMain(DLL_PROCESS_DETACH)`；`flutter_soloud_plugin` 的静态析构在一个内核对象上 `WaitForSingleObjectEx` **无限等待**——能 signal 它的音频初始化线程已不存在。
5. 此时 Dart VM 已随引擎销毁关闭，v1 的 5 s 保底定时器**没有机会执行**（日志无 `fallback_fired` 与此一致），进程永久驻留。

**为什么只在"启动中关窗"出现**：窗口在首帧后才可见，冒烟脚本看到窗口到发 `WM_CLOSE` 之间只有 0~250 ms，而 SoLoud 初始化耗时 28~411 ms → 两者重叠的概率取决于机器抖动，这正是原始失败时隐时现的原因。空闲关窗（场景 1）时初始化早已完成、deinit 正常执行，因此不触发。

**为什么 CI 现在能复现**：当前 `windows-latest`（Windows Server 2025）**有可用音频端点**，日志里三次运行都出现 `SoLoud initialized`；v1 文档中"CI 是 Session 0 无音频设备、init 必失败"的前提已不成立。

**决定性 A/B 对照**：同一分支、同一关窗时机、`SSB_RUNNER_DISABLE_AUDIO=1`（跳过音频初始化）重跑（run `43466369879`），2 轮 × 5 个延迟共 10 次全部 `exit=0`，其中多次同样在 `phase=booting` 关窗。→ **"启动中关窗"本身无害，只有"关窗时音频引擎处于半初始化状态"才会挂死。**

**上游线索**：插件在 `bindings.cpp` 给全局 `player` 加了 `[[clang::no_destroy]]`，该属性只有 clang 生效；Windows 用 MSVC 构建时被忽略，于是这段静态析构在 DLL 卸载时照常执行。可作为独立 issue 反馈上游，本仓库不能依赖它被修复。

### 2.4 两种机制的边界

| 机制 | 触发条件 | 表现 | 现有防线 | 缺口 |
| --- | --- | --- | --- | --- |
| A 清理卡死 | `deinit` / `flushLogs` 永久不返回 | 窗口消失、进程驻留、VM 仍活 | Dart 有界清理 + 5 s 保底强杀（已验证） | 无（已覆盖） |
| B 半初始化后退出 | 关窗时音频初始化仍在飞 | `WM_DESTROY`、消息循环、引擎析构全部正常，卡在 `ExitProcess` 内部 | 无（Dart 已死） | **需要原生层兜底 + 消除半初始化状态** |

结论：v2 需要同时做两件事——**让进程退出前音频引擎一定处于"从未初始化"或"已 dispose"两种确定状态之一**（根因修复），以及**在原生层加一个不依赖 Dart 的看门狗**（兜底）。

---

## 3 目标与验收标准（v2）

| 指标 | 基线 | 目标 |
| --- | --- | --- |
| 点击关闭（空闲态） | 正常 | ≤ 5 s 进程消失 |
| 点击关闭（音频播放中） | 未知 | ≤ 5 s 进程消失 |
| 点击关闭（启动中，音频初始化在飞） | **进程永久驻留（本次 CI 失败）** | ≤ 5 s 进程消失 |
| 退出清理永久卡死（注入） | v1 已覆盖 | ≤ 5 s 进程消失（Dart 保底） |
| 进程退出阶段卡死（注入/回归） | 无防线 | ≤ 5 s 进程消失（原生看门狗） |
| 退出日志 | `exit requested` | 追加可离线判读的退出 trace：`settled` / `deinit_done` / `answering_exit` / `hard_exit` |
| 启动性能 | 改动前同机 AOT release 的 `first frame visible` / `application ready` 时间戳 | 无回归：差值 ≤ max(20 ms, 5%)，且 `soloud_init` 仍与后续启动步骤重叠 |
| 回归 | — | macOS / Linux 关窗仍正常退出；`flutter analyze`、`flutter test` 全绿 |

核心不变量（写进代码注释与评审 checklist）：

> 只有音频引擎处于 **从未初始化** 或 **已完成 dispose** 时，才允许答复 `AppExitResponse.exit` 走正常进程退出；其余任何状态都必须走强制终止，绝不进入 `ExitProcess` 的 DLL 卸载阶段。

---

## 4 方案

分层与优先级：

| 层 | 内容 | 作用 | 优先级 |
| --- | --- | --- | --- |
| ① Dart | 追踪音频初始化，退出前收敛到确定状态 | 根因修复（消除半初始化退出） | P0 |
| ② 原生 runner | 退出看门狗 → `TerminateProcess` | 兜底（覆盖机制 B 及未来同类风险） | P0 |
| ③ CI | 场景 3 延迟扫描 + 挂死取证 | 可复现、可诊断的回归闸门 | P0 |
| ④ 单测 | 有界清理 / 收敛判定的纯函数用例 | PR 阶段快速反馈 | P1 |
| ⑤ 启动可取消 | 退出后不再派发新的启动步骤 | 缩短退出窗口（减少竞态面积） | P2 |

### 4.1 层①：让音频引擎在进程退出前收敛（P0，根因修复）

当前缺口在 [main_app.dart](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_app/main_app.dart#L120-L200)：`_deinitAudio` 用 `SoLoud.instance.isInitialized` 判断，而这个值在初始化在飞期间为 false，于是"跳过"变成了"半初始化直接退出"。

设计：

1. **新增初始化追踪器**（建议 `lib/audio/audio_init_tracker.dart`，由 `_MainAppState` 持有并传给 `_MainAppCubit`）：
   - `Future<void> start()`：包装现有 `_initAudio`，记录 `never-started / running / completed / failed` 四态；
   - `Future<void> get settled`：在 `running` 时完成于 init 结束（成功或失败），其余状态立即完成；
   - 追踪器只做状态与 future 记录，不改变初始化本身的并发行为。
2. **退出流程改为**（示意，非最终代码）：

   ```dart
   Future<AppExitResponse> _handleExitRequest() async {
     Timer(const Duration(seconds: 5), _forceExit);   // 仅覆盖清理卡死

     // 1) 等在飞的初始化收敛，上限 2 s（正常 28~411 ms）
     final settled = await _audio.settledWithin(const Duration(seconds: 2));
     if (!settled) {
       // 半初始化 + 未收敛：不能答复 exit，否则必定卡在 ExitProcess。
       _exitTrace('hard_exit_init_running');
       await flushLogsWithin(const Duration(milliseconds: 500));
       if (!Process.killPid(pid)) exit(1);
       await Completer<void>().future;              // 不再继续
     }

     // 2) 已收敛：无条件有界 deinit（未初始化时它本身只需一次 isolate spawn）
     final disposed = await _deinitAudioBounded(const Duration(seconds: 2));
     if (!disposed) {
       _exitTrace('hard_exit_deinit_unfinished');
       await flushLogsWithin(const Duration(milliseconds: 500));
       if (!Process.killPid(pid)) exit(1);
       await Completer<void>().future;
     }

     _exitTrace('answering_exit');
     return AppExitResponse.exit;
   }
   ```

   - "从未初始化"（含 `SSB_RUNNER_DISABLE_AUDIO=1`）直接进入 2)，行为与现在的空闲关窗一致（A/B 已证明 10/10 安全）。
   - "初始化失败"同样进入 2)：尝试 deinit，失败或超时则强制终止，避免未知状态进入 `ExitProcess`。
   - 强制终止使用 `Process.killPid`（Windows 即 `TerminateProcess`），跳过 CRT/DLL 卸载；这是 v1 已验证可行的手段（场景 2）。
3. **保留** v1 的有界清理（2 s / 1.5 s）与 Dart 保底（5 s），但把注释与文档中的适用范围改为"只覆盖清理卡死，不覆盖进程退出阶段"。
4. **jitter 预算**：等待收敛 2 s + 清理 3.5 s ≤ 5 s 保底；若两段都用满，保底会先触发，属于预期（保底强杀同样安全）。

**音频收尾硬约束（评审 checklist，与 §3 核心不变量同级，基于 flutter_soloud 5.2.3 源码核对）**：

- 不再用 `SoLoud.isInitialized` 决定"要不要 deinit"：它在**整个初始化期间**恒为 false（`_nativeCallbacksInitialized` 在 `_initialize` 开头就被置 false，[soloud.dart#L632-L634](file:///Users/wafer-li/.pub-cache/hosted/pub.dev/flutter_soloud-5.2.3/lib/src/soloud.dart#L632-L634)），"跳过"等于把半初始化状态直接带进 `ExitProcess`。
- `settled` 之后**无条件**执行 `deinitAsync()`，上限 2 s。"未初始化"不是跳过的理由：该状态下 native `dispose()` 在 `player == nullptr` 处直接返回（[bindings.cpp#L1510-L1511](file:///Users/wafer-li/.pub-cache/hosted/pub.dev/flutter_soloud-5.2.3/src/bindings.cpp#L1510-L1511)），整个调用只是"spawn 一个 isolate + 空跑"，毫秒级。**2 s 是超时上限，不是等待时长**，不存在"无谓的 2 s 等待"。
- **禁止同步 `deinit()`**：它把原生 teardown 跑在调用线程（UI isolate），一旦不返回，5 s 保底 Timer 会一起被冻住，等于复活机制 A。退出路径只用 `deinitAsync()`。
- **禁止"竞速式跳过"**：不得用 `Future.any` / 零延时 `Timer` 与 deinit 赛跑、取"先返回的一方"。竞速败方会让 deinit 变成未 await 的孤儿任务继续在原生侧跑 `dispose()`，而我们已经答复 `exit` 进入 DLL 卸载——正是机制 B 的形状。
- **`failed` 不等于"从未初始化"**：`initEngine()` 先 `make_unique<Player>()` 再 `Player::init(...)`，失败时 native 引擎对象已存在（[bindings.cpp#L1135-L1146](file:///Users/wafer-li/.pub-cache/hosted/pub.dev/flutter_soloud-5.2.3/src/bindings.cpp#L1135-L1146)），因此初始化失败也必须照常有界 deinit。
- 若将来要用数据收紧（跳过某些确定状态），唯一允许的判据是 `SoLoud.instance.getAudioDeviceState()`（公开、同步、非阻塞、init 前也可调用，[soloud.dart#L981-L995](file:///Users/wafer-li/.pub-cache/hosted/pub.dev/flutter_soloud-5.2.3/lib/src/soloud.dart#L981-L995)），且必须**在 `settled` 之后读取**；跳过时写 `deinit_skipped` trace。当前版本**不允许跳过**，理由见 §8.4。

5. **启动侧硬约束（评审 checklist，违反即视为方案未实现）**：

   - 追踪器**不得改变 `soloud_init` 的启动点与并发性**：它必须包住现有 `final audioReady = boot.step('soloud_init', _initAudio)` 这一处（见 [启动性能方案](./startup_performance_design.md) §4.3），不得改成 `await` 串行——那会把 80~165 ms（CI 上 28~411 ms）重新放回启动关键路径。
   - `start()` 只能发生在 `_BootGate._start()`（post-frame）内；`_MainAppState.initState` 里最多只构造对象。首帧前不得新增任何 IO 或平台通道（[首屏白屏方案](./first_frame_white_screen_design.md) 的“首帧前 IO = 0”不变）。
   - `settled` / `settledWithin` **只允许在退出路径调用**；`load()` 的等待顺序保持现状（末尾 `await audioReady`），不得让启动流程额外等一次收敛。
   - 追踪器自身不做轮询、不起定时器、不写盘，只保存状态与一个 future；`settled` 的 future 在 `start()` 时创建一次，而不是每次读取时新建。
   - 层⑤（启动可取消）只在 `boot.step` 之间插入 bool 检查，不得重排 `audioReady` 的启动位置。

   接入形状（示意，仅约束并发关系）：

   ```dart
   // _MainAppCubit.load：位置与现在完全一致，只是把 future 交给追踪器
   final audioReady = _audio.start(() => boot.step('soloud_init', _initAudio));

   await boot.step('prefs_ready', ...);
   // ... 其余步骤不变 ...
   await audioReady;   // 仍在 _Ready 之前
   ```

### 4.2 层②：原生退出看门狗（P0，机制 B 唯一兜底）

新增 `windows/runner/exit_watchdog.{h,cpp}`（并注册到 `windows/runner/CMakeLists.txt`）：

- `Arm()`：在窗口过程收到 `WM_CLOSE` 时调用（只武装一次），内部**懒创建**看守线程并 `SetEvent` 唤醒；
- 看守线程：`CreateThread`（或 detach 的 `std::thread`）在 `Arm()` 内创建一次，随即 `WaitForSingleObject(event, 5000)`；**不在进程启动时创建**，启动期成本为零；
- 超时且进程仍存活 → `TerminateProcess(GetCurrentProcess(), EXIT_SUCCESS)`，跳过 `ExitProcess` 与所有 DLL 卸载；
- 正常退出时进程先结束，看守线程随进程消失，不产生额外开销；
- 另写入 startup trace 两个标记：`watchdog_armed` / `watchdog_fired`，便于失败复盘区分"是保底还是看门狗结束的进程"。

不放在进程启动时的原因：本仓库已有一个启动期原生轮询线程（[startup_trace.cpp](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/startup_trace.cpp#L117-L118) 的 `WatchdogMain`，250 ms 间隔，`dart_ready` 或 60 s 观测窗后自行退出），它不能兼作退出看门狗；与其再加一个全程常驻线程，不如让新线程只在真正关窗时存在。二者成本都极低，但懒创建让"v2 不增加任何启动期线程"成为可断言的事实。

为什么必须做在原生层（而不是 Dart）：

| 事实 | 推论 |
| --- | --- |
| 机制 B 的等待发生在 `ExitProcess` 内部（§2.3 dump） | 此时 Dart VM 已关闭，任何 Dart `Timer` / `Isolate` 都不存在 |
| 引擎析构本身只需 58 ms | 问题不在引擎，不能靠"改 OnDestroy 时序"解决 |
| `TerminateProcess` 不执行 DLL 卸载 | 唯一能绕过该等待的方式 |

macOS / Linux：同一类风险（进程退出阶段的原生析构等待）理论上存在，但本次证据只覆盖 Windows，且 macOS 冒烟当前无音频初始化。v2 首期只做 Windows；macOS runner 的同类看门狗作为独立后续项评估，不在本次变更内。

### 4.3 层③：CI 场景 3 改为确定性扫描 + 挂死取证（P0）

当前 [smoke-test-windows.ps1](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/scripts/smoke-test-windows.ps1) 的场景 3 只采样一次，且失败时没有 dump。v2 变更（取证分支已验证可行，正式化后保留）：

| 变更 | 说明 |
| --- | --- |
| 窗口轮询 250 ms → 25 ms | 让关窗能落在"首帧后 0~250 ms"这个窗口内 |
| 场景 3 改为 `延迟 × 轮次` 扫描 | 默认 `0/20/40/80/160 ms` × 2 轮，覆盖 init 的 28~411 ms 区间；仍保留 10 s 断言 |
| 挂死时先取证再强杀 | `procdump -ma`（缺失时回退 `comsvcs.dll,MiniDump <pid> <file> mini`）+ 线程表 + `cdb -z ... -c "~*kn;q"` 符号化线程栈 |
| 证据补全 | 完整 `latest.log`（不再是 40 行 tail）、`boot_<pid>.log`、`exit_<pid>.log` |
| 时长预算 | 10 次启动约 60~90 s，仅在 `package-windows` 成功后运行 |

与取证分支的差异（正式化时收敛）：

- 保留：dump/线程栈/完整日志/退出 trace、场景 3 的扫描结构；
- 删除：workflow 上的 `SSB_SMOKE_ONLY_STARTUP_CLOSE` / `SSB_RUNNER_DISABLE_AUDIO` / `ROUNDS` 覆盖（A/B 是取证手段，不进入常规 CI）；
- 退出 trace（Dart 同步写文件）与原生 `wm_close / destroy_begin / destroy_end / loop_exit` 标记**保留为常设诊断**：只在退出路径各写一行，成本可忽略，但本次正是它们把问题从"引擎析构"纠正到"ExitProcess"。

### 4.4 层④：Dart 单测（P1，保留 v1 并补充）

新增/补充 `test/ui/main_app/exit_flow_test.dart` 与 `test/audio/audio_init_tracker_test.dart`：

| 用例 | 断言 |
| --- | --- |
| 有界清理：两步正常完成 | 顺序 audio → logs，正常返回 |
| 有界清理：`deinitAudio` 永久挂起 | 超时后继续 `flushLogs`，不抛出 |
| 有界清理：任一步抛错 | `onError` 收到对应 step，后续仍执行 |
| 追踪器：未启动 | `settled` 立即完成，状态为 never-started |
| 追踪器：在飞 | `settledWithin(0)` 返回 false；init 完成后返回 true |
| 追踪器：init 失败 | 计入 `failed`，`settled` 正常完成（失败不算挂起） |

### 4.5 层⑤：启动可取消（P2）

退出请求到达后置位 abort 标志，`_MainAppCubit.load` 在每个 `boot.step` 之间检查并停止后续派发（db / dxcc / callsign / worker_manager）。目的不是修 bug，而是缩小"退出时仍有新工作在启动"的面积，降低后续出现同类竞态的概率。

---

## 5 变更清单

| 文件 | 变更 | 状态 |
| --- | --- | --- |
| `lib/ui/main_app/main_app.dart` | v1：`_handleExitRequest` + 有界清理 + 保底强杀 + 测试钩子；v2：接入初始化追踪器、收敛判定、强制终止分支；`_deinitAudio` 从"按 `isInitialized` 跳过"改为无条件有界 `deinitAsync()` | v1 已落地 / v2 待实现 |
| `lib/ui/main_app/exit_flow.dart` | `runBoundedExitCleanup` | 已落地 |
| `lib/audio/audio_init_tracker.dart` | 新增：初始化四态 + `settled` / `settledWithin`；接入方式受 §4.1 第 5 条约束（不改启动并发） | 待实现 |
| `lib/logging/boot_trace.dart` | `lastStep`（退出 trace 记录当前启动步骤） | 已落地（取证分支） |
| `windows/runner/exit_watchdog.{h,cpp}` + `CMakeLists.txt` | 新增：退出看门狗（`Arm()` 内懒创建线程）+ `watchdog_armed/fired` 标记 | 待实现 |
| `windows/runner/win32_window.cpp` | `WM_CLOSE` / `destroy_begin` / `destroy_end` 打点；接入 `Arm()` | 打点已落地（取证分支）/ `Arm()` 待实现 |
| `windows/runner/main.cpp` | `loop_exit` 打点 | 已落地（取证分支） |
| `windows/runner/startup_trace.{h,cpp}` | 导出 `ssb_trace_mark` | 已落地（取证分支） |
| `.github/scripts/smoke-test-windows.ps1` | 25 ms 轮询、场景 3 延迟扫描、`Save-HangDump`、退出 trace 输出 | 已落地（取证分支） |
| `.github/scripts/smoke-evidence.ps1` | 挂死 dump / 线程表 / cdb 栈、完整日志与 exit trace | 已落地（取证分支） |
| `.github/workflows/ci.yml` | 取证分支上的临时 env 需在正式化时移除 | 待收敛 |
| `test/ui/main_app/exit_flow_test.dart`、`test/audio/audio_init_tracker_test.dart` | 有界清理 + 追踪器用例 | 部分待实现 |
| `docs/design/desktop_exit_design.md` | 本文档 | 本次更新 |

---

## 6 风险与对策

| 风险 | 对策 |
| --- | --- |
| 等待初始化收敛拖慢退出 | 上限 2 s，正常 28~411 ms；超时直接强制终止，不阻塞用户 |
| 追踪器接入把启动变成串行 | §4.1 第 5 条硬约束（位置与并发性不变）；用 `BOOT` 时间戳与原生 `shown_us` 对比验收 |
| 用"未初始化 / init 失败"等启发式跳过 deinit | 在 native 状态未知的情况下进入 `ExitProcess`，可能复发机制 B | §4.1 音频收尾硬约束：一律有界 `deinitAsync()`；任何跳过都必须有单独版本的数据支撑 |
| `Process.killPid` 跳过所有 CRT/DLL 卸载 | 只作为"确定状态无法达到"时的兜底；此前已 flush 日志，且进程本来就要结束（v1 已接受同一取舍） |
| 原生看门狗误杀正常退出 | 只从 `WM_CLOSE` 起算，且进程先结束就不会触发；超时 5 s 与 Dart 保底一致 |
| 看门狗本身泄漏/多实例 | `Arm()` 只武装一次（atomic + 事件），线程在 `Arm()` 内懒创建一次，启动期不创建 |
| 场景 3 扫描拉长 CI | 10 次启动约 60~90 s；只在 Windows 打包成功后运行 |
| 退出 trace 写盘影响退出时延 | 每次仅 3~5 行同步 append，毫秒级；任何异常都被吞掉，不影响退出 |
| 取证钩子进入生产包 | `SSB_RUNNER_TEST_EXIT_HANG` 等保持既有约定（默认零影响）；场景扫描参数只在 CI 脚本内 |
| 只修 Windows，macOS/Linux 同风险未覆盖 | 明确记录为后续项；当前证据只覆盖 Windows，macOS 冒烟无音频初始化 |

---

## 7 验收方式

1. `flutter analyze` / `flutter test` 全绿（含有界清理与追踪器新用例）；
2. `gh workflow run ci.yml -f platform=windows`：`package-windows` + `smoke-test-windows`（含场景 3 的 10 次扫描）全绿；
3. 启动性能无回归（人工比对一次，不进 CI 门禁）：
   - 同一台机器、同样 AOT release 构建，对比改动前后 `first frame visible` 与 `application ready` 两条日志的 `sinceProcessMs`，差值须 ≤ max(20 ms, 5%)；
   - `BOOT` 日志里仍能看到 `soloud_init start` 与后续 `prefs_ready` 交错（而不是音频 `ok` 之后才开始下一个步骤）；
   - 原生 `boot_<pid>.log` 的 `shown_us` / `first_frame_us` 与改动前同一量级；v2 不新增启动期线程（§4.2）。
4. 反向验证（必须做一次）：在 `ci/*` 上临时去掉 4.1 的收敛等待，确认场景 3 仍能复现挂死并抓到 dump —— 证明 CI 防线没有失效；
5. 手工回归（Windows 真机，有真实音频设备）：
   - 窗口出现后立即关窗（0 / 100 / 300 ms 三个时点各 5 次），任务管理器 5 s 内无残留；
   - 空闲关窗、音频播放中关窗行为不变；
   - 正常关窗后 `latest.log` 含 `exit requested`，`exit_<pid>.log` 最后一行是 `answering_exit`；
   - 故障路径（注入）下 `exit_<pid>.log` 出现 `hard_exit_*` 或 startup trace 出现 `watchdog_fired`；
6. macOS / Linux 关窗回归通过。

---

## 8 附录：本次取证记录

### 8.1 复现方式（取证分支 `ci/windows-exit-hang-forensics`）

```bash
gh workflow run ci.yml --ref ci/windows-exit-hang-forensics -f platform=windows
```

- 首次运行（`43463159111`）第 1 次尝试即挂死，无需重试；
- 触发条件：窗口可见后 0 ms 发 `WM_CLOSE`（脚本轮询 25 ms），此时 `soloud_init` 刚起步。

### 8.2 关键产物

| 产物 | 内容 |
| --- | --- |
| `hang_<pid>.dmp` | 最小转储（约 56 KB），1 个线程，栈见 §2.3 |
| `hang_<pid>-threads.txt` | 线程表：单线程 `Wait / UserRequest` |
| `hang_<pid>-stacks.txt` | `cdb -z ... -c "~*kn;q"` 的输出 |
| `boot_<pid>.log` | `wm_close → destroy_begin → destroy_end → loop_exit` |
| `exit_<pid>.log` | `enter → logged → geometry_flushed → cleanup_done`，无 `fallback_fired` |
| `latest.log` | 停在 `exit requested`，无 `BOOT 06 soloud_init ok` |

### 8.3 A/B 对照

| 运行 | 音频 | 结果 |
| --- | --- | --- |
| `43463159111` | 正常初始化 | 第 1 次尝试即挂死（10 s 后仍在） |
| `43466369879` | `SSB_RUNNER_DISABLE_AUDIO=1` | 2 轮 × 5 个延迟全部 `exit=0` |

### 8.4 尚未定论的点

- `flutter_soloud_plugin` 静态析构等待的具体内核对象未能符号化（插件无 PDB，`cdb` 只能显示最近导出符号）。这不影响修复方向：无论等待的是线程、事件还是条件变量，能 signal 它的初始化线程已不存在，且该等待发生在 `ExitProcess` 内部。
- **正因为上一条未定论，任何"设备状态为 uninitialized / init 已失败"都不足以证明 `ExitProcess` 安全**：无法排除 native 侧仍有需要 teardown 的对象，也就无法证明跳过 deinit 后不会再次卡在 DLL 卸载。这就是 §4.1 音频收尾硬约束拒绝一切"跳过 deinit"启发式的直接理由；如果将来要放开，必须先把这个等待对象符号化。
- 上游 `[[clang::no_destroy]]` 在 MSVC 下失效属于推测（与 dump 中的 DLL 卸载路径一致），建议单独向上游反馈验证。
