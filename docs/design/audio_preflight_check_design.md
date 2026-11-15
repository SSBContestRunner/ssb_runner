# 音频输出实时检测与界面提示设计

> 状态：已定稿 v5（2026-11-14 定 v4；2026-11-15 按[性能评审](audio_output_probe_performance_design.md)更新 §2.2、§4.1、§4.2.1 的设备存在性判据，D1–D8 方向不变）
> 分支：待定
> 范围：系统音频输出（音量/静音/设备）的实时检测、界面 badge 提示；不涉及赛制、计分、数据库与复盘数据结构
> 关联：[`audio_player.dart`](../../lib/audio/audio_player.dart)、[`audio_engine.dart`](../../lib/audio/audio_engine.dart)、[`audio_output_probe_performance_design.md`](audio_output_probe_performance_design.md)（采样开销与判据来源）、[`desktop_exit_design.md`](desktop_exit_design.md)

---

## 0. 需求边界（先读这一节）

本文档包含两部分，**优先级与归属不同，不可混为一谈**：

| 类别 | 内容 | 来源 |
|---|---|---|
| **原始需求（P0，必须做）** | **实时检测音量**；检测到问题（静音/过低/无设备/引擎未就绪）时，在界面上显示**一个小 badge** 提示 | 用户原话："要求的是实时检测音量，如果有问题，需要在界面提示（一个小 badge 即可）" |
| **加强需求（确定实施，但必须排在原始需求之后）** | E1 开始前阻断式预检（全部异常 + 低音量可不再提示）；E2 **设置页独立试音功能（原"第 3 段"）**；E3 运行中异常提示（复用项目统一 notification） | 设计方提出，**不是用户原始需求**；用户确认："也要实施，只不过要在实现原始需求之后再实现" |

原始需求的判定标准只有三条：实时、有问题要提示、提示形态是一个小 badge。**不包含**弹窗阻断、不包含试音、不包含必须点击确认才能开赛。

加强需求集中在第 5 节，**实施顺序是硬约束**：

1. 先完成 P0（第 4 节）并通过验收；
2. 再按 E2 → E3 → E1 的顺序实施（E1 会改变开赛交互，放在最后；阻断范围已定为全部异常，真机反馈只用于微调阈值与文案）；
3. E 阶段的任何改动不得回退或削弱 P0 的"不打断训练"性质。

第 9 节的 5 项待确认已于 2026-11-14 全部决策（见 §9）；E1 在此基础上对低音量额外提供【低音量时不再提示】能力（见 §5 E1）。同日第二轮评审又补充 D6–D8：E2 试音不套用来台音量、不检测应用内音量、监测层装配与详情弹层形态（见 §4.1.1、§2.2、§4.4.2、§5 E2）。

---

## 1. 结论摘要

| # | 结论 |
|---|---|
| 1 | 现状是点 RUN 直接开赛，全程没有任何音频输出检测；系统静音、音量过低、设备错误、引擎未初始化都会让整局无声 |
| 2 | 引擎未就绪时 `AudioPlayer` 静默丢段，比赛照常计时、状态机照常推进，用户只会觉得"软件卡住/没声音" |
| 3 | 原始需求的落点是**常驻监测 + 顶栏小 badge（仅异常时出现）**，不做阻断、不做试音 |
| 4 | 检测覆盖三层：系统静音/音量、输出设备、引擎就绪；读取失败一律视为 `unknown`，**不报警**，避免误报比不报更糟 |
| 5 | 软件无法判断"人耳是否真的听到"（蓝牙音箱断电、HDMI 路由、音箱旋钮到底）；这类盲区交给加强需求 E2 的**设置页试音**由用户自行验证，因此 E2 是独立加强需求而非原始需求 |
| 6 | P0 需要平台能力：macOS CoreAudio、Windows WASAPI、Linux `pactl`/`wpctl`；正常路径零额外点击、正常态零常驻占位（异常出现时有一次 40dp 位移，已接受） |
| 7 | 加强需求 E1/E2/E3 与 P0 共用同一套探测与裁决层；三项均确定实施，但**必须排在 P0 之后**，按 E2 → E3 → E1 推进；E1 范围为全部异常阻断，仅低音量提供【不再提示】 |

---

## 2. 问题与动机

用户反馈：开始比赛时没有对音量做任何检测。若系统音量过低或静音，用户整局听不到呼叫音频，只会困惑"是不是软件坏了/状态机卡住了"。

本应用的核心训练内容是"听"，音频输出不可用等于训练完全失效。

### 2.1 当前链路（已核实）

