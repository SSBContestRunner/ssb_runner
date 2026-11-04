# 测试完整度分析报告（重构前基线）

> 分析对象：`ssb_contest_runner` 当前工作区（分支 `fix/v0.2.1-alpha01`）
> 分析日期：2026-10-31
> 分析方式：全量执行 `flutter test --coverage` + 静态分析 + 源码/测试逐层比对
> 说明：本报告只做评估，不含任何代码改动。

**结论先行**：当前测试"内核强、外围弱"。纯逻辑层（题目生成、竞赛规则、计分、DXCC、复盘）已达可重构水准；但**输入映射、状态机组合分支、数据库迁移/启动、UI 与桌面壳层**存在明显缺口。若按现状直接重构，最可能出问题的地方不是算法，而是"按键 → 事件 → 状态 → 落库"这条链路。

---

## 一、实测基线

| 项目 | 结果 |
|---|---|
| 测试文件 | 25 个（`test/` 下，无 `integration_test/`） |
| 用例声明 | 163 个 `test`/`testWidgets`，167 次执行（含循环参数化） |
| 执行结果 | 全部通过，耗时约 10 秒 |
| `flutter analyze` | 通过（仅 1 条 info：`CQ_WPX` 命名） |
| 行覆盖率（已插桩文件） | **62.3%**（2864/4600） |
| 测试从未加载的源文件 | **22 个 / 1855 行**（按 0% 计入后整体约 **46%**） |

> 口径说明：`flutter test --coverage` 只统计被测试加载过的库，因此 62.3% 是"乐观值"；把从未被任何测试 import 的文件按未覆盖计入后约 46%。生成文件 `app_database.g.dart` 已从统计中剔除。

### 分层覆盖率

| 层 | 覆盖行/可执行行 | 覆盖率 | 评价 |
|---|---|---|---|
| `lib/training`（题池/随机/复盘） | 174/179 | 97.2% | 优秀 |
| `lib/dxcc` | 96/106 | 90.6% | 优秀 |
| `lib/state_machine`（通用库） | 41/48 | 85.4% | 良好 |
| `lib/contest_type`（规则/交换/计分） | 249/313 | 79.6% | 良好 |
| `lib/settings` | 68/90 | 75.6% | 中等 |
| `lib/contest_run/new`（编排层） | 557/757 | 73.6% | 中等偏上 |
| `lib/contest_run/state_machine` | 187/297 | 63.0% | **不足** |
| `lib/audio` | 258/440 | 58.6% | 不均衡 |
| `lib/common` | 40/86 | 46.5% | 不足（`dirs.dart` 0%） |
| `lib/logging` | 249/555 | 44.9% | 不足 |
| `lib/contest_run` 核心（键盘/计分管理） | 57/133 | 42.9% | **不足** |
| `error_handling.dart` | 10/35 | 28.6% | **不足** |
| `lib/ui` | 585/2361 | 24.8% | **严重不足** |
| `lib/db` | 9/98 | 9.2% | **严重不足** |
| `main.dart` / 启动组装 | 0/75 | 0% | 无测试 |

### 测试从未加载的源文件（22 个）

```
lib/common/constants.dart                         4
lib/common/streams.dart                           5
lib/contest_run/contests.dart                    37
lib/contest_type/contest_type.dart               14
lib/contest_type/exchange_manager.dart           11
lib/logging/boot_trace.dart                      45
lib/logging/logging_bootstrap.dart              112
lib/main.dart                                    75
lib/ui/bottom_panel/bottom_panel.dart            24
lib/ui/bottom_panel/qso_speed_area.dart         243
lib/ui/bottom_panel/time_and_score/score_area/score_area.dart            136
lib/ui/bottom_panel/time_and_score/score_area/score_area_cubit.dart       70
lib/ui/bottom_panel/time_and_score/score_area/score_area_data.dart        15
lib/ui/bottom_panel/time_and_score/time_and_score_area.dart               72
lib/ui/main_app/home_page.dart                   47
lib/ui/main_app/main_app.dart                   435
lib/ui/main_page/key_tips.dart                  133
lib/ui/main_page/main_page.dart                  71
lib/ui/main_page/training_review_overlay.dart   155
lib/ui/qso_result_table/qso_record_table.dart    54
lib/ui/qso_result_table/qso_result_list/qso_result_list.dart              54
lib/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart       43
```

