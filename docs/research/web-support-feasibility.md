# Web 支持可行性与硬限制调研

调研日期：2026-10-31（Asia/Shanghai）。

范围：当前工作区源码、`pubspec.lock` 锁定依赖、本机依赖缓存中的实现，以及浏览器和依赖维护者的官方资料。本文仅作技术调研，不包含业务代码、平台配置或依赖修改。

验证方式：静态源码检查和文档交叉核对；没有执行 Web 构建、浏览器播放测试或延迟测量。因此，“未发现硬性不可行项”表示架构和 API 层面未发现阻断条件，不表示已经验证 Web 可用或达到某项性能指标。

## 1. 结论

**当前核心训练功能具备迁移到 Web 的技术条件，未发现必须放弃 Web 或更换音频引擎的硬性理由。** 当前尚不能直接运行，主要因为启动日志、数据库、窗口与退出流程采用桌面实现，音频 Web 加载配置也不完整。

浏览器确实存在不能靠常规适配消除的能力边界：

| 目标要求 | 判断 | 对当前训练功能的影响 |
| --- | --- | --- |
| 前台浏览器中完成语音、噪声、叠台、计分与复盘 | 未发现平台层面的硬性不可行项 | 需要平台适配和实测 |
| 首次访问无需任何交互就可靠出声 | 无法保证绕过自动播放策略 | 在开始训练的用户交互中解锁音频，并验证可播放状态 |
| 后台、锁屏、页面冻结期间始终连续运行 | 无法作跨浏览器、跨设备保证 | 需要明确暂停、恢复、过期结束等行为 |
| 所有浏览器完整保留相同的 F1–F8 操作行为 | 无法无条件保证 | 提供备用按键和屏幕操作 |
| 直接配置原生音频驱动、独占输出 | 现有 Web 链路不提供这类控制 | 当前项目没有使用这类能力，不阻断现有功能 |
| 所有设备都满足固定的按键到出声延迟上限 | 无法作通用保证 | 必须测量目标设备；普通语音训练不等于硬实时系统 |
| 历史永久保存且只依赖浏览器本地存储 | 无法无条件保证 | 需要持久化申请、导出或同步策略 |
| 更稳定的接播、减少主线程计算 | 可以通过调整实现改善 | 属于工程工作，不是 Web 无法实现 |

建议首个验证目标为：**桌面浏览器、HTTPS、自有可配置响应头的部署环境、训练页面保持前台。** 对后台运行、默认快捷键和历史保存分别制定降级行为，避免将“能运行”直接解释成“与桌面行为完全相同”。

## 2. 检查基线

仓库基准提交：`c80be2b`。调研读取的是当时的工作区，其中已有其他任务的未提交变更；本次仅新增本文档，没有更改这些已有变更。

主要实际锁定版本如下；判断以 `pubspec.lock` 为准，不以 `pubspec.yaml` 的版本范围或官网最新版本代替。

| 依赖 | 实际版本 | 本次相关用途 |
| --- | --- | --- |
| `flutter_soloud` | 5.1.5 | PCM 播放、底噪、音量与完成事件 |
| `worker_manager` | 7.2.9 | WAV 解析、字节拼接任务 |
| `drift` | 2.35.0 | 数据库与持久化 |
| `drift_flutter` | 0.3.1 | 平台数据库连接 |
| `sqlite3` | 3.6.0 | SQLite 支持 |
| `window_manager` | 0.5.2 | 桌面窗口操作 |
| `path_provider` | 2.1.6 | 本机目录解析 |
| `file_selector` | 1.1.0 | 诊断文件导出位置 |

仓库已有 `web/index.html`、manifest 和图标，但这只是 Web 工程模板，不足以证明应用适配完成。当前 CI 发布矩阵覆盖 Linux、Windows、macOS，未覆盖 Web 构建和浏览器音频验证。

## 3. 当前确定存在的编译、启动与功能阻塞

