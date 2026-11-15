# 音频输出探测的运行时开销分析与改造方案

> 状态：已实施（2026-11-15，P-1…P-5 全部按推荐方案决策，见 §9；A + F + G + H + I 已落地）
> 范围：`AudioOutputMonitor` 采样路径的运行时开销（同步 FFI、事件风暴、Linux 子进程），不涉及 badge 视觉、文案、赛制与计分
> 关联：[`audio_preflight_check_design.md`](audio_preflight_check_design.md)（P0 主设计）、[`startup_performance_design.md`](startup_performance_design.md)（同类实测文档写法）
> 结论一句话：**采样的常态开销可以忽略，唯一的真风险是每 2s 在 UI isolate 上同步执行一次设备枚举；删除它即可，不需要 isolate、不需要新增原生缓存。**
> 决策一句话：**实施 A + F + G + H + I——删除 `listPlaybackDevices()`，设备存在性改用平台 `hasDevice`；补事件节流、空闲期采样、慢采样记录与 Linux 单进程读取。**

---

## 1. 结论摘要

| # | 结论 |
|---|---|
| 1 | 启动耗时**不受影响**：监测层 `start()` 在首帧绘制之后、`load()` 与引擎初始化 settled 之后才调用，不在首帧路径上（[`main_app.dart`](../../lib/ui/main_app/main_app.dart#L483-L489)） |
| 2 | 常态采样开销可忽略：原生 probe 每次约 95 µs（平台线程，不占 Dart 帧预算），引擎侧两个 FFI 调用是原子读 |
| 3 | **唯一真风险**是 [`readSoLoudEngineStatus()`](../../lib/audio/audio_output_probe.dart#L348-L372) 里的 `listPlaybackDevices()`：同步 FFI，在 UI isolate 上直接执行，每次约 0.6 ms（本机实测），且**每 2s 一次**、事件到达时也会触发 |
| 4 | 该调用的成本 99% 花在“逐设备读显示名”上，而代码只用了 `.length`；它换来的信息（设备数是否为 0）比已有的 `hasDevice` 与 `deviceUninitialized` 判据**更弱** |
| 5 | 尾部风险不在平均值，而在：拖动音量滑块时的事件风暴（10–20 次/秒 × 0.6 ms，正好落在 UI 最忙的窗口）、驱动级阻塞（蓝牙/虚拟声卡异常时可阻塞几十至数百 ms 并直接卡帧）、与 `initEngine()` 的生命周期锁竞争 |
| 6 | 采纳组合：**A（删除枚举）+ F（事件节流）+ G（空闲期采样）+ H（慢采样可观测）+ I（Linux 单进程读取）**，不采纳 isolate 化（SoLoud 单例绑定主 isolate，只能隔离一半） |
| 7 | 改造后每次采样在 UI isolate 上的主动工作降到 ≤ 50 µs，且不含任何设备枚举；事件风暴下最多 3–5 次/秒 |

> 上述结论已于 2026-11-15 固化为决策：推荐方案整体采纳（A + F + G + H + I），P-1…P-5 见 §9，实施清单见 §7，实施顺序见 §6.3。

---

## 2. 现状链路（代码事实）

### 2.1 谁在什么时候采样

| 触发 | 代码位置 | 频率 |
|---|---|---|
| 周期轮询（兜底 + 健康检查） | [`_restartPollTimer()`](../../lib/audio/audio_output_monitor.dart#L338-L345) | 可见 2 s（Linux 3 s），隐藏 10 s |
| 平台事件唤醒 | [`_onProbeEvent()`](../../lib/audio/audio_output_monitor.dart#L201-L203) | 由原生属性监听决定，拖动音量时密集 |
| 事件后的静默复核 | [`_apply()`](../../lib/audio/audio_output_monitor.dart#L272-L278) | 事件采样后 600 ms 一次 |
| 启动首次采样 | [`start()`](../../lib/audio/audio_output_monitor.dart#L84-L102) | 1 次 |
| 窗口恢复可见补采 | [`_onVisibilityChanged()`](../../lib/audio/audio_output_monitor.dart#L191-L199) | 每次恢复 1 次 |

### 2.2 一次采样做了什么

```text
_sample(eventDriven)                      [audio_output_monitor.dart#L219-L241]
  ├─ _refreshVisibility()                 读 window.isMinimized（Dart 侧，纳秒级）
  ├─ await _probe.read()
  │    ├─ macOS/Windows: MethodChannel 'read'  → 平台线程
  │    │    ├─ defaultOutputDevice()      CoreAudio 属性读      13 µs
  │    │    ├─ outputVolume()             最多 3 次属性读        57 µs
  │    │    ├─ outputMuted()              最多 2 次属性读
  │    │    └─ deviceName()               1 次属性读（CFString）
  │    └─ Linux: Process.run × 3（volume / mute / default-sink），失败再 wpctl × 1
  └─ _readEngine()                        [audio_output_probe.dart#L348-L372]
       ├─ SoLoud.instance.isInitialized   FFI isInited()（原子读）
       ├─ listPlaybackDevices()           ✱ 同步 FFI，设备枚举（本次分析的对象）
       └─ getAudioDeviceState()           FFI 原子读（原生注释明确为 cheap 查询）
```

### 2.3 `listPlaybackDevices()` 为什么贵

三层放大，逐层确认：

1. **Dart 侧**：每次调用 `calloc` 255 个指针 + 50×2 个指针数组，逐设备 `strdup` 名称，返回后再 `free`（[`bindings_player_ffi.dart`](../../../../.pub-cache/hosted/pub.dev/flutter_soloud-5.2.3/lib/src/bindings/bindings_player_ffi.dart#L577-L596)）。
2. **C++ 侧**：`Player::listPlaybackDevices()` 调 `miniaudio_listPlaybackDevices()`（[`player.cpp`](../../../../.pub-cache/hosted/pub.dev/flutter_soloud-5.2.3/src/player.cpp#L612-L635)）。
3. **miniaudio 侧**：即使引擎已初始化也**不读缓存**，而是调 `ma_context_get_devices()` → 每次重新执行 `onContextEnumerateDevices`；CoreAudio 后端对每个设备要读 uid、名称、播放能力（[`miniaudio.h`](../../../../.pub-cache/hosted/pub.dev/flutter_soloud-5.2.3/src/soloud/src/backend/miniaudio/miniaudio.h#L34701-L34746)）。

另外，整个过程持 `gDeviceOperationMutex`，而 `initEngine()` 在 worker 线程持同一把锁（[`soloud_miniaudio.cpp`](../../../../.pub-cache/hosted/pub.dev/flutter_soloud-5.2.3/src/soloud/src/backend/miniaudio/soloud_miniaudio.cpp#L1020-L1045)）。

**关键差异**：原生 probe 的 CoreAudio 调用跑在**平台主线程**，Dart 侧只是 `await`，不占 Dart 帧预算；而 `listPlaybackDevices()` 是 FFI，**直接在 UI isolate 上同步执行**。这是两者风险量级不同的根本原因。

### 2.4 这个信息是否必要

[`classifyAudioAlert()`](../../lib/audio/audio_alert_state.dart#L129-L150) 的 noDevice 判定有三条：

| 判据 | 来源 | 语义 |
|---|---|---|
| `engine.playbackDeviceCount == 0` | `listPlaybackDevices()` | “系统里一个播放设备都没有” |
| `status.hasDevice == false` | 原生 probe（CoreAudio 默认输出设备 / WASAPI 默认端点） | “**没有可用的默认输出端点**” |
| `engine.deviceUninitialized` | `getAudioDeviceState()` | “引擎的输出设备处于未初始化” |

macOS/Windows 的 `hasDevice` 直接调用 `GetDefaultAudioEndpoint` / `kAudioHardwarePropertyDefaultOutputDevice`（[`audio_output_probe.cpp`](../../windows/runner/audio_output_probe.cpp#L235-L247)、[`AudioOutputProbe.swift`](../../macos/Runner/AudioOutputProbe.swift#L117-L131)），而 SoLoud 开流也按默认设备走。**“有设备但默认设备不可用”时 count 判据会漏报，hasDevice 不会。** 也就是说现有实现用最贵的手段拿到了最弱的判据。

---

## 3. 实测数据

### 3.1 方法

本机 macOS（arm64），5 个 CoreAudio 设备（含 Teams Audio、WeMeet 两个虚拟设备），用 Swift 直调 CoreAudio 复现各层工作量（脚本见 §10）。测的是“原生侧工作量”的等价近似，不含 Dart/FFI 编解码开销（那部分是几十 µs 量级的固定成本）。

### 3.2 结果

| 操作 | 实测 | 对应代码 |
|---|---|---|
| 只取设备 ID 列表 | **1.0 µs** | — |
| 设备列表 + 逐设备读名称 | **495 µs** | `listPlaybackDevices()` 的主要成本 |
| 完整枚举（再读 is-default） | **591 µs** | `listPlaybackDevices()` 的上界近似 |
| 默认设备 + 音量 + 静音 | **95 µs** | 原生 probe 每次 poll 的全部工作 |
| 只读默认设备 | 13 µs | — |
| 只读音量 | 57 µs | — |

### 3.3 解读

| 项 | 数值 |
|---|---|
| 可见时轮询占空比（枚举 0.6 ms / 2 s） | ≈ 0.03% 单核 |
| 设备名读取占枚举成本 | ≈ 99% |
| 5 个设备 → 10+ 个设备（OBS / BlackHole / Loopback） | 估算 1.2–1.5 ms/次（线性放大） |
| 拖动音量滑块时（事件 10–20 次/秒） | 6–12 ms/秒的 UI 线程同步阻塞 |
| Windows（WASAPI 枚举 + 每设备 `OpenPropertyStore`） | 估算 1–3 ms/次（未实测，见 §9 待补） |
| Linux（3 次 `Process.run`） | 每次 3 个 fork+exec，5–15 ms/个，但异步执行，UI isolate 不阻塞 |

---

## 4. 风险分析

### 4.1 常态：可忽略

0.6 ms / 2 s = 0.03% 单核，且单次小于一帧（16.7 ms）。**单独看平均值，这不是问题，也不构成“必须改”的理由。** 本文的重点是下面四个尾部场景。

### 4.2 尾部场景一：拖动音量滑块时的事件风暴（概率最高）

拖动 Slider 时原生属性监听连续触发事件，每次事件都走一次完整采样；[`_sampling`](../../lib/audio/audio_output_monitor.dart#L219-L224) 只防重入、不防频率。于是：**每次拖动的 1 秒里，UI 线程被 6–12 ms 的同步枚举切碎，而这恰好是用户正在与 Slider 交互、每帧都需要及时响应的窗口。** 事件越多、设备越多，碎片越明显。

补充：600 ms 静默窗口只延后**状态跃迁**（[`_apply()`](../../lib/audio/audio_output_monitor.dart#L272-L278)），并不减少读取次数。

### 4.3 尾部场景二：驱动级阻塞会直接卡帧

蓝牙音箱断电、USB DAC 拔插、虚拟声卡驱动异常时，CoreAudio/WASAPI 的属性读取可能阻塞几十到数百 ms。此时：

- 原生 probe：阻塞在平台主线程，Dart 帧不受直接阻塞（窗口输入、插件通道会受影响）；
- `listPlaybackDevices()`：阻塞在 **UI isolate** → 原样变成掉帧，且因为持 `gDeviceOperationMutex`，还可能连带拖住引擎的生命周期操作。

这类故障态正是本功能要提示的场景（用户蓝牙音箱没开机），也就是说**最需要检测的时刻，恰好是探测本身最贵、最可能卡的时刻**。

### 4.4 尾部场景三：与引擎生命周期的锁竞争

`miniaudio_listPlaybackDevices()` 与 `initEngine()` 共用 `gDeviceOperationMutex`。当前 `start()` 已排在引擎 settled 之后，正常路径不重叠；但引擎重试、退出路径 `deinitAsync()` 与采样并发时（设计 §4.1.1 要求退出前先 `stop()`，属于已覆盖的约束）仍存在等待窗口，属于“低概率、但后果是 UI 线程等锁”的一类。

### 4.5 尾部场景四：无意义的内存分配噪声

每次采样 `calloc` 255 个指针 + 每设备 `strdup`/`free`，0.5 Hz 稳定发生。绝对量小，但在一个以“零常驻开销”为目标的监测层里属于纯浪费。

### 4.6 结论

> 风险的真实来源不是“轮询太频繁”，而是“轮询路径里塞了一个同步的、做大量无用工作的原生枚举”。

---

## 5. 方案空间与取舍（已决策）

| 方案 | 做法 | 收益 | 代价 / 风险 | 评价（2026-11-15） |
|---|---|---|---|---|
| **A. 删除枚举** | 去掉 `playbackDeviceCount`，noDevice 只用 `hasDevice == false` + `deviceUninitialized` | 彻底消除同步 FFI、驱动阻塞尾部、每次采样的大块分配；代码变少 | 丢失“设备列表非空”信号（§5.2 已用 Linux 判据补齐）；驱动阻塞尾部消失 | **采纳** |
| **B. 降频保留** | 音量/静音仍 2 s；设备枚举 30 s 一次 + 事件后一次 | 保留 count 能力 | 多一条时间维度需推理；驱动阻塞尾部仍在，只是变稀；状态可能滞后于两次采样之间的设备变化 | 不采纳（P-1 已否决） |
| **C. 原生侧缓存清单** | macOS 监听 `kAudioHardwarePropertyDevices`、Windows 用 `IMMNotificationClient` 维护缓存，`read` 直接返回 | 能力保留且每次采样零枚举 | Windows 需新增 30–60 行 COM 通知客户端 + 生命周期管理；CI 覆盖不到 | 不采纳；仅当将来产品要展示“可用设备列表”时重新评估 |
| **D. isolate 化** | 把采样搬到后台 isolate | 隔离阻塞 | 平台 channel 可行（`BackgroundIsolateBinaryMessenger` + `RootIsolateToken`），但 **FFI/SoLoud 部分不可行**：`SoLoud.instance` 是主 isolate 单例，loader / activeSounds / StreamController 不能跨 isolate，枚举只能在主 isolate 的 FFI 上调用；还要新增 IPC 与生命周期 | 不采纳（只能隔离一半，不划算） |
| **E. keepalive 探针** | 播放极低电平片段让设备保持 active，用 `getAudioDeviceState()` 判活 | 更接近“链路是否活着” | 破坏 SoLoud 的 idle 挂起省电策略；与训练音频排队冲突；仍不回答“人耳是否听到” | 不采纳 |
| **F. 事件节流**（正交） | 事件触发的采样加最小间隔 **300 ms** | 消除拖动风暴；同时压住 Linux 的 fork 频率 | 事件响应最多延迟 300 ms（设计目标 1 s 内，仍满足） | **采纳** |
| **G. 空闲期采样**（正交） | 采样排到 post-frame / `Priority.idle` | 即使有残余同步工作也不占帧预算，把“掉一帧”降级为“晚一次采样” | 实现极轻；采样延迟增加不到一帧 | **采纳** |
| **H. 慢采样可观测**（正交） | debug 下两段分别计时、各自 8 ms 预算：UI isolate 同步段 > 8 ms 记一条 warn；平台往返段只在 in-process 平台（macOS/Windows）计入，Linux 子进程豁免（否则会常态误报）。非周期日志，同一慢序列只记一条 | 把残余风险从“猜”变成“数据”，且能区分“Dart 侧变慢”与“平台线程被卡” | 无 | **采纳** |
| **I. Linux 单进程读取**（正交） | 3 次 `pactl` 合并为一次 `pactl --format=json list sinks`；多 sink 时再加一次 `--format=json info` 解析默认 sink（`wpctl get-volume` 本就同时返回音量与 mute） | fork 数 3 → 1（多 sink 时 2） | 解析代码需要重写 + 单测 | **采纳（Linux）** |

### 5.1 为什么 A 在语义上不吃亏

要回答的问题是“**现在能不能听到声音**”，对应的物理事实是“**系统有没有可用的默认输出端点，且引擎能不能在这上面开流**”。

- 设备列表非空 ≠ 能出声：列表里有设备、但默认设备不可用（被拔掉的蓝牙设备仍可能留在列表里）时，旧判据漏报；
- `hasDevice == false` 直接对应“默认输出端点不存在”，且与 SoLoud 的实际开流选择一致；
- `deviceUninitialized` 覆盖“引擎侧输出设备未就绪”。

所以 A 不是“为了性能牺牲能力”，而是**用一个更准的判据替换一个更贵且更弱的判据**。

### 5.2 A 的唯一功能损失

Linux：`pactl` 正常但 `@DEFAULT_SINK@` 缺失的情况。当前会被 count 判据捕获，A 之后读到 `unsupported/unknown`，按设计不报警。两种处理：

1. 仅接受：`unknown` 语义就是“降低置信度、不误报”；
2. 在 Linux probe 补一条：命令成功但默认 sink 解析为空 → `hasDevice = false`，成本为零（此时本来就要解析输出文本）。

**决策（P-5，2026-11-15）：选 2，使 A 的功能损失归零。**

### 5.3 为什么不推荐 B 作为最终态

B 保留了驱动阻塞的尾部（虽然变稀），又引入第二条时间轴（音量 2 s / 设备 30 s）导致状态可推理性下降。只有当产品确实需要 count 信息时才选 B，且应配合 F 一起做。

**决策（P-1，2026-11-15）：选 A。B 与 C 均不实施；C 只在将来产品要展示“可用设备列表”时重新评估。**

---

## 6. 实施方案与预期（已定稿）

**实施组合：A + F + G + H + I（Linux），已于 2026-11-15 决策，不再比较其他组合。**

### 6.1 改造后的采样成本

| 平台 | 每次采样的 UI isolate 主动工作 | 平台线程 / 子进程 |
|---|---|---|
| macOS | MethodChannel 编解码 + 两个 FFI 原子读（≤ 50 µs） | 95 µs CoreAudio 属性读 |
| Windows | 同上 | WASAPI 端点 + `GetMasterVolumeLevelScalar` + `GetMute`（估 < 200 µs） |
| Linux | 同上 + JSON/文本解析（≤ 100 µs） | 1 个 `pactl` 子进程 / 3 s（多 sink 时 2 个），事件触发受 F 节流 |

### 6.2 改造后的行为差异

| 行为 | 现状 | 改造后 |
|---|---|---|
| 拖动音量时的读取次数 | 10–20 次/秒，每次 0.6 ms 同步 | ≤ 3–5 次/秒（F），每次 ≤ 50 µs 同步 |
| 蓝牙设备无响应时的 UI 影响 | 可能整帧阻塞 | 阻塞只发生在平台线程 |
| noDevice 判定准确性 | “列表非空”会出现漏报 | 默认端点缺失 / 设备未初始化，均能命中 |
| 启动耗时 | 不受影响 | 不受影响 |

### 6.3 实施顺序

| 步 | 内容 | 说明 |
|---|---|---|
| 1 | A：删除 `playbackDeviceCount` 与 `listPlaybackDevices()`，noDevice 改用 `hasDevice` / `deviceUninitialized` | 纯 Dart，收益最大、风险最低；先让同步枚举消失 |
| 2 | F + G + H：事件节流 300 ms、采样排到空闲期、慢采样 debug 记录 | 都在 `AudioOutputMonitor` 内部，配套节流单测 |
| 3 | I：Linux 三次 `Process.run` 合并为一次，并补默认 sink 缺失判定 | 只改 Linux probe 与解析单测 |
| 4 | 文档与测试收口：主设计 §4.2.1 探测表（**已按本决策更新，2026-11-15**）、§7 清单第 5–6 项的单测调整（**已实施**） | 与实际实现同步 |

约束：

- 本改造属于 P0 的收尾，**不改变 P0 的功能范围**（badge 触发条件、文案、阈值不变），因此不需要重跑 P0 的界面验收，只需跑 §8。
- 加强需求 E1/E2/E3 复用同一份 `AudioMonitorSnapshot`，本改造对其**无接口影响**；E1 的“重新检测”按钮继续走 `refresh()`。
- 各步可独立提交，任一步回滚都不会破坏其余部分。

> 实施记录（2026-11-15）：第 1–3 步已落地；第 4 步的单测已按实际实现调整（`test/audio/audio_alert_state_test.dart`、`audio_output_monitor_test.dart`、`audio_output_probe_test.dart`），主设计 §4.2.2 的 Linux 说明已同步。

---

## 7. 连带改动清单（已实施，2026-11-15）

| # | 位置 | 改动 |
|---|---|---|
| 1 | [`audio_alert_state.dart`](../../lib/audio/audio_alert_state.dart#L49-L61) | 删除 `AudioEngineStatus.playbackDeviceCount` 及 [`classifyAudioAlert()`](../../lib/audio/audio_alert_state.dart#L136-L141) 中对应分支 |
| 2 | [`audio_output_probe.dart`](../../lib/audio/audio_output_probe.dart#L348-L372) | `readSoLoudEngineStatus()` 去掉 `listPlaybackDevices()`，只保留 `isInitialized` 与 `getAudioDeviceState()` |
| 3 | [`audio_output_monitor.dart`](../../lib/audio/audio_output_monitor.dart#L201-L203) | 事件采样加最小间隔（F）；采样调度改到 post-frame / idle（G）；debug 慢采样记录（H） |
| 4 | Linux probe | 三次 `Process.run` 合并为一次单进程读取（I）；补默认 sink 缺失 → `hasDevice = false`（P-5）；默认 sink 选取抽为 `selectPactlSink()` 并补单测 |
| 5 | [`test/audio/audio_alert_state_test.dart`](../../test/audio/audio_alert_state_test.dart#L36-L49) | 去掉 `playbackDeviceCount` 用例，改为 `hasDevice` / `deviceUninitialized` 覆盖 |
| 6 | [`test/audio/audio_output_monitor_test.dart`](../../test/audio/audio_output_monitor_test.dart#L10) | fake engine 构造简化；新增“事件节流”与“采样不在帧内”的断言 |
| 7 | [`audio_preflight_check_design.md`](audio_preflight_check_design.md) §2.2 / §4.1 / §4.2.1 | **已完成**：设备存在性来源改为平台 `hasDevice`，并补充本文档链接与 §9.1 说明 |

---

## 8. 验证方式

### 8.1 自动化

- 单测：`unknown` 仍不产生 badge；`hasDevice == false` → `noDevice`；`deviceUninitialized` → `noDevice`；`hasDevice == null` → `none`。
- 节流单测：注入时钟，模拟 20 次/秒的事件，断言实际采样次数 ≤ N。
- 回归：`test/audio/*`、`test/ui/main_page_layout_test.dart` 全绿，`flutter analyze` 无新增告警。

### 8.2 手工 / 真机

| 场景 | 观察点 |
|---|---|
| 边拖音量滑块边跑比赛 | DevTools timeline 帧时间分布无尖刺；badge 仍在 1 s 内出现 |
| 蓝牙音箱断电（模拟驱动阻塞） | UI 不卡顿；badge 正常出现 |
| 5 语言 × 1.0/1.3 字号 × 1108×796 | 顶栏布局不回归 |
| 待机挂机 30 min | CPU 无明显变化，日志无周期刷屏 |
| `SSB_RUNNER_DISABLE_AUDIO=1` | 全程无 badge、无采样 |

### 8.3 数据补全（可选，不阻塞实施）

本文的 Windows（1–3 ms）、Linux（fork 成本）为估算值。若希望用实测替代估算，可在真机上跑一次 `listPlaybackDevices()` 的 100 次循环计时（一次性脚本，不提交）。这不影响方案选择：A 的结论与具体耗时无关，只与“是否需要在 UI isolate 上做这件事”有关。

---

## 9. 决策记录（2026-11-15）

5 项全部决策，均采纳推荐方案，正文相应章节已按结论更新：

| # | 事项 | 决策 | 落点 |
|---|---|---|---|
| P-1 | 是否放弃“设备列表非空”判据 | **选 A**：删除 `playbackDeviceCount` 与 `listPlaybackDevices()`；B（降频保留）、C（原生缓存）均不实施 | §5.3、§7 #1–#2 |
| P-2 | 事件节流的最小间隔 | **300 ms**（与 600 ms 静默窗口配合，事件最多延迟 300 ms，仍满足 1 s 内出现的目标） | §5 表 F、§7 #3 |
| P-3 | 采样是否排到空闲期（G） | **做**：作为“未来新增同步调用”的通用保险，把最坏情况从“掉一帧”降级为“晚一次采样” | §5 表 G、§7 #3 |
| P-4 | Linux 单进程解析（I）是否纳入本次 | **纳入**：三次 `Process.run` 合并为一次，改动局限在 Linux probe 内部 | §5 表 I、§7 #4 |
| P-5 | 是否补 Linux 默认 sink 缺失判定 | **补**：命令成功但默认 sink 解析为空 → `hasDevice = false`，使 A 的功能损失归零 | §5.2、§7 #4 |

已无待确认项。后续只保留实现期调整：节流间隔在真机上是否改为 200 ms、慢采样阈值是否从 8 ms 收紧，均不改变 A + F + G + H + I 的方向。

### 9.1 本方案的边界（避免与主设计混淆）

- 不改 badge 的触发条件、阈值（10%）、文案与 5 份 ARB；
- 不改 `AudioMonitorSnapshot` 的外部字段与订阅方式，E1/E2/E3 不受影响；
- 不新增原生代码（C 未采纳），Windows/macOS runner 保持现状；
- 不改轮询频率与隐藏态降频策略（2 s / 3 s / 10 s 不变），轮询仍然承担事件通道失效时的健康检查职责。

---

## 10. 附录：测量脚本

在本机 macOS 复现 §3 数据的最小 Swift 脚本（一次编译运行，非项目代码，不入库）：

```swift
import CoreAudio
import Foundation

func addr(_ sel: AudioObjectPropertySelector,
          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
  AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
}

func defaultOutputDevice() -> AudioDeviceID? {
  var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
  var dev = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
  let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
  return (st == noErr && dev != 0) ? dev : nil
}

func allDeviceIDs() -> [AudioDeviceID] {
  var a = addr(kAudioHardwarePropertyDevices); var size = UInt32(0)
  guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
  var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
  guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
  return ids
}

func readDeviceName(_ dev: AudioDeviceID) -> String? {
  var a = addr(kAudioObjectPropertyName); var name: Unmanaged<CFString>?
  var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
  guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &name) == noErr,
        let v = name?.takeRetainedValue() else { return nil }
  return v as String
}

func readFloat(_ dev: AudioDeviceID, _ a0: AudioObjectPropertyAddress) -> Float? {
  var a = a0
  guard AudioObjectHasProperty(dev, &a) else { return nil }
  var v = Float(0); var size = UInt32(MemoryLayout<Float>.size)
  return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
}

func readMute(_ dev: AudioDeviceID) -> Bool? {
  var a = addr(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
  guard AudioObjectHasProperty(dev, &a) else { return nil }
  var m = UInt32(0); var size = UInt32(MemoryLayout<UInt32>.size)
  return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &m) == noErr ? (m != 0) : nil
}

func time(_ label: String, _ iterations: Int, _ body: () -> Void) {
  for _ in 0..<5 { body() }
  let start = DispatchTime.now().uptimeNanoseconds
  for _ in 0..<iterations { body() }
  let ns = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations)
  print(label.padding(toLength: 46, withPad: " ", startingAt: 0)
        + String(format: "%8.1f us/op", ns / 1000.0))
}

print("audio devices: \(allDeviceIDs().count)")

time("device list only", 2000) { _ = allDeviceIDs() }

time("device list + names", 500) {
  for d in allDeviceIDs() { _ = readDeviceName(d) }
}

time("default device + volume + mute", 2000) {
  guard let d = defaultOutputDevice() else { return }
  _ = readFloat(d, addr(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput))
  _ = readMute(d)
}

time("default device only", 2000) { _ = defaultOutputDevice() }
```

复现命令：

```bash
swiftc -O main.swift -o bench && ./bench
```

本机（macOS arm64，5 个设备）输出：

```text
device list only                                1.0 us/op
device list + names                           495.1 us/op
default device + volume + mute                 95.6 us/op
default device only                            12.9 us/op
```
