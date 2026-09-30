# SSB Runner 日志系统：现有库调研

> 调研目的：判断"完善日志系统"的需求里，哪些能直接用现成库满足，哪些必须自研。
> 需求基准：`docs/design/logging_system_design.md` 中的目标 G1 - G7。
> 调研时间：2026-09-30
> 数据来源：pub.dev API（版本 / 发布日期 / 平台标签 / likes / pub points）+ 解包源码逐项核对 API 能力 + 许可证核对。
> 说明：库的版本、维护度与政策会随时间变化，正式落地前建议复核一次。

---

## 0. 结论（TL;DR）

1. **没有任何单一库能覆盖全部需求。** 覆盖度最高的是"文件落盘 + 轮转 + 保留"这一层，其余四块必须自研或引入第二个库。
2. **管道层已有成熟库，而且本项目现有依赖就已内建。** 已锁定的 `logger 2.8.0` 自带 `AdvancedFileOutput`（缓冲 + 按大小轮转 + 保留数 + 文件头尾）和 `LogfmtPrinter`（logfmt 输出）；无需新增依赖即可满足 G1 与 G6。
3. **需要自研的只有四块胶水：**
   - 启动序列编号埋点（G2）——无任何库提供；
   - 环境快照组装（G3）——`package_info_plus` / `device_info_plus` 只给原料，组装与落盘要自己做；
   - 错误前上下文 dump 到文件（G4）——库里有内存环形缓冲，但没有库会自动把它写进日志文件；
   - 导出 zip 与脱敏（G5 / G7）——无库覆盖。
4. **候选库结论：**
   - 首选组合：`package:logging` + `logging_appenders`（提供 `RotatingFileAppender` 与"异步初始化缓冲"）；若想零新增依赖，则 `logger.AdvancedFileOutput`。
   - 可选远程增强：`sentry_flutter` + `sentry_logging`（桌面原生崩溃 + breadcrumb 环形缓冲 + 设备上下文），代价是数据外传与后端成本。
   - 可选现场可视化：`talker` / `talker_flutter`（应用内日志屏 + 分享），但**不解决"应用起不来"的场景**。
   - 明确淘汰：`f_logs`、`lumberdash`（停更且 SDK < 3.0.0）、`flutter_logs`（仅移动端），以及 pub.dev 搜索中大量 0 - 2 likes 的新包。
5. **一个任何库都不解决的问题：** 本项目 Windows release 是 GUI 子系统、没有控制台，因此**不能依赖 stdout**，日志必须落盘。这是工程约束，不是库能力。

---

## 1. 调研范围与方法

**需求分解（来自设计文档）：**

| 编号 | 需求 |
|---|---|
| G1 | 全生命周期落盘（含启动早期） |
| G2 | 启动失败可定位（编号埋点 + 错误信息） |
| G3 | 环境可复现（session header：OS / 版本 / 运行时环境） |
| G4 | 崩溃上下文完整（环形缓冲 dump + 异常详情） |
| G5 | 用户可交付日志（导出 zip / 复制摘要） |
| G6 | 体积性能可控（级别 / 轮转 / 保留 / 去重 / 异步写） |
| G7 | 不泄露敏感信息（路径脱敏） |

**方法：**

1. 用 pub.dev API 拉取候选包元数据与评分标签（含平台标签）。
2. 下载包 tarball 解包，**直接读源码**核对能力，而不是只看 README。
3. 核对许可证与 SDK 约束是否与本项目（Dart ^3.8.1 / Flutter 3.47.5）兼容。
4. 用 pub.dev 搜索接口做补充发现，再用采用度指标过滤低质量包。

**排除标准：** SDK 不兼容、平台不含桌面、停更（> 2 年无发布）、零采用度。

---

## 2. 候选库总览

