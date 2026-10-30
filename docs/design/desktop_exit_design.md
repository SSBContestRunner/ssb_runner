# SSB Runner 桌面端退出流程技术方案（关闭窗口后进程残留）

> 状态：待评审
> 适用范围：桌面端退出路径（Windows / macOS / Linux），重点是 Windows
> 不在范围：退出期间的业务数据落库策略、崩溃上报流程

---

## 1. 背景与现场证据

用户反馈：点击窗口关闭按钮后，窗口消失但进程仍驻留在任务管理器（CPU 0%，多次关闭会累积多个僵尸进程，只能"结束任务"清掉）。

排查结论：

| 证据 | 结论 |
| --- | --- |
| 本地 macOS（Debug / Release）实测关闭最后一个窗口，进程 1 s 内退出 | macOS 退出链路正常，问题在 Windows |
| 2025-08 曾修过同类问题（`fix: windows soloud block background process` / `... hang`），手段是 Dart 侧 `AppLifecycleListener.onExitRequested` 里调 `SoLoud.instance.deinit()` | 现有兜底不完整，用户侧仍能复现 |
| 上游 flutter_soloud issue #413 记录完全相同的症状（Windows 关窗后进程留在后台、强杀无残留） | 属桌面端原生音频析构与 Windows 消息循环的已知时序问题 |
| 用户诊断包显示 Windows 10、便携目录运行；启动失败/正常使用后关窗都会出现 | 与业务状态无关，只与退出路径有关 |

## 2. 根因分析

### 2.1 Windows 关闭时序

```
点击 X → WM_CLOSE
       → 引擎拦截（framework 已监听 flutter/platform）
       → 向 Dart 发送 System.requestAppExit
       → Dart 回调结束后答复 exit
       → 引擎重新 PostMessage(WM_CLOSE) → DefWindowProc 销毁窗口
       → WM_DESTROY → Win32Window::Destroy() → FlutterWindow::OnDestroy()
       → flutter_controller_ = nullptr（**同步**析构 FlutterEngine / Dart VM）
       → 之后才 PostQuitMessage(0) → 消息循环退出 → 进程结束
```

