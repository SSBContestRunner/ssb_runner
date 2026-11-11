# 窗口几何技术方案：内容区单一尺寸源（Post-Frame Variant）

> 状态：待评审（核心决策已确认，2026-11-11；§11「恢复上次窗口尺寸」同日追加）
> 适用范围：桌面端主窗口（Windows / macOS / Linux）
> 关联文档：[首帧零 IO 方案](./first_frame_white_screen_design.md)、[启动性能优化设计方案](./startup_performance_design.md) §4.4
> 本文处理窗口尺寸、最小尺寸、窗口解析、诊断日志，以及 §11 的「恢复上次窗口尺寸」；**不改变**首帧零 IO 的调用顺序、首帧内容和窗口显隐时机。

---

## 0. 已确认决策（2026-11-11）

| 决策 | 结论 |
| --- | --- |
| 最小尺寸契约 | **内容区 1108×772**；发布说明改为「最小内容区」，不再写「窗口 1108×796」 |
| 原生 runner | **客户端尺寸语义**：Windows 用 `AdjustWindowRectExForDpi`，Linux/macOS 直接设置内容区 1108×772 |
| 初始尺寸 | **内容区 1108×772**，与最小尺寸一致（保持当前“打开即最小”的行为） |
| 恢复上次尺寸 | **Option A**：首帧后、`prefs_ready` 就绪即恢复；接受一次 post-reveal resize，详见 §11 |
| 实施顺序 | 先评审本文档；评审通过后按 §10 / §11.9 实施清单执行 |

仍待实现后验证的开放项（不阻塞文档评审）：

- Linux CSD 标题栏/阴影下的 `default-size` 口径，需在 X11 与 Wayland 实测；
- Windows 100% / 125% / 150% 与多显示器居中的非客户区换算，需在 Windows 机器上验收。

---

## 1. 问题定义

用户诊断日志（`ssb-runner-diagnostics-20261109-172510`）对应的 0.3.0 Windows 构建中，实际窗口尺寸与配置值不一致：

- Dart 侧按 **1108×796** 配置窗口；
- Windows/Linux runner 以 **1280×720** 创建窗口，macOS XIB 为 **800×600**；
- 导出日志里没有任何窗口几何字段，`window_ready` 步骤在 0.3.0 启动链路中已经不存在，问题无法从诊断包自证。

由此带来的用户可见后果：

1. 首帧按 runner 的尺寸绘制，首帧之后才 resize，引擎 surface 被销毁重建；
2. `window_manager` 的 `setSize` / `minimumSize` 是**窗口外框**（frame）尺寸，而布局验收标准是**内容区**（content）尺寸。Windows 非客户区比 macOS 标题栏高，1108×796 外框只能得到约 1092×757 内容区，低于已验收的 1108×772；
3. 最小窗口下，QSO 只读格、三位数收发交换信息、armed 状态下的会话卡片可能被裁切或出现滚动。

本文的目标是让 **内容区尺寸成为唯一契约**，并让窗口配置在**首帧之后的 post-frame 回调**里完成，从而不增加首帧延迟。

## 2. 现状与根因

### 2.1 尺寸存在两个来源

