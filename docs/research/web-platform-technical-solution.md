# Web 平台技术方案

调研日期：2026-11-10（Asia/Shanghai）。
基线：仓库提交 `dbf4b55`，工作区干净；Flutter 版本以 `.fvmrc` 的 3.47.9 为准。
关联文档：[web-support-feasibility.md](web-support-feasibility.md)（2026-10-31，可行性与硬边界）。

本文在上一轮可行性结论的基础上，补充了对锁定依赖实现的逐项核对，并给出可执行的改造方案。验证方式仍为静态源码检查加依赖源码核对；**没有执行 Web 构建、浏览器播放测试或性能测量**。文中“可行”均指未发现架构级阻断，不等于已经验证。

## 1. 结论

**推荐方案：保留单入口 `lib/main.dart`，在应用与平台之间增加一层条件导入的适配端口，核心训练逻辑、状态机、计分、DXCC 与音频算法不改。**

需要改的只有四类：

| 类别 | 现状问题 | 方案 |
| --- | --- | --- |
| 启动与日志 | 文件日志、本机环境探测、窗口隐藏全部在启动路径上无条件执行 | 按平台选择日志后端，Web 使用内存日志加浏览器环境快照 |
| 数据库 | 强制走 `drift/native.dart`，且 `driftDatabase` 没有 Web 参数 | 条件导入 native / WASM 两套连接实现，Web 使用 SQLite WASM 加 IndexedDB |
| 窗口与退出 | `window_manager` 无 Web 平台，且间接导入 `dart:io`；退出路径调用 `Process.killPid` 与 `exit` | 窗口与退出抽象为端口，Web 为空实现加页面生命周期处理 |
| 音频初始化 | `web/index.html` 缺少 SoLoud Web 初始化脚本，启动即初始化音频 | 补初始化脚本，把引擎初始化推迟到首次用户交互 |

Web 端的定位已确认为：**与桌面保持同等能力的训练客户端**，不按“只做训练、弱化历史与诊断”的降级方案设计；首发以桌面 Chrome / Edge 为基线，Firefox 与 Safari 只保证回退路径可用。浏览器无法提供后台连续运行，这部分以暂停策略处理，但不属于功能降级。

## 2. 范围与能力边界

| 能力 | 桌面现状 | Web 目标 | 说明 |
| --- | --- | --- | --- |
| CQ / S&P / 叠台训练 | 完整 | 对齐 | 核心目标 |
| 历史记录 | 本地 SQLite | 同等能力：SQLite WASM + IndexedDB + 持久化申请 + 备份/恢复 | 不按“可丢失”设计；浏览器回收通过备份补偿 |
| 诊断日志 | 轮转文件 | 内存环形缓冲 + 下载导出 | 不写文件系统，导出内容与桌面同构 |
| 崩溃上报 | 构建期令牌直连 GitHub | Cloudflare Worker 代理，前端零令牌 | Worker 持有细粒度令牌并限流 |
| F1–F8 快捷键 | 完整 | 默认全屏 + Keyboard Lock，失败回退屏幕按钮与重映射 | Chrome 系列优先 |
| 切后台 / 锁屏 | 进程持续 | 暂停并明确提示 | 浏览器无法提供后台连续运行 |
| 原生音频设备选择 | 未使用 | 不提供 | 当前 SoLoud Web 后端只暴露默认设备 |
| PWA / 离线 | 不涉及 | 启用安装与离线缓存 | 首版即纳入 |
| 移动浏览器 | 不涉及 | 不作为发布目标 | Chrome 桌面优先 |

## 3. 继续调研的新发现

上一轮文档已列出主要阻塞点。本轮对照 `pubspec.lock` 锁定版本检查了依赖实现，补充以下会直接导致编译失败或启动即抛错的事实：

