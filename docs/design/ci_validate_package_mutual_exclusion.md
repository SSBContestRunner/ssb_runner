# CI 设计：Validate packaging 与 Package 互斥

> 状态：已实施（2026-11-15）
> 日期：2026-11-15
> 关联：[ci-run-43702798064-failure-analysis.md](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/docs/research/ci-run-43702798064-failure-analysis.md)（L0–L3 验证层的引入背景与边界）

---

## 0. 结论摘要

- **现状唯一的重叠点**是 `workflow_dispatch`：三个 `Validate packaging (*)` 与对应的 `Package (*)` 会在同一次 run 里对同一平台各执行一遍。
- **方案**：三个 validate 作业的 `if` 去掉 `workflow_dispatch`，只保留 `pull_request` / `merge_group`。package 侧不做任何改动。
- 不改任何 `needs`：validate 仍依赖 `packaging-contract`，package 仍依赖 `analyze` / `setup` / `packaging-contract`。
- 改造后 validate 与 package 的触发集合按事件类型**结构性互斥**，不依赖额外条件。
- 另含一条**可选加固**：在 L0 契约里断言 validate 作业不得包含 `workflow_dispatch`，防止以后被改回去。

判定口径：**同一次 run 内互斥**。“PR 上验证、合入后 tag 再打包”是两次不同目的的执行，不算重复；若要消除它，等于取消合并前门禁。

---

## 1. 现状

### 1.1 触发条件

