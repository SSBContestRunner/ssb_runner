# Windows 10 RTM（Build 10240）启动崩溃根因分析：cnativeapi.dll 加载失败

> 调研时间：2026-11-15
> 关联 Issue：[SSBContestRunner/ssb_runner#71](https://github.com/SSBContestRunner/ssb_runner/issues/71)（`[crash] ArgumentError · 0.3.0+300003 · windows`）
> 调研对象：`v0.3.0-alpha03`（`0.3.0+300003`）Windows zip 产物 + 当前 `main` 源码
> 实施状态：**决策已定并实施（2026-11-15）：采用 P0，不实施 P1。** 各条目落地位置见 §5.1。
> 结论置信度：根因来自发布产物 DLL 导入表实测 + 上游源码 + 微软 API 文档三方互证；旧系统上的行为需在 10240 虚拟机复验（见 §6）。

---

## 0. 结论（TL;DR）

`window_manager 0.6.0 → nativeapi/cnativeapi 0.5.10` 在 Windows 侧**静态导入**了 `user32!GetDpiForWindow`，该 API 自 **Windows 10 1607（Build 14393）** 才存在。报告者机器是 **Windows 10 RTM，Build 10240**，其 `user32.dll` 没有这个导出，于是 `LoadLibrary("cnativeapi.dll")` 直接以 `ERROR_PROC_NOT_FOUND (127)` 失败，整个原生库一次都加载不进来。此后 Dart 侧任何 `window_manager` 调用（首个是 `WindowManager.instance.getCurrent()`）都抛 `ArgumentError`。

应用侧放大了这个故障：`resolveAppWindow()` 没有容错，且 `_revealWindow()` 把它放在 `try` 之外、`WindowGeometryController.attach()` 又位于启动主流程中，于是“可选能力不可用”被升级为“启动 FATAL + 崩溃上报”。窗口解析本应可降级——同一项目里隐藏窗口、可见性监听两条链路都已经做了 try/catch，只有几何链路漏了。

**影响面**：仅 Windows < 10.0.14393（10240 / 10586）。1607 及以上完全正常。

**下限复核（§8）**：1607 恰好是 cnativeapi 决定的；逐个核对引擎、sqlite3、flutter_soloud、VC++ 运行库、插件与本项目 runner 的导入表后，**没有任何组件要求高于 1607**（最高只到 Windows 8），所以不需要再抬高下限。

---

## 1. 崩溃现象

来自 Issue #71 的关键字段：

| 字段 | 值 |
|---|---|
| Platform / Version | `windows` / `0.3.0+300003` |
| Error type | `ArgumentError` |
| OS | `windows "Windows 10 Home China" 10.0 (Build 10240)` |
| 运行方式 | 便携 zip，`E:\新建文件夹\ssb_runner-0.3.0+300003-windows\...` |
| exe 目录 DLL 数 | 15（其中包含 `cnativeapi.dll`） |

错误正文（节选）：

```text
Invalid argument(s): Couldn't resolve native function 'native_window_manager_get_current'
in 'package:cnativeapi/cnativeapi.dart' :
Failed to load dynamic library 'cnativeapi.dll':
Failed to load dynamic library 'cnativeapi.dll':
The specified procedure could not be found. (error code: 127).
```

两条调用栈：

1. `WindowManager.getCurrent → resolveAppWindow (window_geometry.dart:54) → _MainAppState._revealWindow (main_app.dart:177) → initState 的 post-frame 回调` —— 记为 `Uncaught asynchronous error`；
2. `resolveAppWindow → WindowGeometryController.attach (window_geometry.dart:110) → _MainAppCubit.load (main_app.dart:440)` —— 记为 `FATAL startup failed`，随后界面进入 `_Failed`。

> 注：栈里的行号来自发布版 `300003`，当前源码对应 `window_geometry.dart:54/110`、`main_app.dart:283`、`main_app.dart:592`。

---

## 2. 证据链

### 2.1 错误码语义：是“加载失败”，不是“符号缺失”

Dart FFI 的 `@Native` 解析分两步：先 `DynamicLibrary.open`，再 `lookup`。

| 阶段 | 失败时的报错 | Windows 错误码 |
|---|---|---|
| 加载 DLL | `Failed to load dynamic library 'x.dll': ...` | 126 依赖缺失 / 127 依赖缺少导出过程 / 193 位数不符 / 5 访问被拒 |
| 查找符号 | `Failed to lookup symbol '...'` | — |

报文是 `Failed to load dynamic library 'cnativeapi.dll' ... The specified procedure could not be found (error code: 127)`，即 **DLL 没有加载成功**；127 对应 `ERROR_PROC_NOT_FOUND`，含义是“某个已找到的依赖 DLL 中不存在所需的导出函数”。这排除了以下猜测：

- 导出名/版本错配（那会是 `Failed to lookup symbol`；且实测该 DLL 确实包含 `native_window_manager_get_current` 字符串）；
- 缺文件（126）或 32/64 位不符（193）；
- 被杀软/网络标记阻止（通常 5 / 193）。

### 2.2 发布产物 `cnativeapi.dll` 的导入表实测

对 `v0.3.0-alpha03` 的 `ssb_runner-0.3.0+300003-windows.zip` 解包后，解析 `cnativeapi.dll` 的 PE 导入表，`USER32.dll` 段落中包含：

```text
USER32.dll: GetDpiForWindow, GetGUIThreadInfo, GetMonitorInfoA, ...（其余均为 Vista/Win7 时代 API）
```

逐项核对后，**整个导入表中只有 `GetDpiForWindow` 一项要求 Windows 10 1607+**；其余可疑项都在 10240 上可用：

| 导入 | 最低系统 | 10240 是否可用 |
|---|---|---|
| `GetDpiForWindow` | Windows 10 1607 | ❌ |
| `GetCurrentPackageFamilyName` | Windows 8 | ✅ |
| `QueryDisplayConfig` / `DisplayConfigGetDeviceInfo` / `GetDisplayConfigBufferSizes` | Windows 7 | ✅ |
| `Shell_NotifyIconGetRect` / `SHAppBarMessage` / `SHCreateDataObject` | Windows 7 / Vista | ✅ |
| `ChangeWindowMessageFilterEx` | Windows 7 | ✅ |
| `AddClipboardFormatListener` / `SetWindowDisplayAffinity` | Vista / Windows 7 | ✅ |
| `DwmSetWindowAttribute` / `DwmGetWindowAttribute` 等 4 项 | Vista | ✅ |

### 2.3 上游源码：两处直接调用，且没有延迟加载

`cnativeapi 0.5.10`（`~/.pub-cache/hosted/pub.dev/cnativeapi-0.5.10`）：

- `cxx_impl/src/platform/windows/window_windows.cpp:2993`：`Window::Dock` 中 `width * GetDpiForWindow(hwnd) / 96.0 >= ...`；
- `cxx_impl/src/platform/windows/window_docking_windows.h:114`：`PositionDock` 中 `dock.width * GetDpiForWindow(hwnd) / 96.0`（该头文件被 `window_windows.cpp:28` 包含）；
- `hook/build.dart` 的 Windows 编译选项只有 `/EHsc`、`/utf-8` 与链接库列表，**没有 `/DELAYLOAD:user32.dll`**，因此上述调用必然落在 DLL 的静态导入表（IAT）里，`LoadLibrary` 时就会被解析。
- 同一包里已有正确的动态写法：`cxx_impl/src/platform/windows/dpi_utils_windows.cpp:34-72` 的 `GetScaleFactorForWindow()` 先用 `GetProcAddress` 取 `GetDpiForWindow`，失败则回退 `GetDpiForMonitor`，再回退 `GetDeviceCaps`。**只是 `Dock` 两处没走它。**
- 版本比对：`cnativeapi 0.6.1` 仍是同样的直接调用（`window_windows.cpp:2998`、`window_docking_windows.h:114`）。**升级依赖无法修复此问题。**
- `message_dialog_winui3_windows.cpp:86` 也直接调用，但 build hook 已显式排除 `*_winui3_windows.cpp`，不参与编译。

### 2.4 微软 API 文档

`GetDpiForWindow`（winuser.h）：

| 要求 | 值 |
|---|---|
| 最低支持客户端 | Windows 10, version 1607（Build 14393）[桌面应用] |
| 最低支持服务器 | Windows Server 2016 |

即 Build 10240 的 `user32.dll` 从未导出过该函数（该 API 未回移到 1507/1511 分支）。

### 2.5 排除项：其余原生组件都能在 10240 上工作

| 组件 | 导入表检查结果 | 日志证据 |
|---|---|---|
| `ssb_runner.exe` | 无 1607+ 静态导入；`AdjustWindowRectExForDpi` 是用 `GetProcAddress` 动态取、失败回退 `AdjustWindowRectEx`（`windows/runner/win32_window.cpp:145-157`） | 已创建窗口并出首帧 |
| `flutter_windows.dll` | 检查 `GetDpiForWindow` / `SetProcessDpiAwarenessContext` / `GetSystemMetricsForDpi` / `AdjustWindowRectExForDpi` / `EnableNonClientDpiScaling` / `SetThreadDescription` / `GetSystemTimePreciseAsFileTime` 均无静态导入 | 引擎渲染出首帧 |
| `flutter_soloud_plugin.dll`、`sqlite3.dll`、`file_selector_windows_plugin.dll` 等 | 未发现异常 | `BOOT 06 soloud_init ok`、日志目录与 SQLite 目录解析成功 |
| 随包 CRT（`msvcp140.dll` / `vcruntime140*.dll`） | 与当前工具链匹配（v0.3.0 前已完成 CRT 版本随工具链匹配的修复） | exe 正常启动 |

> 结论：**不是打包缺文件、不是 CRT 版本、不是引擎不支持，唯一阻塞项就是 cnativeapi.dll 的 `GetDpiForWindow` 静态导入。**

### 2.6 应用侧为什么从“功能不可用”变成“启动失败”

| 位置 | 现状 | 后果 |
|---|---|---|
| `lib/main.dart:119-131` `_hideWindowUntilFirstFrame` | 有 try/catch | 仅记 warn，启动继续 |
| `lib/ui/main_app/window_visibility.dart:19-33` `WindowManagerVisibility.attach` | 有 try/catch，返回 null | 音频可见性降级 |
| `lib/ui/main_app/window_geometry.dart:53-66` `resolveAppWindow` | 无任何保护，`getCurrent()` / `getAll()` 抛异常直接外泄 | 两个调用方全部被击穿 |
| `lib/ui/main_app/main_app.dart:280-332` `_revealWindow` | `resolveAppWindow()` 在 `try` **之外**（第 283 行） | post-frame 回调里未捕获 → 崩溃上报 |
| `lib/ui/main_app/main_app.dart:592` `onSettingsReady → WindowGeometryController.attach` | 位于 `_MainAppCubit.load()` 的 try 内 | 异常被当作启动致命错误，`emit(_Failed)`，用户看到失败页 |

另外，`windows/runner/flutter_window.cpp:69-78` 在首帧回调里已 `Show()` 窗口，所以窗口本身是可见的——用户看到的是“加载页 → 启动失败页”，而不是白屏或隐藏进程。`_hideWindowUntilFirstFrame` 在同机上同样失败（被吞掉），恰好让窗口保持不透明。

---

## 3. 为什么 CI 没抓到

| 环节 | 现状 |
|---|---|
| Windows CI runner | `windows-latest`（Server 2022/2025），远高于 1607 |
| 冒烟测试 | 只验证“能起来、能关掉”，不覆盖 OS 下限 |
| 安装器 | `windows/packaging/exe/installer.iss` 无 `MinVersion`，10240 可安装 |
| 文档 | `README.md:41` 只写 “Windows 10 or 11”，无 build 下限 |
| 依赖升级 | 新依赖的真实 OS 下限无人校验，只能靠用户崩溃报告发现 |

---

## 4. 修复方案

### 4.1 P0（已采纳，待实施）：把下限说清楚，并让它体面失败

1. **原生预检**（`windows/runner/main.cpp`，创建 `FlutterWindow` 之前）
   - 用 `GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow")` 判断 OS 是否满足 cnativeapi 的硬要求；
   - 再 `LoadLibraryW(L"cnativeapi.dll")` 做一次真实加载，覆盖“打包缺 DLL / 依赖损坏”等其他加载失败；
   - 任一失败：弹出**中英双语 MessageBox**（说明需要 Windows 10 1607 / Build 14393 或更高），`return EXIT_FAILURE`，不进入 Dart 启动、不生成崩溃报告、不留不可见进程。
   - 放在原生层的原因：zip 便携版没有安装器可拦截；此时 Dart 侧 `window_manager` 已完全不可用，无法自行提示或自行关闭窗口。
2. **安装器下限**：`installer.iss` 的 `[Setup]` 增加 `MinVersion=10.0.14393`（仓库已 vendored `WindowsVersionNotSupported` 翻译，会按安装器语言显示）。
3. **Dart 侧容错**（纵深防御，任何原生失败都不应拖垮启动）
   - `resolveAppWindow()` 内部捕获异常、返回 `null` 并只记一次 warn（单点收口，两个调用方同时受益）；
   - `_revealWindow()` 在 `window == null` 时继续走显示兜底（首帧已由 runner 显示），不再让异常逃逸到 zone；
   - `WindowGeometryController.attach()` 拿不到窗口时跳过尺寸恢复与监听，保证 `load()` 仍能到达 `_Ready`；
   - 需要提示用户时，复用 `_AppDeps.warning`（需补 4 个 ARB 语言文案），不要新增独立弹窗体系。
4. **文档**：README 支持矩阵改为 “Windows 10 1607（Build 14393）+ / Windows 11”；发布说明补充该下限；在 Issue #71 回复“升级系统”的处置建议。
5. **CI 回归护栏（必做，见 §5.1 P0-5）**：打包后解析 `Release/` 下全部 DLL 的导入表，出现白名单之外的已知 1607+ API 即失败，防止后续依赖升级把 OS 下限悄悄抬高。

### 4.2 P1（不采纳）：真正继续支持 10240

> 决策：本次不实施。保留此节仅为记录“若后续确认仍有 10240 用户”时的改法与代价（见 §5 触发条件）。

由于唯一阻塞点只有两处调用，改造成本很低，但需要维护 fork：

1. 把 `Window::Dock`（`window_windows.cpp:2993`）与 `PositionDock`（`window_docking_windows.h:114`）的 `GetDpiForWindow(hwnd) / 96.0` 改为已有的 `GetScaleFactorForWindow(hwnd)`（动态解析 + `GetDpiForMonitor` / 系统 DPI 回退）；`window_docking_windows.h` 需补 `dpi_utils_windows.h` 包含；
2. 通过 `dependency_overrides` 指向自维护 fork 提交；同时向 `libnativeapi/nativeapi-core` 提 upstream PR，修复后切回官方版本；
3. 在 10240 真机/VM 上验证：DLL 加载、100%/125%/150% 下的窗口尺寸与恢复记忆、可见性监听、退出路径；
4. 已知退化：manifest 的 `PerMonitorV2` 在 1703 以下会被忽略，等效系统 DPI 感知，跨显示器缩放不精确；且 10240 早已停止安全更新，长期维护收益有限。

### 4.3 不推荐

| 方案 | 不采用的原因 |
|---|---|
| 只加 Dart `try/catch` | 窗口功能（最小尺寸钳制、尺寸记忆、可见性）静默失效，用户看不到原因；最小尺寸约束完全消失（runner 目前没有原生 `WM_GETMINMAXINFO` 兜底） |
| 降级 `window_manager` 0.5.x | 丢掉 0.6 的 `getCurrent` 语义与既有退出/CRT 修复，回归风险大于收益 |
| 盲目升级 `nativeapi` / `cnativeapi` | 0.6.1 仍是相同静态导入，且 `window_manager 0.6.0` 约束在 `^0.5.5`，升级无效 |

---

## 5. 决策记录

**结论：采用 A（只做 P0），不实施 B（P0 + P1）。** 决策时间 2026-11-15，同日实施完毕。

| 选项 | 范围 | 结果 | 决策 |
|---|---|---|---|
| **A. 只做 P0** | 原生预检 + 安装器下限 + Dart 容错 + 文档 + CI 导入表护栏 | 10240 用户看到明确提示并退出；1607+ 行为不变；无 fork 维护成本 | ✅ **采纳并实施** |
| **B. P0 + P1** | 追加 cnativeapi fork 补丁 | 10240 可继续使用（DPI 精度退化）；需长期维护 fork 与旧系统验证 | ❌ 不采纳 |

### 5.1 采纳范围与顺序

| 项 | 内容（详见 §4.1） | 状态 |
|---|---|---|
| P0-1 | `windows/runner/main.cpp` 原生预检 + 双语 MessageBox + `EXIT_FAILURE`；`windows/runner/CMakeLists.txt` 为 runner 增加 `/utf-8`（中文宽字面量） | ✅ 已实施 |
| P0-2 | `windows/packaging/exe/installer.iss` 加 `MinVersion=10.0.14393` | ✅ 已实施 |
| P0-3 | Dart 侧 fail-soft：`resolveAppWindow()` 单点收口、`_revealWindow()` 空窗口兜底、`WindowGeometryController.attach()` 返回 `bool` 并跳过；新增 `windowGeometryUnavailable` 文案（5 个 ARB）经 `_AppDeps.warning` 提示 | ✅ 已实施 |
| P0-4 | `README.md` 支持矩阵、`docs/release/0.3.0-alpha07-{en,zh}.md`、Issue #71 回复 | ✅ 文档已改；Issue 回复待发布时执行 |
| P0-5 | CI 解析 `Release/` 下全部 DLL 导入表，1607+ API 白名单之外即失败（`tool/check_windows_imports.dart` + `package-windows` 步骤） | ✅ 已实施（白名单为 `GetDpiForWindow`、`AdjustWindowRectExForDpi`） |
| 测试 | `test/ui/main_app/window_geometry_test.dart` 覆盖「解析返回 null / 原生抛异常」两条降级路径 | ✅ 已实施 |

顺序：P0-1 与 P0-3 必须同批（原生拦住 + Dart 兜住，任一单独存在都不完整）；P0-2、P0-4、P0-5 可并行。验收口径见 §6。

### 5.2 不采纳 P1 的理由与重启条件

- 理由：10240 已停止安全更新；fork 需长期跟随 upstream；`PerMonitorV2` 在 1703 以下本就失效，高缩放下体验已打折。收益不足以支撑维护成本。
- 重启条件（满足任一即重新评估 P1）：Issue 追踪中来自 < 1607 系统的“无法使用”反馈达到需要支持的规模；或 upstream 官方版本自行改为动态解析 `GetDpiForWindow`（此时等于零成本拿到 P1 效果，切回官方依赖即可）。

### 5.3 责任边界（明确的非目标）

- 本次不修改 `window_manager` / `cnativeapi` 依赖版本，不加 `dependency_overrides`；
- 本次不追求“10240 可用”，只保证“10240 体面退出 + 1607+ 无回归”；
- §8.3 列出的旧系统能力降级（DPI 感知、深色标题栏、Mica 等）不在本次修复范围内。

---

## 6. 验证方法

| 验证项 | 方法 |
|---|---|
| 根因确认（无需旧系统） | 对任意版本的 `cnativeapi.dll` 执行 `dumpbin /imports`（Windows）或解析 PE 导入表，确认 `USER32.dll` 段含 `GetDpiForWindow` |
| 旧系统行为 | Windows 10 10240 虚拟机运行修复后的包：应出现说明框并干净退出（返回码非 0），无崩溃报告、无残留进程 |
| 降级路径（不依赖 OS） | 为 `resolveAppWindow` / `WindowGeometryController.attach` 注入“抛异常/返回 null”的假实现，断言启动仍到 `_Ready`、无 `FATAL startup failed` |
| 正常系统回归 | Windows 10 1607+/Windows 11：窗口尺寸恢复、最小尺寸、居中、退出路径与现状一致 |
| 静态门禁 | `flutter analyze --fatal-infos`、`flutter test` 全绿；5 语言 × 1.0/1.3 字号 × 运行/武装重放/暂停/恢复中四态无溢出 |

---

## 7. 经验教训

1. **原生依赖会静默抬高 OS 下限**：`window_manager` 从自带 Win32 实现改为基于 nativeapi 后，下限从“Windows 10”事实上变成了 1607，但项目文档、安装器、CI 都不知道。
2. **CI 只能证明“新系统能跑”，不能证明“声明的最低系统能跑”**：OS 下限类的兼容性问题必须靠文档约束、安装器门禁或导入表静态检查兜底。
3. **可选能力必须有单点容错**：窗口能力在本项目里被多处使用，但容错只做了一半；对 `window_manager` 这类“平台能力型”依赖，解析入口应统一 fail-soft，并由启动主流程显式区分“致命失败”与“能力降级”。
4. **127/126/193 的区分很有价值**：先确定“加载失败还是符号缺失”，能一次性排除版本错配、缺文件、位数不符等大半猜测。

---

## 8. 下限复核：把门槛定在 1607 后，是否还有组件把它推得更高

> 复核时间：2026-11-15。目标：确认“Windows 10 1607（14393）”作为新下限是否够用，即是否还有其他原生组件静态依赖 1703+ 的 API。

### 8.1 方法

| 组件（实际版本） | 复核方式 |
|---|---|
| `flutter_windows.dll`（Flutter 3.47.9 / engine `89c39edfdf`，windows-x64-release） | 下载 `windows-x64-flutter.zip`，解析 PE 导入表（常规导入 + 延迟加载导入） |
| `sqlite3.dll`（`sqlite3` 3.9.0 官方预编译 x64） | 从 GitHub release 取二进制，解析导入表 |
| `FLAC/ogg/opus/vorbis*.dll`（flutter_soloud prebuilds v1.1.1 windows-x64） | 同上 |
| VC++ 运行库（本机审计 14.44.35211；CI 实际随工具链为 14.51） | 解包 `vc_redist.x64.exe`，解析 `vcruntime140(_1)` / `msvcp140` 导入表 |
| `cnativeapi.dll`（0.5.10）、`flutter_soloud_plugin.dll`（5.2.3）、`file_selector_windows_plugin.dll`（0.9.3+6）、`dartjni.dll`（jni 1.1.2）、`ssb_runner.exe` | 这类二进制由本机工具链/AOT 编译，仓库里没有产物，按源码 + CMake 链接库审计 |

### 8.2 结论：没有任何组件要求高于 1607

| 组件 | 导入表里“最高”的 API | 最低系统 |
|---|---|---|
| `flutter_windows.dll`（x64 release） | `RtlAddGrowableFunctionTable`/`RtlDeleteGrowableFunctionTable`、`WaitOnAddress`/`WakeByAddressSingle`、`GetCurrentThreadStackLimits`、`GetSystemTimePreciseAsFileTime`、`PathCchCombineEx`/`PathCchRemoveFileSpec` | Windows 8（`RtlAdd*GrowableFunctionTable` 官方文档即标注 Win8） |
| `sqlite3.dll` | 仅 `FlushFileBuffers`/`GetTickCount64`/`InitializeSRWLock` 等，且 CRT 静态链接（无 `api-ms-win-crt-*`） | Windows 7 级别 |
| `FLAC/ogg/vorbis/vorbisenc/vorbisfile.dll` | `TzSpecificLocalTimeToSystemTime` 等；`opus.dll` 额外用 UCRT + `VCRUNTIME140` | Vista / Windows 10（UCRT 为系统组件） |
| VC++ 运行库 | `api-ms-win-crt-*` + `RtlUnwindEx`/`EncodePointer` 等老 kernel32 | Windows 7 SP1 + KB2999226，Win10 原生满足 |
| `cnativeapi.dll` | **`GetDpiForWindow`、`AdjustWindowRectExForDpi`** | **Windows 10 1607（唯一 1607 项）** |
| `flutter_soloud_plugin.dll` | Media Foundation（`MFStartup`/`MFCreateSourceReaderFromURL`）、WASAPI、`shlwapi` | Vista |
| `file_selector_windows_plugin.dll` | `IFileDialog`、`SHCreateItemFromParsingName` | Vista |
| `dartjni.dll` | 只延迟加载 `jvm.dll`（`/DELAYLOAD:jvm.dll`），静态导入仅 Dart API + 老 kernel32 | 无额外要求 |
| `ssb_runner.exe` | `GetSystemTimePreciseAsFileTime`（Win8）、`DwmSetWindowAttribute`（Vista）、`RegGetValue`（Vista）；`AdjustWindowRectExForDpi`/`EnableNonClientDpiScaling` 已用 `GetProcAddress` 动态解析 | Windows 8 级别 |

引擎另有两条**延迟加载**导入：`dwmapi.dll`、`dbghelp.dll`（缺失不影响加载）。x64 引擎静态导入 `d3d9.dll`（仅 `D3DPERF_*`）、`dxgi.dll`、`OPENGL32.dll`、`UIAutomationCore.dll`、`OLEACC.dll`，这些在 Windows 10 客户端均为系统自带。

**旁证（比导入表更直接）**：Issue #71 的 10240 机器上，`flutter_windows.dll` 已成功加载并出首帧，`sqlite3.dll` / `flutter_soloud_plugin.dll` 也完成了加载（`BOOT 06 soloud_init ok`）。也就是说这些 DLL 的静态导入在 10240 上就已全部满足，1607 自然更没问题。

### 8.3 1607 上会“降级但不崩溃”的能力（不影响下限，影响体验）

| 能力 | 实际要求 | 1607 上的表现 |
|---|---|---|
| `dpiAwareness=PerMonitorV2`（`runner.exe.manifest`） | 1703 | 未知值被忽略，且没有 `dpiAware` 兜底 → 进程 DPI 不感知，125%/150% 下整窗位图拉伸、界面发虚 |
| `DWMWA_USE_IMMERSIVE_DARK_MODE`（`win32_window.cpp:321`） | 1809+（值 20 需 1909+） | 调用返回 `E_INVALIDARG`，标题栏保持浅色 |
| `DWMWA_SYSTEMBACKDROP_TYPE`（Mica）、`DWMWA_WINDOW_CORNER_PREFERENCE` | Windows 11 | `DwmSetWindowAttribute` 返回错误，忽略 |
| `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE=0x11)` | Windows 10 2004 | cnativeapi 已按 build 号回退 `WDA_MONITOR`（截图里窗口变黑而不是被排除） |
| `SetWindowCompositionAttribute`（亚克力/透明背景） | 未文档化，Win7+ 导出 | `GetProcAddress` 空指针检查，失败即降级为不透明 |

### 8.4 与版本无关、但会被误当成“门槛”的限制

1. **Windows 10 N 版**：`flutter_soloud_plugin.dll` 静态依赖 `mfplat.dll` / `mfreadwrite.dll`（Media Foundation）。N 版默认不含完整 Media Foundation，安装 Media Feature Pack 前该 DLL 可能加载失败 → 音频能力缺失。启动路径需要像现在的 SoLoud 初始化一样 fail-soft（当前 CI 冒烟已覆盖“无声卡”，但未覆盖“DLL 加载失败”）。
2. **Server Core / Nano Server**：没有 `d3d9.dll` / `OPENGL32.dll` / 完整 `user32.dll` 栈，引擎无法渲染。客户端版本不受影响。
3. **仅 x64**：`ArchitecturesAllowed={{ARCHITECTURES_ALLOWED}}` 由 fastforge 注入，维持现状即可。

### 8.5 建议

1. **下限维持 1607**，不需要再抬高；`installer.iss` 加 `MinVersion=10.0.14393`（§4.1）。
2. 把 §4.1 第 5 条的“CI 导入表护栏”从可选升级为必做：对 `Release/` 下**全部** DLL 跑同一条导入表脚本，维护一张“允许的 1607+ API 白名单”（当前只有 `GetDpiForWindow`、`AdjustWindowRectExForDpi`），出现新条目即失败。本次复核里的 `flutter_soloud_plugin.dll`、`dartjni.dll`、`file_selector_windows_plugin.dll` 都是本地编译产物，只有 CI 能对真实二进制把关。
3. README 支持矩阵在写“Windows 10 1607+”的同时，注明 1607 上 DPI 为系统级缩放（高缩放下界面会被位图拉伸），1703+ 才有 PerMonitorV2。

---

## 9. 参考

- Issue #71：<https://github.com/SSBContestRunner/ssb_runner/issues/71>
- 微软文档 `GetDpiForWindow`：<https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiforwindow>
- 上游源码 `cnativeapi 0.5.10`：`cxx_impl/src/platform/windows/window_windows.cpp`、`window_docking_windows.h`、`dpi_utils_windows.cpp`、`hook/build.dart`
- 本项目相关文件：`lib/ui/main_app/window_geometry.dart`、`lib/ui/main_app/main_app.dart`、`lib/ui/main_app/window_visibility.dart`、`lib/main.dart`、`windows/runner/main.cpp`、`windows/runner/win32_window.cpp`、`windows/packaging/exe/installer.iss`、`README.md`