---

## 二、按测试类型逐项评估

### 1. 状态机流转测试：`C+`（结构有，矩阵不全）

现有 [single_call_run_state_machine_test.dart](../../test/single_call_run_state_machine_test.dart)（18 例）与 [contest_state_change_handler_test.dart](../../test/contest_state_change_handler_test.dart)（14 例）覆盖了主链路：抄对呼号 → 索要交换 → 提交序号 → `QsoEnd` → `NextCall`，以及 QsoEnd/S&P 落库后的兜底推进。近期硬冻结修复（`a884107`）已有 4 个回归用例：空输入跳过落库、落库异常、签字音频期间输入被清空、呼号更正，这部分**可以放心重构**。

但按"状态 × 事件"矩阵看，28 个事件处理器中约 13 个被完整覆盖（约 46%）：

| 状态 | 未覆盖的流转 | 风险 |
|---|---|---|
| `WaitingSubmitCall` | `WorkedBefore`、`NoCopy`、`SubmitCall` 抄全、`SubmitCall` 前缀 | 中（前两个事件在 `lib/` 中**从未被发射**，属死分支） |
| `WaitingSubmitCall` | `SubmitCallAndHisExchange`（F5 只抄到呼号、未抄序号） | **高** |
| `HeRepeatCorrectCallAnswer` | `Retry`、`SubmitCallAndHisExchange`、`SubmitHisExchange` | 中高 |
| `ReportMyExchange` | `ReceiveExchange`（呼号校验通过后进入报序号） | **高** |
| `WaitingSubmitMyExchange` | `Retry`（AGN 或 10s 超时）、`NoCopy` | **高**（超时真实可触发） |
| `SpListeningCq` | `Retry`（超时/AGN）、`NextCall` | **高** |
| `SpWaitingHisExchange` | `Retry`、`NextCall` | **高** |
| 全部状态 | 无效事件的 `dropped` 告警分支、`_transitionFields` 的 S&P 分支 | 低 |