1. 点击 RUN（idle 态）：`_RunButton.onPressed` 直接调用 `manager.startContest()`（[`session_panel.dart`](../../lib/ui/main_page/session_panel.dart#L1037-L1069)），无任何音频检查。
2. `startContest()` 把设置里的 `audioVolume` 写进训练档案后启动播放（[`contest_manager.dart`](../../lib/contest_run/new/contest_manager.dart#L337-L350)）。
3. `audioVolume` 只是**应用内增益**，被钳制在 0.2–1.2（[`app_settings.dart`](../../lib/settings/app_settings.dart#L177-L180)），与系统音量、静音、输出设备完全无关。
4. 引擎初始化失败只记录日志、不阻断启动（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L640-L662)）。
5. 引擎未就绪时 `AudioPlayer._startSegment` 直接丢段并 `log.warn`（[`audio_player.dart`](../../lib/audio/audio_player.dart#L273-L280)），状态机继续推进。

### 2.2 需要检测的异常

| 编号 | 异常 | 检测手段 | 用户表现 |
|---|---|---|---|
| A | SoLoud 引擎未初始化/初始化失败 | `isInitialized` | 全程无声，计时与状态机正常 |
| B | 无可用输出设备 | 平台 `hasDevice`（默认输出端点）/ `getAudioDeviceState()` | 全程无声 |
| C | 系统静音或主音量接近 0 | 平台 API（CoreAudio / WASAPI / pactl） | 全程无声或听不清 |

**不检测应用内来台音量（D7）**：`AppSettings.audioVolume` 是应用内增益，已被钳制在 0.2–1.2，且用户在设置页能直接看到滑块位置；把它纳入检测只会与系统音量混淆，因此不产生任何 badge 或状态。

### 2.3 软件侧的检测边界

系统音量 API 只能回答"系统认为音量是多少"，不能回答"声音是否到达耳朵"。以下情况所有 API 都显示正常：

- 输出切到没有扬声器的 HDMI 显示器；
- 蓝牙音箱已配对但未开机；
- 有源音箱电源关闭或旋钮拧到底；
- 耳机插在前级但主板未连接；
- 音频资源缺失导致合成 PCM 为空。

这个边界决定了**原始需求只能做到"能听得到的机会很低时提醒"**，无法承诺"一定听得到"。补足手段属于加强需求 E2（设置页独立试音，不参与开赛流程），见第 5 节。

---

## 3. 目标与非目标

### 3.1 目标（原始需求）

1. 应用运行期间**实时**监测系统音频输出状态（含待机与比赛进行中）。
2. 检测到异常时，在界面上显示一个**小 badge**，不打断任何操作、不弹窗、不阻断开赛。
3. 异常恢复正常后，badge 自动消失，无需用户操作。
4. 平台能力缺失或读取失败时**不显示 badge**，静默降级，绝不误报。
5. 检测开销可忽略：不引起界面掉帧、不产生日志洪水、不增加启动时间。
6. 三平台（macOS / Windows / Linux）行为一致，文案覆盖 5 种语言。

### 3.2 非目标（原始需求不做）

- 不弹阻断式对话框，不要求用户确认才能开始比赛（该能力属于加强需求 E1，P0 之后实施）。
- 开局流程不播放试音、不做人耳确认；试听能力放在设置页由用户主动触发（E2，P0 之后实施）。
- 不修改系统音量、不静音、不自动切换输出设备。
- 不引入麦克风/录音检测（需要权限、有回声反馈、且无法区分"听到"）。
- 不影响现有暂停/恢复语义：恢复走 3-2-1，不重新检测。

---

## 4. 详细设计（原始需求）

### 4.1 方案总览

```
应用就绪
   │
   └─ AudioOutputMonitor（常驻）
        │  事件驱动优先，轮询兜底
        ├─ 引擎：SoLoud.isInitialized
        ├─ 设备：hasDevice（默认输出端点）/ getAudioDeviceState
        └─ 系统：音量 + 静音（平台适配层，失败即 unknown）
             │
             ▼
        AudioOutputStatus（不可变快照）
             │  去抖 + 迟滞
             ▼
        AudioAlertState { none | low | muted | noDevice | engineDown }
             │
             ▼
        顶栏 badge（仅异常时高亮）+ 点击查看详情
```

监测层是纯后台服务，不持有 UI、不依赖 `ContestManager`；badge 只是它的一个订阅者。这样加强需求 E1/E2 可以复用同一份状态，不必重写探测。

#### 4.1.1 装配、生命周期与可见性

监测层必须覆盖待机（打开应用、未开赛时也要提示），所以所有权放在应用根，而不是 badge 或页面：

| 事项 | 决策 |
|---|---|
| 创建 | `_MainAppState` 持有唯一实例（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L42-L57)），通过 `RepositoryProvider<AudioOutputMonitor>.value` 放进顶层的 `MultiRepositoryProvider`（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L340-L349)）；badge 只订阅，不自行创建 |
| 启动 | `_BootGateState._start()` 在 `load()` 正常返回且 `mounted` 后调用 `start()`（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L438-L461)）。此时 `await audioReady` 已完成、`_Ready` 已发出，引擎初始化已 settled；启动失败或退出中止则不启动 |
| 状态出口 | 单个 `ValueNotifier<AudioMonitorSnapshot>`（异常枚举 + 原始读数 + 原因 + 窗口是否可见），沿用项目已有的 `ValueListenableBuilder` 写法（[`app_topbar.dart`](../../lib/ui/main_page/app_topbar.dart#L90-L96)） |
| 停止 | `_MainAppState.dispose()`，以及退出路径 `_handleExitRequest` 在 `_audio.settledWithin` 之前调用 `stop()`（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L136-L166)），保证探测不与 `deinitAsync()` 并发 |
| 幂等 | `start()` / `stop()` 可重复调用：重复启动不注册第二份监听、不建第二个 timer；停止后不再产生状态 |
| CI 禁用 | `SSB_RUNNER_DISABLE_AUDIO=1` 时 `start()` 直接进入 `disabled`，不注册监听、不建 timer、不产生状态，只留一条 warn（§4.2.1） |
| 依赖方向 | 监测层不引用 `ContestManager`、`AppSettings` 或任何 Widget；E3 的 toast 订阅放在页面层 |