| 模块 | 源码依据 | 不兼容点 | 可行处理方向 |
| --- | --- | --- | --- |
| 启动日志 | `lib/main.dart`、`lib/logging/logging_bootstrap.dart`、`lib/logging/log_paths.dart` | 界面启动前无条件解析本机日志目录并建立文件日志；使用 `Platform`、`File`、`Directory` | 隔离 Web 日志、环境信息和导出实现 |
| 环境信息 | `lib/logging/log_session.dart` | 无条件导入 `dart:ffi`、使用 `Abi.current()`，读取可执行文件、工作目录等本机信息 | 用条件导入隔离原生实现，Web 采集适用的信息 |
| 数据库 | `lib/db/app_database.dart`、`lib/db/database_bootstrap.dart`、`lib/common/dirs.dart` | 直接导入 `drift/native.dart`，使用本地目录和 `NativeDatabase.memory()`；`driftDatabase()` 没有传入 Web 参数 | 提供 Web 连接，配置 SQLite WASM 与 drift worker，隔离目录准备和旧文件迁移 |
| 窗口与退出 | `lib/main.dart`、`lib/ui/main_app/main_app.dart` | `window_manager` 仅支持桌面；代码还读取环境变量、调用 `Process.killPid()` 和 `exit()` | 隔离桌面窗口与进程逻辑，单独设计页面生命周期 |
| 音频加载 | `web/index.html` | 页面只有 Flutter bootstrap，没有 SoLoud 5.x 的 Web 初始化脚本 | 接入 `assets/packages/flutter_soloud/web/init_soloud.js`，验证初始化时序 |
| 诊断导出 | `lib/logging/log_export.dart` | 通过 `File(target.path)` 写 ZIP，无法沿用浏览器端的路径语义 | 生成字节后走浏览器下载流程 |
| 崩溃上报 | `lib/logging/crash_issue_reporter.dart` | 使用 `dart:io` 的 `HttpClient`；支持构建时注入 GitHub issue 写入令牌 | 改用适合浏览器的 HTTP 实现；保留自动上报时采用服务端代发或其他授权方案 |

补充：`drift_flutter 0.3.1/lib/src/web.dart` 在没有 `web` 参数时会明确抛出 `ArgumentError`。仅隔离本地目录代码，仍不足以完成数据库适配。

这些问题不等同于浏览器不能实现相应功能。日志可保存在内存或浏览器存储中，SQLite 可通过 WASM 运行，文件可通过下载导出，但需要不同的平台实现。

`dart:io` 的导入、API 调用和不同编译目标的失败形式也不能混为一谈：部分代码可能编译后在调用时抛错，FFI/native 依赖还可能形成编译阻塞。本文未运行构建，不列出未经验证的具体编译错误清单。