| 作业 | 触发条件 | 位置 |
|---|---|---|
| `Packaging contract`（L0） | 无 job 级 `if`，所有事件都跑 | [ci.yml#L148-L182](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L148-L182) |
| `Validate packaging (windows)`（L1） | `pull_request` / `merge_group` / `workflow_dispatch` | [ci.yml#L338-L342](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L338-L342) |
| `Validate packaging (linux)`（L2） | 同上 | [ci.yml#L380-L384](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L380-L384) |
| `Validate packaging (macos)`（L3） | 同上 | [ci.yml#L426-L430](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L426-L430) |
| `Package (linux)` | tag `v*`，或 dispatch 且矩阵含 linux | [ci.yml#L471-L473](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L471-L473) |
| `Package (windows)` | tag `v*`，或 dispatch 且矩阵含 windows | [ci.yml#L563-L565](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L563-L565) |
| `Package (macos)` | tag `v*`，或 dispatch 且矩阵含 macos | [ci.yml#L699-L701](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L699-L701) |

### 1.2 重叠矩阵

| 事件 | Validate | Package | 是否重叠 |
|---|---|---|---|
| `pull_request` | 跑 | 不跑 | 否 |
| `merge_group` | 跑 | 不跑 | 否 |
| push 分支 | 不跑 | 不跑 | 否 |
| push tag `v*` | 不跑 | 跑 | 否 |
| `workflow_dispatch` | **跑** | **跑** | **是** |

### 1.3 为什么重叠发生在 dispatch

- validate 的 `if` 只判断事件名，不读 `needs.setup.outputs.matrix`，因此任何一次 dispatch 都会把 **三个平台** 的 dry run 全跑一遍。
- package 在 dispatch 上按 `inputs.platform` 决定构建哪个平台；`setup` 的输出保证至少有一个平台命中。
- 于是 `platform=linux` 的 dispatch 会同时执行：三个平台的 dry run + Linux 的真实打包。

### 1.4 两者覆盖关系（决定改造方向的依据）

| 平台 | validate 实际执行 | package 实际执行 | 关系 |
|---|---|---|---|
| Windows | `exe`（ISCC 真编译，stub bundle） | `zip,exe`（真实 bundle） | package 是超集 |
| Linux | `deb,appimage`（stub bundle） | `deb,appimage,zip`（真实 bundle） | package 是超集 |
| macOS | `dmg`（stub `.app`） | `dmg`（真实 `.app`） | package 是超集 |

`zip` 是 fastforge 内置 maker，无配置可验，validate 不需要覆盖。除 bundle 内容与上传/发布外，package 走的是同一条 maker 链路。

---

## 2. 方案

### 2.1 变更点（已实施）

1. 三个 validate 作业的 `if` 删除 `github.event_name == 'workflow_dispatch' ||` 一行，保留：
   - `github.event_name == 'pull_request'`
   - `github.event_name == 'merge_group'`
2. `package-*` 的 `if` 与 `needs` 保持原样。
3. `validate-*` 的 `needs: packaging-contract` 保持原样。
4. `packaging-contract` 保持无 `if`（全事件运行），因为本需求只约束 validate 与 package 两者。

### 2.2 改造后矩阵

| 事件 | contract | Validate | Package | Smoke / Release |
|---|---|---|---|---|
| `pull_request` | 跑 | **跑（三平台）** | — | — |
| `merge_group` | 跑 | **跑（三平台）** | — | — |
| push 分支 | 跑 | — | — | — |
| push tag `v*` | 跑 | — | **跑（三平台）** | 跑 |
| `workflow_dispatch` | 跑 | — | **跑（按输入）** | 跑 |

两个作业集合的交集为空，且互斥由事件类型保证，无需在 `if` 里互相判断。

### 2.3 为什么删 validate 侧，而不是 package 侧

- package 在 dispatch 上的职责就是手工出包；跳过它等于取消手工发布能力。
- 对同一平台 package 是 validate 的严格超集（见 1.4），dispatch 上保留 package 不损失任何 maker 层验证能力，只是少了“秒级 dry run”这一快速反馈形态。
- 反方向（dispatch 只跑 validate）需要额外引入 `mode` 输入来区分“验证”与“出包”两种意图，复杂度更高，且会改变现有手工发布流程。

### 2.4 覆盖影响

- **PR / merge_group**：contract + 三个 dry run 全部保留，required check 不受影响。
- **tag**：unchanged。
- **dispatch**：不再验证未被请求的平台（例如 `platform=macos` 时不再跑 Windows/Linux 的 dry run）。这是需求本身的结果；跨平台验证由 PR 阶段的三个 validate 保证。
- **不丢失检查项**：dispatch 上的真实打包会执行同一份 `make_config.yaml`、模板与工具，并额外覆盖 `zip`、真实 bundle、签名与产物上传。

---

## 3. 配套影响

### 3.1 L0 契约自检

[_checkCiOrchestration](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/tool/packaging/packaging_contract.dart#L441-L517) 原有断言：

- `packaging-contract` 作业存在；
- 三个 `validate-packaging-<platform>` 作业存在；
- 每个 `package-<platform>` 作业块包含 `packaging-contract`；
- `merge_group` 与 `pull_request` 触发器存在；
- 打包重试短路与共享脚本引用。

这些基础断言不需要为本次修改调整。实施时按 §4 的加固新增了一条 validate 触发断言，因此校验器现在会解析 validate 作业块中的 `workflow_dispatch` 并附上行号。

### 3.2 单元测试

[packaging_contract_test.dart](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/test/packaging/packaging_contract_test.dart) 的现有 fixture 中没有 `workflow_dispatch` 或 validate 触发条件的断言，不受本次修改影响；实施时按 §4.3 追加了一条互斥 fixture。

### 3.3 文档同步

- [ci-run-43702798064-failure-analysis.md](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/docs/research/ci-run-43702798064-failure-analysis.md#L220-L224) §4.5 表格：L1–L3 的触发列 `PR / merge_group / dispatch` 改为 `PR / merge_group`。
- 同文档 §7 追加决策行（建议编号 D10）：`Validate packaging(*)` 与 `Package(*)` 按事件互斥，dispatch 只走真实打包；避免后续维护者按旧决策把 dispatch 加回去。
- `ci.yml` 中 validate 作业上方的注释（[L326-L334](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L326-L334)）未提及 dispatch，不需要改；实施时建议在 `if` 上方补一行说明互斥原因，属于配置注释改动。

---

## 4. 可选加固：把互斥写进 L0 契约

### 4.1 内容

在 `_checkCiOrchestration` 中新增一条断言：三个 `validate-packaging-<platform>` 的作业块不得包含 `workflow_dispatch`。实现复用现有的 `_jobBlock` 与 `requireJob` 结构：

- 对每个平台取 `_jobBlock(ci, 'validate-packaging-$platform')`；
- 若块内出现 `workflow_dispatch`，报 `ContractIssue`，说明“validate 与 package 不允许在同一事件上同时执行”。

### 4.2 收益与代价

- 收益：以后有人把 dispatch 加回 validate 时，PR 上的 `Packaging contract` 会直接失败，互斥不会静默退化。
- 代价：校验器多一条与打包产物无关的编排规则；将来若确实需要 dispatch 上的 dry run（例如新增 `mode` 输入），必须同时修改此断言。

### 4.3 配套测试

在 `test/packaging/packaging_contract_test.dart` 增加一条 fixture：validate 作业块包含 `workflow_dispatch` → 期望失败；不含 → 通过。与现有“校验器自身要被测”的做法一致。

---

## 5. 被否决的备选方案

| 方案 | 否决理由 |
|---|---|
| dispatch 上保留 validate、跳过 package | 破坏手工出包能力；且需要 `mode` 输入区分意图，流程变复杂 |
| 新增 `workflow_dispatch` 输入 `mode=validate|package`，两侧互斥 | 能满足需求，但给 CI 增加一个维度，且需要同时改三个 validate 与三个 package 的 `if` 及 L0 断言；当前没有“手工轻量验证”的明确需求 |
| 用工作流级 `paths` 过滤区分验证与打包 | required check 在路径不命中时永远 pending（见 D1） |
| 删除 validate 作业，只保留 package | PR 阶段将没有任何 maker 层验证，等于回到本次事故前的状态 |

---

## 6. 实施顺序

1. 修改三个 validate 作业的 `if`（`ci.yml` L338–L342、L380–L384、L426–L430）。
2. （可选）在 `if` 上方补注释说明互斥原因。
3. （可选加固）在 `packaging_contract.dart` 增加 validate 触发断言，并补 fixture。
4. 同步 `ci-run-43702798064-failure-analysis.md` §4.5 与 §7。
5. 按下节验收。

---

## 7. 验收清单

1. **PR**：作业列表为 `Packaging contract` + 三个 `Validate packaging (*)`，无任何 `Package (*)`。
2. **dispatch `platform=windows`**：`Packaging contract` + `Package (windows)` + 两个 Windows smoke，无任何 `Validate packaging (*)`。
3. **dispatch `platform=all`**：`Packaging contract` + 三个 `Package (*)` + 四个 smoke，无任何 `Validate packaging (*)`。
4. **tag `v*`**：`Packaging contract` + 三个 `Package (*)` + 四个 smoke + `Draft GitHub Release`，无任何 `Validate packaging (*)`。
5. **静态比对**：三个 validate 的 `if` 不含 `workflow_dispatch` 与 tag 条件；三个 package 的 `if` 不含 `pull_request` / `merge_group`；交集为空。
6. **可选加固的故障注入**：把 `workflow_dispatch` 临时加回任一 validate 作业，PR 上 `Packaging contract` 必须失败并给出行号。

---

## 8. 风险与边界

- **dispatch 不再提供秒级 dry run**：需要轻量验证时走 PR / 分支 push；这是本需求接受的取舍。
- **PR 成为唯一合并前验证入口**：与现状一致，未新增单点。
- **contract 仍在 dispatch 上运行**：本需求只约束 validate 与 package；若后续要求 contract 与 package 也互斥，需另行决策，并同步修改 `_checkCiOrchestration` 中“package 必须依赖 packaging-contract”的断言，否则 L0 会失败。
- **`merge_group` 保留**：合并队列启用后，validate 仍需在队列中运行，避免 required check 永久 pending（D1）。