| 层 | 当前值 | 单位 | 位置 |
| --- | --- | --- | --- |
| Windows runner | 1280×720 | 外框（`Create` 内按 DPI 缩放） | [`windows/runner/main.cpp`](../../windows/runner/main.cpp#L27-L31) |
| Linux runner | 1280×720 | 内容区（GTK `default-size`） | [`linux/runner/my_application.cc`](../../linux/runner/my_application.cc#L50) |
| macOS runner | 800×600 | 内容区（`contentRect`） | [`macos/Runner/Base.lproj/MainMenu.xib`](../../macos/Runner/Base.lproj/MainMenu.xib#L335) |
| Dart 配置 | 1108×796 | 外框 | [`lib/ui/main_app/main_app.dart`](../../lib/ui/main_app/main_app.dart#L184-L185) |

### 2.2 配置在首帧之后才生效

[`main.dart`](../../lib/main.dart#L62-L74) 在 `runApp` 之前只设置透明度；尺寸、最小尺寸和居中都放在 [`_revealWindow`](../../lib/ui/main_app/main_app.dart#L162-L216) 的 post-frame 回调里。

runner 已经用 1280×720（或 800×600）构造了 `FlutterViewController`，[`flutter_window.cpp`](../../windows/runner/flutter_window.cpp#L17-L28) 的注释明确要求该尺寸与窗口尺寸一致，否则启动路径会多一次 surface 创建/销毁。因此当前每次启动都必然多一次 resize 和一次额外绘制。

### 2.3 `getCurrent()` 为空时配置被静默跳过

[`main.dart`](../../lib/main.dart#L64-L65) 与 [`main_app.dart`](../../lib/ui/main_app/main_app.dart#L166-L187) 都写成 `if (window != null)`，没有 `else` 日志。

Windows 的 `WindowManager::GetCurrent()` 基于 `GetActiveWindow()`；窗口尚未 show、尚未激活，或调用线程不是窗口所属线程时都可能返回空。此时透明度、尺寸、最小尺寸、居中全部跳过，窗口保持 runner 的 1280×720，且日志里没有任何记录。

### 2.4 外框与内容区单位错配

window_manager 0.6.0 的语义：

- `Window.setSize` / `Window.minimumSize`：窗口外框（Windows 经 `WM_GETMINMAXINFO` 生效）；
- `Window.contentSize`：客户区，即 Flutter 实际布局区域。

对应实现见 cnativeapi 0.5.10 的 `window_windows.cpp`：`SetSize` 把逻辑外框乘以 DPI 后交给 `SetWindowPos`，`SetMinimumSize` 通过 `WM_GETMINMAXINFO` 的 `ptMinTrackSize` 生效（同样是外框、逻辑像素乘以 DPI）。

布局验收使用的是内容区 1108×772，但测试注释把它写成「1108×796 外框减去 24dp macOS 标题栏」（[session_panel_end_confirm_test.dart](../../test/ui/session_panel_end_confirm_test.dart#L88-L91)）。24dp 只适用于 macOS；Windows 非客户区纵向通常约 31–39dp、横向约 16dp，因此外框 1108×796 在 Windows 上只剩下约 1092×757，**达不到验收基线**。

## 3. 目标与验收

| 指标 | 目标 |
| --- | --- |
| 默认内容区 | 无保存值时为 **1108×772**（`MediaQuery.sizeOf` 一致）；有保存值时为保存值（§11） |
| 最小窗口下的内容区 | 仍为 1108×772；QSO 只读格、三位数交换格、四态会话卡片不裁切、不滚动 |
| 首帧绘制尺寸 | 与默认内容区一致；原生 runner 对齐后，无保存值启动不再出现首帧后 resize |
| 恢复上次尺寸 | 有保存值：`prefs_ready` 后**恰好一次** resize 到保存值；无保存值或保存值等于最小内容区：零 resize |
| 配置可见性 | 日志记录解析来源、frame、content、minimumSize 和耗时；失败留 warn |
| 首帧延迟 | 不回归；`main()` 不新增任何窗口调用 |
| 回归 | `flutter analyze` / `flutter test` 全绿 |

验收矩阵：Windows 100% / 125% / 150%、macOS、Linux；五种语言 × 字号 1.0 / 1.3。

## 4. 设计原则

1. **内容区是唯一尺寸单位**：代码里所有与布局相关的常量都用 content 表示；外框只在 Windows 原生层通过 `AdjustWindowRectEx` 推导。
2. **保留 post-frame 变体**：窗口几何继续在 `_revealWindow` 里执行，[`main.dart`](../../lib/main.dart) 不新增调用，首帧路径与 `d32489a` 保持一致。
3. **幂等**：原生 runner 已按目标内容区创建窗口后，Dart 侧的 `contentSize` 赋值应为 no-op（尺寸未变化时不触发 `WM_SIZE`）。
4. **失败留痕**：窗口解析失败、几何调用抛异常都必须写日志，且不能阻止后续 `opacity = 1` 显示。
5. **诊断自证**：每次启动至少一条窗口几何记录，导出诊断包即可核对。

## 5. 总体设计

```text
原生 runner：创建内容区 1108×772 的窗口
        │
        ▼
main()（同步，无 IO，不新增窗口调用）
  ├─ window.opacity = 0                    // 现有逻辑
  ├─ installLogger(AppLogger.buffered())
  └─ Catcher2 → runApp
        │
        ▼
第一帧：MaterialApp + _Loading（纯绘制）
        │
        ├─ post-frame #1：_revealWindow()
        │     ├─ resolve: getCurrent() ?? getAll().firstOrNull
        │     ├─ contentSize = 1108×772      // 通常 no-op
        │     ├─ chrome = frame - content
        │     ├─ minimumSize = content + chrome
        │     ├─ center()
        │     ├─ opacity = 1; show(); focus()
        │     └─ log window geometry
        │
        └─ post-frame #2：_BootGate._start()  // 日志文件 / prefs / db / DXCC / 呼号 / 音频，不变
```

post-frame 回调按注册顺序执行，`_revealWindow` 仍然先于 `_BootGate` 的 IO 启动（[main_app.dart](../../lib/ui/main_app/main_app.dart#L58-L65)）。

## 6. 详细设计

### 6.1 单一常量

新增一个窗口几何常量，放在 `lib/ui/main_app/` 下（例如 `window_geometry.dart`）：

```dart
/// 布局验收基线：五种语言 × 字号 1.0/1.3 下不裁切、不滚动的内容区。
const Size kMinWindowContentSize = Size(1108, 772);
```

说明：

- 1108×772 是**内容区**契约，不再写成 796 外框；
- 796 只作为 macOS 的换算结果出现（772 + 24dp 标题栏），不进入 Dart 常量；
- 原生 runner 的初始内容区也使用同一组数值：1108×772。

### 6.2 解析应用窗口

```dart
Window? _resolveAppWindow() {
  final current = WindowManager.instance.getCurrent();
  if (current != null) return current;

  final all = WindowManager.instance.getAll();
  if (all.length == 1) return all.first;

  log.warn(
    'window not resolved',
    tag: 'boot',
    fields: <String, Object?>{'candidates': all.length},
  );
  return null;
}
```

要点：

- `getAll()` 只枚举本进程顶层窗口，单窗口应用天然只有一个候选；数量不为 1 时不猜，留 warn；
- 解析失败只影响几何，`_revealWindow` 仍继续执行 `opacity = 1`，保证窗口可见、应用可用。

### 6.3 应用几何（post-frame）

```dart
void _applyWindowGeometry(Window window) {
  // 先读取当前外框与内容区，得到平台非客户区尺寸。
  final frame = window.size;
  final content = window.contentSize;
  final chromeWidth = frame.width - content.width;
  final chromeHeight = frame.height - content.height;

  // 内容区是契约；外框由内容区 + 平台非客户区推导。
  window.contentSize = kMinWindowContentSize.toNative();
  window.minimumSize = Size(
    kMinWindowContentSize.width + chromeWidth,
    kMinWindowContentSize.height + chromeHeight,
  ).toNative();
  window.center();
}
```

顺序与原因：

1. **先测量再设置**：`frame - content` 直接给出当前 DPI 下的非客户区，不写死 24dp/39dp；先测量可以避免「写后立即读」的时序依赖。
2. **先内容区、后最小外框**：`minimumSize` 是外框约束，必须由内容区换算；如果先设最小外框，Windows 可能在 `WM_GETMINMAXINFO` 阶段把窗口夹到旧值。
3. **居中放在最后**：避免移动跨 DPI 显示器后再改尺寸；即使非客户区因 DPI 有 1–2dp 变化，`minimumSize` 也只是下限，不会破坏当前内容区。
4. 原生 runner 已对齐时，`contentSize` 赋相同值不会触发 `WM_SIZE`，`minimumSize` 只触发一次 `WM_NCCALCSIZE`，`center()` 只触发 `WM_MOVE`。

### 6.4 原生 runner 对齐（关键）

只有原生初始尺寸与 Dart 目标一致，post-frame 的几何调用才是 no-op，首帧才不会再 resize。

#### Windows

`Win32Window::Create` 现在把入参当外框使用。改为内容区语义：

```cpp
// windows/runner/win32_window.cpp
const DWORD style = WS_OVERLAPPEDWINDOW ^ WS_MAXIMIZEBOX;

// Create() 的入参是逻辑像素：先换算到物理像素，再用该 DPI 的非客户区修正。
RECT rect = {0, 0, Scale(size.width, scale_factor),
             Scale(size.height, scale_factor)};

using AdjustWindowRectExForDpiFn = BOOL(WINAPI*)(LPRECT, DWORD, BOOL, DWORD, UINT);
auto adjust_for_dpi = reinterpret_cast<AdjustWindowRectExForDpiFn>(
    ::GetProcAddress(::GetModuleHandleW(L"user32.dll"),
                     "AdjustWindowRectExForDpi"));
if (adjust_for_dpi != nullptr) {
  adjust_for_dpi(&rect, style, FALSE, 0, dpi);
} else {
  ::AdjustWindowRectEx(&rect, style, FALSE, 0);
}

::CreateWindow(window_class, title.c_str(), style,
               Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
               rect.right - rect.left, rect.bottom - rect.top,
               nullptr, nullptr, GetModuleHandle(nullptr), this);
```

[`main.cpp`](../../windows/runner/main.cpp#L29) 改为：

```cpp
Win32Window::Size size(1108, 772);   // 内容区
```

注意：`AdjustWindowRectExForDpi` 需要 Windows 10 1607+；低于该版本回退到 `AdjustWindowRectEx`（非 DPI 感知版本）。两者都在创建窗口前执行，不影响首帧路径。

#### Linux

GTK 的 `default-size` 按内容区口径，直接改为：

```c
gtk_window_set_default_size(window, 1108, 772);
```

启用 CSD 标题栏时，GTK 的尺寸口径会包含 header bar 与阴影的差异；nativeapi 的 `SetContentSize` / `GetContentSize` 已经处理 CSD 标题栏、阴影和未 map 窗口的请求尺寸，Dart 侧 post-frame 的 `contentSize` 是最终校正。验收时在 X11 与 Wayland 各测一次：若首帧后仍出现一次 header bar 高度的 resize，则在 `my_application.cc` 里把 header bar 高度计入 `default-size`。

#### macOS

XIB 的 `contentRect` 是内容区，改为：

```xml
<rect key="contentRect" x="335" y="390" width="1108" height="772"/>
```

NSWindow 会自动把外框变成约 1108×796（标题栏约 24dp），与现有测试假设一致。

### 6.5 诊断日志

在 `_revealWindow` 内记录一条 boot 日志：

```dart
log.info(
  'window geometry',
  tag: 'boot',
  fields: <String, Object?>{
    'frame': '${window.size.width}x${window.size.height}',
    'content': '${window.contentSize.width}x${window.contentSize.height}',
    'minimum': '${window.minimumSize.width}x${window.minimumSize.height}',
    'durMs': stopwatch.elapsedMilliseconds,
  },
);
```

- 解析失败记录 `window not resolved`；
- 几何配置抛异常记录 `window configure failed`（保留现有 catch）；
- 该记录会进入 `latest.log`，随诊断包导出，下一次即可直接核对，不依赖用户描述。

### 6.6 测试与文档

- widget 测试继续使用内容区 `Size(1108, 772)`；[main_page_layout_test.dart](../../test/ui/main_page_layout_test.dart#L628-L651) 中「macOS 标题栏 24dp」的注释改为「内容区 1108×772」。
- 抽一个纯函数便于测试外框推导：

  ```dart
  Size minimumFrameFor(Size content, Size chrome) =>
      Size(content.width + chrome.width, content.height + chrome.height);
  ```

  用单测覆盖 macOS（chrome 0×24）、Windows（chrome 16×39）、0 边框三种输入。
- 发布说明中的「最小窗口 1108×796」改为「最小内容区 1108×772（macOS 外框约 1108×796）」。
- [session_panel_end_confirm_test.dart](../../test/ui/session_panel_end_confirm_test.dart#L88-L91) 的注释同步更新。

## 7. 首帧时间影响（为什么选 post-frame 变体）

窗口几何调用是**原生 FFI，不是 IO**；[`first_frame_white_screen_design.md`](./first_frame_white_screen_design.md#L90-L94) 也把 `window.opacity = 0` 归为同一类，而非首帧前的 IO。但为了不扩大首帧路径，本方案仍不把它们前移，原因是指标优先级：

| 变体 | `main()` 新增调用 | 首帧延迟 | 首帧内容 |
| --- | --- | --- | --- |
| **post-frame（本文）** | 0 | 不变 | 与原生初始尺寸一致，因此首帧即最终尺寸 |
| pre-`runApp` | 几何 | 增加 0.5–3ms | 首帧即最终尺寸 |

post-frame 变体下，几何调用发生在第一帧已经绘制之后：

| 调用 | 常态成本 |
| --- | --- |
| `getCurrent()` | µs |
| `getAll()` 回退 | 一次 `EnumWindows`，约 0.1–0.5ms，仅 `getCurrent()` 为空时发生 |
| `contentSize` | 尺寸未变化时不发 `WM_SIZE`，约 0.1ms |
| `minimumSize` | 一次 `WM_NCCALCSIZE`，约 0.1–1ms |
| `center()` | `WM_MOVE`，约 0.1–1ms |

合计常态约 **1–2ms**，最坏不超过 3ms，且发生在 splash 已经绘制之后；不进入 `main()` 到首帧的路径。也就是说：

- **首帧延迟**（`main()` → 第一帧可见）与 `d32489a` 基线一致；
- **首帧可见内容**因为原生 runner 已对齐，不再需要首帧后的 resize 与第二帧；
- 与「全部 IO 后移」的结论不冲突：没有新增文件、网络或平台通道等待。

§11 的「恢复上次尺寸」同样不进入首帧路径：它发生在 `prefs_ready` 之后，只增加一次 `contentSize` 赋值，仅当保存值与默认值不同时才会产生一次可见 resize。`first frame visible` / `sinceMainMs` 不受影响。

验收时对比新日志中的 `first frame visible` / `sinceMainMs` 与改造前 10 次冷启动，差异应落在测量噪声内；同时确认 post-frame 几何块耗时没有超过 16ms 的单次阻塞。

## 8. 备选方案与取舍

| 方案 | 结论 | 原因 |
| --- | --- | --- |
| 几何前移到 `main()`（pre-`runApp`） | 不采用 | 会占用首帧延迟预算；与「首帧路径最小化」目标冲突 |
| 继续用 `setSize` / `minimumSize` 写 1108×796 | 不采用 | Windows 内容区不足 1108×772，最小窗口会裁切 |
| 只改 Dart、不改原生 runner | 不采用 | 首帧仍按 1280×720/800×600 绘制，必有一次 resize 和 surface 重建 |
| 只改原生 runner、不改 Dart | 不采用 | `getCurrent()` 为空时最小尺寸与居中仍然丢失；跨平台非客户区也不同 |
| 写死平台非客户区（macOS 24dp / Windows 39dp） | 不采用 | 随 Windows 版本、主题、DPI 变化；运行时测量更可靠 |

## 9. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| `getCurrent()` 在 Windows 未激活时返回空 | `getAll()` 单候选回退；解析失败留 warn，且不阻断显示 |
| Windows 非客户区随 DPI/主题变化 | 运行时用 `frame - content` 推导；验收覆盖 100/125/150% |
| Linux CSD 标题栏/阴影导致内容区偏差 | 使用 nativeapi `contentSize` 语义；在 X11 与 Wayland 各验一次 |
| 居中跨显示器导致非客户区微变 | 先测后设，`minimumSize` 只是下限；误差 1–2dp 不影响内容区 |
| 原生 runner 尺寸以后再次漂移 | 把 1108×772 写进文档与测试；诊断日志每次启动可核对 |

## 10. 实施清单

1. 新增 `kMinWindowContentSize`、`_resolveAppWindow()`、`_applyWindowGeometry()`（`lib/ui/main_app/`）。
2. 在 `_revealWindow` 中按「解析 → 测量 → contentSize → minimumSize → center → 显示」顺序接入，并补日志。
3. Windows：`Win32Window::Create` 改为内容区语义（`AdjustWindowRectExForDpi`），`main.cpp` 传 1108×772。
4. Linux：`gtk_window_set_default_size(1108, 772)`。
5. macOS：XIB `contentRect` 改为 1108×772。
6. 更新测试注释、外框推导单测与发布说明措辞。
7. 按 §3 验收矩阵做冷启动与最小窗口检查，并比对 `sinceMainMs` 无回归。

---

## 11. 追加方案：恢复上次窗口尺寸（Option A，post-frame 变体）

> 追加日期：2026-11-11。本节依赖 §6 已实施（`kMinWindowContentSize` 与 `contentSize` 语义）。
> 结论：**恢复所需的读取完全复用已有的 `prefs_ready`**，不新增任何首帧前 IO；代价是当保存值与默认值不同时，窗口显示后会有**一次**可见 resize。

### 11.1 需求与非目标

需求：

- 用户调整窗口尺寸后退出，下次启动恢复到上次的内容区尺寸。
- 不把新的 IO 放回首帧路径，也不改变 `main()` → 首帧的调用顺序。

非目标：

- **不恢复窗口位置/所在显示器**。位置继续由 `center()` 决定，避免外接屏被拔掉后窗口落在屏幕外。
- **不恢复最大化/全屏状态**。只记录正常态（normal）的内容区尺寸。
- 不改变 1108×772 的最小内容区契约。

已接受的代价：

- 有保存值时，窗口先以 1108×772 显示，`prefs_ready` 之后再 resize 一次，用户可能看到一次尺寸跳变。这是 Option A 与「原生几何旁路文件」（Option C）的本质取舍；本方案选择不牺牲首帧时间。

### 11.2 数据模型（单键、单次写入）

`AppSettings` 新增一个键和两个访问器：

```dart
const _settingWindowContentSize = 'setting_window_content_size';

Size? get windowContentSize {
  final raw = _prefs.getString(_settingWindowContentSize);
  if (raw == null) return null;
  final parts = raw.split('x');
  if (parts.length != 2) return null;
  final width = double.tryParse(parts[0]);
  final height = double.tryParse(parts[1]);
  if (width == null || height == null) return null;
  if (!width.isFinite || !height.isFinite) return null;
  if (width <= 0 || height <= 0) return null;
  return Size(width, height);
}

void saveWindowContentSize(Size size) {
  _prefs.setString(
    _settingWindowContentSize,
    '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}',
  );
}
```

设计点：

1. **单键 `"WxH"`**：一次 `setString` 就是一次写入，不会出现「宽写成功、高写失败」的半状态；两个独立键无法保证原子性。
2. **不 bump `settingsRevision`**：窗口尺寸不参与任何 widget 重建，bump 只会触发一次无意义的重建。
3. **不新增存储**：与其它设置同属 `SharedPreferencesWithCache`，`prefs_ready` 已经加载，因此恢复不产生新的文件、平台通道或存储位置。
4. **写入是异步的**：`setString` 立即更新内存缓存、异步落盘；启动恢复只依赖缓存，因此不受影响。

### 11.3 恢复时机（关键）

```text
post-frame #1  _revealWindow()
                 ├─ contentSize = 1108×772（§6.3）
                 ├─ minimumSize = content + chrome
                 ├─ center()
                 └─ opacity = 1; show(); focus()

post-frame #2  _BootGate._start()
                 ├─ bootstrapLoggingAfterFirstFrame()          不变
                 └─ _MainAppCubit.load()
                      ├─ soloud init（async，不 await）          不变
                      ├─ prefs_ready → AppSettings 构造
                      ├─ ★ onSettingsReady(settings) → 恢复尺寸  新增
                      ├─ worker_manager / db / dxcc / callsign / audio   不变
                      └─ emit(_Ready)
```

恢复点选在 `AppSettings` 构造之后、其余启动项之前：

- 不进入 `main()` → 首帧路径，`sinceMainMs` 不变；
- 不等待 DB / DXCC / 呼号 / 音频，用户在最早的时机看到正确尺寸；
- 只依赖 `prefs_ready`，而这已经是既有的首帧后 IO 步骤。

接线时保持 cubit 不依赖 window_manager——`load` 增加一个回调参数：

```dart
// _MainAppCubit.load
final settings = AppSettings(
  prefs: prefs,
  languageNotifier: _language,
  themeModeNotifier: _themeMode,
);
onSettingsReady?.call(settings);   // ★ 新增，紧随构造之后
```

```dart
// _BootGate._start
await context.read<_MainAppCubit>().load(
  dxccManager: context.read(),
  callsignLoader: context.read(),
  onSettingsReady: widget.geometry.attach,   // ★ 新增
);
```

### 11.4 恢复与持久化实现

新增 `lib/ui/main_app/window_geometry.dart`（与 §6.1 的常量放在同一文件）：

```dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nativeapi/nativeapi.dart' show DisplayManager;
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:window_manager/window_manager.dart';

/// 保存值低于最小内容区时抬到下限；高于主屏工作区时压回工作区。
Size clampWindowContentSize(Size saved, Size minimum, Size? workArea) {
  var width = max(saved.width, minimum.width);
  var height = max(saved.height, minimum.height);
  if (workArea != null) {
    width = min(width, workArea.width);
    height = min(height, workArea.height);
  }
  return Size(width, height);
}

class WindowGeometryController {
  Window? _window;
  ListenerId? _listenerId;
  Timer? _saveDebounce;
  AppSettings? _settings;
  Size? _lastSaved;

  /// prefs 就绪后调用：恢复一次，然后开始跟踪用户缩放。
  void attach(AppSettings settings) {
    _settings = settings;

    final window = WindowManager.instance.getCurrent();
    if (window == null) {
      log.warn('window not resolved', tag: 'boot');
      return;
    }
    _window = window;

    final saved = settings.windowContentSize;
    if (saved != null) {
      final workArea = DisplayManager.instance.getPrimary()?.workArea;
      final target = clampWindowContentSize(
        saved,
        kMinWindowContentSize,
        workArea == null ? null : Size(workArea.width, workArea.height),
      );
      if (target != window.contentSize.toSize()) {
        window.contentSize = target.toNative();
        window.center();
      }
      _lastSaved = target;
      log.info(
        'window size restored',
        tag: 'boot',
        fields: <String, Object?>{
          'saved': '${saved.width}x${saved.height}',
          'applied': '${target.width}x${target.height}',
        },
      );
    }

    _listenerId = window.addListener(_onWindowEvent);
  }

  void _onWindowEvent(WindowEvent event) {
    if (event is! WindowResizedEvent) return;
    final window = _window;
    if (window == null) return;
    // 最大化 / 全屏 / 最小化的尺寸不是用户选择的正常态尺寸。
    if (window.isMaximized || window.isFullScreen || window.isMinimized) return;

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  void _saveNow() {
    final window = _window;
    final settings = _settings;
    if (window == null || settings == null) return;
    if (window.isMaximized || window.isFullScreen || window.isMinimized) return;

    final size = window.contentSize.toSize();
    if (size.width < kMinWindowContentSize.width ||
        size.height < kMinWindowContentSize.height) {
      return;
    }
    if (size == _lastSaved) return;
    _lastSaved = size;
    settings.saveWindowContentSize(size);
  }

  /// 退出前把尚未落盘的防抖值写掉。
  void flush() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _saveNow();
  }

  void dispose() {
    _saveDebounce?.cancel();
    final window = _window;
    final listenerId = _listenerId;
    if (window != null && listenerId != null) {
      window.removeListener(listenerId);
    }
    _listenerId = null;
    _window = null;
    _settings = null;
    _lastSaved = null;
  }
}
```

要点：

1. **只监听 `WindowResizedEvent`**：`WindowMovedEvent` 不处理，因为本方案不恢复位置。
2. **500ms 防抖**：一次拖动只在停手后写一次，避免每帧一次 prefs 写。
3. **最大化/全屏/最小化期间不记录**，否则会把屏幕尺寸写进正常态尺寸；用户最大化后退出，下次恢复的仍是最大化前的尺寸。
4. **避免自触发回写**：`_lastSaved` 让恢复引发的那次 resize 不会再写一遍相同值。
5. **恢复后 `center()`**：给 `contentSize` 赋值后窗口原点不变、会向右下生长；居中让最终位置可预期。
6. **对尺寸做精确比较**：`window.contentSize` 是 nativeapi 的 `Size`，必须 `.toSize()` 后再与 Flutter `Size` 比较、赋值时再 `.toNative()`。

生命周期：

- `_MainAppState` 持有 `WindowGeometryController`，构造 `_BootGate` 时传入；
- `_handleExitRequest` 在 `runBoundedExitCleanup` 之前调用 `flush()`；
- `_MainAppState.dispose()` 调用 `dispose()`，移除原生监听。

写入可靠性：防抖 500ms 意味着正常退出时值早已落盘；`flush()` 覆盖「调整后 500ms 内直接退出」的情况。进程被强杀（`_forceExit()`）时无法保证最后一次写入完成，这属于可接受的丢失范围（最多丢失最后一次调整）。

### 11.5 上下限与坐标口径

- **下限**：`kMinWindowContentSize`（1108×772）。低于下限的保存值（旧版本、手工改配置、缩放后 DPI 变化）直接抬到下限。
- **上限**：主显示器 `workArea`。`Display.workArea` 已扣除任务栏，避免恢复出一个超出屏幕的窗口。
- **依赖**：`DisplayManager` 在 `package:nativeapi/nativeapi.dart` 中。`window_manager` 0.6 基于 nativeapi，但没有 re-export `DisplayManager`，因此需要在 `pubspec.yaml` 增加直接依赖：

  ```yaml
  nativeapi: ^0.5.10   # 已是 window_manager 的传递依赖，版本由它锁定
  ```

  若团队不接受新增直接依赖，可退化为「只做下限保护、不做上限保护」，并在日志中保留 `saved` / `applied` 便于排查；但窗口可能大于当前屏幕。
- **单位**：`Window.contentSize` 与 `Display.workArea` 都应在逻辑像素口径。验收时在 Windows 125% / 150% 与 macOS Retina 上确认两者可直接比较；若发现口径不一致，在比较前按 `devicePixelRatio` 换算，而不是写死比例。

### 11.6 失败处理

| 情况 | 行为 |
| --- | --- |
| 无保存值 | 保持默认 1108×772，不产生 resize |
| 值格式非法 / NaN / 非正数 | 视为无保存值，保持默认 |
| `getCurrent()` 返回空 | 记 `window not resolved` warn，保持默认，不阻断启动 |
| 保存值低于最小内容区 | 抬到 1108×772 |
| 保存值大于主屏工作区 | 压到 `workArea` |
| 恢复过程抛异常 | 记 `window configure failed` warn，继续 `opacity = 1`，应用可用 |
| prefs 加载失败 | 走既有 `_Failed` 启动失败分支，与本次改动无关 |

### 11.7 首帧时间影响

| 项 | 影响 |
| --- | --- |
| `main()` 新增调用 | 0 |
| 首帧前新增 IO | 0（恢复复用 `prefs_ready`） |
| `first frame visible` / `sinceMainMs` | 不变 |
| 首帧后新增成本 | 一次 `contentSize` 赋值 + 一次 `center()`，约 0.1–1ms，发生在 splash 绘制之后 |
| 可见代价 | 仅当保存值 ≠ 默认值：一次 post-reveal resize |

因此本方案与「全部 IO 后移」的结论一致：没有把文件、网络或平台通道等待放回首帧前。

### 11.8 验收

- 调整到 1400×900 → 退出 → 再启动：先 1108×772，随后变为 1400×900；`latest.log` 出现 `window size restored`，`saved=1400.0x900.0`。
- 不调整直接退出并重启：无 resize，日志无 `window size restored`（或无保存值）。
- 最大化后退出：下次恢复的是最大化前的正常态尺寸。
- 在副屏调整尺寸后退出、拔掉副屏再启动：按主屏 `workArea` 收口，窗口完整可见。
- 保存值被手工改成 `100x100`：启动后为 1108×772。
- 保存值被手工改成非法字符串：启动后为 1108×772，无异常。
- 连续拖动缩放：停手 500ms 后只有一次 prefs 写（可在 verbose 日志或调试器中确认）。
- `sinceMainMs` 与改造前 10 次冷启动基线差异在测量噪声内。

### 11.9 实施清单

1. `AppSettings`：新增 `_settingWindowContentSize`、`windowContentSize`、`saveWindowContentSize`。
2. 新建 `lib/ui/main_app/window_geometry.dart`：`kMinWindowContentSize`（随 §6.1 迁移）、`clampWindowContentSize`、`WindowGeometryController`。
3. `_MainAppState`：持有 controller，传给 `_BootGate`；`_handleExitRequest` 先 `flush()`；`dispose()` 中 `dispose()`。
4. `_MainAppCubit.load`：新增 `onSettingsReady` 参数，在 `AppSettings` 构造后立即调用。
5. `pubspec.yaml`：增加 `nativeapi: ^0.5.10` 直接依赖（仅用于 `workArea` 上限）。
6. 单测：
   - `clampWindowContentSize`：低于下限、正常、高于工作区、`workArea == null`；
   - `AppSettings.windowContentSize`：`null`、`"1108x772"`、`"abc"`、`"1108x"`、`"1108x772x1"`、`"-1x-1"`、`"NaNxNaN"`。
7. 按 §11.8 做手工验收，并确认 §3 的「恰好一次 resize」指标。