| 包 | 版本 | 最近发布 | 平台 | 采用度 | 许可 | 定位 | 结论 |
|---|---|---|---|---|---|---|---|
| `logging` | 1.3.0 | 2024-10-17 | 全平台 | 1005 likes / 160 pts | BSD-3 | 官方日志 facade | **采用**（facade） |
| `logger` | 2.8.0 | 2026-09-05 | 全平台 | 3730 likes / 150 pts | MIT | 美化输出 + 文件输出 | **采用**（已在依赖） |
| `logging_appenders` | 2.0.0+1 | 2026-02-03 | 全平台 | 44 likes / 160 pts | MIT | 轮转文件 + 远程 appender | **候选首选** |
| `sentry_flutter` | 9.30.1 | 2026-09-22 | 全平台含桌面 | 1085 likes / 140 pts | MIT | 远程崩溃上报 | 可选（P3） |
| `sentry_logging` | 9.30.1 | 2026-09-22 | 全平台 | 26 likes / 160 pts | MIT | `logging` -> Sentry 桥 | 可选（配合上者） |
| `talker` | 5.1.20 | 2026-07-28 | 全平台 | 859 likes / 160 pts | MIT | 日志中枢 + 内存历史 | 可选 |
| `talker_flutter` | 5.1.20 | 2026-07-28 | 全平台 | 665 likes / 160 pts | MIT | 应用内日志屏 + 分享 | 可选（现场） |
| `catcher_2` | 2.1.12 | 2026-08-20 | 全平台 | 57 likes / 150 pts | MIT | 异常捕获与上报 | **已用**（保留） |
| `simple_logger` | 1.10.1 | 2026-09-09 | 全平台 | 100 likes / 150 pts | MIT | 控制台美化 | 不满足（无落盘） |
| `logman` | 1.0.0 | 2026-04-02 | 全平台 | 10 likes / 150 pts | MIT | 加密日志 | 不采用（采用度低） |
| `isolate_logger` | 1.0.14 | 2026-07-05 | 全平台 | 18 likes / 160 pts | MIT | 多 isolate 文件日志 | 不采用（采用度低） |
| `chirp` | 0.9.0 | 2026-05-08 | 全平台 | 25 likes / 150 pts | MIT | 结构化日志 | 不采用（0.x） |
| `alice` | 1.11.0 | 2026-09-29 | 全平台 | 348 likes / 160 pts | MIT | HTTP 抓包检查器 | 不适用（领域不同） |
| `f_logs` | 2.0.1 | 2022-04-26 | 桌面 | 99 likes / 130 pts | MIT | 日志 + 崩溃 + UI | **淘汰**（SDK < 3.0.0） |
| `lumberdash` | 3.0.0 | 2021-03-08 | 全平台 | 59 likes / 140 pts | MIT | 可插拔日志抽象 | **淘汰**（停更 5 年） |
| `flutter_logs` | 2.2.7 | 2026-05-06 | 仅 Android / iOS | 123 likes / 130 pts | MIT | 文件日志 | **淘汰**（不支持桌面） |
| `flog` | 0.2.1 | 2021-06-24 | 全平台 | 5 likes / 140 pts | MIT | 控制台美化 | **淘汰**（停更） |

**pub.dev 搜索发现但采用度过低（0 - 2 likes），不予考虑：** `file_logs`、`flex_logger_file`、`comon_logger_file`、`omni_logger`、`hyper_logger`、`logkit`、`logger_export`、`purple_logger`、`light_logger_pro`、`x_logger`、`the_logger_viewer_widget`。

---

## 3. 关键库能力核对（源码级）

### 3.1 `package:logger`（本项目已依赖，锁定 2.8.0）

**这是本次调研最重要的发现：轮转文件输出已经内建。**

- `AdvancedFileOutput`（`lib/src/outputs/advanced_file_output.dart`）：
  - 内存缓冲 + 定时批量落盘（`maxDelay` 默认 2s，`maxBufferSize` 默认 2000）；
  - 按大小轮转（`maxFileSizeKB` 默认 1024；`> 0` 时 `path` 视为目录，当前文件固定叫 `latest.log`）；
  - 保留数量控制（`maxRotatedFilesCount`，默认 null = 不限）；
  - 指定级别立即 flush（`writeImmediately` 默认 warning / error / fatal）；
  - 支持 `fileHeader` / `fileFooter` —— **可直接用来写 session header**；
  - Windows 行尾适配（`\r\n`）；文件创建用同步检查，注释里明确写着"避免在早期崩溃场景丢失初始启动日志"。
  - 限制：轮转检查走定时器（`fileUpdateDuration` 默认 1 分钟），**不是实时触发**；只按大小、不按天。