**可见性判据**（决定兜底轮询是否降频到 10s）：

- 复用 [`window_geometry.dart`](../../lib/ui/main_app/window_geometry.dart#L53-L58) 的 `resolveAppWindow()` 取窗口句柄，不新起一套窗口发现逻辑；
- 窗口可用时用 `Window.addListener` 订阅 `WindowMinimizedEvent`、`WindowRestoredEvent`、`WindowOcclusionChangedEvent`（[`window_geometry.dart`](../../lib/ui/main_app/window_geometry.dart#L53-L70) 已在用 window_manager 0.6 的 `Window` 句柄）；
- 取不到窗口、注册失败或平台不产生对应事件时，退化为在轮询里读 `window.isMinimized`；`WindowOcclusionState.unknown` 一律视为可见，绝不据此判定"不可见"；
- 从不可见恢复可见时立刻补采一次，并把轮询间隔恢复为 2s / 3s。

### 4.2 探测源

#### 4.2.1 引擎与设备（纯 Dart，零原生代码）

使用 flutter_soloud 5.2 已有能力（当前锁定 5.2.3，`pubspec.yaml` 约束 `^5.1.5`），不新增依赖：

| 探测项 | API | 判定 |
|---|---|---|
| 引擎就绪 | `SoLoud.instance.isInitialized` | false → 异常 A |
| 输出设备存在 | 平台 probe 的 `hasDevice`（默认输出端点） | false → 异常 B；null（读不到）→ 不报警 |
| 设备交付状态 | `getAudioDeviceState()` | **仅 `uninitialized` 视为异常** |

**决策（P-1，2026-11-15）：不再调用 `listPlaybackDevices()`。** 该调用是同步 FFI，每次约 0.6ms 且直接在 UI isolate 上执行（成本 99% 花在逐设备读显示名，而代码只用 `.length`），只换来一个比 `hasDevice` 更弱的判据。设备存在性改由 macOS/Windows 的默认输出端点探测回答；Linux 在默认 sink 解析为空时置 `hasDevice = false`。详见 [`audio_output_probe_performance_design.md`](audio_output_probe_performance_design.md) §5。

**关键约束**：`getAudioDeviceState()` 返回 `stopped` 是正常状态。SoLoud 5.x 在 500ms 无活跃 voice 后会挂起输出设备（[`audio_player.dart`](../../lib/audio/audio_player.dart#L13-L17) 已记录），把 `stopped` 当作故障会导致每次空闲都误报。

CI 冒烟通过 `SSB_RUNNER_DISABLE_AUDIO=1` 跳过引擎初始化（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L630-L662)）。此时监测必须识别为"环境禁用"并整体关闭，不显示 badge、不写 error 日志，否则 macOS/Linux 冒烟会出现意外 UI 差异（关闭方式见 §4.1.1）。

#### 4.2.2 系统音量与静音（平台适配层）

定义统一接口，返回值全部可空，用 `unknown` 表达"本次无法判定"：

```
AudioOutputStatus {
  bool?    hasDevice;
  String?  deviceName;
  double?  volume;     // 0.0–1.0，主输出
  bool?    muted;
  Source   source;     // coreAudio | wasapi | pactl | wpctl | unsupported | error
}
```

**macOS**

- `macos/Runner` 新增 Swift 实现，由 `MainFlutterWindow` 注册 `MethodChannel`。
- 默认输出设备：`kAudioHardwarePropertyDefaultOutputDevice`。
- 音量/静音：`kAudioDevicePropertyVolumeScalar`（output scope）、`kAudioDevicePropertyMute`。
- 只暴露虚拟主音量的设备回退 `kAudioHardwareServiceDeviceProperty_VirtualMasterVolume`；都不支持则 `unknown`。
- **禁止用 `Process` 调 `osascript`**：Release 构建开启 App Sandbox（[`Release.entitlements`](../../macos/Runner/Release.entitlements)），子进程与 AppleScript 在沙箱下不可靠。

**Windows**

- `windows/runner` 新增 `audio_output_probe.cpp`，由 `flutter_window.cpp` 注册 channel。
- WASAPI：`MMDeviceEnumerator::GetDefaultAudioEndpoint(eRender, eConsole)` → `IAudioEndpointVolume::GetMasterVolumeLevelScalar` / `GetMute`。
- 注意 COM 初始化/反初始化与接口释放；任一环节失败返回 `unknown`，不得把异常抛到 Dart 侧。
- `windows/runner/CMakeLists.txt` 补 `ole32` 链接。

**Linux**

- 不加原生代码，`Process.run` 调 `pactl --format=json list sinks` 一次读出音量与静音；多 sink 时再用 `--format=json info` 解析默认 sink（[性能改造](audio_output_probe_performance_design.md) §5 I）。PipeWire 回退 `wpctl get-volume`。
- 非零退出码或文本无法解析即 `unknown`；命令成功但默认 sink 缺失（无 sink，或默认名对不上）视为 `hasDevice = false`；Debian 冒烟容器通常没有音频栈，必须安静降级。

### 4.3 实时监测机制

#### 4.3.1 采样方式

| 平台 | 主路径（事件驱动） | 兜底（轮询） |
|---|---|---|
| macOS | `AudioObjectAddPropertyListenerBlock` 监听默认设备、音量、静音属性 | 2s |
| Windows | `IAudioEndpointVolume::RegisterControlChangeNotify` + `IMMNotificationClient`（设备变更） | 2s |
| Linux | `pactl subscribe` 长驻进程，解析 sink 事件 | 3s |

**决策（D3，2026-11-14）：P0 直接实现事件驱动，轮询作为兜底。** 两条路径共用同一 `AudioOutputProbe` 接口；事件回调只负责"叫醒"监测层，真正的状态读取仍走同一份采样与裁决代码，避免两套逻辑漂移。

兜底触发条件：

- 监听器注册失败（平台不支持、权限或沙箱限制）；
- 每 60s 做一次健康检查：主动读一次状态，若与最近一次事件值不一致，说明监听链路已失效，切回轮询；
- Linux `pactl subscribe` 进程退出且重启失败。

轮询兜底间隔与代价：
- macOS/Windows 原生属性读取是微秒级，2s 一次可忽略；
- Linux 每轮需 fork 一个进程，代价约 5–15ms，因此间隔取 3s；
- 应用窗口不可见/最小化时，兜底轮询降频到 10s；事件驱动不受影响，恢复可见后立刻补采一次（可见性判据与装配见 §4.1.1）。

#### 4.3.2 去抖与迟滞

避免 badge 在阈值附近闪烁：

- 事件驱动路径：事件到达后等 **600ms 静默窗口**再复核一次，避免拖动音量滑块时 badge 闪烁；复核命中才切换；
- 轮询兜底路径：仍用连续 2 次采样命中（2s × 2 ≈ 4s）；
- 退出异常：与进入对称，连续 2 次正常或一个 600ms 静默窗口；
- 静音与"无设备"属于硬状态，可立即生效；
- badge 的显隐**不做动画位移**，只切换颜色/图标，避免吸引过多注意力；D2 决策为"正常态隐藏"，插入时会有一次 40dp 位移，这是已接受的代价，不再额外加动画。

#### 4.3.3 状态机

```
none ──(静音)──────────► muted
none ──(音量 < 10%)────► low
none ──(无设备)────────► noDevice
none ──(引擎未就绪)────► engineDown
  ▲                          │
  └──────(恢复正常)──────────┘
unknown 不产生任何状态变化（保持 none）
```

`unknown` 的语义是"降低置信度"，不是"故障"：读取失败**不得**升级为任何 badge。

### 4.4 界面：badge 的位置与交互

#### 4.4.1 位置

放在顶栏右侧、主题切换与设置按钮之间（[`app_topbar.dart`](../../lib/ui/main_page/app_topbar.dart#L68-L132)）：

- 复用现有 `IconButton` 40×40 尺寸与 `Stack` 角标写法（设置按钮的 `settingsIssueBadge` 已有 8px 圆点先例，[`app_topbar.dart`](../../lib/ui/main_page/app_topbar.dart#L113-L128)）。
- **决策（D2）：正常态完全不显示**，异常时才插入 `volume_off_outlined` + 8px 圆点（`scheme.error`），恢复正常后移除。代价是出现/消失时右侧设置按钮整体位移 40dp；这是评审明确接受的取舍，换取正常态更干净的顶栏。
- 因为正常态没有占位，badge 必须可点击展开详情，不能只依赖 tooltip，否则用户看到图标时无从确认原因。
- 不进入会话卡片头部：该区域已承担"设置就绪 chip + 复盘胶囊"，再加元素会挤压 1108dp 宽度下的布局预算（[`session_panel.dart`](../../lib/ui/main_page/session_panel.dart#L171-L225) 有明确的宽度分配逻辑）。

#### 4.4.2 交互

- Hover：Tooltip 显示具体原因，如"系统已静音 / 音量 8% / 未检测到输出设备"。
- 点击：弹出轻量详情（`AlertDialog`，与项目其他轻量对话框写法一致），内容为原因 + 当前音量百分比 + 设备名 + `[打开系统声音设置]` + `[关闭]`。
- 打开系统声音设置：macOS `x-apple.systempreferences:com.apple.Sound-Settings.extension`；Windows `ms-settings:sound`；Linux 尝试 `pavucontrol`，打不开则仅保留文字指引。
- 无障碍：`Semantics(liveRegion: true)`，状态变化时读屏播报；笔误不打断焦点，不抢键盘输入。

#### 4.4.3 文案（5 份 ARB）

`app_en` / `app_zh_Hans` / `app_zh_Hant` / `app_zh` / `app_ja` 各新增：

- `audioBadgeMutedTooltip`：`系统输出已静音，将听不到呼叫音频`
- `audioBadgeLowTooltip`：`系统音量仅 {percent}%，可能听不清呼叫音频`
- `audioBadgeNoDeviceTooltip`：`未检测到可用的音频输出设备`
- `audioBadgeEngineDownTooltip`：`音频引擎未启动，本局不会有声音`
- `audioBadgeOpenSoundSettings`：`打开系统声音设置`
- `audioBadgeVolumeLabel`：`当前音量 {percent}%`

### 4.5 运行期间的行为

- 比赛进行中 badge 依然工作：用户中途调低音量或切换设备，事件驱动路径 1s 内出现提示；监听失效走轮询兜底时 2–4s 内出现。
- **默认只提示、不弹窗、不暂停**，不打断当前输入与状态机。
- 运行中由正常转为异常时的额外提醒属于加强需求 E3（第 5 节），P0 不实现；P0 期间只靠 badge 自身变化表达。
- 暂停态（含 3-2-1 恢复窗口）检测照常运行；恢复流程本身不触发任何新的提示。

### 4.6 日志

新增 `tag: 'audio.monitor'`，**只在状态跃迁时记录**，不按采样周期打印：

- `info`：`{from, to, volume, muted, device, source}`；
- `warn`：`engineDown` 与 `noDevice`；
- `unknown` 只记录一次（首次降级），避免日志洪水。

---

## 5. 加强需求（确定实施，排在 P0 之后）

> 以下三项均为设计方提出的附加能力，**不是用户原始需求**。已确认全部实施，但**必须等 P0 完成并通过验收后再动**，实施顺序为 E2 → E3 → E1。

### E2：设置页独立试音（原"第 3 段"）

> 该段此前被误当作原始需求的一部分；现明确：**它是一个独立的设置功能，不是用户要求，也不参与开赛流程**。

**定位：设置 → 声音分区里的一个小功能，可随时手动触发的试听。**

**决策（D4，2026-11-14）：按本节方案执行——优先固定真实片段，加载/解码失败退化为生成双音。**
**决策（D6，2026-11-14）：试音不套用来台音量，直接播放；音量由用户凭听感自行调整。**

- 位置：`_AudioPanel` 的"来台音量"滑块下方新增一行 `_ListRow` 风格的"播放试音"入口（[`settings_sheet.dart`](../../lib/ui/main_page/settings_sheet.dart#L537-L577)），与现有"练习种子"等行保持一致。
- 行为：点击后直接播放约 0.8 秒片段，**不乘来台音量增益**；播放中按钮短暂显示"播放中"并禁用，防止叠加；可反复点击复听。用户觉得太响或太轻时，直接调系统音量或"来台音量"滑块后重听。
- **不阻断比赛、不出现在开局流程、不弹确认框、不写入比赛会话**。用户是否试听完全自主。
- 播放路径：`AudioCheckService` 复用 `AudioEngine.createSegment()`（[`audio_engine.dart`](../../lib/audio/audio_engine.dart#L41-L75)），**不经过 `AudioPlayer` 队列**——未开局时播放器处于 `_stopped`。来台音量是在 `AudioTrainingEffects` 的 PCM 层乘上去的（[`training_profile.dart`](../../lib/training/training_profile.dart#L172-L195)），`createSegment()` 本身没有音量参数，因此试音天然按素材原始电平播放，不需要额外接口。
- 素材：优先固定真实资源（顺带验证资源解码链路），加载失败退化为 800ms 双音（700Hz→1000Hz，30ms 淡入淡出）；两条路径都失败则用项目统一 notification 提示"音频播放失败"。
- 运行中设置抽屉本身是禁用的（`_AudioPanel` 的 `enabled` 取 `!MainSettingsCubit.state`，[`settings_sheet.dart`](../../lib/ui/main_page/settings_sheet.dart#L544)），因此不会与比赛音频冲突；若将来允许运行中打开设置，需要额外做互斥。
- 价值：覆盖 §2.3 的盲区（HDMI 路由、蓝牙断电、音箱旋钮到底），但**把判断权交给用户**，不做任何弹窗追问。

### E3：运行中异常提示（复用项目统一 notification）

- 使用项目现有统一通知 `toastification.show`，与 [`settings_sheet.dart`](../../lib/ui/main_page/settings_sheet.dart#L773-L806)、[`error_handling.dart`](../../lib/error_handling.dart#L95) 等调用点保持一致：`ToastificationStyle.fillColored` + `ToastificationType.warning` + 3–4 秒自动关闭。
- 触发条件：`AudioOutputMonitor` 状态从 `none` 转为 `muted / low / noDevice / engineDown`，且 `sessionPhase == running`。
- 同一局同一原因最多提示一次；状态恢复后计数清零，再次异常可再提示一次。
- 非模态、不抢焦点、不暂停、不影响键盘输入。
- 文案复用 badge 的 tooltip 文本，不新增第二套说法。

### E1：开始前阻断式预检（决策：全部异常阻断，仅低音量可不再提示）

**决策（D5，2026-11-14）：全部异常都阻断；只有低音量允许【低音量时不再提示】，其余原因始终提示。**

在 RUN 的 idle 分支，若监测层已处于异常状态，弹出阻断对话框：

| 状态 | 按钮 | 不再提示 |
|---|---|---|
| 静音 | `[打开系统声音设置]` / `[重新检测]` / `[仍然开始]` | 不提供 |
| 低音量（< 10%） | 同上 | **提供 Checkbox** |
| 无可用输出设备 | 同上 | 不提供 |
| 引擎未初始化 | `[重试]` / `[仍然开始]` | 不提供 |

**不再提示（仅低音量）**

- 只有低音量对话框底部提供 Checkbox `[ ] 低音量时不再提示`；静音、无设备、引擎未就绪一律不提供抑制入口，每次开赛都会阻断。
- 勾选后只有点 `[仍然开始]` 才写入设置（点关闭/取消不写入）。被抑制后，低音量不再弹阻断框，RUN 直接开赛；badge 与 E3 toast 照常工作。
- 持久化：`AppSettings` 新增 `audioPreflightLowVolumeWarning`（bool，默认 true）；关闭即等于勾选"不再提示"。
- 恢复入口：设置 → 声音分区新增 `低音量时提示` 开关（默认开）；与对话框 Checkbox 双向一致，随时可恢复。
- 新增 5 份 ARB 文案：`audioPreflightDontAskLowVolume`（低音量时不再提示）、`audioPreflightLowVolumeWarningLabel`（低音量时提示）、`audioPreflightLowVolumeWarningHint`（关闭后低音量不再阻断开赛）。

其他约束：

- 预检必须在 `startContest()` **之前**完成，不消耗比赛时间与第一道题。
- 顺带补上 RUN 按钮当前缺失的重入保护（[`session_panel.dart`](../../lib/ui/main_page/session_panel.dart#L1037-L1069) 无忙态，连点会触发两次 `startContest()`）。
- 放在 E 阶段最后实施，但阻断范围已不再是开放问题；真机反馈只用于调整阈值与文案。

---

## 6. 改动清单

### P0（原始需求）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `lib/audio/audio_output_probe.dart`（新） | 探测接口、平台工厂、`unknown` 实现 |
| 2 | `lib/audio/audio_output_monitor.dart`（新） | 事件驱动 + 轮询兜底的调度、去抖与迟滞、状态流 |
| 3 | `lib/audio/audio_alert_state.dart`（新） | 状态枚举与纯函数裁决（唯一需要密集单测的部分） |
| 4 | `lib/ui/main_page/audio_status_badge.dart`（新） | 顶栏 badge 与详情弹层（`AlertDialog`） |
| 5 | `lib/ui/main_app/main_app.dart` | `_MainAppState` 持有监测层并注入顶层 `MultiRepositoryProvider`；`_BootGate` 就绪后 `start()`；`dispose` 与退出路径 `stop()` |
| 6 | `lib/ui/main_page/app_topbar.dart` | 插入 badge（正常态隐藏，异常时插入；接受 40dp 位移） |
| 7 | `macos/Runner/*.swift` | CoreAudio 音量/静音探测 + 属性监听 + channel 注册 |
| 8 | `windows/runner/audio_output_probe.cpp`（新）、`flutter_window.cpp`、`CMakeLists.txt` | WASAPI 探测 + 音量/设备变更通知 + channel 注册 |
| 9 | Dart 侧 Linux 实现 | `pactl` / `wpctl` 子进程解析 + `pactl subscribe` 长驻监听与进程回收 |
| 10 | 五份 ARB | badge 与详情文案 |
| 11 | 测试 | 裁决/去抖单测、装配与可见性单测、监听失效回退单测、Linux 解析单测、badge widget 测试 |

### 加强需求（P0 完成后再做，顺序 E2 → E3 → E1）

| # | 文件 | 改动 |
|---|---|---|
| E2 | `lib/audio/audio_check_service.dart`（新）、`lib/ui/main_page/settings_sheet.dart` | 设置 → 声音分区新增"播放试音"行，直接播放 0.8s 片段（不套用来台音量）；失败走统一 notification |
| E3 | `lib/ui/main_page/*`、`lib/audio/audio_output_monitor.dart` | 运行中异常跃迁触发 `toastification.show`，同一局同一原因一次 |
| E1 | `lib/ui/main_page/session_panel.dart` + 新对话框 + `lib/settings/app_settings.dart` + `settings_sheet.dart` | 全部异常阻断（仅低音量可不再提示）、`audioPreflightLowVolumeWarning` 设置、设置页开关、RUN 忙态与重入保护、5 份 ARB 文案 |

---

## 7. 测试与验收

### 7.1 自动化

- 裁决/去抖单测：静音 / 音量 0 / 音量 5% / 音量 20% / 无设备 / 引擎未就绪 / `unknown` / 恢复；断言 **`unknown` 永不产生 badge**、600ms 静默窗口不抖动。
- 监听回退单测：事件通道注册失败或健康检查发现事件值不一致时，监测层切到轮询且状态不跳变。
- 装配/生命周期单测：`start()`/`stop()` 幂等（重复启动不注册第二份监听、不建第二个 timer）；`SSB_RUNNER_DISABLE_AUDIO=1` 时不产生状态与周期日志；窗口不可见时轮询降频到 10s、恢复后立即补采，期间状态不跳变。
- Linux 解析单测：`pactl`、`wpctl` 正常与异常输出；`pactl subscribe` 事件行解析与进程退出重启。
- Widget 测试：异常状态插入 badge 与正确 tooltip；恢复后 badge 消失（顶栏回到无占位）；点击打开详情；正常态不存在 badge。
- 回归：`test/ui/main_page_layout_test.dart`、`test/audio/*` 全绿，`flutter analyze` 无新增告警。

### 7.2 手工验收（P0）

- 系统静音、音量拉到 0、音量 5%、插入/拔出输出设备，各验一次 badge 是否在 1s 内出现（事件驱动）并自动消失；再强制关闭监听，验证轮询兜底仍能在 4s 内出现。
- 比赛进行中调低音量，badge 出现且**不打断输入、不暂停、不弹窗**。
- 5 语言 × 1.0/1.3 字号 × 1108×796：顶栏仍为 64dp、标题正常省略、无溢出。
- `SSB_RUNNER_DISABLE_AUDIO=1` 启动时全程无 badge，macOS/Linux 冒烟保持通过。
- 待机挂机 10 分钟：CPU 占用无明显变化，日志无周期刷屏。

### 7.3 加强需求验收（P0 验收通过后）

- E2：设置 → 声音点"播放试音"能出声；播放中按钮禁用；试音音量**不随**"来台音量"滑块变化（凭听感调系统音量或滑块后重听）；引擎异常时弹出统一 notification 错误提示；确认试音**不会**触发任何比赛状态变化。
- E3：比赛进行中调低音量，出现一次 warning toast，同一局重复调低不再刷屏；恢复后再次异常可再提示一次。
- E1：静音状态下点 RUN 先出现阻断对话框，`[仍然开始]` 后恰好开始一局；连点 RUN 只开始一局。
- E1：勾选`低音量时不再提示`并 `[仍然开始]` 后，再次低音量 RUN 不再弹框；静音 / 无设备 / 引擎故障仍每次弹框；设置 → 声音打开`低音量时提示`开关后，低音量阻断重新出现。

---

## 8. 分期

| 期 | 内容 | 说明 |
|---|---|---|
| P0-a | 引擎/设备检测 + 顶栏 badge（异常时插入）+ 文案 + 测试 | 纯 Dart，零原生代码，先让 badge 可用 |
| P0-b | macOS CoreAudio / Windows WASAPI / Linux 音量探测 + 事件驱动 + 轮询兜底 | 让 badge 能反映"静音/音量低"，并满足 <1s 响应 |
| E2 | 设置页"播放试音" | P0 全部验收通过后的第一个加强需求 |
| E3 | 运行中异常提示（统一 notification） | 依赖 P0 的状态跃迁事件 |
| E1 | 开局阻断预检（全部异常 + 不再提示） | 最后实施，范围已定 |

顺序约束：P0 未全部完成前，不开始任何 E 项；E 阶段内部按 E2 → E3 → E1 推进。

---

## 9. 决策记录（2026-11-14）

原第 9 节 5 项待确认已全部决策，正文相应章节已按结论更新：

| # | 事项 | 决策 | 落点 |
|---|---|---|---|
| D1 | badge 位置 | **顶栏常驻图标**（主题与设置之间，40×40） | §4.4.1 |
| D2 | 正常态显示 | **正常态完全不显示**，异常时插入；接受出现/消失时 40dp 位移 | §4.4.1、§4.3.2 |
| D3 | 轮询间隔 | **P0 直接上事件驱动 + 轮询兜底**（macOS/Windows 2s、Linux 3s 兜底） | §4.3.1、§8 |
| D4 | 试音素材 | **固定真实片段，失败退化双音** | §5 E2 |
| D5 | E1 阻断范围 | **全部异常阻断**；仅低音量提供【低音量时不再提示】，静音/无设备/引擎故障始终提示 | §5 E1、§6 |
| D6 | 试音音量 | **不套用来台音量，直接播放**；用户凭听感自行调系统音量或滑块 | §5 E2 |
| D7 | 应用内音量（原异常 D） | **不检测**，不产生 badge 或状态 | §2.2 |
| D8 | 装配与弹层形态 | **`_MainAppState` 持有 + 顶层 `RepositoryProvider`**，就绪后启动、退出前停止；详情用 **`AlertDialog`**；可见性复用 `resolveAppWindow()` | §4.1.1、§4.4.2 |

补充需求（D5）：只有低音量允许"不再提示"；静音、无设备、引擎未就绪一律始终阻断，不提供任何抑制入口。设置页提供 `低音量时提示` 开关用于随时恢复。

已无待确认项。后续只保留"真机阈值 / 文案微调"这类实现期调整，不再改变 D1–D8 的方向。

### 9.1 性能评审补充（2026-11-15）

P0 实施后另做了一轮采样开销评审，结论落在独立文档 [`audio_output_probe_performance_design.md`](audio_output_probe_performance_design.md)（P-1…P-5）。与本设计的交点只有一条：**设备存在性不再用 `listPlaybackDevices()` 判断**，改用平台 `hasDevice`（macOS/Windows 默认输出端点；Linux 默认 sink）。badge 触发条件、阈值、文案、装配方式与 E1/E2/E3 均不变。