最关键的缺口是 **Run 模式按 F5 的路径**（[contest_operation_event_handler.dart](../../lib/contest_run/new/contest_operation_event_handler.dart#L334-L344) → `SubmitCallAndHisExchange` → `ReportMyExchange` → 自动 `ReceiveExchange` → 报序号）。这条链路同时命中了 45% 覆盖率的入口文件与状态机未覆盖分支，重构状态机时最容易断。

另有代码异味值得在重构时处理：`WorkedBefore` 与 `NoCopy` 事件没有任何生产代码发射，只有状态机里挂着处理器——是死代码或漏接的发射点，测试无法替你判断，需要产品/交互确认。

### 2. 逻辑测试：`B`（规则强，输入层弱）

强项：
- 五种竞赛模板的重复判定、计分器（[contest_definition_test.dart](../../test/contest_definition_test.dart)）覆盖了**真实** `CqWpxScoreCalculator`，不是全部用假计算器；
- 交换值与站点配置（[station_exchange_test.dart](../../test/station_exchange_test.dart)）96.9%，含 ARRL/IARU/JIDX 的 US、JA 细化；
- 呼号模糊匹配、前缀提取、列表 diff、大写格式化均 100%；
- 训练题池种子、音频种子独立性、复盘/回放、边界终止（[replay_test.dart](../../test/replay_test.dart)、[session_random_test.dart](../../test/session_random_test.dart)）质量高。

薄弱项：
- **输入映射层几乎无测试**：[key_event_handler.dart](../../lib/contest_run/key_event_handler.dart#L37-L98) 覆盖率 48.3%，且 `test/` 中**没有任何测试直接构造 `KeyEventHandler`**。F1–F8 映射、Enter/Esc/分号/空格、按住不放的抑制、KeyUp 复位、自定义键位（设置项）全部未被验证。
- [contest_operation_event_handler.dart](../../lib/contest_run/new/contest_operation_event_handler.dart#L228-L349) 45%：按状态的 Enter 语义（S&P 第一/第二下回车、`HeAskForExchange` 空序号重听、hisCall+exchange 组合）、F2 `exch`、Esc 取消（[L311-L313](../../lib/contest_run/new/contest_operation_event_handler.dart#L311-L313)）都没有用例。
- 协议层校验逻辑（`_handleReportMyExchange` 的 500ms + 音频等待 + 呼号复核）只在"呼号无效"分支有测试，通过分支没有（[L522-L544](../../lib/contest_run/new/contest_state_change_handler.dart#L522-L544)）。
- `received_exchange` 76.8%：加拿大省份细分、JIDX 无数字呼号回退、未知 CQ zone 回退未覆盖。
- `score_manager` 只有 2 个用例，且用假计算器；Penalty 分支只验证了"重复不加分"的场景。

### 3. 数据存储测试：`D`（最薄弱的一块）

实测：
- `lib/db` 9.2%；[database_bootstrap.dart](../../lib/db/database_bootstrap.dart) 5.7%（53 行仅 3 行被覆盖）；[app_database.dart](../../lib/db/app_database.dart) 24%。
- 现有 DB 相关测试全部是"内存库 + 经由业务层间接读写"：
  - `qsoTable` 插入/查询（[contest_state_change_handler_test.dart](../../test/contest_state_change_handler_test.dart#L160-L240)）；
  - `prefixTable` 播种/回滚（[dxcc_manager_test.dart](../../test/dxcc_manager_test.dart)）；
  - `eventLogTable` 写入 + 回放读取（完整会话 replay 用例）。

完全缺失的存储测试：
1. **Schema 迁移**：`schemaVersion 5` 的 v2→v5 升级路径（建表、加列、清前缀表）没有任何测试。重构若调整表结构，这是最容易造成老用户数据丢失的地方。
2. **启动目录解析**：`ensureDatabaseReady()` 的首选/回退目录、Documents 旧库迁移、迁移失败告警、全部目录不可用时退化为内存库，均未测试；`dirs.dart` 0%。
3. **文件库持久性**：没有任何测试"写入 → 关闭 → 重新打开 → 数据仍在"；全部使用 `NativeDatabase.memory()`，无法发现关闭/刷盘/路径问题。
4. **约束与索引**：`QsoTable`/`PrefixTable`/`EventLogTable` 无唯一索引、无外键，去重完全依赖应用层 `qso_duplicates`（应用层测试 100%，但存储层无保险）。重构引入查询优化时缺少基准测试。
5. **损坏/异常数据**：设置里历史复盘的 JSON 解码（`TrainingRunReview.decode`）、30 条上限、事件日志写入失败（[contest_manager.dart L316-L323](../../lib/contest_run/new/contest_manager.dart#L316-L323) 的 catch）都未覆盖。
6. **多 runId / 多会话共存**、同一 `runId` 重放时的顺序稳定性，只有间接覆盖。

### 4. 其他必须点名的缺口

| 区域 | 现状 | 风险 |
|---|---|---|
| 音频 | 58.6%；`audio_player`/`noise_bed`/混音用例扎实，但 `audio_engine` 1.9%、`payload_to_audio` 7%、`audio_loader` 18.6%、`pcm_to_wav`/`wav_to_pcm` 0% | **中高**。"代码引用的音频文件必须存在"这一历史崩溃原因没有自动化校验 |
| UI | 24.8%；`main_app.dart`(435 行)、`main_page.dart`、`score_area`、`qso_speed_area`、`training_review_overlay`、`key_tips`、`qso_result_list/*` 全部 0% | 高。现有 UI 测试都是针对具体历史缺陷的回归（最小宽度裁切、溢出、IME、焦点），不是页面级覆盖 |
| 启动/日志 | `logging_bootstrap`、`boot_trace`、`log_session` 0%；`log_paths` 47%；`crash_issue_reporter` 50%；`error_handling` 28.6% | 中。组合根（`main.dart`）完全未测试，重构装配方式时无网 |
| CI | 仅 ubuntu 跑 `flutter test`，无覆盖率门槛、无 integration test、无 macOS/Windows 单测；发布流程只校验打包 smoke test | 中。桌面差异（window_manager、sqlite 原生库、音频后端）只在 Linux 上验证 |
| 测试卫生 | 多处依赖真实 `Timer`/`Future.delayed`（如 500ms 协议等待、重试超时），只靠 `pumpEventQueue` 推进 | 低中。重构后时序变化易产生偶发失败，建议引入 `fake_async` |

---

## 三、重构安全度评分

| 目标重构对象 | 现有测试保护 | 建议 |
|---|---|---|
| 竞赛规则/计分/交换生成 | ★★★★☆ | 可直接重构，补少量边界即可 |
| 训练题池/随机/复盘/回放 | ★★★★★ | 可直接重构 |
| 状态机（主链路 + 落库兜底） | ★★★☆☆ | 先补 F5 路径、S&P 超时、WSME Retry 再动 |
| 编排层（`ContestManager`/`ContestRunningManager`） | ★★☆☆☆ | 先补 start→stop→review 生命周期与事件日志失败路径 |
| 输入/键盘/操作事件映射 | ★☆☆☆☆ | **动之前必须补**，否则重构等于无保护重写 |
| 数据库/迁移/启动目录 | ★☆☆☆☆ | **动之前必须补**，尤其是迁移与回退 |
| UI / 桌面壳层 | ★☆☆☆☆ | 先加页面冒烟 + 少量 golden，再抽组件 |

---

## 四、建议补齐顺序（不涉及代码）

**P0（重构前必须完成）**

1. 状态 × 事件矩阵补全：Run 模式 F5（`SubmitCallAndHisExchange`）全链路、`ReportMyExchange` 的 `ReceiveExchange`、`WaitingSubmitMyExchange` 的 Retry、S&P 的 Retry/NextCall、无效事件告警分支。
2. 键盘输入层单测：F1–F8 映射、组合键（仅按下 Enter/Esc/`;`/空格）、按住抑制、KeyUp 复位、自定义键位读取。
3. 一条完整 `ContestManager` 生命周期测试：start → 多次操作 → stop → 复盘写入 + 历史记录 + event log 落盘（用真实内存 DB）。
4. DB：v1→v5 迁移测试、`ensureDatabaseReady` 的回退/迁移/不可用路径、文件库"关-开"持久性、历史 JSON 损坏与 30 条上限。
5. 音频资产完整性：遍历所有 `CommonPayload` 文件名与音素资产路径，断言资源存在；对每个状态断言产生的 payload 类型（当前 `_SilentAudioLoader` 把所有音频都静默化，无法发现状态与音频映射错配）。

**P1**

6. 操作事件映射（F2/F3/F4/F6/F7/F8/Esc）与真实音频 payload 断言。
7. 真实计分器的边界补充（ARRL 加拿大省份、JIDX 无区号、未知 CQ zone、Penalty 计分）。
8. 关键 UI 页面冒烟（`main_app`、`main_page`、`score_area`、`training_review_overlay`）+ 2–3 个 golden。

**P2**

9. 增加 `integration_test/` 桌面启动冒烟；CI 增加覆盖率门槛（建议先设"已插桩文件不低于 60%、关键模块不低于 75%"）与 macOS/Windows 单测执行。

---

## 五、总体评价

- **逻辑内核已经具备"测试驱动重构"的条件**（training 97%、dxcc 91%、规则 80%、通用状态机库 85%）。
- **真正的风险集中在框架层**：按键/操作事件（42.9%）、状态机未覆盖组合（63%）、存储与迁移（9.2%）、UI/启动（0–25%）。这些恰好是架构重构改动最频繁、也最容易被"看似通过"的测试放过的地方。
- 现有测试的风格是"缺陷驱动"（每个用例几乎都对应一次线上问题），质量高但不成体系。重构前建议把状态机与输入层升级为**矩阵驱动**，把存储升级为**迁移/持久化驱动**，这样重构才有真正的安全网。

---

## 附：本次分析产物

- 覆盖率原始数据：`coverage/lcov.info`（由 `flutter test --coverage` 生成，未纳入版本控制）
- 复现命令：`fvm flutter test --coverage`、`fvm flutter analyze --no-fatal-infos`