| 依赖（锁定版本） | 事实 | 影响 |
| --- | --- | --- |
| `window_manager` 0.6.0 | `pubspec.yaml` 只声明 linux / macos / windows；主入口 `window_manager.dart` 还导出了 `src/widgets/virtual_window_frame.dart`，该文件导入 `dart:io` | 仅在 [main.dart](../../lib/main.dart#L10) 与 [main_app.dart](../../lib/ui/main_app/main_app.dart#L28) 中 import 就会让 Web 编译失败，不只是运行不支持 |
| `logger` 2.8.0 | `AdvancedFileOutput` 在非 IO 平台使用 `advanced_file_output_stub.dart`，构造函数直接抛 `UnsupportedError` | [app_logger.dart](../../lib/logging/app_logger.dart#L83-L95) 的 `AppLogger.fileBacked` 在 Web 启动即失败，必须在构造前分流 |
| `drift_flutter` 0.3.1 | `src/web.dart` 的 `driftDatabase` 在 `web == null` 时抛 `ArgumentError`；`connect.dart` 用 `dart.library.js_interop` / `dart.library.ffi` 做条件导出 | [app_database.dart](../../lib/db/app_database.dart#L78-L81) 只传 `native:`，Web 必然失败；条件导入应沿用同一判定顺序 |
| `drift` 2.35.3 | `lib/native.dart` 导入 `dart:io` / `dart:ffi` | [app_database.dart](../../lib/db/app_database.dart#L2) 的 import 本身就是 Web 编译阻断 |
| `file_selector_web` 0.9.5 | `getSaveLocation` 返回 `FileSaveLocation('')`，路径为空 | [log_export.dart](../../lib/logging/log_export.dart#L108) 的 `File(target.path)` 在 Web 不可用，需要改成浏览器下载 |
| `path_provider` 2.1.6 | 无 Web 实现 | [dirs.dart](../../lib/common/dirs.dart#L26-L36) 与 [log_paths.dart](../../lib/logging/log_paths.dart#L25-L35) 不能进入 Web 启动路径 |
| `flutter_soloud` 5.2.3 | 提供 `web/init_soloud.js`、单线程与多线程 WASM；初始化脚本需显式加入 `index.html` | 当前 [web/index.html](../../web/index.html#L35-L37) 只有 Flutter bootstrap，音频不会就绪 |
| `worker_manager` 7.2.9 | Web 的 `work()` 直接执行任务，没有真正的计算 Worker | WAV 解析不会并行，但单段数据很小，先测量再决定是否优化 |
| `sqlite3` 3.9.0 | 声明支持 web，但需要单独提供特制编译的 `sqlite3.wasm` | 需将 WASM 与 drift worker 作为 Web 静态资源发布 |

`window_manager` 这一条比上一轮文档的判断更严格：上一轮写的是“仅支持桌面”，本轮确认其**导出的组件文件本身导入 `dart:io`**，因此必须移除启动路径上的直接 import，而不能只靠 try/catch 兜底。

## 4. 目标架构

```text
┌──────────────────────────────────────────────────────────────┐
│ UI / Cubit / 状态机 / 训练 / 计分 / DXCC / 音频算法           │  平台无关，不改
└───────────────────────────┬──────────────────────────────────┘
                            │ 只依赖端口接口
┌───────────────────────────▼──────────────────────────────────┐
│ Platform ports（lib/platform/，条件导入选实现）               │
│  EnvironmentPort   本机信息 / 浏览器信息                      │
│  LogPort           文件日志 / 内存日志                        │
│  DatabasePort      NativeDatabase / WASM + IndexedDB          │
│  WindowPort        窗口控制 / 空实现                          │
│  ExitPort          进程退出 / pagehide                        │
│  ExportPort        保存对话框 / 浏览器下载                    │
│  CrashPort         HttpClient / 关闭或服务端代理               │
└───────────────┬──────────────────────────────┬───────────────┘
                │                              │
        dart:io / dart:ffi            package:web / Web Audio
```

约定：

- 条件导入统一使用 `dart.library.js_interop` 优先、`dart.library.ffi` 其次的顺序，与 `drift_flutter` 保持一致；不使用已过时的 `dart:html` 判定，保证 JS 与 WASM 两种编译目标都成立。
- `kIsWeb` 只允许出现在端口实现和面向用户的提示文案中，不进入训练、计分、状态机等业务代码。
- 不为 Web 单独复制一份 `main.dart`；启动顺序只维护一份，差异由端口承担。
- 不引入路由框架。当前应用是单页 HomePage，Web 没有深链需求，`go_router` 属于无收益改动。

建议的目录形态（名称可调整，边界不变）：

```text
lib/platform/
  capabilities.dart              能力矩阵，UI 据此显示提示
  environment/                   本机或浏览器环境快照
  logging/                       日志目录与日志后端
  database/                      native 与 wasm 连接
  window/                        窗口控制
  exit/                          退出清理
  export/                        文件保存与下载
  crash/                         崩溃上报传输
```

## 5. 模块方案

### 5.1 启动流程

现状：[main.dart](../../lib/main.dart#L12-L41) 在 UI 之前依次执行日志、`AppInfo`、隐藏窗口、错误处理；[main_app.dart](../../lib/ui/main_app/main_app.dart#L339-L408) 在首帧后初始化音频、设置、worker、数据库、DXCC 与呼号库。

方案：

1. 日志初始化改为端口调用，桌面保持现状，Web 直接安装内存日志并记录浏览器环境快照。
2. 窗口隐藏与首帧显示移到 `WindowPort`，Web 实现为空操作。
3. 音频初始化拆成“引擎准备”和“用户解锁”两步。桌面仍在启动时初始化；Web 在首个明确交互（开始训练/播放按钮）时初始化，并在真正播放前确认引擎可用。
4. 启动失败页保留。Web 的“导出日志”按钮改为浏览器下载，文案中的本地路径改为文件名。
5. 环境变量测试钩子（`SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER`、`SSB_RUNNER_TEST_EXIT_HANG`、`SSB_RUNNER_DISABLE_AUDIO`）只在桌面实现中读取；Web 不读取进程环境。

验收：Web 首屏进入 HomePage；没有未捕获异常；启动轨迹中能看到端口选择的实现名称。

### 5.2 日志与环境信息

现状：[logging_bootstrap.dart](../../lib/logging/logging_bootstrap.dart#L17-L56) 无条件解析日志目录、读取 `Platform`、探测可执行文件目录；[log_session.dart](../../lib/logging/log_session.dart#L1-L55) 导入 `dart:ffi` 并使用 `Abi.current()`；[app_logger.dart](../../lib/logging/app_logger.dart#L83-L116) 构造文件后端；[log_export.dart](../../lib/logging/log_export.dart) 用 `File` 读写。

方案：

- **日志后端**：新增内存后端工厂，复用现有 `MemoryOutput` 与 `AppLogPrinter`，只装环形缓冲，不构造 `AdvancedFileOutput`。桌面继续使用文件后端与轮转策略。
- **环境快照**：拆出纯字符串脱敏逻辑与平台信息来源。桌面保留 `Platform`、`Abi`、可执行文件路径、工作目录；Web 记录浏览器类型、语言、时区、逻辑处理器数、`navigator.storage.estimate()` 的配额与使用量、是否处于跨源隔离状态。不再记录可执行文件与工作目录。
- **日志内容**：Web 端保留当前 200 条上下文缓冲，另外增加一个可配置的诊断缓冲（建议上限 2 MB 或 5000 行，二者先到为准），供“复制诊断”和“导出日志”使用。
- **持久化**：首版不把日志写入 IndexedDB，避免日志本身放大配额压力；需要跨刷新保留时再单独评估。
- **脱敏**：Web 没有本机主目录，保留现有正则兜底即可；浏览器环境不记录完整 URL 查询串与用户标识。

验收：Web 启动日志包含环境快照；`copyDiagnosticSummary` 可用；导出的 zip 内容与桌面结构一致，只是来源改为内存。

### 5.3 数据库与持久化

现状：[app_database.dart](../../lib/db/app_database.dart#L2) 导入 `drift/native.dart`，`_connect()` 在无目录时使用 `NativeDatabase.memory()`，有目录时调用 `driftDatabase(native: ...)`；[database_bootstrap.dart](../../lib/db/database_bootstrap.dart) 负责目录探测、写探针与旧库迁移，全部依赖 `dart:io`。

方案：

- 把 `_openConnection()` 下沉到 `lib/platform/database/` 的两个实现，`AppDatabase` 只保留 schema、迁移与可选 executor 构造。
- **桌面实现**：保持现有逻辑不变，包括目录回退、旧库迁移、内存兜底与警告。
- **Web 实现**：调用 `driftDatabase` 并传入 `DriftWebOptions`，指向同目录下的 `sqlite3.wasm` 与 `drift_worker.js`。`onResult` 回调把实际选中的存储实现（OPFS 共享/独占、IndexedDB、内存）与缺失能力写入启动日志。
- **失败处理**：WASM 打开失败或只能得到内存实现时，进入可重试的启动错误页，而不是静默降级为“历史本次不可用”。已确认 Web 与桌面保持同等能力，数据持久化不能作为可选项。内存实现只保留为显式开启的诊断模式。
- **持久化申请**：首次成功打开数据库后调用 `navigator.storage.persist()`，把授予结果写入日志；未授予时在设置页持续显示状态与备份入口，不反复弹窗。
- **历史备份与恢复**：新增数据库快照导出与导入，入口放在设置页；导出包包含数据库文件与 schema/应用版本元数据，导入前校验版本并提示覆盖。Web 端至少在以下时机提醒备份：首次完成训练、持久化未获授予、存储配额接近上限。Chrome 系列可进一步使用 File System Access API 让用户选定固定备份文件并一键覆盖；该增强不作为其他浏览器的前提。
- **容量监控**：定期读取 `navigator.storage.estimate()`，接近配额时提示清理旧会话或导出备份，避免在训练中触发写入失败。
- **多标签页**：drift 会优先尝试 SharedWorker 与 OPFS 锁，无法满足时退到 IndexedDB。方案上接受 drift 的选择结果，并在启动日志记录实现名称；检测到多标签同时写入时给出明确提示，避免把并发写入当成正常场景。
- **静态资源**：`web/sqlite3.wasm` 来自 `sqlite3` 包对应版本的发布物，`web/drift_worker.js` 来自 `drift` 对应版本的发布物，或按官方方式自行编译。两者版本必须与 `pubspec.lock` 的 `sqlite3`、`drift` 对齐；升级依赖时同步替换，并写入维护说明。
- **不做**：不引入服务端数据库，不把桌面 SQLite 文件直接搬到浏览器，不做自动云同步。

验收：完成一次训练后刷新页面，历史与设置仍在；备份导出后清除站点数据，再导入能恢复历史；持久化被拒或配额不足时有明确状态与可操作入口；两个标签页同时写入不产生不可恢复错误。

### 5.4 音频

现状：音频算法与 `AudioEngine` 接口已经解耦；[audio_engine.dart](../../lib/audio/audio_engine.dart#L82-L201) 使用 `setBufferStream`、`addAudioDataStream`、`setDataIsEnded`、`loadMem`、循环、音量与渐变；[audio_player.dart](../../lib/audio/audio_player.dart) 依赖 `allInstancesFinished` 推进队列；`web/index.html` 未加载 SoLoud Web 初始化脚本。

方案：

- **初始化脚本**：在 `index.html` 的 Flutter bootstrap 之前加入 SoLoud 的 `init_soloud.js`，保持 `defer` 顺序，确保引擎模块在 Dart 侧调用前开始加载。
- **自动播放策略**：Web 上音频引擎初始化由明确的用户交互触发，例如“开始训练”“播放示例音”。初始化完成后用实际播放状态确认可听，不把 `init()` 成功当成用户能听到声音。
- **接口不变**：现有 `AudioEngine` 与 `AudioPlayer` 的队列、watchdog、暂停/恢复语义保留；Web 只替换底部引擎装配策略，不重写播放逻辑。
- **后端选择**：托管已确认使用 Cloudflare Pages，可在 `_headers` 中设置 COOP/COEP，因此 Web 默认目标为跨源隔离下的 AudioWorklet 多线程后端。启动日志仍需记录实际后端，避免因响应头或 Service Worker 配置错误而静默回退。
- **接播**：完成事件会从音频线程转发到主线程，再经 Dart 队列创建下一段。Web 首版先测量准备耗时与片段间隙；若叠台规模下出现可感知空档，再考虑预拼接、预调度或批量提交，不在方案阶段直接重构。
- **降级**：引擎初始化失败时保持“训练可进入但无声音”的明确提示，不静默继续，避免用户误以为是题目没有声音。

验收：首次点击后能稳定出声；连续片段无异常静默；底噪循环、暂停/恢复、音量渐变、打断与释放均可用；切换标签页后按 5.5 的策略处理。

### 5.5 窗口、生命周期与退出

现状：[main_app.dart](../../lib/ui/main_app/main_app.dart#L52-L207) 使用 `AppLifecycleListener(onExitRequested:)`、`window_manager` 的窗口尺寸/透明度/焦点、`Process.killPid` 与 `exit(0)`；[exit_flow.dart](../../lib/ui/main_app/exit_flow.dart) 对音频释放与日志刷新做有界清理。Web 没有对应语义。

方案：

- **WindowPort**：桌面封装现有的隐藏、显示、尺寸、居中、最小尺寸与测试关闭钩子；Web 为空实现，UI 不感知窗口状态。
- **ExitPort**：桌面保留有界清理与强制退出；Web 监听 `pagehide` 与 `visibilitychange`，做尽力而为的音频停止与日志落盘（内存日志无需落盘），不调用进程退出。卸载前不能依赖异步操作完成，因此不把“关闭前保存”作为正确性保证。
- **会话生命周期**：训练中页面隐藏或被冻结时，产品上选择“暂停训练”，恢复时要求用户显式继续；计时以墙上时间与暂停区间计算，不依赖定时器 tick 数。当前 [contest_timer.dart](../../lib/contest_run/new/contest_timer.dart#L99-L111) 使用 `Timer.periodic` 的 `timer.tick` 累加，浏览器节流后会与真实时间不一致，需要改为时间戳差值。
- **冻结后的状态**：音频完成事件、重试定时器与 watchdog 在冻结期间不会执行，恢复后必须从一致状态继续，而不是补播冻结期间的所有片段。方案上接受“丢失后台片段”，并在恢复时重新对齐当前题目的播放位置。

验收：切标签页再返回时会话状态明确；长时间后台后不会出现计时跳跃或连播历史片段；关闭页面不会留下“正在运行”的假状态。

### 5.6 键盘与输入

现状：[key_event_handler.dart](../../lib/contest_run/key_event_handler.dart#L24-L28) 按逻辑键映射 F1–F12；[contest_running_manager.dart](../../lib/contest_run/new/contest_running_manager.dart#L216-L231) 通过 `ServicesBinding.instance.keyboard.addHandler` 全局监听，回调返回 `false`，不消费事件。

方案：

- **默认策略（已确认）**：Web 端以“全屏 + Keyboard Lock”为默认交互模式。开始训练时由用户点击触发全屏与键盘锁定，锁定成功后再进入计时；退出全屏或按 Esc 会解除锁定。
- **失败回退**：用户拒绝全屏、浏览器不支持或权限未授予时，不阻断训练，自动切到“屏幕按钮 + 可重映射快捷键”，并在训练页保留一次明确提示。
- **Chrome 系列优先**：以桌面 Chrome / Edge 的目标版本为验收基线；Firefox 与 Safari 只保证回退路径可用，不做全屏锁定承诺。
- **事件消费**：只在能够阻止默认行为的按键上消费事件，例如空格滚动、Tab 焦点移动；F5、F11、F12 等浏览器保留键不做“可拦截”承诺。具体哪些键可拦截以 Chrome / Edge 实测为准。
- **焦点**：输入框与全局快捷键的优先级保持现状；页面失焦时清理按键闩锁的逻辑继续保留，并补充 Web 可见性变化的测试。

验收：在 Chrome / Edge 目标版本上完成按键矩阵，锁定成功时 F1–F8 不被浏览器截获；锁定失败时屏幕按钮可完成同一操作；输入框输入不会触发 F 键动作。

### 5.7 诊断导出与剪贴板

现状：[log_export.dart](../../lib/logging/log_export.dart#L84-L111) 通过 `file_selector` 选择保存位置再写文件；`file_selector_web` 的保存位置为空字符串，不能沿用。

方案：

- 抽出 `ExportPort`：桌面使用现有保存对话框；Web 生成 zip 字节后走浏览器下载（`Blob` + 链接触发，或 `XFile.saveTo` 的 Web 实现）。
- 导出结果改成“显示名 + 是否成功”，不再把 `File` 暴露给 UI。桌面的 toast 仍显示完整路径，Web 显示文件名与“已开始下载”。
- 剪贴板复制在安全上下文可用；失败时退化为显示摘要文本供手动复制。
- 导出内容：诊断摘要、内存日志、环境快照、数据库实现与音频后端信息。Web 不包含本机路径。

验收：Web 点击导出能下载可用 zip；取消不会报错；无剪贴板权限时有替代路径。

### 5.8 崩溃上报

现状：[crash_issue_reporter.dart](../../lib/logging/crash_issue_reporter.dart#L3) 导入 `dart:io`，用 `HttpClient` 调用 GitHub API；令牌通过 `--build-dart-define` 注入。

方案（已确认采用 B：Cloudflare Worker 代理）：

- **为什么不能直连**：构建期注入的令牌会原样进入可被任何人下载的 JS 产物；GitHub 令牌即使只授予 Issues 写权限，也足以被用来批量创建或关闭 issue、触发通知并消耗配额。把令牌交给浏览器，等同于把仓库的写入能力公开。此外 `api.github.com` 的浏览器跨域行为不受我们控制，不能作为稳定依赖。
- **部署形态**：使用独立 Worker，不放在 Pages Functions。原因有两点：`_headers` 不作用于 Functions 响应；独立 Worker 可以单独限流、单独轮换密钥，也不会和站点构建耦合。路由优先使用同域 `/api/crash`（Workers Route 优先于 Pages 静态资源），省去 CORS；如果同域路由受限，再退到 `crash.<domain>` 子域，并在 Worker 内只允许正式站点来源。
- **请求契约**：只接受 `POST` 与 `application/json`，请求体上限 256 KB。字段白名单固定为：应用版本与构建号、浏览器与系统信息、语言与时区、错误类型与消息、截断后的堆栈（上限 32 KB）、截断后的诊断日志（上限 64 KB）、用户描述、指纹、可选联系方式。不接收截图、附件、完整 URL 查询串；未知字段直接丢弃，不进入 issue。
- **用户同意**：崩溃页明确列出将发送的内容，用户点击后才发送；默认不自动上报。
- **防滥用**：第一层校验 `Origin` 与 `Sec-Fetch-Site`，只允许正式站点与预览域；这一层可被脚本伪造，只作为门槛。第二层使用 Workers Rate Limiting binding，按 IP 限制为每分钟 5 次、每天 50 次，超限返回 429。第三层做 body 大小、字段长度与 JSON 结构校验。默认不启用 Turnstile，出现滥用后再加；崩溃状态下隐形校验可能失败，必须保留跳过路径。
- **去重**：用“错误类型 + 堆栈 + 版本”计算指纹。KV 保存 24 小时指纹，命中时不再创建新 issue；KV 免费额度每天只有 1,000 次写，写入失败时退化为“不去重但正常上报”，不能因为配额问题丢报告。
- **GitHub 侧**：使用细粒度令牌，只授予目标仓库的 Issues 写权限，存放在 Worker secret 中，前端零令牌。issue 标题带 `[web]` 与指纹，正文用代码块包裹用户内容，转义反引号并限制 `@` 提及，避免触发团队通知。标签固定为 `web-crash` 与应用版本。若要先搜索同指纹 issue，需要额外考虑搜索 API 每分钟 30 次的限制，并缓存结果；首版可以直接创建新 issue，避免复杂度。
- **可观测性**：Workers Analytics 记录状态码、限流命中、GitHub 调用耗时与失败率；不记录报告正文与原始 IP，IP 只用于限流。5xx 与限流异常升高时告警。
- **失败回退**：客户端只做一次带退避的重试；仍失败时提示改用“复制诊断摘要”或“导出日志”，不无限重试，也不把发送失败伪装成成功。
- **密钥与部署**：令牌通过 Wrangler secret 写入，不进入仓库与构建产物；CI 使用最小权限的 Cloudflare API token 部署；预发布使用独立路由；令牌定期轮换。
- **成本**：按当前免费额度（每天 100,000 次请求、每次 10 ms CPU、KV 每天 100,000 次读与 1,000 次写）可覆盖；若日志裁剪或去重逻辑变重，需要重新核算 CPU。
- `CrashPort` 在 Web 上提供代理实现，桌面保留现有直连实现；`canSendReport` 与 UI 文案按平台切换。
- 无论是否上报，Catcher2 的崩溃页、内存日志与导出能力保留。

验收：Web 构建产物中检索不到 GitHub 令牌；伪造来源的脚本被限流或拒绝；超长请求被拒绝且不进入 issue；正常报告能创建带标签的 issue；GitHub 故障时客户端回退到复制/导出；Worker 日志不含报告正文与原始 IP。

### 5.9 计算与资源加载

现状：559 个 WAV，`assets/voice` 目录约 18 MB；[payload_to_audio.dart](../../lib/audio/payload_to_audio.dart#L14-L22) 通过 `rootBundle` 逐文件读取并调用 `worker_manager` 解析；呼号内部已先拼接再播放。

方案：

- **不改训练节奏**：呼号拼接逻辑已经避免逐字母等待播放完成，Web 保持该实现。
- **按需加载**：只预取当前口音与当前难度的资源；首题前可对本次会话可能用到的呼号字符集做一次后台预热，但不阻塞开始。
- **缓存**：依赖浏览器 HTTP 缓存，部署时给带哈希的静态资源设置长缓存；`index.html` 与 `flutter_bootstrap.js` 使用短缓存或协商缓存。
- **计算**：`worker_manager` 在 Web 没有真正并行。WAV 解析是纯字节切分，单段开销小，先测量；底噪生成与叠台混音若在主线程造成可感知卡顿，再评估真正的 Web Worker 或预计算缓存，不在首版引入新依赖。
- **体积**：构建产物中确认只包含实际使用的语音资源；如首屏过大，再评估按口音拆分懒加载或压缩传输。当前目录大小不是传输体积，不能直接当作首屏指标。

验收：冷缓存与热缓存各测一次首题准备时间；弱网下不出现按键后长时间无响应；训练中不因资源加载产生节拍变化。

### 5.10 UI 与文案

- 新增 Web 能力提示：存储持久化状态与备份入口、后台会暂停、快捷键可能被浏览器占用、建议使用桌面 Chrome / Edge。
- 启动警告、崩溃页、设置页中所有涉及“本地路径/日志目录”的文案需要与平台无关，路径由 `ExportPort` 返回。
- `web/index.html` 的模板描述、`manifest.json` 的应用名、主题色与图标需要替换为正式内容；PWA 安装与离线缓存已确认启用，离线只保证已缓存资源可用，后台运行与存储回收的边界不变。
- 当前布局按 1108×796 的最小窗口设计，浏览器窗口可能更小。需要确定 Web 的最小支持视口与缩放策略，并补充窄视口下的滚动与焦点测试。

## 6. 构建、部署与运维

### 6.1 构建

- 首版使用 `flutter build web --release`（默认 JS 编译目标），优先保证兼容性与可调试性；WASM 渲染目标作为后续单独评估项，不与平台适配同时进行。
- 已确认启用 PWA，构建使用离线优先的 Service Worker 策略，缓存版本与构建号绑定；升级后提示刷新，避免旧 Service Worker 继续提供旧资源。首次加载会预热体积较大的语音资源，需在发布说明中提示。
- 使用 `--base-href` 匹配实际部署路径，避免子路径部署时资源 404。
- Web 静态资源必须包含：`sqlite3.wasm`、`drift_worker.js`、SoLoud 的 `init_soloud.js` 及其 `libflutter_soloud_plugin*.js/.wasm`。SoLoud 资源由插件声明自动进入构建产物，`sqlite3.wasm` 与 `drift_worker.js` 需要显式放入 `web/`。
- 版本号继续使用现有 `pubspec.yaml`；Web 页脚显示版本与构建号，便于问题定位。

### 6.2 响应头与缓存

**COOP / COEP 是什么**：它们是两个 HTTP 响应头。COOP（Cross-Origin-Opener-Policy）把当前页面与其他源的窗口上下文隔开，防止跨窗口引用；COEP（Cross-Origin-Embedder-Policy）要求页面加载的所有跨源资源显式声明允许被嵌入（通过 CORS 或 CORP）。两者同时满足时，页面进入“跨源隔离”状态，浏览器才会开放 `SharedArrayBuffer`。SoLoud 的多线程 AudioWorklet 后端依赖 `SharedArrayBuffer`，所以：

- 能设置这两个响应头：音频处理在独立线程，主线程做 UI 或布局时不挤压音频，适合训练场景。
- 不能设置：自动回退到单线程后端。功能可用，但音频处理与 UI 竞争主线程，叠台或复杂渲染时更容易出现间隙，因此需要实测。

启用这两个头的代价：所有跨源资源都必须带 CORP 或 CORS，否则会被拦截；第三方统计、字体、嵌入内容可能失效；Service Worker 返回的文档响应也必须保留这两个头，否则隔离状态会丢失。本站当前没有第三方嵌入，代价可控。

- 需要 AudioWorklet 多线程后端时，HTML、worker 与静态资源响应需一致设置 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: require-corp`。
- 启用 PWA 后，Service Worker 的导航响应必须保留上述响应头；缓存策略不能把无头响应写入文档。
- 带内容哈希的资源使用长期不可变缓存；入口 HTML 与 bootstrap 使用短缓存，避免升级后仍加载旧版本。
- 站点必须是 HTTPS（安全上下文），否则剪贴板、存储持久化、全屏、键盘锁定与 Service Worker 都不可用。

### 6.3 托管与 CI

- **托管已确认：Cloudflare Pages**。构建命令 `flutter build web --release`，输出目录 `build/web`；在 `web/_headers` 中统一设置 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: require-corp`，并对入口 HTML、`flutter_bootstrap.js` 与 Service Worker 使用短缓存，对带哈希资源使用长期不可变缓存。`_headers` 只作用于静态资源，不作用于 Pages Functions 的响应；如果崩溃代理放在 `functions/` 或 `_worker.js`，需要在代码里单独设置响应头。
- **崩溃代理单独部署 Worker**：使用同域 `/api/crash` 路由，或在同域不可用时使用 `crash` 子域；GitHub 令牌只存在于 Worker secret 中，预发布与生产使用不同路由和不同令牌。Worker 响应自行设置 CORS 与安全头，不依赖 `_headers`。
- Cloudflare Pages 免费额度足够本项目：每月 500 次构建、单站点 20,000 个文件、单文件 25 MiB、100 条 `_headers` 规则，静态请求与带宽不计费。当前 559 个语音文件与构建产物体积都在范围内。
- GitHub Pages 不能自定义 COOP/COEP，因此不作为托管选项。
- CI 增加独立的 Web 构建任务：`flutter build web` 成功、产物包含必需静态资源、产物中不含崩溃上报令牌。发布流程在 M4 前不把 Web 加入正式下载列表。
- 增加一个浏览器冒烟测试：加载首页、开始训练、执行一次 QSO、刷新后历史仍在、导出日志可下载。浏览器自动化只能作为冒烟，不替代目标设备的音频与延迟实测。
- 现有 `flutter test` 继续在 VM 上运行；依赖 `dart:io` 的测试不需要迁移到 Web。只为端口层与纯逻辑补充 Web 可运行的测试。

## 7. 实施阶段

| 阶段 | 内容 | 验收标准 | 可回滚点 |
| --- | --- | --- | --- |
| M0 编译打通 | 引入端口接口与条件导入；窗口/退出空实现；内存日志；内存数据库；补 SoLoud 初始化脚本 | `flutter build web` 成功；首页可显示；无未捕获异常；桌面行为不变 | 端口默认为桌面实现，Web 仅为新增分支 |
| M1 数据可用 | SQLite WASM + IndexedDB；持久化申请与容量监控；历史备份/恢复；Web 日志缓冲与下载导出；设置读写 | 刷新后历史与设置保留；备份导出后清站点数据可导入恢复；数据库失败进入可重试错误页；导出 zip 可用 | 关闭 Web 构建，桌面发布不受影响 |
| M2 音频可用 | 交互式音频初始化；SoLoud 初始化时序；完成事件与底噪验证 | 首次点击后出声；连续片段正常；暂停/恢复与音量有效 | 音频未就绪时给出明确提示并允许重试 |
| M3 交互与生命周期 | 可见性暂停/恢复；计时改为时间戳；默认全屏 + 键盘锁定及回退；关闭页面清理 | Chrome / Edge 按键矩阵通过；后台恢复一致；计时不漂移 | 关闭锁定模式，回退屏幕按钮与重映射 |
| M4 发布准备 | 响应头、缓存、子路径、PWA 安装与离线缓存、崩溃代理 Worker 与限流、CI 构建与冒烟；文案与 manifest；发布说明 | 预发布环境通过验收清单；PWA 可安装且升级后不加载旧资源；代理拒绝伪造来源与超频请求；CI 产物检查通过 | 保留桌面发布；Web 可单独下线 |

每个阶段结束后先在桌面回归一次完整训练流程，避免端口化重构影响现有平台。

## 8. 验证矩阵

| 项目 | 环境 | 观察点 |
| --- | --- | --- |
| 构建与启动 | Chrome / Edge（主）、Firefox / Safari（回退） | 首页进入、无控制台错误、实际数据库与音频后端 |
| 音频首次出声 | 新站点、无历史交互、拒绝自动播放 | 点击后解锁成功或明确失败提示 |
| 音频连续性 | 不同难度与叠台规模 | 片段间隙、准备耗时、卡顿与 GC 影响 |
| 底噪与音量 | 暂停、恢复、AGC 渐变、音量设置 | 循环无中断、渐变无爆音 |
| 历史持久化 | 普通/隐私模式、刷新、清站点数据 | 数据保留、备份恢复、持久化状态提示 |
| 历史备份/恢复 | 导出后清站、重新导入 | schema 校验、覆盖确认、数据完整 |
| 多标签页 | 两个标签同时训练 | 写入冲突、数据一致性、提示 |
| 生命周期 | 切标签、最小化、冻结、恢复、关闭 | 暂停/恢复、计时、无补播风暴 |
| 快捷键 | Chrome / Edge F1–F12、焦点丢失、锁定拒绝 | 锁定成功不被截获、回退可用、无副作用 |
| 存储 | 配额不足、持久化被拒、存储清理 | 启动可用性、警告、备份入口 |
| 导出与剪贴板 | 正常、取消、权限拒绝 | zip 内容、下载行为、替代路径 |
| 崩溃上报代理 | 正常、伪造来源、超频、超长请求、GitHub 故障 | 无令牌泄露、限流生效、错误可回退、日志无正文 |
| PWA | 安装、离线、版本升级 | 可安装、离线启动、旧缓存不残留 |
| 弱网与冷缓存 | 限速、清缓存 | 首题准备时间、资源失败提示 |
| 令牌检查 | 正式产物 | 全文检索无崩溃上报令牌 |

## 9. 风险与待决策

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 浏览器回收站点存储 | 历史丢失 | 持久化申请 + 备份/恢复 + 容量监控；把备份作为产品能力，而不是提示语 |
| 后台节流/冻结 | 训练中断、计时漂移 | 暂停策略 + 时间戳计时；不承诺后台运行 |
| 快捷键被浏览器占用 | 操作不完整 | 默认全屏 + Keyboard Lock，失败回退屏幕按钮与重映射 |
| 首次自动播放失败 | 用户以为无声音 | 交互解锁 + 可播放状态确认 |
| 单线程音频回退 | 大数据量下卡顿 | 优先支持自定义响应头的托管；记录实际后端并实测 |
| 首屏资源体积 | 进入训练慢 | 按需预取、HTTP 缓存、PWA 预热；后续评估懒加载 |
| Web 端令牌泄露 | 仓库被写入 | 前端零令牌；Worker secret 保存细粒度 token；限流、去重与字段白名单 |
| Service Worker 旧缓存 | 升级后行为不一致 | 缓存版本绑定构建号，升级提示刷新 |
| 窄视口布局 | 内容截断 | 先确定最小支持视口，再决定是否调整布局 |

### 9.1 已确认的决策

1. Web 与桌面保持同等能力，不按“只做训练、弱化历史与诊断”降级。
2. 首发以桌面 Chrome / Edge 为基线；Firefox 与 Safari 只保证回退路径。
3. 快捷键默认采用“全屏 + Keyboard Lock”，失败时回退。
4. 启用 PWA 安装与离线缓存。
5. 托管使用 Cloudflare Pages，启用 COOP/COEP 与多线程音频。
6. Web 崩溃上报采用 Cloudflare Worker 代理，前端不携带任何令牌。

### 9.2 实施前需要准备的参数

1. 目标 GitHub 仓库，以及只授予 Issues 写权限的细粒度令牌。
2. 正式域名、Cloudflare Pages 项目与 `/api/crash` 路由；若同域不可用，准备 `crash` 子域。
3. 预发布环境的独立路由、独立 Worker secret 与 Cloudflare 部署用 API token。
4. 崩溃页的隐私说明与用户同意文案，需要与最终字段白名单一致。

## 10. 参考

- Flutter Web 常见问题：https://docs.flutter.dev/platform-integration/web/faq
- Drift Web 配置：https://drift.simonbinder.eu/platforms/web/
- sqlite3 Web 支持与 WASM 发布物：https://github.com/simolus3/sqlite3.dart
- flutter_soloud Web 初始化说明：https://docs.page/alnitak/flutter_soloud_docs/get_started/web_notes
- Chrome Web Audio 自动播放策略：https://developer.chrome.com/blog/web-audio-autoplay
- Page Lifecycle API：https://developer.chrome.com/docs/web-platform/page-lifecycle-api
- Keyboard Lock：https://developer.chrome.com/docs/capabilities/web-apis/keyboard-lock
- 存储持久化：https://developer.mozilla.org/en-US/docs/Web/API/StorageManager/persist