- `LogfmtPrinter`（`lib/src/printers/logfmt_printer.dart`）：直接输出 `level=... msg="..." key=value` 格式 —— 与设计文档 5.3 的格式一致。
- `MemoryOutput`（`lib/src/outputs/memory_output.dart`）：**固定容量的环形缓冲**（`ListQueue` + 满则淘汰队首，`bufferSize` 默认 20），并支持 `secondOutput` 链式转交 —— 正好是设计文档里 RingBufferSink 的原语。
- `FileOutput`：最简单的追加写，无轮转。
- `MultiOutput`：多输出扇出。

结论：**G1 + G6 的管道部分零新增依赖即可满足。**

### 3.2 `package:logging`（官方 facade，本项目已是 transitive 依赖）

- 提供 `Logger('a.b')` 层级命名、`Level`（FINEST - SHOUT）、`Logger.root.onRecord` 流。
- 是所有 appender 生态的公共接口。
- 依赖它不增加风险（Dart 官方包，BSD-3）。

### 3.3 `logging_appenders` 2.0.0+1（轮转文件的另一选择）

- `RotatingFileAppender`（`lib/src/rotating_file_appender.dart`）：
  - 构造参数：`baseFilePath` / `keepRotateCount` 默认 3 / `rotateAtSizeBytes` 默认 10 MB / `rotateCheckInterval` 默认 5 分钟；
  - 句柄常开，空闲 `keepOpenDuration`（2 分钟）后自动 flush + close；
  - **`getAllLogFiles()` 直接返回当前所有轮转文件** —— 对导出功能非常友好；
  - 显式处理了 Windows 限制：注释写明"打开中的文件在 Windows 上无法重命名，于是先关闭再重试"；
  - 校验：父目录不存在时构造即抛 `StateError`（需先建目录）。
- `AsyncInitializingLogHandler`：**在异步解析出的路径就绪之前，先缓冲所有日志记录，就绪后回放** —— 正好对应"启动最早期日志不能丢"的需求。
- 配套：`ColorFormatter`、`DefaultLogRecordFormatter`（含异常链 `causedBy`）、`PrintAppender`。
- 远程 appender：Loki、logz.io、GELF / Graylog —— 为 P3 远程上报预留通路，无需换框架。
- 约束：SDK `>= 3.8.0`（本项目 ^3.8.1，满足）；MIT；单一维护者，44 likes。

### 3.4 `sentry_flutter` 9.30.1 + `sentry_logging` 9.30.1

- `sentry_flutter` 是 Flutter 插件，平台标签包含 windows / linux / macos；仓库内存在 `windows/`、`linux/`、`macos/` 原生集成，其 `windows/CMakeLists.txt` 使用 `crashpad` 作为 `native_backend` —— **桌面原生崩溃可捕获**。
- 自动采集设备与应用上下文（依赖 `package_info_plus`），自带 breadcrumb 环形缓冲（默认 100 条）并附加到事件上。
- `sentry_logging` 提供 `LoggingIntegration`：监听 `Logger.root.onRecord`，按级别分别转成 breadcrumb（默认 `>= INFO`）、事件（默认 `>= SEVERE`）与 Sentry Logs。
- 脱敏：可在 `beforeSend` 钩子里洗数据。
- 代价：需要 Sentry 项目与 DSN，日志会**离机上传**；免费额度与隐私政策需评估；这也是 P3 才考虑的原因。

### 3.5 `talker` 5.1.20 + `talker_flutter` 5.1.20

- `talker` 核心：内存 `history` + `TalkerObserver`（`onLog` / `onError` / `onException`）。
- **核心不含文件持久化。** 源码中除 `talker_flutter` 的导出逻辑外，没有任何写文件的代码。
- `talker_flutter`：`TalkerScreen` 应用内日志屏、过滤、设置、`runTalkerZonedGuarded`，以及"导出"—— 实现方式是把内存日志写成一个临时 txt 再走 `share_plus` 分享，**没有 zip，也没有落到固定位置**。
- 适用场景：开发/测试/现场排查时自带日志界面；对"应用起不来"完全无能为力。
- 扩展点：`TalkerObserver` 接口很简单，可以自己实现一个把 `onLog` 追加到文件的 observer。