参考：[Flutter Web FAQ](https://docs.flutter.dev/platform-integration/web/faq)、[Drift Web 配置](https://drift.simonbinder.eu/platforms/web/)。

## 4. 音频能力与硬边界

### 4.1 当前需求与实际链路

音频链路为：

```text
rootBundle 加载 WAV
  → 提取并拼接 PCM
  → Dart 训练音效／叠台处理
  → SoLoud WASM
  → Web Audio
  → 浏览器与系统音频输出
```

本次检查的 559 个 WAV 均为 24 kHz、单声道、16-bit PCM。当前语音目录约 16.81 MiB；这是本地目录大小，不是 Web 首屏下载大小或最终压缩传输体积。

当前使用的 `setBufferStream()`、`addAudioDataStream()`、`setDataIsEnded()`、`loadMem()`、循环播放、音量与渐变，在锁定版本中存在 Web 实现。未发现当前播放流程依赖必须使用原生驱动的接口。

项目的 `lib/audio/audio_engine.dart` 已定义 `AudioEngine` 接口，后续若需 Web 特定实现，有现成的隔离位置。

### 4.2 设备选择：当前库只提供默认设备

检查 `flutter_soloud 5.1.5` 内的：

```text
src/soloud/src/backend/miniaudio/miniaudio.h
  ma_context_enumerate_devices__webaudio()
  ma_context_get_device_info__webaudio()
```

该后端只枚举默认设备；查询设备信息时忽略传入的设备 ID。因此，不能依靠现有 `listPlaybackDevices()`／`changeDevice()` 调用获得桌面端完整的声卡选择能力。

这属于当前后端的限制。浏览器存在输出选择相关 API，但还受支持范围、权限和用户交互约束，需要单独接入；不能据此宣称所有浏览器都无法选择输出设备。当前项目未提供设备选择，因此不构成现有功能阻塞。

参考：[MediaDevices.selectAudioOutput()](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/selectAudioOutput)。

### 4.3 低延迟与时间测量不能照搬原生实现

锁定版本 `lib/src/soloud.dart` 明确说明：

- `lowLatency` 在 Web 被忽略。
- `devicePeriodFrames` 在 Web 被忽略。
- `renderAheadFrames` 在 Web 被忽略。

`lib/src/bindings/bindings_player_web.dart` 的实现为：

```dart
Duration getPlayheadTime() => getEngineTime();
Duration getOutputLatency() => Duration.zero;
bool isRenderAheadEnabled() => false;
```

上述代码为便于阅读的等价摘录。含义是：Web 不提供此处的原生 render-ahead 能力，返回的播放位置是混音时钟，返回零也不代表实际输出延迟为零。

浏览器的 `latencyHint` 是请求，不是端到端延迟承诺。若未来将反应时间、精确声画同步或极低延迟作为指标，需要区分引擎混音完成、交给系统输出和用户实际听到声音三个时刻，并在目标设备测量。

不能把项目的 `bufferingTimeNeeds: 0.1` 直接当成测得的输出延迟，也不能据此给出固定的 100 ms 端到端延迟结论。

参考：[AudioContext.baseLatency](https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/baseLatency)、[AudioContext 构造参数](https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/AudioContext)。

### 4.4 AudioWorklet 与主线程接播是两层问题

SoLoud 提供两个 Web WASM 后端：

| 后端 | 选择条件 | 含义 |
| --- | --- | --- |
| AudioWorklet 多线程后端 | 页面跨源隔离，可用 `SharedArrayBuffer` | 音频渲染在独立线程执行，减少 UI 工作对已排队音频的影响 |
| ScriptProcessorNode 单线程后端 | 不满足上述条件时回退 | 渲染依赖主线程，更容易受到 UI 工作和 GC 影响；该 Web API 已被弃用 |

但当前项目的接播路径仍然是：

```text
音频线程结束当前片段
  → 完成事件转发到浏览器主线程
  → Dart 收到 allInstancesFinished
  → AudioPlayer._onSegmentFinished()
  → _pump() 创建并播放下一段
```

证据：

- SoLoud `src/bindings.cpp` 的 `voiceEndedCallback()` 在 AudioWorklet 线程上触发时，使用 `emscripten_audio_worklet_post_function_vii()` 转发到主浏览器线程。
- SoLoud `lib/src/bindings/bindings_player_web.dart` 接收 worker 消息并派发完成事件。
- 项目 `lib/audio/audio_engine.dart` 使用 `allInstancesFinished`。
- 项目 `lib/audio/audio_player.dart` 在完成事件后调用 `_pump()`；watchdog 同样使用 Dart `Timer`。

由此推断：独立音频线程不能保证下一段接播、新题生成和状态推进都不受主线程阻塞影响。这里确认的是调度依赖，并没有实测片段间隙或已经证明某浏览器必然卡顿。

这可以通过提前拼接、预调度、调整队列等方式改善，不是 Web 本身无法精确播放音频。呼号内部已在 `AudioLoader._loadCallsign()` 中先拼接各字符 PCM，无需逐个字母等待播放完成事件。

### 4.5 首次播放受浏览器策略约束

普通网站无法保证首次访问、零交互时可靠出声。应在用户点击开始训练的流程中处理音频上下文解锁，并检查实际可播放状态。引擎初始化完成不能直接等同于用户能听到声音。

具体策略会因浏览器、用户设置和既有交互记录而不同；不能以开发机器上自动播放成功作为普遍保证。

参考：[Chrome Web Audio 自动播放策略](https://developer.chrome.com/blog/web-audio-autoplay)。

### 4.6 单音源滤镜：官网概述与锁定版本源码不完全一致

SoLoud Web 文档概述称支持单音源滤镜，但锁定版本的 `lib/src/filters/filters.dart` 中，部分单音源参数读写仍明确执行：

```dart
if (kIsWeb && _soundHandle != null) {
  throw const SoLoudFilterForSingleSoundOnWebDartException();
}
```

因此不能仅凭官网概述承诺 5.1.5 的所有滤镜 API 与桌面等价，也不能将本次发现扩大为“所有 Web 滤镜不可用”。

当前项目的 QSB、噪声、重采样、叠台主要通过 Dart 直接处理 PCM，没有使用这些单音源滤镜参数 API，因此未发现这项限制阻断现有训练音效。

项目依据：`lib/training/training_profile.dart`、`lib/audio/noise_bed.dart`、`lib/audio/ssb_passband.dart`、`lib/audio/mix_pileup.dart`。

## 5. 后台运行与生命周期硬边界

浏览器可以冻结或丢弃页面。冻结后，页面中的相关任务和计时器停止执行；丢弃后，页面代码无法继续运行，且丢弃通知不能作为可靠保存机会。

当前受影响的流程包括：

- `ContestTimer` 的周期回调和比赛结束判断。
- 状态机自动重试定时器。
- 音频完成事件后的接播和 watchdog。
- `_waitAudioNotPlaying()` 的 100 ms 轮询。
- 关闭时依赖异步清理或刷新日志的操作。

切换标签页不代表马上停止；正在出声时，部分浏览器会放宽节流。不过，这种行为不能作为跨浏览器、锁屏和资源紧张场景的持续执行保证。

使用时间戳可以在恢复后校正计时，但不能补回停顿期间应发生的音频和交互。安装为 PWA 也不能据此承诺持续后台执行。

可选择的行为包括：离开页面暂停训练、恢复时继续；或继续计算墙上时间并在恢复后判定过期。具体行为需要产品决定，本文不将其中任何一种视为已选方案。

参考：[Chrome Page Lifecycle API](https://developer.chrome.com/docs/web-platform/page-lifecycle-api)、[Chrome 后台计时器节流](https://developer.chrome.com/blog/timer-throttling-in-chrome-88/)。

## 6. 键盘与持久化边界

### 6.1 快捷键不是全部不可用，但不能保证跨浏览器完整等价

默认 F1–F8 与浏览器操作有冲突。部分按键可通过消费事件阻止默认行为，因此“F5 一概无法拦截”是不准确的。

真正的边界是：网页不能无条件获得浏览器和操作系统保留的全部按键。Keyboard Lock 还存在全屏、权限、支持范围与操作系统限制。Chrome 官方资料说明其要求 JavaScript 发起的全屏；Chrome 130 起请求还需要权限。

项目当前 `ContestRunningManager._onKeyEvent()` 返回 `false`，未声明消费事件；需要单独验证 Web 事件处理、焦点丢失、按键释放及备用交互。

参考：[Chrome Keyboard Lock](https://developer.chrome.com/docs/capabilities/web-apis/keyboard-lock)、[Keyboard.lock()](https://developer.mozilla.org/en-US/docs/Web/API/Keyboard/lock)。

### 6.2 浏览器本地存储不能直接承诺永久保存

Drift Web 可使用 SQLite WASM 和浏览器存储后端，不需要为当前本地训练功能强制增加数据库服务端。

但站点存储默认可能是 best-effort；浏览器可以在存储压力、配额或自身清理策略下回收数据。申请持久化可改善自动回收风险，但是否授予由浏览器决定，也不能阻止用户清除站点数据。

需要验证普通模式、隐私模式、持久化被拒绝、多标签页和存储不可用时的行为。若要求历史可靠长期保留，应提供导出或同步路径，不能只把桌面 SQLite 路径替换成 IndexedDB 就视为保证相同。

参考：[Drift Web](https://drift.simonbinder.eu/platforms/web/)、[WebKit 存储策略](https://webkit.org/blog/14403/updates-to-storage-policy/)。

## 7. 计算与部署条件

### 7.1 worker_manager 的 Web 实现不提供计算并行

检查 `worker_manager 7.2.9/lib/src/worker/worker_web.dart`：`work()` 直接执行 `task.execution()`，没有创建真正的计算 Worker。

项目的 WAV 解析和字节拼接因此不会获得原生 isolate 的并行效果。训练音效、叠台、底噪生成也包含逐样本计算，需要测量其主线程开销。

这是当前依赖实现的限制。Web 可以使用真正的 Web Worker，预计算和 PCM 缓存也可减少开销，不能由此得出“Web 没有多线程能力”或“必须关闭训练音效”的结论。

### 7.2 SoLoud 多线程后端依赖部署环境

当前 SoLoud 多线程后端需要 HTTPS 和跨源隔离，典型响应头为：

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

需要检查响应头在实际 HTML、worker 和资源响应上的一致性。启用这些策略后，跨域资源必须满足对应的 CORS／CORP 要求，部分弹窗或嵌入流程也需要另行验证。

无法配置响应头的部署环境仍可使用单线程回退，但不能假定拥有独立音频线程。**生产构建使用 `flutter build web --wasm` 本身，不会自动替生产服务器配置响应头。** Flutter 应用代码的 JS/WASM 编译目标和 SoLoud 音频后端选择是两件事。

参考：[SoLoud Web Notes](https://docs.page/alnitak/flutter_soloud_docs/get_started/web_notes)。

## 8. 后续验证项（本次未执行）

以下用于未来实施时明确证据要求，不代表本次已经创建原型或运行测试。

| 验证项 | 需要观察的结果 |
| --- | --- |
| Web release 构建和首次启动 | 排除 FFI/native 导入、桌面 API 和插件缺失；数据库、设置和 UI 正常进入可用态 |
| 音频加载与首次出声 | 新站点首次访问、已有交互、解锁失败及恢复流程明确 |
| 当前音频 API 覆盖 | PCM 流、短片段、完成事件、打断、底噪循环、音量渐变和释放均可工作 |
| 后端选择 | 确认实际选择单线程或 AudioWorklet，而非只检查构建参数 |
| 接播与性能 | 比较不同难度、叠台规模、UI 负载和 GC 情况下的准备耗时、片段间隙与卡顿 |
| 实际延迟 | 使用可验证的测量方法记录按键到声输出；不使用 SoLoud Web 的零返回值代替测量 |
| 生命周期 | 切标签页、最小化、冻结、恢复、页面丢弃重载；若支持移动浏览器，再覆盖锁屏 |
| 快捷键 | 目标浏览器的 F1–F8、焦点丢失、重复事件与按键释放；确认默认浏览器行为是否同时触发 |
| 存储 | 普通／隐私模式、多标签页、持久化拒绝、清理数据后的恢复与导出 |
| 资源加载 | 冷缓存与热缓存、弱网、素材预加载；防止按字符读取资源引入训练节奏变化 |

现有源码和官方能力说明足以支持“值得进行 Web 原型验证”的判断；具体浏览器兼容范围、延迟上限和完整迁移工作量，仍需上述验证后确定。
