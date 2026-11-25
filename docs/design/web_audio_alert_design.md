# Web 端音频可用性提示设计（方案 A · 桌面冻结版）

> 状态：已定稿 v2（2026-11-26；v1 采用方案 A，v2 按评审要求**冻结桌面端全部既有逻辑**，web 改为独立实现）
> 分支：待定
> 范围：仅 web 端的音频可用性检测、顶栏 badge、运行中 toast 与设置页一致性
> 关联：[`audio_preflight_check_design.md`](audio_preflight_check_design.md)（桌面 P0/E1–E3 原始设计，本文不改动其结论）、[`audio_output_probe_performance_design.md`](audio_output_probe_performance_design.md)、[`../research/web-platform-technical-solution.md`](../research/web-platform-technical-solution.md) §2、§5.4、[`audio_monitor_ui_web.dart`](../../lib/platform/audio/audio_monitor_ui_web.dart)

---

## 0. 硬约束（先读这一节）

**桌面端保持原样，一行逻辑都不改。** 具体为：

| 冻结项 | 文件 |
|---|---|
| 探测与裁决 | `lib/audio/audio_output_monitor.dart`、`lib/audio/audio_output_probe.dart`、`lib/audio/audio_alert_state.dart` |
| 桌面 UI 与动作 | `lib/ui/main_page/audio_status_badge.dart`、`lib/ui/main_page/audio_alert_toaster.dart`、`lib/ui/main_page/audio_preflight_dialog.dart` |
| 桌面装配 | `lib/platform/audio/audio_monitor_ui_native.dart`、`lib/platform/audio/audio_monitor_ui.dart`、`lib/platform/audio/audio_bootstrap_native.dart` |
| 桌面测试 | `test/ui/audio_status_badge_test.dart`、`test/ui/main_page_layout_test.dart` 等 |

由此推导出的两条实现原则：

1. **不新增共享接口、不改共享枚举、不改共享裁决规则**（v1 里的 `AudioAlertSource`、`AudioProbeSource.webAudio`、`adjudicator` 例外全部撤销）。
2. web 端所有新增代码放在 web 专属文件里；共享文件只允许“纯增量且桌面分支结果不变”的改动（本方案只有 §5.8 的能力位与开关隐藏，以及 ARB 新增文案）。

---

## 1. 结论摘要