### 3.6 `catcher_2` 2.1.12（本项目已用）

- 定位是**异常捕获与呈现**，不是通用 logger：只有未处理异常与显式 `reportCheckedError` 会进入 handler。
- 已有 handler：file / console / sentry / http / slack / discord / email(auto+manual) / toast / snackbar。
- 已有 mode：`DialogReportMode` / `PageReportMode` / `SilentReportMode`。
- 报告内自带 device parameters 与 application parameters（环境信息的一部分）与 custom parameters。
- 已接管 `FlutterError.onError` / `PlatformDispatcher.instance.onError` / `Isolate.current.addErrorListener` / `runZonedGuarded`。
- 结论：继续保留，作为"异常汇聚与 UI 呈现"的一环；但要补齐"过程日志落盘"，它本身做不到。

### 3.7 其他与淘汰说明

- `f_logs`：功能形态最接近（日志 + 崩溃 + 文件 + UI），但最后发布 2022-04，SDK 约束 `>= 2.12.0 < 3.0.0`，与当前 Dart 3.8 不兼容。
- `lumberdash`：可插拔抽象 + 多 client，但 2021 年后停更，SDK 同样 < 3.0.0。
- `flutter_logs`：文件日志 + 加密，但平台标签只有 Android / iOS，**不支持桌面**。
- `simple_logger`：基于 `logging` 的漂亮控制台输出与堆栈格式化，无文件能力。
- `logman`：基于 `logger` 的加密日志，10 likes，采用度不足。
- pub.dev 搜索命中的 `file_logs` / `omni_logger` / `hyper_logger` 等：0 - 2 likes，无可验证的维护记录，不建议作为基础设施依赖。

---

## 4. 需求覆盖矩阵

图例：满足 用 Y；部分满足 用 P；不覆盖 用 N。

| 需求 | logger | logging + logging_appenders | sentry_flutter | talker_flutter | catcher_2 | 需自研 |
|---|---|---|---|---|---|---|
| G1 全生命周期落盘 | Y | Y | P（上报，不是本地文件） | N（内存） | N（仅异常） | — |
| G2 启动埋点 | N | N | N | N | N | **Y** |
| G3 环境快照 | N | N | Y（自动上下文，但随上报） | N | P（仅错误报告内） | **Y**（本地 header） |
| G4 崩溃上下文 | P（`MemoryOutput` 环形缓冲） | N | Y（breadcrumb） | Y（history + UI） | N | **Y**（dump 到文件） |
| G5 导出 | N | P（`getAllLogFiles`） | P（控制台下载附件） | P（分享临时 txt） | N | **Y**（zip + 摘要） |
| G6 轮转 / 保留 / 缓冲 | Y（`AdvancedFileOutput`） | Y（`RotatingFileAppender`） | N | N | N | — |
| G7 脱敏 | N | N | P（`beforeSend` 钩子） | N | N | **Y** |

**读法：** 没有任何一列是"全 Y"。选择任一库之后，仍然有一到四块必须自研。

---

## 5. 缺口：必须自研的部分

| 缺口 | 为什么库不覆盖 | 实现规模 |
|---|---|---|
| 启动序列编号埋点 `boot.step(...)` | 属于应用启动流程编排，与日志后端无关 | 小（一个包装函数 + 12 个调用点） |
| session header 组装 | package_info_plus / device_info_plus 只提供原料 | 小 |
| 错误前上下文 dump 到文件 | 库提供环形缓冲，但不会在错误时主动落盘 | 小（订阅 `SEVERE` + 冲刷 `MemoryOutput`） |
| 导出 zip + 复制诊断摘要 | 无库做"打包日志 + 环境信息 + 脱敏" | 中（`archive` 已是依赖，`share_plus` / `file_selector` 可选） |
| 脱敏 | 通用库不知道哪些字段敏感 | 小 |
| 日志目录回退链 | 依赖 `path_provider` 的返回，属于业务策略 | 小 |
| 运行时"详细日志"开关 | 属应用设置 | 小 |