关键代码：[win32_window.cpp#L182-L187](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/win32_window.cpp#L182-L187)（`Destroy()` 在 `PostQuitMessage(0)` 之前）、[flutter_window.cpp#L42-L47](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/flutter_window.cpp#L42-L47)（`OnDestroy` 同步销毁引擎）。

**窗口销毁发生在引擎析构之前**。只要析构过程中任意一步阻塞（原生音频设备线程、退出瞬间仍在跑的 `Isolate.run` 音频启停任务等），窗口已经消失，但 `WM_QUIT` 永远不会投递，`GetMessage` 永久阻塞——任务管理器里就留下一个空闲进程。这就是用户看到的"进程残留"。

### 2.2 Dart 侧当前的三个放大因素

[main_app.dart#L41-L47](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/lib/ui/main_app/main_app.dart#L41-L47)：

```dart
_listener = AppLifecycleListener(
  onExitRequested: () async {
    SoLoud.instance.deinit();   // 同步、阻塞 UI isolate
    await flushLogs();          // 无超时
    return AppExitResponse.exit;
  },
);
```

| 问题 | 后果 |
| --- | --- |
| `deinit()` 是同步 native 调用 | flutter_soloud 5.x 明确说明：若与 `init()` 的设备启动重叠，会等 `init_deinit_mutex`；退出瞬间若正好有 idle-timeout 的设备启停 worker，可能长时间/永久阻塞 UI isolate |
| 清理没有任何超时 | 清理卡住 → 永远不会答复 `exit` → Dart 侧没有第二道防线 |
| UI isolate 被阻塞 | 任何基于 Dart `Timer` 的兜底都失效（定时器本身就依赖 UI isolate 事件循环） |
| `deinit()` 抛错会中断后续 `flushLogs()` | 日志丢失，后续无法复盘 |

### 2.3 为什么原生 runner 修改不作为主方案

曾在首版方案中考虑修改 `FlutterWindow::OnDestroy`（release 引擎所有权、跳过同步析构）。放弃理由：

- runner 是 Flutter 模板生成后入库的代码，`flutter create` 升级模板时容易被覆盖/漂移；
- 该改动只在 Windows 生效，macOS/Linux 仍需另一套处理；
- Dart 侧"有界清理 + 保底强制退出"在任何平台上都能给出同等保证，且不侵入模板。

## 3. 目标与验收标准

| 指标 | 基线 | 目标 |
| --- | --- | --- |
| 点击关闭（空闲态） | 进程残留（用户侧） | ≤ 5 s 进程消失 |
| 点击关闭（音频播放中） | 未知/可复现残留 | ≤ 5 s 进程消失 |
| 点击关闭（启动中） | 未知 | ≤ 5 s 进程消失 |
| 退出清理永久卡死（注入） | 进程永不退出 | ≤ 5 s 进程消失（保底） |
| 退出日志 | 无退出记录 | 正常退出时 `latest.log` 含 `exit requested` |
| 回归 | — | macOS / Linux 关窗仍正常退出；`flutter analyze`、`flutter test` 全绿 |

## 4. 方案总览（三层）

| 层 | 内容 | 作用 | 平台 |
| --- | --- | --- | --- |
| ① 代码修复 | 退出清理有界化 + 保底强制退出 | 真正修复与保证"进程绝不残留" | 全桌面端 |
| ② Windows 冒烟 CI | 用真实 `WM_CLOSE` 关窗并断言进程退出（3 个场景） | 端到端防回归闸门 | Windows CI |
| ③ Dart 单测 | 对"有界清理"纯函数做超时/异常用例 | PR 阶段快速反馈 | 任意平台 |

### 4.1 层 ①：退出清理有界化 + 保底强制退出

时间预算（必须能算清楚，否则保底会抢跑）：

| 步骤 | 上限 |
| --- | --- |
| `SoLoud.deinitAsync()` | 2.0 s |
| `flushLogs()` | 1.5 s |
| 合计最坏 | 3.5 s |
| 保底 `exit(0)` 定时器 | **5.0 s**（大于正常最坏路径，只在异常路径触发） |

`main_app.dart`：

```dart
_listener = AppLifecycleListener(onExitRequested: _handleExitRequest);

/// 桌面端「关闭窗口后进程残留」的最后一道保险。
///
/// Windows runner 在 WM_DESTROY 里同步析构 FlutterEngine，之后才
/// PostQuitMessage（windows/runner/win32_window.cpp:182-187）。析构中任何
/// 一步卡住（如原生音频线程），窗口已消失但消息循环不会退出，进程残留。
/// 因此退出流程必须有硬上限：无论清理是否完成，进程都必须结束。
Future<AppExitResponse> _handleExitRequest() async {
  // UI isolate 必须保持可响应，否则这个兜底定时器也不会触发。
  Timer(const Duration(seconds: 5), _forceExit);

  // 仅 CI 使用：模拟退出清理永久卡死，验证“进程绝不残留”的保底逻辑。
  if (Platform.environment['SSB_RUNNER_TEST_EXIT_HANG'] == '1') {
    await Completer<void>().future;
  }

  log.info('exit requested', tag: 'exit');

  await runBoundedExitCleanup(
    deinitAudio: _deinitAudio,
    flushLogs: flushLogs,
    onError: (step, error, stackTrace) =>
        log.warn('$step failed', tag: 'exit', error: error, stackTrace: stackTrace),
  );

  return AppExitResponse.exit;
}

Future<void> _deinitAudio() async {
  // deinit() 同步阻塞 UI isolate；改用 deinitAsync（内部 Isolate.run）。
  if (SoLoud.instance.isInitialized) {
    await SoLoud.instance.deinitAsync();
  }
}

/// 保底：直接终止进程，不走 exit(0) 的 CRT/DLL 析构路径。
void _forceExit() {
  log.warn('exit fallback fired', tag: 'exit');
  if (Process.killPid(pid)) {
    return;
  }
  exit(0);
}
```

新增 `lib/ui/main_app/exit_flow.dart`（层 ③ 的可测接缝，只做一件小事）：

```dart
typedef AsyncAction = Future<void> Function();
typedef ExitCleanupErrorHandler = void Function(
  String step,
  Object error,
  StackTrace stackTrace,
);

/// 逐步执行退出清理：每步要么完成、要么超时、要么被记录后跳过；永不抛出。
Future<void> runBoundedExitCleanup({
  required AsyncAction deinitAudio,
  required AsyncAction flushLogs,
  Duration deinitTimeout = const Duration(seconds: 2),
  Duration flushTimeout = const Duration(milliseconds: 1500),
  ExitCleanupErrorHandler? onError,
}) async {
  Future<void> run(String step, AsyncAction action, Duration timeout) async {
    try {
      await action().timeout(timeout);
    } catch (error, stackTrace) {
      onError?.call(step, error, stackTrace);
    }
  }

  await run('audio deinit', deinitAudio, deinitTimeout);
  await run('log flush', flushLogs, flushTimeout);
}
```

说明：

- 用 `deinitAsync()` 而不是 `deinit()`：原生拆解放到 worker isolate，UI isolate 始终可运行，保底定时器才有机会触发；
- 每步 try/catch + `Future.timeout`：任何一步失败/卡死都不会阻断下一步，也不会阻断答复 `exit`；
- 保底只在异常路径触发（正常路径 3.5 s 内必然已经退出进程，定时器随进程一起消失）；
- `deinitAsync` 超时后被放弃的 worker isolate 由保底强杀直接终止，不产生额外进程；
- 保底不用 `exit(0)` 而是 `Process.killPid`（Windows 即 `TerminateProcess`）：首次 CI 实测发现注入卡死后 `exit(0)` 仍未退出——`exit()` 会执行 CRT/DLL 析构，而卡住的插件线程正在这些析构里，强杀跳过全部析构才能保证进程结束；保底触发时先写 `exit fallback fired`（warn 级立即落盘），便于冒烟失败时定位。

### 4.2 层 ②：Windows 冒烟 CI

当前 `fix/v0.2.0` 的 CI 只有 Debian 冒烟，**没有** Windows 冒烟。新增 `.github/scripts/smoke-test-windows.ps1`：

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Fail([string]$m) { Write-Host "::error::$m"; exit 1 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
}
"@

# 取进程自己的顶层可见窗口；MainWindowHandle 在部分会话下为 0，用 EnumWindows 兜底。
function Get-TopWindow([int]$TargetId) {
  $script:found = [IntPtr]::Zero
  $cb = [Win32+EnumProc]{
    param($h, $l)
    [uint32]$pid = 0
    [void][Win32]::GetWindowThreadProcessId($h, [ref]$pid)
    if ($pid -eq $TargetId -and [Win32]::GetParent($h) -eq [IntPtr]::Zero -and [Win32]::IsWindowVisible($h)) {
      $script:found = $h; return $false
    }
    return $true
  }
  [void][Win32]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:found
}

# 关键断言：PostMessage(WM_CLOSE) 等价于用户点 X，之后进程必须在限定时间内消失。
function Close-WindowAndWaitForExit($proc, [int]$Seconds = 10) {
  $deadline = (Get-Date).AddSeconds(20)
  do {
    $hwnd = Get-TopWindow $proc.Id
    if ($hwnd -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  if ($hwnd -eq [IntPtr]::Zero) { Fail "pid $($proc.Id) 始终没有顶层窗口" }

  [void][Win32]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  if (-not $proc.WaitForExit($Seconds * 1000)) {
    Fail "关闭窗口后 $Seconds s 进程仍在（残留进程：$($proc.Id)）"
  }
  Write-Host "  进程已退出，exit code=$($proc.ExitCode)"
}
```

脚本其余部分：从 `artifacts/` 递归找 `*.zip` → `Expand-Archive` 到 `$env:RUNNER_TEMP\ssb-smoke` → 找 `ssb_runner.exe`；日志路径 `%APPDATA%\com.ssbrunner\ssb_runner\log\latest.log`，回退 `<解压目录>\log\latest.log`。

三个场景：

| 场景 | 做法 | 断言 |
| --- | --- | --- |
| 1. 正常关窗 | 启动 → 等 12 s（首帧已完成、`setOpacity(1)` 已恢复）→ WM_CLOSE | 10 s 内退出；日志含 `exit requested` |
| 2. 清理卡死（保底） | 带 `SSB_RUNNER_TEST_EXIT_HANG=1` 启动 → WM_CLOSE | 10 s 内退出（5 s 保底强杀生效） |
| 3. 启动中关窗 | 启动 → 出现窗口后立即 WM_CLOSE | 10 s 内退出 |

CI job（并加入 `release.needs`，与 Debian 冒烟同级）：

```yaml
  smoke-test-windows:
    name: Smoke test (Windows)
    needs: package-windows
    runs-on: windows-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v7
      - name: Download Windows artifact
        uses: actions/download-artifact@v8
        with:
          name: ssb-runner-windows
          path: artifacts
      - name: Run Windows smoke test
        shell: pwsh
        run: ./.github/scripts/smoke-test-windows.ps1
```

```yaml
  release:
    needs:
      - package-linux
      - package-windows
      - package-macos
      - smoke-test-debian
      - smoke-test-windows
      - smoke-test-macos
```

**能力边界（必须写清）**：GitHub `windows-latest` 运行在 Session 0，无音频设备，`SoLoud.init` 会失败并被启动流程吞掉（因此还能顺带覆盖"音频未初始化时退出"）。CI 无法复现"音频线程导致原生析构卡死"的具体触发条件；场景 2 通过环境变量注入可确定的卡死，验证的是**保底防线**是否有效，而不是音频驱动本身。

### 4.3 macOS / Linux 关窗回归

macOS 与容器内的 Linux 都无法从外部发关窗请求（macOS 需要辅助功能/自动化授权，Debian 容器没有窗口管理器），因此改由 App 自己关窗：测试钩子 `SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER=<秒>` 到点调用 `windowManager.close()`——macOS 是 `[NSWindow performClose]`、Linux 是 `gtk_window_close`，都和点关闭按钮同一条原生路径。

- 新增 `.github/scripts/smoke-test-macos.sh`：挂载 dmg → 拷贝 .app → 两个场景 → 断言 40 s 内进程消失；新增 `smoke-test-macos` job 并加入 `release.needs`；
- `smoke-test-debian.sh` 增加第 (4) 步：带关窗钩子起 App，`timeout 40` 返回 124（仍在运行）即失败。

| 场景 | 做法 | 断言 |
| --- | --- | --- |
| macOS 正常关窗 | 12 s 自动关窗 | 40 s 内退出，退出码 0 |
| macOS 清理卡死 | 12 s 关窗 + `SSB_RUNNER_TEST_EXIT_HANG=1` | 40 s 内退出（5 s 保底强杀，退出码 143） |
| Debian 正常关窗 | `xvfb-run` 下 12 s 自动关窗 | `timeout` 未返回 124 |

**能力边界**：CI 的 macOS runner 与 Debian 容器都没有可用音频设备，两处都用 `SSB_RUNNER_DISABLE_AUDIO=1` 跳过音频初始化；"音频播放中关窗"仍需真机验收。

### 4.4 层 ③：Dart 单测

新增 `test/ui/main_app/exit_flow_test.dart`，针对 `runBoundedExitCleanup`：

| 用例 | 断言 |
| --- | --- |
| 两步都正常完成 | 顺序为 audio → logs，正常返回 |
| `deinitAudio` 永久挂起 | 在 `deinitTimeout` 后继续执行 `flushLogs`（用 50 ms 注入验证） |
| `flushLogs` 永久挂起 | 在 `flushTimeout` 后返回，不抛出 |
| 任一步抛错 | `onError` 收到对应 step，后续步骤仍执行 |

该层只验证清理的边界行为，验证不了原生析构，因此是**补充**而非替代层 ②。

## 5. 变更清单

| 文件 | 变更 |
| --- | --- |
| `lib/ui/main_app/main_app.dart` | 退出处理改为 `_handleExitRequest`（保底强杀、`deinitAsync`、有界清理）；新增 CI 钩子 `_scheduleTestWindowClose`（`SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER`）；补 `dart:async` import |
| `lib/ui/main_app/exit_flow.dart` | 新增 `runBoundedExitCleanup`（可测接缝） |
| `test/ui/main_app/exit_flow_test.dart` | 新增 4 个超时/异常用例 |
| `.github/scripts/smoke-test-windows.ps1` | 新增：zip 解压 + 三场景关窗断言 |
| `.github/scripts/smoke-test-macos.sh` | 新增：dmg 挂载 + 两场景关窗断言 |
| `.github/scripts/smoke-test-debian.sh` | 增加第 (4) 步：Xvfb 下关窗后进程必须退出 |
| `.github/workflows/ci.yml` | 新增 `smoke-test-windows` / `smoke-test-macos` job；`release.needs` 增加两者 |
| `docs/design/desktop_exit_design.md` | 本文档 |

## 6. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 保底强杀跳过引擎/插件的收尾析构 | 在此之前已完成音频释放与日志落盘；进程退出本就要终止这些线程，可接受 |
| 保底定时器误杀正常退出 | 5 s > 正常最坏 3.5 s；正常路径进程早已结束，定时器不会触发 |
| 注入钩子进入生产包 | 仅在 `SSB_RUNNER_TEST_EXIT_HANG=1` 时生效，默认路径零开销；如需更严格可只在 CI 构建时启用 |
| Windows 冒烟偶发（窗口句柄找不到） | 20 s 轮询 + `EnumWindows` 兜底；失败信息带 PID，便于判断是环境问题还是回归 |
| CI 时长增加 | 三个场景约 1–2 分钟；只在 `package-windows` 成功时运行，不影响 PR（PR 不构建 Windows） |

## 7. 验收方式

1. `flutter analyze` / `flutter test` 通过（含层 ③ 新用例）；
2. `gh workflow run ci.yml -f platform=windows`：`package-windows` + `smoke-test-windows` 全绿；
3. 手工回归：Windows 真机在「空闲 / 音频播放中 / 启动中」三种状态关窗，任务管理器 5 s 内无残留；macOS / Linux 关窗仍正常退出；
4. 正常关窗后 `latest.log` 出现 `exit requested`。