| # | 结论 |
|---|---|
| 1 | web 端当前完全没有音频输出提示：web 端口的 badge、toast、预检全部为空实现（[`audio_monitor_ui_web.dart`](../../lib/platform/audio/audio_monitor_ui_web.dart#L5-L15)），顶栏因此永不构建异常图标（[`app_topbar.dart`](../../lib/ui/main_page/app_topbar.dart#L88-L90)） |
| 2 | 不是图标资源问题：web 产物 `FontManifest.json` 含 `MaterialIcons`，`build/web/assets/fonts/MaterialIcons-Regular.otf` 存在，其余图标显示正常 |
| 3 | 根因是能力边界：浏览器不提供系统音量/静音/输出设备读取 API；`AudioOutputMonitor` 又依赖 `dart:io`、平台通道与 `pactl`，web 无法编译 |
| 4 | web 只做浏览器真实可检测的一种情况：**播放被浏览器阻止 / 音频引擎不可用**；不产出 `low` / `muted` / `noDevice` |
| 5 | 桌面代码冻结；web 自带 badge、toast、判定与文案，仅复用纯类型 `AudioMonitorSnapshot` / `AudioAlertReason` 与通用 toast 组件 |
| 6 | web 不轮询；只在初始化落定、页面重新可见、用户点“启用声音”三个事件上采样 |
| 7 | web 开赛预检保持不阻断（沿用现状 `true`），理由见 §4.3 |

---

## 2. 背景与根因

### 2.1 现有链路（已核实）

1. 顶栏插入点：`AppTopbar` 无条件调用 `buildAudioStatusBadge()`（[`app_topbar.dart`](../../lib/ui/main_page/app_topbar.dart#L88-L90)）。
2. 分流：`audio_monitor_ui.dart` 用 `dart.library.js_interop` 条件导出（[`audio_monitor_ui.dart`](../../lib/platform/audio/audio_monitor_ui.dart#L1-L2)）。
3. web 实现全部为空：`buildAudioStatusBadge()` / `buildAudioAlertToaster()` 返回 `SizedBox.shrink()`，`startAudioMonitor()` 等为 no-op（[`audio_monitor_ui_web.dart`](../../lib/platform/audio/audio_monitor_ui_web.dart#L5-L15)）。
4. 图标映射：`low` → `volume_down_outlined`，其余 → `volume_off_outlined`（[`audio_status_badge.dart`](../../lib/ui/main_page/audio_status_badge.dart#L126-L130)）。web 上 badge 从未构建，任何图标都不会出现。
5. 桌面监测不可移植：`AudioOutputMonitor` 直接 `import 'dart:io'` 并读 `Platform.environment` / `Platform.isLinux`（[`audio_output_monitor.dart`](../../lib/audio/audio_output_monitor.dart#L1-L3)、#L47-L48、#L451-L452）；探针只有 CoreAudio/WASAPI 的 MethodChannel 与 Linux `pactl/wpctl`（[`audio_output_probe.dart`](../../lib/audio/audio_output_probe.dart#L376-L382)）。
6. 桌面共享 UI 与桌面类型强绑定：badge 通过 `context.watch<AudioOutputMonitor?>()` 取状态（[`audio_status_badge.dart`](../../lib/ui/main_page/audio_status_badge.dart#L19)），toast 通过 `context.read<AudioOutputMonitor?>()`（[`audio_alert_toaster.dart`](../../lib/ui/main_page/audio_alert_toaster.dart#L36)）。在冻结约束下，web **不能**复用这两个 widget，必须自带等价实现。
7. web 音频引擎刻意推迟到首次点击才初始化（[`audio_bootstrap_web.dart`](../../lib/platform/audio/audio_bootstrap_web.dart#L21-L28)），启动时 `SoLoud.instance.isInitialized == false` 是正常态。

### 2.2 为什么 HTTPS 也解决不了

HTTPS 只是安全上下文门槛，只能解锁规范里明确列出的能力（`getUserMedia`、`setSinkId`、Service Worker 等）。系统混音器状态从未被纳入 Web Audio 规范：页面拿不到系统音量、系统静音、标签页静音；即使 `AudioContext.state == running`，用户仍可能因系统静音或音箱未开而听不到。浏览器自身也无法判断“是否真的出声”。

web 可检测上限：

| 信号 | 是否可检测 | 说明 |
|---|---|---|
| 音频引擎是否初始化成功 | ✅ | `SoLoud.instance.isInitialized`、`init()` 返回值 |
| 浏览器是否暂停了音频上下文 | ✅（依赖内部路径，见 §9 R1） | `window.miniaudio.devices[0].webaudio.state` |
| 输出设备是否存在 | ⚠️ 不稳定 | `enumerateDevices()` 需媒体权限，Chrome 系才可靠 |
| 系统音量 / 系统静音 / 标签页静音 | ❌ | 无任何 Web API |
| 应用内增益 | ✅ 但无意义 | 已被钳制在 0.2–1.2（[`app_settings.dart`](../../lib/settings/app_settings.dart#L177-L180)），永不低于 10% |

### 2.3 现存的一处不一致

设置页“低音量时提示”开关在 web 仍显示并可切换（[`settings_sheet.dart`](../../lib/ui/main_page/settings_sheet.dart#L586-L589)、#L688-L725），但它依赖的开赛预检在 web 恒返回 `true`，是无效控件；“播放试音”行是共享实现、web 可用，造成“个别音频 UI 有、个别没有”的错觉。本方案一并处理（§5.8）。

---

## 3. 目标与非目标

### 3.1 目标

1. web 端在**浏览器阻止播放 / 音频引擎不可用**时，顶栏出现与桌面同形的小 badge，点击可看到原因并就地重试。
2. 运行中若从正常转为不可用，弹出一次非阻断 toast。
3. 正常态（首次手势前、引擎就绪、上下文 running）零占位、零打扰。
4. **桌面端代码与行为完全不变**，现有测试不改、全绿。
5. web 端不产生任何它无法验证的结论（不出现“音量仅 x%”“系统已静音”“未检测到设备”）。

### 3.2 非目标

| 项 | 原因 |
|---|---|
| web 端 `low` / `muted` / `noDevice` | 浏览器无对应 API；造假信号必然误报 |
| web 端阻断式开赛预检（E1） | 浏览器即使上下文 running 也不能保证可听；阻断会把不可控因素变成用户阻塞，见 §4.3 |
| web 端 2s 轮询 | 没有需要轮询的系统状态；事件驱动足够 |
| 麦克风回采验证“真的出声” | 需要额外权限与回声消除，误报与隐私成本高于收益 |
| 修改桌面探针/裁决/UI/装配 | 违反 §0 冻结约束 |
| 抽共享接口以复用 badge/toast | 会触碰桌面文件；改为 web 独立实现，代价见 §9 R7 |

---

## 4. 方案总览

### 4.1 分层

```text
┌─────────────────────────────────────────────────────────────┐
│ 共享（冻结，不改）                                          │
│  app_topbar.dart → buildAudioStatusBadge()                  │
│  main_page.dart  → buildAudioAlertToaster()                 │
│  main_app.dart   → wrapWithAudioMonitor / start / stop      │
│  桌面：AudioOutputMonitor + AudioStatusBadge + Toaster      │
├─────────────────────────────────────────────────────────────┤
│ 平台端口（条件导入，只改 web 实现）                         │
│  audio_monitor_ui_native.dart  （冻结）                     │
│  audio_monitor_ui_web.dart     （重写，唯一 web 装配点）     │
├─────────────────────────────────────────────────────────────┤
│ web 专属（全部新增）                                        │
│  WebAudioMonitor（判定+去抖，纯 Dart、可单测）              │
│  WebAudioSignals（SoLoud / WebAudio / visibility 的 js 适配）│
│  WebAudioStatusBadge / WebAudioAlertToaster（web 专用 UI）   │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 关键决策

| 决策 | 内容 | 理由 |
|---|---|---|
| D1 | 桌面端冻结（§0），不新增共享接口、不改裁决、不改桌面 UI/装配 | 评审硬约束；避免为 web 引入桌面回归风险 |
| D2 | web 使用独立实现，只复用纯类型 `AudioMonitorSnapshot` / `AudioAlertReason`（`audio_alert_state.dart` 仅依赖 `foundation`，无 `dart:io`） | 复用状态语义，避免第二套状态定义；不触碰桌面逻辑 |
| D3 | web 只产出 `engineDown`，使用 web 自己的图标/文案函数 | 不扩展共享枚举；文案可完全按浏览器语境撰写 |
| D4 | web 开赛预检保持 `true` | 见 §4.3 |
| D5 | web 不轮询，只在三个事件上采样 | 无系统状态可读，轮询是纯浪费 |
| D6 | 未初始化（尚未发生用户手势）一律 `none` | 避免每个 web 用户一进页面就见到报错图标 |
| D7 | 设置页在 web 隐藏“低音量时提示”开关，保留“播放试音” | 开关在 web 无效果；试音是浏览器里唯一可靠的“能不能听到”自测手段 |
| D8 | badge 的补救动作在 web 弹层内直接调用重试初始化，不引入跨平台端口 | 冻结约束下不必为单一平台抽端口 |
| D9 | 接受约 60 行 UI 与约 20 行播报逻辑的重复 | 换取桌面零改动；用相同 Key 与同步注释控制漂移（§9 R7） |

### 4.3 为什么 web 预检不阻断（D4）

桌面的 E1 预检目的是拦住“必然无声”的开赛（静音、音量 <10%、无设备、引擎未就绪）。web 只有“引擎被浏览器拦住”一种可判定故障，且通常发生在**用户手势之后**：RUN 本身就是手势，此时初始化才真正执行。若改成阻断，会出现“点 RUN → 弹窗 → 点重试 → 仍可能被策略拒绝”的死循环，而浏览器永远无法保证可听。

因此 web 预检保持 `true`，由三处覆盖：

1. 现有 RUN 流程里的 `ensureAudioInitialized()` 失败 toast（`audioUnavailable`，[`session_panel.dart`](../../lib/ui/main_page/session_panel.dart#L1055-L1068)）；
2. 本方案新增的 badge（可点击重试）；
3. 运行中 toast。

---

## 5. 模块设计

### 5.1 web 装配点：`audio_monitor_ui_web.dart`（重写）

保持与当前完全相同的对外 API，只把空实现换成真实装配，因此 `app_topbar.dart`、`main_page.dart`、`main_app.dart` 一行都不用改：

| API | web 新实现 |
|---|---|
| `wrapWithAudioMonitor(child)` | 原样返回 `child`（web 不需要 provider：badge/toast 由装配点注入同一单例，见下） |
| `buildAudioStatusBadge()` | `WebAudioStatusBadge(source: _sharedMonitor())` |
| `buildAudioAlertToaster()` | `WebAudioAlertToaster(source: _sharedMonitor())` |
| `startAudioMonitor()` | 注册 `audioInitState` 与 `visibilitychange` 监听；初始快照 `none` |
| `stopAudioMonitor()` | 取消监听与延迟计时器 |
| `disposeAudioMonitor()` | 释放 notifier 并清空单例 |
| `confirmRunAudioPreflight(context)` | 维持 `Future<bool>.value(true)` |

单例创建与桌面的 `_sharedMonitor()` 同构（[`audio_monitor_ui_native.dart`](../../lib/platform/audio/audio_monitor_ui_native.dart#L10-L26)），不持有 UI、不依赖 `ContestManager`。

### 5.2 `WebAudioMonitor`（新增）

职责：把 web 可观测信号翻译成 `AudioMonitorSnapshot` 并去抖。

**对外（供 web UI 与测试使用）**

- `ValueNotifier<AudioMonitorSnapshot> snapshot`
- `void start()` / `void stop()` / `void dispose()`
- `Future<bool> retry()`：调用 `retryAudioInitialized()` 后立即采样，返回是否恢复

**信号来源（构造注入，便于 VM 单测）**

| 注入项 | 生产实现 | 说明 |
|---|---|---|
| `engineInitialized` | `SoLoud.instance.isInitialized` | 无成本同步读 |
| `deviceState` | `SoLoud.instance.getAudioDeviceState()` | web 后端已实现（`flutter_soloud-5.3.2/lib/src/bindings/bindings_player_web.dart` L638-L641）；`stopped` 是空闲 500ms 的正常态，不告警 |
| `audioContextState` | `window.miniaudio.devices[0].webaudio.state` 的受控读取 | 只区分 `running` / `suspended` / `closed`；读不到返回 `null` |
| `initNotifier` | `audioInitState`（§5.4） | `notAttempted` / `ready` / `failed` |
| `visibilityChanges` | `document.visibilitychange` | 只在页面可见时采样 |
| `clock` / `scheduleTimer` | 生产用 `DateTime.now` 与 `Timer` | 单测可控 |

**判定规则**

| 条件 | 结果 |
|---|---|
| `initState == notAttempted` | `none`（D6） |
| `initState == failed` | `engineDown` |
| `initState == ready` 且 `engineInitialized == false` | `engineDown` |
| `initState == ready` 且上下文为 `suspended` / `closed` | `engineDown` |
| `initState == ready` 且上下文为 `running` | `none` |
| `initState == ready` 且上下文不可读（`null`） | `none`（静默降级，不猜） |
| 设备 `uninitialized` 但引擎已初始化 | `engineDown`（防御分支；web 不产出 `noDevice`） |
| 页面不可见 | 不采样、不改状态 |

**快照内容**：`reason` 如上；`volume` / `muted` / `deviceName` 恒为 `null`；`source` 保持默认 `unsupported`（不改共享枚举）；`windowVisible` 取实际可见性；`disabled = false`。

**去抖**：`engineDown` 属硬进入，立即生效；恢复 `none` 需 600ms 静默窗口后复采样一次（与桌面 `recheckDelay` 同值，[`audio_output_monitor.dart`](../../lib/audio/audio_output_monitor.dart#L56-L58)）。**不复用** `AudioAlertAdjudicator`：它的“unknown 不清除告警”规则（[`audio_alert_state.dart`](../../lib/audio/audio_alert_state.dart#L191-L195)）会把 web 的 `engineDown` 永久锁死，而修改它违反冻结约束；web 的 4 条规则在 §8.1 单测中逐条覆盖。

**采样时机**：`audioInitState` 变化；`visibilitychange` 变为可见后延迟 300ms（浏览器恢复上下文是异步的）；`retry()` 落定后。可选增强（不阻塞本期）：`AudioPlayer` 丢段时补采一次，覆盖“上下文 running 但写入失败”的边角。

**资源与并发**：`start` 幂等；`stop` 取消订阅与计时器；重试单飞（进行中忽略重复点击）；不调用 `listPlaybackDevices()`（同步 WASM 调用代价高，且 web 只有默认设备）。

### 5.3 `WebAudioSignals`（新增，js 适配层）

把 §5.2 的注入项落到浏览器实现，是**唯一**接触 `package:web` / `dart:js_interop` 的文件，保证判定逻辑能在 VM 单测：

- SoLoud 读数：`isInitialized`、`getAudioDeviceState()`（`try/catch` 包裹，未初始化时返回 `uninitialized`）。
- 上下文状态：受控读取 `window.miniaudio.devices[0].webaudio.state`，任何异常或缺字段返回 `null`。
- 可见性：`document.visibilityState == 'visible'` 判定，`visibilitychange` 事件转 `Stream<bool>`。
- 初始化通知与重试：直接 import `audio_bootstrap_web.dart`（两边都只在 web 编译，无需条件导出）。

### 5.4 web 启动端口扩展（`audio_bootstrap_web.dart`）

只改 web 文件，桌面 `audio_bootstrap_native.dart` 不动：

1. `ValueNotifier<AudioInitState> audioInitState`：`_init()` 开始时保持 `notAttempted`，成功置 `ready`，异常置 `failed`；若 `SoLoud.instance.isInitialized` 已为真，直接 `ready`。
2. `Future<bool> retryAudioInitialized()`：`ready` 时直接返回 `true`；否则清空现有单飞的 `_pending`（当前失败结果会被永久缓存，见 [`audio_bootstrap_web.dart`](../../lib/platform/audio/audio_bootstrap_web.dart#L25-L28)），重置为 `notAttempted` 后重新执行 `_init()`。**必须由用户手势触发**，与现有 `onPointerDown` 解锁路径一致（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L169-L176)）。

### 5.5 `WebAudioStatusBadge`（新增）

与桌面 badge 同形、同 Key，便于既有选择器与视觉验收：

- 外层 `ValueListenableBuilder` 订阅 `WebAudioMonitor.snapshot`（或构造注入的 `WebAudioAlertSource` 接口），`reason == none` 时返回 `SizedBox.shrink()`。
- 异常态是一个 40×40 `IconButton` + 8px 红点，图标 `Icons.volume_off_outlined`，`Key('audioStatusBadge')`，`Semantics(liveRegion: true)`。
- 点击弹 `AlertDialog`：图标 + 标题（`audioBadgeEngineBlockedTooltip`）+ 一行说明（`audioBadgeWebBlindSpotHint`）+ 主操作“启用声音”（`audioBadgeEnableAudio`，调用 `retry()`）+ “关闭”。
- 重试失败时保留弹层与 badge，并以现有 `audioUnavailable` 文案弹一次 warning toast；重试进行中按钮禁用。
- 不复用桌面 `audioAlertIcon` / `audioAlertTooltip`（它们所在文件引用 `dart:io` 类型，web 无法 import）。

### 5.6 `WebAudioAlertToaster`（新增）

- 订阅同一 `WebAudioMonitor.snapshot`；只在 `ContestSessionPhase.running` 时播报（复用桌面既有规则：每个原因每局一次、恢复后重置）。
- 文案固定为 `audioBadgeEngineBlockedTooltip`；`ToastificationType.warning`、`fillColored`、4s，与桌面一致（[`audio_alert_toaster.dart`](../../lib/ui/main_page/audio_alert_toaster.dart#L69-L75)）。
- 桌面 `AudioAlertAnnouncer` 定义在引用 `dart:io` 的文件里，web 无法复用；在 web 文件内实现等价的 `_WebAudioAlertAnnouncer`（约 20 行，§9 R7）。

### 5.7 文案与 i18n

新增 ARB 键（5 个语言文件同步：`app_en.arb`、`app_zh.arb`、`app_zh_Hans.arb`、`app_zh_Hant.arb`、`app_ja.arb`），均为纯增量，桌面既有键不变：

- `audioBadgeEngineBlockedTooltip`：浏览器已阻止音频播放
- `audioBadgeEnableAudio`：启用声音
- `audioBadgeWebBlindSpotHint`：浏览器无法检测系统音量；若仍无声，请检查系统与标签页是否静音。

`lib/l10n/generated/` 由 `flutter gen-l10n` 重新产出（[`l10n.yaml`](../../l10n.yaml)）。

### 5.8 设置页一致性（共享文件唯一改动）

- `PlatformCapabilities` 增加 `supportsAudioOutputMonitoring`：桌面 `true`，web `false`（沿用现有能力位风格，[`capabilities.dart`](../../lib/platform/capabilities.dart#L8-L27)）。业务代码仍不直接判断 `kIsWeb`。
- `_AudioPanel` 在该能力为 `false` 时**隐藏** `_LowVolumeWarningSwitch` 及其间距（[`settings_sheet.dart`](../../lib/ui/main_page/settings_sheet.dart#L586-L589)、#L688-L725）。桌面分支渲染结果与现在逐像素一致；已存设置值保留，切回桌面仍生效。
- “播放试音”行保留：web 上它是唯一可靠的“是否真的能听到”自测手段。

---

## 6. 文件改动清单

| 文件 | 类型 | 桌面影响 |
|---|---|---|
| `lib/platform/audio/audio_monitor_ui_web.dart` | 重写 | 无（原本为空实现） |
| `lib/platform/audio/web/web_audio_monitor.dart` | 新增 | 无 |
| `lib/platform/audio/web/web_audio_signals.dart` | 新增 | 无 |
| `lib/platform/audio/web/web_audio_alert_source.dart` | 新增 | 无 |
| `lib/platform/audio/web/web_audio_status_badge.dart` | 新增 | 无 |
| `lib/platform/audio/web/web_audio_alert_toaster.dart` | 新增 | 无 |
| `lib/platform/audio/web/web_audio_copy.dart` | 新增 | 无 |
| `lib/platform/audio/audio_bootstrap_web.dart` | 修改 | 无（web 专用） |
| `lib/platform/capabilities.dart` | 修改（纯增量） | 无（桌面返回 true） |
| `lib/ui/main_page/settings_sheet.dart` | 修改（条件渲染） | 无（桌面分支不变） |
| `lib/l10n/*.arb`（5 份）+ `lib/l10n/generated/*` | 修改/生成 | 无（仅新增键） |
| `test/platform/audio/web_audio_monitor_test.dart` | 新增 | 无 |
| `test/ui/web_audio_status_badge_test.dart` | 新增 | 无 |

**明确不改**：`audio_output_monitor.dart`、`audio_output_probe.dart`、`audio_alert_state.dart`、`audio_monitor_ui_native.dart`、`audio_monitor_ui.dart`、`audio_bootstrap_native.dart`、`audio_status_badge.dart`、`audio_alert_toaster.dart`、`audio_preflight_dialog.dart` 及全部桌面测试。

---

## 7. 状态机

```text
notAttempted ──(首次手势，init 成功)──► none ⇄ engineBlocked
      │                                   ▲            │
      │(init 失败)                        │(上下文 running
      ▼                                   │ /引擎恢复)
engineBlocked ◄──(上下文 suspended/closed)┘
      │
      └──(用户点“启用声音”，retry 成功)──► none
```

| 转移 | 条件 | 去抖 |
|---|---|---|
| `none → engineBlocked` | 初始化失败 / 上下文 suspended、closed / 引擎未初始化（已尝试过） | 硬进入，立即 |
| `engineBlocked → none` | 引擎就绪且上下文 running | 600ms 静默窗口 |
| 任意 → 不变 | 页面不可见 | 不采样 |
| `notAttempted → none` | 首次手势前 | 无 badge |

---

## 8. 测试计划

### 8.1 单元测试（VM 可跑）

- `web_audio_monitor_test.dart`：注入假信号与假时钟，逐条覆盖 §5.2 判定表；不可见不采样；上下文不可读时静默降级；600ms 退出窗口；`retry()` 单飞与成功/失败两条路径。
- 边界：`initState` 从 `notAttempted` 直接到 `failed`；`ready` 后引擎读数抛异常按未知处理（不误报）。

### 8.2 Widget 测试（VM 可跑）

- `web_audio_status_badge_test.dart`：注入假 `WebAudioAlertSource`，断言 `Key('audioStatusBadge')` 的出现/消失、图标、弹层标题与“启用声音”回调、重试进行中禁用。
- `WebAudioAlertToaster`：非 running 不播报、running 下 `none → engineDown` 播报一次、恢复后再异常可再播报（可在同一测试文件中用假 source 覆盖）。

### 8.3 手动验证矩阵（Chrome 桌面，基线）

| # | 场景 | 期望 |
|---|---|---|
| 1 | 首次打开页面，未点击 | 无 badge、无 toast |
| 2 | 首屏点击任意位置 | 引擎初始化日志出现 `ready`；无 badge |
| 3 | 站点声音被禁用（chrome://settings/content/sound）后点 RUN | badge 出现，文案为“浏览器已阻止音频播放”；现有 `audioUnavailable` toast 同时出现 |
| 4 | 恢复站点声音并点“启用声音” | badge 在 600ms 内消失；无残留弹层 |
| 5 | 训练中切到后台再回来 | 不因后台挂起误报；若恢复后仍 suspended，可见 600ms 后出现 badge |
| 6 | 刷新页面 | 回到场景 1 行为 |
| 7 | 设置页音频分区 | 无“低音量时提示”开关；试音行可点击且能出声 |

### 8.4 桌面回归（证明冻结）

- `flutter analyze` 零新增告警。
- 全量单元/widget 测试全绿，且**不修改任何既有测试文件**。
- macOS 冒烟：badge 四类文案、toast、E1 预检、试音与现版本逐项一致。
- `flutter build web` 成功（`dart:io` 实现由条件导入在 web 编译期排除，编译通过即是证明）。

---

## 9. 风险与回退

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | `window.miniaudio.devices[0].webaudio.state` 是 flutter_soloud 依赖 miniaudio 的**内部路径**，非公开 API（`flutter_soloud-5.3.2/lib/src/bindings/js_extension.dart` L14-L15） | 升级插件后可能读不到 | 受控读取 + `try/catch`，读不到按 `null` 处理（静默降级）；升级 `flutter_soloud` 时把该路径列入核对清单 |
| R2 | 读到 `running` 但实际无声（系统静音/音箱未开） | 漏报 | 已知能力边界；由设置页试音兜底，弹层文案明确“浏览器无法检测系统音量” |
| R3 | 页面恢复可见瞬间上下文仍 suspended | 误报 | 只在可见时采样 + 300ms 延迟 + 600ms 静默窗口 |
| R4 | 初始化/重试并发 | 重复初始化或状态错乱 | 单飞保护；重试必须来自手势 |
| R5 | Safari/Firefox 行为差异 | 可能无法读出上下文状态 | 降级为仅看 `isInitialized`；最坏情况不显示 badge，不产生误报 |
| R6 | 新增能力位与设置页条件渲染 | 桌面渲染意外变化 | 桌面分支返回 `true`，渲染路径不变；靠全量 widget 测试与 macOS 冒烟把关 |
| R7 | web 与桌面的 badge/toast/播报逻辑重复，后续可能漂移 | 两端体验不一致 | 相同 `Key('audioStatusBadge')`、相同尺寸/颜色/阈值常量；在 web 文件头注释指向桌面实现；改动任一端时同步核对另一端 |

回退策略：`audio_monitor_ui_web.dart` 是唯一 web 装配点，若 R1/R5 在真机不可接受，可整体退回 `SizedBox.shrink()`；由于桌面未改动，回退零风险。

---

## 10. 实施顺序

1. `audio_bootstrap_web.dart`：初始化状态 notifier + `retryAudioInitialized()`（web 独立，先打通可测状态源）。
2. `WebAudioMonitor` + 假信号单测（判定表、去抖、单飞）。
3. `WebAudioSignals`：SoLoud、上下文状态、可见性、初始化通知的 js 适配。
4. `WebAudioStatusBadge` / `WebAudioAlertToaster` + widget 测试（与桌面同形、同 Key）。
5. 重写 `audio_monitor_ui_web.dart` 装配（单例、start/stop/dispose、预检保持 `true`）。
6. 能力位与设置页隐藏；5 份 ARB + `flutter gen-l10n`。
7. 验证：`flutter analyze`、全量测试、`flutter build web`、Chrome 手动矩阵、macOS 冒烟。

---

## 11. 已定决策与遗留

已定：D1–D9（§4.2）。其中 D1 为硬约束：**桌面端逻辑保持原样**。

遗留（不阻塞本期）：

- web 端是否需要在“引擎被阻止”时也弹一次非阻断确认（当前仅 badge + toast + RUN 失败 toast）。
- 若后续 `flutter_soloud` 暴露公开的 AudioContext 状态 API，应替换 R1 的内部路径。
- 若未来桌面也愿意接受接口抽取，可把 web 的 badge/toast 合并回共享实现，消除 R7；本期不做。