---

## 6. 组合方案与推荐

### 方案 A：零新增依赖（用现有 `logger`）

`logger 2.8.0` 的 `AdvancedFileOutput` + `LogfmtPrinter` + `MemoryOutput`，配自研胶水。

- 优点：不引入新依赖；锁定版本已具备轮转 / 保留 / 缓冲 / 文件头 / logfmt。
- 缺点：`logger` 的 `LogOutput` 与 `package:logging` 是两套 API；轮转靠定时检查；无 `getAllLogFiles()` 之类的文件枚举（需自己 `list` 目录）；不按天轮转。

### 方案 B：标准 facade（推荐）

`package:logging` 作为 facade + `logging_appenders` 的 `RotatingFileAppender` / `AsyncInitializingLogHandler`，配自研胶水。

- 优点：官方 facade 生态；`AsyncInitializingLogHandler` 正好解决"日志目录还没解析出来时早期日志会丢"的问题；`getAllLogFiles()` 直接服务导出；远程 appender（Loki / GELF）为 P3 铺路，不必换框架。
- 缺点：新增 1 个依赖，采用度不高（44 likes，单一维护者），需要锁定版本并留意维护状态。

### 方案 C：在 A 或 B 之上叠加远程（可选，P3）

加 `sentry_flutter` + `sentry_logging`。

- 收益：桌面原生崩溃（Windows Crashpad）、breadcrumb 自动环形缓冲、设备 / 版本上下文、离线缓存后上报。
- 代价：数据外传 + DSN + 隐私告知 + 免费额度。

### 方案 D：叠加现场可视化（可选）

加 `talker_flutter`，在设置页开一个日志屏，方便现场与测试人员查看与分享。

- 注意：它读的是内存历史，应用起不来的场景用不上；不能替代文件落盘。

### 推荐

| 阶段 | 建议 |
|---|---|
| P0 / P1 | **方案 B**；若团队希望先零新增依赖，则**方案 A**，两者只差"文件 sink 的实现"，接口设计相同 |
| P2 | 自研导出 + 开关 + 脱敏（无论 A / B 都需要） |
| P3 | 视隐私决策评估**方案 C**；如需现场可视化补**方案 D** |

---

## 7. 风险与选型注意

1. **低采用度依赖风险**：`logging_appenders` 只有 44 likes、单一维护者。若采用，建议在 `pubspec.yaml` 锁死版本，并把它的使用面收敛到一个 `FileSink` 适配器里，必要时可替换为方案 A（`logger.AdvancedFileOutput`）。
2. **轮转不是实时的**：`logger.AdvancedFileOutput` 与 `logging_appenders.RotatingFileAppender` 都靠定时检查触发轮转。若对单文件体积有硬性上限，需要在应用侧补充检查。
3. **Windows 文件重命名限制**：`logging_appenders` 已处理（关闭再重试）。若自研 sink，必须注意打开中的文件不能改名。
4. **首发日志丢失**：这是"没有日志"最隐蔽的形态 —— 目录解析、依赖初始化都发生在最早期。`logger` 的同步目录检查与 `logging_appenders` 的缓冲 handler 都是针对这一点，选型时应优先考虑。
5. **隐私**：任何远程方案都会把日志送出设备，必须默认关闭或明确告知；本地文件方案也要脱敏用户路径。
6. **不要高估"应用内日志屏"**：`talker_flutter` 这类方案在"应用根本没起来"时不可用，只能作为补充。

---

## 8. 结论

- 需求中的**文件落盘、轮转、保留、缓冲、格式化**已有成熟库，且本项目**现有依赖 `logger` 就已内建**，无需从零写文件 sink。
- **启动埋点、环境快照组装、崩溃前上下文 dump、导出与脱敏**必须自研，但每块规模都不大。
- 因此设计文档中原计划的 `FileSink` / `RingBufferSink` 可以从"自研实现"改为"**优先复用库、自研仅做适配与胶水**"，可显著减少代码量与维护面。
- 推荐路线：**P0/P1 用方案 B（或 A）**，P2 自研导出与脱敏，P3 再评估 Sentry 与 talker。

---

## 附录 A：原始数据（pub.dev API，2026-09-30 采集）

| 包 | 版本 | 发布日期 | likes | pub points | 平台标签 |
|---|---|---|---|---|---|
| logging | 1.3.0 | 2024-10-17 | 1005 | 160 | android, ios, windows, linux, macos, web |
| logger | 2.8.0 | 2026-09-05 | 3730 | 150 | android, ios, windows, linux, macos, web |
| logging_appenders | 2.0.0+1 | 2026-02-03 | 44 | 160 | android, ios, windows, linux, macos |
| talker | 5.1.20 | 2026-07-28 | 859 | 160 | android, ios, windows, linux, macos, web |
| talker_flutter | 5.1.20 | 2026-07-28 | 665 | 160 | android, ios, windows, linux, macos, web |
| sentry_flutter | 9.30.1 | 2026-09-22 | 1085 | 140 | android, ios, windows, linux, macos, web |
| sentry | 9.30.1 | 2026-09-22 | 582 | 160 | android, ios, windows, linux, macos, web |
| sentry_logging | 9.30.1 | 2026-09-22 | 26 | 160 | android, ios, windows, linux, macos, web |
| catcher_2 | 2.1.12 | 2026-08-20 | 57 | 150 | android, ios, windows, linux, macos, web |
| simple_logger | 1.10.1 | 2026-09-09 | 100 | 150 | android, ios, windows, linux, macos, web |
| logman | 1.0.0 | 2026-04-02 | 10 | 150 | android, ios, windows, linux, macos, web |
| isolate_logger | 1.0.14 | 2026-07-05 | 18 | 160 | android, ios, windows, linux, macos |
| chirp | 0.9.0 | 2026-05-08 | 25 | 150 | android, ios, windows, linux, macos, web |
| alice | 1.11.0 | 2026-09-29 | 348 | 160 | android, ios, windows, linux, macos, web |
| f_logs | 2.0.1 | 2022-04-26 | 99 | 130 | android, ios, windows, linux, macos |
| lumberdash | 3.0.0 | 2021-03-08 | 59 | 140 | android, ios, windows, linux, macos, web |
| flutter_logs | 2.2.7 | 2026-05-06 | 123 | 130 | android, ios |
| flog | 0.2.1 | 2021-06-24 | 5 | 140 | android, ios, windows, linux, macos, web |

**本项目相关锁定版本：** `logger 2.8.0`（pubspec 约束 `^2.6.2`）、`logging 1.3.0`（transitive）、Flutter 3.47.5、Dart SDK ^3.8.1。

## 附录 B：核对过的源文件

| 包 | 文件 | 结论要点 |
|---|---|---|
| logger | `lib/src/outputs/advanced_file_output.dart` | 缓冲 / 大小轮转 / 保留数 / fileHeader / writeImmediately / Windows 行尾 |
| logger | `lib/src/outputs/memory_output.dart` | 固定容量环形缓冲 + secondOutput 链 |
| logger | `lib/src/printers/logfmt_printer.dart` | logfmt 输出 |
| logger | `lib/src/outputs/file_output.dart` | 最简追加写，无轮转 |
| logging_appenders | `lib/src/rotating_file_appender.dart` | 大小轮转 / keepRotateCount / getAllLogFiles / Windows 重命名处理 / AsyncInitializingLogHandler |
| logging_appenders | `lib/src/logrecord_formatter.dart` | DefaultLogRecordFormatter / ColorFormatter / 异常链 |
| logging_appenders | `lib/src/base_appender.dart` | attachToLogger / dispose 订阅管理 |
| sentry_flutter | `windows/CMakeLists.txt` | `native_backend = crashpad`（桌面原生崩溃） |
| sentry_logging | `lib/src/logging_integration.dart` | logging -> breadcrumb / event / logs 的级别映射 |
| talker | `lib/src/observer.dart` | TalkerObserver(onLog/onError/onException)，核心无文件写 |
| talker_flutter | `lib/src/utils/download_logs/download_logs_native.dart` | 写临时 txt + share_plus，无 zip |
| catcher_2 | `lib/mode/page_report_mode.dart` 等 | handler / mode 清单，仅异常不记过程 |
