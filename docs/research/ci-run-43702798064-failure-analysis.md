# CI run 43702798064 失败分析：Inno Setup `[Code]` 续行被当成节标签

> 分析时间：2026-11-15
> 关联 CI run：[43702798064](https://github.com/SSBContestRunner/ssb_runner/actions/runs/43702798064)（`workflow_dispatch`，分支 `feat/windows-installer-upgrade-flow`，2026-11-15 10:10Z 起）
> 被验证提交：`a7cfab8 feat(windows): prompt on overwrite and block installer downgrades`
> 结论置信度：ISCC 直接报错 + 行号 1:1 对齐 + 全文扫描，三重互证。
> 实施状态：**已按 §4.9 落地 P0 + P1 + P2**（2026-11-15）。实施记录与两处与计划的偏差见 §8。

---

## 0. 结论

单一故障：`windows/packaging/exe/installer.iss` 的 `[Code]` 段里，[installer.iss#L437-L438](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/packaging/exe/installer.iss#L437-L438) 把 `FmtMessage` 的参数数组折到了下一行，续行以 `[` 开头：

```pascal
  FVersionLabel.Caption := FmtMessage(CustomMessage('UpgradeVersionLine'),
    [Prev, PackageVersion]);
```

Inno Setup 的脚本是**按行识别节标签**的：任何一行只要去掉前导空白后第一个字符是 `[`，编译器就把它当作新节的开头。`[Prev, PackageVersion]);` 不是合法节名，于是：

```text
Error on line 438 in D:\a\ssb_runner\ssb_runner\dist\0.3.0+300007\ssb_runner-0.3.0+300007-windows-setup_exe.iss: Invalid section tag.
Compile aborted.
```

`ISCC.exe` 非零退出 → fastforge `exe` maker 抛 `MakeError` → `Package (windows)` 失败 → 依赖它的 `Smoke test (Windows)`、`Smoke test (Windows installer)`、`Draft GitHub Release` 全部跳过。

**影响面**：没有任何产物被错误发布；`Analyze & Test`、`Resolve build matrix` 均正常。故障纯属打包期的模板语法错误，不涉及 Dart 代码、CMake 或运行逻辑。

**代价**：一个 1 行即可定位的语法错误让 `Package (windows)` 跑满 17m11s，其中约 9m30s 是两次无意义的重建（§2.3）。

**修复成本**：改一处换行即可。**但防回归不是可选项**：这类错误能穿过所有门禁，根源不是少了一条校验，而是整个 maker 层（三平台的 `make_config.yaml`、模板、语言文件、打包工具调用）只在 tag 上第一次执行。§4 因此重写为「PR 阶段的三平台打包验证层」：在合并前用真实工具验证打包配置，但不做真实构建。

---

## 1. 本轮作业结果

| 作业 | 结果 | 起止（UTC） | 耗时 |
|---|---|---|---|
| Analyze & Test | 通过 | 10:10:43–10:15:59 | 5m16s |
| Resolve build matrix | 通过 | 10:10:44–10:10:46 | 2s |
| Package (windows) | **失败** | 10:16:01–10:33:12 | 17m11s |
| Compile (windows) / Package (linux/macos) / Smoke test (Debian/macOS/Windows/Windows installer) / Draft GitHub Release | 跳过 | — | 0s |

环境：Inno Setup 编译器 **6.7.1**、fastforge **0.6.12**、Flutter **3.47.9**、`--build-number 300007`。

---

## 2. 现象

### 2.1 失败点

`Build & package` 步骤内，`flutter build windows` 本身成功（`√ Built build\windows\x64\runner\Release\ssb_runner.exe`，约 271–301s），`zip` 目标也成功；失败发生在紧接着的 `exe` 目标：

```text
$ C:\Program Files (x86)\Inno Setup 6\ISCC.exe dist/0.3.0+300007/ssb_runner-0.3.0+300007-windows-setup_exe.iss
...
Parsing [Setup] section, line 49
Parsing [Setup] section, line 56
...（line 57–69、82–93）
Error on line 438 ...: Invalid section tag.
Compile aborted.
MakeError
#0  AppPackageMakerExe._make (package:flutter_app_packager/src/makers/exe/app_package_maker_exe.dart:49:7)
```

### 2.2 三次尝试完全一致

| 尝试 | 开始 | 构建耗时 | 失败时间 |
|---|---|---|---|
| 1/3 | 10:18:26 | 303s | 10:23:38 |
| 2/3 | 10:23:39 | 276s | 10:28:23 |
| 3/3 | 10:28:24 | 273s | 10:33:06 |

三次报错的行号、文案、调用栈完全相同，是确定性错误。

### 2.3 重试策略没有识别它

[ci.yml#L409-L417](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L409-L417) 只在日志匹配 `error C\d{4}:`（MSVC 诊断）时短路不重试；ISCC 的诊断是 `Invalid section tag.` / `Compile aborted.`，不匹配，于是完整重建并重跑 Inno 两次。Windows 打包单次约 5 分钟，多付约 9m30s。

---

## 3. 根因

### 3.1 Inno Setup 的解析模型

ISCC 先把整份脚本切成节（`[Setup]`、`[Files]`、`[Code]`…），再逐节解析内容。切节的判定是行级的：**某行去掉前导空白后以 `[` 开头，即视为新节标签**。因此 Pascal Script 部分虽然语法上允许多行语句，但任何续行不能以 `[` 起头——否则会被当作一个未知节名，报 `Invalid section tag`。

这一类错误对编译器而言发生在"进入 `[Code]` 解析之前"，所以不会给出 Pascal 语法级的提示（例如"unexpected token"），只报无效节名，定位信息只有行号。

### 3.2 触发点

[installer.iss#L437-L438](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/packaging/exe/installer.iss#L437-L438) 的续行：

- L437 以逗号结尾，参数数组被折到 L438；
- L438 的前导空白被忽略后，首个字符是 `[`。

同一函数（`CurPageChanged`）里 L390 是 `MsgBox(FmtMessage(CustomMessage(...), [FPrevVersion, PackageVersion]),`——数组在行尾，因此不受影响。这说明问题与"是否使用数组参数"无关，只与**折行位置**有关。

引入该行的是 `a7cfab8`（覆盖安装提示与降级拦截），本轮是它第一次真正执行 `exe` 打包。

### 3.3 交叉验证

1. **行号 1:1 对齐**：日志中 ISCC 打印的 `Parsing [Setup] section, line 49 / 56–69 / 82–93` 与模板文件的行号完全一致（`AppId` 在 L49、`MinVersion` 在 L56、`WizardSmallImageFile` 在 L82、`RestartApplications` 在 L93）。fastforge 的 Liquid 渲染只做行内替换（`{% if %}` 也在行内），不增删行，因此渲染后的 L438 就是模板的 L438。
2. **全文扫描**：对 `windows/packaging/exe/installer.iss` 匹配 `^\s*\[` 只有 10 处命中——9 个真节标签（L48/95/101/134/142/145/149/153/156）+ L438 这一处假标签。没有第二处同类隐患。
3. **错误文案语义吻合**：`Invalid section tag` 正是"行首 `[` 但节名不存在"的唯一报错形态；如果是 Pascal 语法问题，报错会是 `Unknown identifier` / `Semicolon expected` 一类。

### 3.4 为什么现有校验全部漏过

| 层级 | 现状 | 为何没拦住 |
|---|---|---|
| 本地 | 只有 macOS，ISCC 只能在 Windows 上跑 | 无法编译 |
| `Analyze & Test` | `flutter analyze` + `flutter test` | 不涉及 `.iss` |
| `Compile (windows)`（PR/push 均触发） | [ci.yml#L163-L166](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L163-L166) `flutter build windows --release` | 明确"只编译不出包、不跑 Inno Setup" |
| 模板静态断言 | [smoke-test-windows-installer.ps1#L98-L144](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/scripts/smoke-test-windows-installer.ps1#L98-L144)：Liquid 分隔符、四语言覆盖、`[InstallDelete]` 数据边界 | 属于 `Smoke test (Windows installer)` 作业，[ci.yml#L614](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L614) 依赖打包产物；打包先死，断言永远没执行 |
| `Package (windows)` | 唯一真正编译 `.iss` 的地方 | 只在 tag 与手工 dispatch 触发（[ci.yml#L281-L283](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L281-L283)） |

即：**"检查模板"和"编译模板"之间存在一段没有门禁的空档**——静态断言在打包之后，而模板错误恰好会让打包在几十秒内失败。

### 3.5 一个容易踩空的细节

现有 `[Code]` 段的提取正则是 `(?ms)^\[Code\](.*?)(?=^\[|\z)`（[smoke-test-windows-installer.ps1#L108](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/scripts/smoke-test-windows-installer.ps1#L108)）。结束条件是**列 0** 的 `[`，所以 L438 这种缩进 `[` 不会被截断。若要新增"`[Code]` 内不得有行首 `[`"的断言，匹配必须是 `^\s*\[`（与 ISCC 的判定一致），不能沿用 `^\[`，否则断言自身会被截断而漏报。

---

## 4. 修订后的技术方案：PR 阶段的三平台打包验证层

> 本节是 v2，取代 v1 的 G1–G3（单条 lint + 注释 + 重试短路）。修订原因：v1 只堵住 Windows 模板「行首 `[`」这一种形态，而根本问题是 **maker 层在合并前没有任何覆盖**——三平台的 `make_config.yaml`、Liquid 模板、语言文件清单、appdmg 布局、deb 字段，全都只在 tag 上第一次被执行。

### 4.0 v1 → v2 的差异

| 维度 | v1 | v2 |
|---|---|---|
| 范围 | 仅 Windows 模板 | Linux / Windows / macOS 三平台 |
| 手段 | 文本 lint + 注释 | 静态契约（L0）+ 真实工具 dry run（L1–L3） |
| 时机 | `Build & package` 之前 | PR 门禁，合并前 |
| 覆盖面 | 行首 `[` | 配置解析、模板渲染、工具编译、产物命名、仓库耦合 |
| CI 成本 | 打包前多一个 step | 3 个并行 job，关键路径不变 |

### 4.1 必做：调整折行位置

目标：让 `[` 不出现在任何行的第一个非空白字符位置。三种写法等价，推荐第 2 种（改动最小、可读性不受影响）：

```pascal
// 方案 1：整句一行（行长偏长，不推荐）
FVersionLabel.Caption := FmtMessage(CustomMessage('UpgradeVersionLine'), [Prev, PackageVersion]);

// 方案 2（推荐）：折在逗号后，续行以 CustomMessage 开头
FVersionLabel.Caption := FmtMessage(
  CustomMessage('UpgradeVersionLine'), [Prev, PackageVersion]);

// 方案 3：先取文案到局部变量
var Line: String;
...
Line := CustomMessage('UpgradeVersionLine');
FVersionLabel.Caption := FmtMessage(Line, [Prev, PackageVersion]);
```

不要采用"再缩进一格"或"把 `[` 用括号包起来"之类的规避：ISCC 忽略前导空白，缩进无效；`([Prev, ...])` 虽然在 Pascal 里可能合法，但会让数组语义变得可疑，且不解决根因。

验证口径：`grep -n '^\s*\[' windows/packaging/exe/installer.iss` 应只剩 9 个真节标签（L48/95/101/134/142/145/149/153/156）。

改完后 `[Code]` 段的其余部分是否还有语法问题，只有跑一次 ISCC 才能确认（本轮编译器在 L438 就中止）。§4.5 的 L1 正是为此设计的：它会在 PR 上完成这次全量语法验证。

### 4.2 现状缺口

| 阶段 | 实际执行 | 覆盖的打包面 |
|---|---|---|
| PR | `Analyze & Test`、`Compile (windows)`（只编译 runner，明确不出包） | Dart 代码、Windows 原生编译 |
| tag / dispatch | `package-linux/windows/macos`（调用 maker） | 全部（tag 全平台；dispatch 按输入） |
| tag / dispatch | 4 个 smoke test | 安装/启动/卸载等运行时行为 |

即 §3.4 的结论在三个平台上都成立：**「检查模板」与「执行模板」之间没有门禁**。Windows 只是这次恰好先炸的地方；Linux 的 deb 字段、macOS 的 dmg 布局同样只在 tag 上第一次被工具解析。

### 4.3 设计原则

1. **只验证，不发布**：dry run 的产物写到临时目录，断言后丢弃；不进入 `dist/` 上传，不触碰 release。
2. **走真实代码路径**：调用 fastforge 依赖的同一个 packager，而不是复刻模板渲染或 control 生成逻辑。唯一被跳过的是 `flutter build`。
3. **秒级优先，分钟级兜底**：能在纯文本层面判定的不进平台 runner；必须依赖工具的才起对应平台的 job。
4. **失败可定位**：报错必须带 `文件:行号`（GitHub Actions 注解），渲染产物与工具日志在失败时保留。
5. **校验器自身要被测**：fixture 单测挂在现有 `flutter test` 里，避免校验器变成新的单点。
6. **不改变既有发布语义**：tag 的真实打包、smoke test、release 依赖关系保持原样。

### 4.4 关键实现：跳过 `flutter build`，直连 packager

fastforge 的 `package` 命令在 `flutter build` 之后调用 `FlutterAppPackager.package(...)`。后者是 **公开 API**（`flutter_app_packager` 的 `lib/flutter_app_packager.dart` 直接导出），它的入参包含 `buildOutputDirectory` 与 `buildOutputFiles`——也就是说，**调用方可以自己指定"构建产物目录"**。

因此 PR 阶段可以这样验证：先用几毫秒造一个 stub 产物目录，再以它为 `buildOutputDirectory` 调用同一个 packager。真实发生的链路是：

`make_config.yaml` 解析 → config loader 校验必填字段 → Liquid 渲染模板 → 调用平台工具（ISCC / dpkg-deb / appimagetool / appdmg）→ 按 fastforge 的 artifact name 规则产出文件。

唯一没发生的是 Flutter 编译。产物写入临时输出目录，断言存在与命名后删除。

实现位置：`tool/packaging/`。`validate_packaging.dart` 负责 L0，与它的被测库 `packaging_contract.dart` 一起属于应用包，因此受 `flutter analyze --fatal-infos` 与 `flutter test` 覆盖。`dry_run_packaging.dart` 负责 L1–L3 的 stub 装配与 packager 调用，被放在独立包 `tool/packaging/dry_run/`（原因见 §8.1）。两者都在仓库根目录执行；dry run 会自行把 CWD 切到仓库根，因为 maker 的路径全部相对 CWD。

**成本对比**：

| | 真实打包（tag） | PR dry run |
|---|---|---|
| Flutter 编译 | 约 4–5 分钟 | 跳过 |
| maker + 工具 | 约 1 分钟（含数百 MB 压缩） | 秒级（stub 只有几个文件） |
| 产物 | 上传并发布 | 临时目录，断言后删除 |

**版本耦合**：dry run 所在的独立包必须精确固定 `flutter_app_packager`，且与 fastforge 的解析结果一致。fastforge 0.6.12 对它的约束是 `^0.6.11`，所以**一次全新激活会解析到当时最新的 0.6.x——实施时为 0.6.13**，而不是本机旧缓存里的 0.6.11；tag 构建用的正是这个新解析结果，因此 pin 必须跟着走。fastforge 通过 `dart pub global activate` 单独解析依赖，pub 不会替你比对两者，所以 L0 要加一步「激活 fastforge 后读出其全局 lock，断言 packager 版本与 dry run 包的 `pubspec.lock` 一致」——否则 PR dry run 用一套版本、tag 用另一套，漂移会只在 tag 上暴露。这条检查在实施当轮就被触发过一次，见 §8.2。

**被否决的替代方案**：

| 方案 | 否决理由 |
|---|---|
| 自己实现 Liquid 渲染器 | 第二套真相。模板里的 `{% if %}`、`{#StringChange#}` 语义一旦漂移，校验器会给出与 fastforge 不同的结果 |
| 复刻 deb control / desktop 文件生成 | 同上，而且会把 maker 的升级风险藏起来 |
| 直接复用 fastforge CLI | 没有 `--skip-build`（`package` 只有 `--skip-clean`），必然触发 5 分钟 Flutter 编译 |
| 用假 `flutter` 可执行文件短路 | 依赖 CLI 内部对 build 输出的解析方式，上游一改就静默失效 |

### 4.5 分层设计

| 层 | 作业 | 运行环境 | 触发 | 执行内容 |
|---|---|---|---|---|
| L0 | `Packaging contract` | ubuntu-latest | PR / merge_group / push / tag / dispatch | 三平台配置与模板的静态契约 + 仓库耦合 + CI 编排一致性 |
| L1 | `Validate packaging (windows)` | windows-latest | PR / merge_group | stub bundle → `exe` maker → ISCC 真实编译 → 断言产物存在、命名正确、`ProductName` 为 `SSB Runner` |
| L2 | `Validate packaging (linux)` | ubuntu-22.04 | PR / merge_group | stub bundle → `deb` maker → `dpkg-deb` → 断言 control 与文件清单 |
| L3 | `Validate packaging (macos)` | macos-latest | PR / merge_group | stub `*.app` → `dmg` maker → appdmg → 挂载断言卷内容 |
| L4 | 现有 tag 流水线 | 各平台 | tag / dispatch | 不变：真实打包 + 4 个 smoke test + release |

`merge_group` 已纳入触发（见 §7 D1）：当前未启用合并队列，但保留该触发，避免将来启用时 required check 缺失。

PR 阶段的作业图：

```text
PR（四条并行关键路径）:
  Analyze & Test
  Compile (windows)            （独立，保持现状，只编译 runner）
  Packaging contract ──┬─> Validate packaging (windows)
                       ├─> Validate packaging (linux)
                       └─> Validate packaging (macos)
```

tag 阶段（只增加一条前置依赖）：

```text
analyze + setup + Packaging contract ─> package-{linux,windows,macos} ─> smoke-* ─> release
```

为什么不把 L1 顺带塞进 `Compile (windows)`：那个作业手里是约 300 MB 的真实 bundle，用 ISCC 压一遍是分钟级；dry run 用 stub 是秒级。独立作业还能让「Windows 编译失败」与「打包配置失败」分别出现在各自的检查里，重跑与定位都更直接。

**各层能拦住 / 拦不住什么**（边界必须写清楚，否则会高估收益）：

- L0 能拦：本次故障、未知 Liquid 变量、语言文件漏拷、dmg 的 `.app` 名称漂移、deb 必填字段缺失、`ci.yml` targets 与配置目录不一致。拦不住：工具自身的语义错误（Pascal 语法、control 字段取值、appdmg 规格）。
- L1 能拦：ISCC 的全部编译期错误——Pascal 语法、无效节标签、语言文件/图标/路径缺失、Liquid 渲染后的空值。拦不住：安装/覆盖/降级/卸载行为、真实 bundle 的完整性、MSVC 运行时是否齐全（这些仍是 tag 的 `Smoke test (Windows installer)`）。
- L2 能拦：control 字段非法、包名不合规、依赖语法错误、desktop 文件生成、图标缺失。拦不住：`dpkg -i` 后的运行、glibc/GLIBCXX 符号（仍是 tag 的 `Smoke test (Debian 12)`）。
- L3 能拦：appdmg 配置、`.app` 名称与布局、图标/背景路径、hdiutil 失败。拦不住：签名与公证（当前未签名）、应用启动行为（仍是 tag 的 `Smoke test (macOS)`）。

**为什么 L0 和 L1–L3 都要**：L0 是秒级、跨平台、也在 tag 上前置执行，让模板错误在 30 秒内失败而不是 17 分钟；L1–L3 用真实工具兜住 L0 无法判断的语义错误。两者互补，不是重复。

### 4.6 检查清单

#### 4.6.1 跨平台与 CI 编排（L0）

1. `ci.yml` matrix 中出现的每个 target（`deb` / `appimage` / `zip` / `dmg` / `exe`）在 `<platform>/packaging/<target>/` 下都有配置；反过来，仓库里的配置目录必须能在 matrix 中被调用（防孤儿配置）。
2. `zip` 是 fastforge 内置 maker，不需要 `make_config.yaml`；若出现配置目录则告警。
3. 三处 `display_name` 必须一致（当前均为 `SSB Runner`）。
4. 任何模板或配置里不得出现字面版本号，版本只来自 `pubspec.yaml`。
5. `windows/packaging/exe/languages/*.isl` 的文件集合 == `.github/scripts/ensure-inno-setup.ps1` 的复制清单 == 模板 `[Languages]` 引用的非官方语言文件集合（`Default.isl` 与 `Japanese.isl` 等由 Inno 自带，不参与比对）。
6. `make_config.yaml` 引用的文件必须存在：`script_template`、`setup_icon_file`、`icon`。
7. `wizard_small_image_{58,116,174}.png` 存在——模板通过 `{#StringChange#}` 从 `setup_icon_file` 派生这三个路径，静态阅读模板看不出来。
8. `tool/packaging/dry_run/pubspec.yaml` 的 `flutter_app_packager` 版本 == 该包 `pubspec.lock` == 全局激活的 fastforge 解析出的版本（读 `~/.pub-cache/global_packages/fastforge/pubspec.lock`）。fastforge 的激活版本同样来自 `ci.yml`，两处必须一致。

#### 4.6.2 Windows（`installer.iss` + `make_config.yaml`）

| 检查 | 拦住的失败形态 |
|---|---|
| 所有 `^\s*\[` 命中必须落在合法节名白名单（注意不是 `^\[`，见 §3.5） | 本次 L438 一类「续行被当成节标签」 |
| Liquid 变量必须在 fastforge 注入的 17 个变量内；未知变量直接报错 | 变量拼错后被渲染成空串，产物静默缺字段 |
| `{% if %}` / `{% endif %}` 配平；`[Code]` 内不得出现 Liquid 分隔符 | 覆盖安装检测逻辑被静默掏空 |
| `[Languages]` 有 4 条；`[CustomMessages]` 每个键都有 4 种语言；`[Code]` 里每个 `CustomMessage('X')` 的 X 都有定义 | 非英语向导回退英文或直接显示键名 |
| `[InstallDelete]` 不得出现 `{app}\*`、裸 `{app}`、`db\`、`log\` | 覆盖安装删掉用户数据 |
| `AppId` 是合法 GUID 且不带花括号；`privileges_required ∈ {lowest, admin, none}`；`install_dir_name` 使用 Inno 常量 | 安装器被当成不同产品、弹 UAC、装到错误目录 |
| `MinVersion` 与 `windows/runner/main.cpp` 的运行时下限一致（10.0.14393） | 安装器与便携包对系统下限的承诺不一致 |
| `SetupIconFile` 存在且为 `.ico`；三个 wizard PNG 存在 | 打包期才发现资源缺失 |

#### 4.6.3 macOS

1. `dmg.contents` 中 `type: file` 的 basename 必须等于 `macos/Runner/Configs/AppInfo.xcconfig` 的 `PRODUCT_NAME`（去掉首尾空白）+ `.app`。当前模板写死 `SSB Runner.app`，而 xcconfig 的写法是 `PRODUCT_NAME =  SSB Runner `（多余空白），这正是需要机器校验的漂移点。
2. 恰好一个 `file` 项、一个 `link /Applications` 项；`type` ∈ {`file`, `link`, `position`}；`x` / `y` 为数字。
3. 若配置了 `window.size`，图标坐标必须落在窗口可视范围内。
4. `Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` 必须是 `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`，不得写死。

#### 4.6.4 Linux

1. deb 必填：`package_name`、`maintainer.name` / `maintainer.email`、`installed_size`（正整数）。
2. `package_name` 符合 Debian policy 字符集（小写字母、数字、`+` `-` `.`）。
3. `dependencies` 每项可解析为 `name (>= version)` 形式；`libc6 (>= 2.35)` 与 issue #23 的下限承诺一致。
4. `icon` 存在且为 PNG；`categories` ∈ freedesktop 主分类白名单；`generic_name` / `keywords` 非空。
5. appimage：`display_name`、`icon`、`categories` 同上。
6. `linux/CMakeLists.txt` 的 `BINARY_NAME` 与 desktop 文件名、安装路径一致。

### 4.7 校验器自测（防止校验器成为新的单点）

fixture 用例，跑在现有 `flutter test` 里，不新增作业：

| 用例 | 期望 |
|---|---|
| 当前真实模板与配置 | 全部通过 |
| 把 L437–438 还原成折行 | 失败，且注解指向第 438 行 |
| `^\[` 与 `^\s*\[` 的差异用例（缩进 `[` 不能被当成节尾） | 覆盖 §3.5 的陷阱 |
| 模板里塞一个未知 Liquid 变量 | 失败，指出变量名与行号 |
| `PRODUCT_NAME` 改一个字符 | macOS 检查失败 |
| `[CustomMessages]` 删掉一条日文 | 失败，指出缺失的语言 |
| deb 删掉 `maintainer` | 失败，指出缺失字段 |

同一套 fixture 也用于验证「检查不会误报」——真实模板必须干净通过，否则 PR 会被无关错误卡住。

### 4.8 tag 路径的加固

1. `package-linux` / `package-windows` / `package-macos` 的 `needs` 增加 `Packaging contract`：模板错误在几十秒内失败，不再消耗 17 分钟（本次运行的代价）。
2. 重试短路追加确定性诊断：`Invalid section tag` / `Compile aborted`（ISCC 专有）。不动 `MakeError` 的偶发重试逻辑——native assets 下载失败仍需要它。
3. 失败时上传渲染后的 `.iss` 与 maker 日志。fastforge 成功后会删除渲染产物，失败时会留在 `dist/`；dry run 则无论成败都保留，便于对比。
4. 打包前打印 `ISCC.exe /?` 的版本行，把 runner 镜像的 Inno Setup 版本记进日志，便于区分"模板错"与"编译器漂移"。

### 4.9 分阶段落地

**P0（与 4.1 一起合入）**

- 4.1 修复折行；
- L0 + L1 + §4.7 的自测；
- `Packaging contract` 作为三个 package 作业的 `needs`；
- §4.8 的重试短路与版本打印；
- 把 `Packaging contract` 与 `Validate packaging (windows)` 加入分支保护的 required checks（首次全绿后启用，见 D3）。

**P1**

- L2（deb）、L3（dmg），并把它们加入分支保护的 required checks；
- 把 `smoke-test-windows-installer.ps1` 里的静态断言收敛到 L0，脚本只保留安装/覆盖/降级/卸载的运行时行为，消除重复实现与 §3.5 的正则陷阱。

**P2**

- L2 的 AppImage dry run。它比 deb 麻烦：maker 会对 `AppDir/lib/libflutter_linux_gtk.so` 无条件执行 `ldd`，stub 必须是真实 ELF（可把系统里的 `libm.so.6` 之类拷成该文件名），否则 `ldd` 非零退出。可用 `APPIMAGE_EXTRACT_AND_RUN=1` 免装 libfuse2。
- 若启用合并队列，`on:` 增加 `merge_group`，否则 required check 在合并队列里不会触发。
- 更细的产物结构断言（dmg 内 `.app` 的目录结构、deb 内 desktop 文件内容），视 L2/L3 的稳定性再定。

### 4.10 不做的事

- **不在 PR 上跑 `flutter build`**：三平台编译合计超过 10 分钟，且编译错误已由 `Compile (windows)` 与 `flutter test` 覆盖；打包验证只需要"产物目录长得对"，不需要真产物。
- **不在 PR 上验证安装/升级/卸载/启动**：那需要真实产物，属于 tag smoke 的职责。dry run 只证明"能打包"，不证明"装完能跑"。
- **不复刻 maker 逻辑**：避免第二套真相，也避免 maker 升级后校验器与真实行为分叉。
- **不把三平台合成一个 matrix job**：验证失败需要独立结论、独立重跑，与现有 package 作业的决策一致。
- **不升级 / 降级 Inno Setup**：6.7.x 的行为稳定，与本次失败无关。
- **不改 `[InstallDelete]`、`[CustomMessages]` 等已审设计**：本次失败与它们无关。

---

## 5. 验证清单

### 5.1 合并前（PR）

1. 本地 `dart tool/packaging/validate_packaging.dart`（L0）全绿；把 L437–438 还原成折行后，1 秒内报错并指向第 438 行（`flutter test test/packaging/` 有同一条 fixture）。
2. P0 阶段全绿：`Packaging contract` 与 `Validate packaging (windows)`；P1 完成后追加 `Validate packaging (linux)` 与 `Validate packaging (macos)`。它们都与 `Analyze & Test` 并行，PR 关键路径不变。
3. Windows dry run 日志出现 `Successful compile`，产物名符合 `ssb_runner-0.3.0+300007-windows-setup.exe`，并与 tag 实际产物名逐字一致（D8）；`dist/` 没有残留、也没有 artifact 上传（失败证据除外）。
4. 故障注入（各开一个 PR 验证，验证后回滚）：
   - 还原 L438 折行 → L0 与 L1 都失败，错误带行号（P0）；
   - 新增一种安装语言但不加复制清单 → L0 失败（P0）；
   - dmg 的 `SSB Runner.app` 改成 `SSB Runner2.app` → L0 失败，L3 在 appdmg 阶段失败（P1）；
   - 删掉 deb 的 `maintainer.email` → L0 失败，L2 在 config loader 阶段失败（P1）。

### 5.2 tag / dispatch

1. `Packaging contract` 先于三个 package 作业完成。
2. `Package (windows)` 全绿，`dist/0.3.0+300007/` 下同时有 `.zip` 与 `-windows-setup.exe`；ISCC 日志走到 `Successful compile`，不再出现 `Invalid section tag` / `Compile aborted`。
3. 产物 VersionInfo：`ProductName` 为 `SSB Runner`；`AppVersion` 若为纯数字版本，再断言 `ProductVersion` / `FileVersion` 与 `pubspec.yaml` 一致。
4. `Smoke test (Windows installer)` 通过：静默安装、同版本二次覆盖安装、伪造 `DisplayVersion=99.0.0` 的降级被拒且安装目录未变、卸载后目录与快捷方式消失。
5. 失败注入：人为制造一次 ISCC 失败，确认只在第 1 次尝试后失败（§4.8-2），且日志包含 `ISCC /?` 的版本行。
6. `Smoke test (Windows)`、`Smoke test (Debian 12)`、`Smoke test (macOS)` 与 `Draft GitHub Release` 不再被跳过（dispatch 时）。
7. 本轮在 L438 中止后，`[Code]` 剩余部分（`CurPageChanged` 后半段、`ShouldSkipPage`）首次进入解析——一次 tag 全绿即等价于一次全量语法验证。

---

## 6. 遗留与风险

1. **版本同步**。dry run 包里的 `flutter_app_packager` 必须与 fastforge 全新激活后解析到的一致（fastforge 0.6.12 约束 `^0.6.11`，实施时为 0.6.13）。§4.6.1-8 的版本比对会在不一致时直接失败，所以升级 fastforge 必须在同一个 PR 里同步这个 pin；这条约束也写进了 `tool/packaging/dry_run/pubspec.yaml` 与 `installer.iss` 的头注释。
2. **stub 的边界**。L1–L3 验证的是「配置 + 工具 + 产物外壳」，不是 bundle 内容。AppImage 的 dry run 尤其受限：maker 对 `libflutter_linux_gtk.so` 无条件 `ldd`，stub 必须放真实 ELF 才能通过，因此它只能验证到"工具接受 AppDir"这一层。
3. **appdmg 的无头风险**。dmg 布局依赖 Finder 自动化，无头会话下可能不稳定。若 macOS runner 上反复失败，降级方案是：L3 只做 appdmg 规格校验 + 用 `hdiutil` 从 stub `.app` 生成一次只读卷，真实 dmg 生成仍留给 tag。
4. **`[Code]` 的其余部分**。本轮 ISCC 在 L438 中止，后面的代码从未进入解析。P0 的 L1 会在 PR 上完成这次验证；若还有问题，会以新的行号出现，属同一类修复，不影响根因结论。
5. **新增作业的成本**。每个 PR 增加 3 个分钟级作业，与 5 分钟的 `Analyze & Test` 并行，关键路径不变，但 runner 分钟数上升。这是把"打包问题在合并前暴露"所付的代价；若后续觉得昂贵，优先把 L2/L3 改为仅在打包相关路径变更时触发（注意路径过滤必须用 job 级 `if`，不能在工作流级 `paths`，否则 required check 会永远 pending）。
6. **工具版本漂移**。runner 镜像里的 Inno Setup、appimagetool、appdmg 版本都不由仓库控制。L1–L3 会在 PR 上先暴露漂移，但只覆盖"会改变编译/打包结果"的那部分；版本号仍要打印进日志便于对照。
7. **校验器自身的维护**。L0 的 fixture 与模板必须同步演进：模板新增 Liquid 构造或模板段时，L0 可能误报，此时以 L1 的真实渲染结果为准（直连 packager 不存在漂移面）。这也是不自己实现渲染器的直接原因。
8. **上一轮教训的覆盖**。[ci-run-43677974432-failure-analysis.md](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/docs/research/ci-run-43677974432-failure-analysis.md) 的 C2（重试只对 MSVC 诊断短路）与 C3（产物脚本自检）都不覆盖安装器模板；本方案的 §4.8-2 扩展了 C2，§4.6 + L1–L3 补上了 C3 的空白，三类问题（编译诊断、脚本自检、打包模板）现在各有归口。

---

## 7. 决策记录（2026-11-15 拍板）

> 下列为 §4 方案中未决事项的最终结论，均按推荐默认执行。后续如需变更，修改本节并在 PR 说明中引用对应编号。

| # | 事项 | 结论 |
|---|---|---|
| D1 | 触发语义 | 以 PR 门禁为准：`pull_request` 必跑；`merge_group` 一并保留（当前未启用合并队列，保留以免启用时 required check 缺失）；不使用工作流级 `paths` 过滤。 |
| D2 | P0 范围 | L0（三平台静态契约）+ L1（Windows 真实 ISCC）+ §4.7 自测 + §4.8 加固；L2/L3 放 P1。 |
| D3 | 依赖与门禁 | `flutter_app_packager` 不作为应用包的 dev_dependency，而是放进独立包 `tool/packaging/dry_run/`（实施期发现 archive 版本不可调和，见 §8.1）；新作业在首次完整 PR 全绿后设为 required check，启用前不阻塞现有 PR。 |
| D4 | 静态断言去重 | 接受 P1 的去重：`smoke-test-windows-installer.ps1` 的静态断言迁到 L0，脚本只保留安装/覆盖/降级/卸载的运行时行为。 |
| D5 | L3 的 appdmg | 先按"真实生成 dmg"实现；若 macOS runner 上 Finder 自动化不稳定，降级为"规格校验 + hdiutil 只读卷"，tag 的真实 dmg 生成不变。 |
| D6 | AppImage dry run | 归入 P2，不阻塞 P0/P1；stub 需要真实 ELF 才实施。 |
| D7 | 版本一致性比对 | 以 `~/.pub-cache/global_packages/fastforge/pubspec.lock` 为准；路径不可读时任务失败并提示人工确认，禁止静默跳过。 |
| D8 | stub 保真度验收 | P0 实施后对比一次 dry run 产物名与 tag 实际产物名，必须逐字一致；不一致视为 dry run 不可信，先修 stub 装配再启用门禁。 |
| D9 | L0 触发范围 | PR / merge_group / push / tag / dispatch 全开：L0 是秒级文本校验，重复执行的代价低于漏检的代价。 |
| D10 | Validate 与 Package 的触发互斥 | `Validate packaging (*)` 只在 PR / merge_group 运行，`Package (*)` 只在 tag / dispatch 运行，两者按事件类型结构性互斥；dispatch 只做真实打包，不再对同一平台重复执行 dry run（见 [ci_validate_package_mutual_exclusion.md](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/docs/design/ci_validate_package_mutual_exclusion.md)）。 |

结论：§4 方案已无未决事项；§6 中的条目均为已知边界或实施期验收点，不阻塞开工。

---

## 8. 实施记录（2026-11-15）

落地范围：§4.1 折行修复、L0/L1/L2/L3、§4.7 自测、§4.8 加固、P1 静态断言去重、P2 AppImage dry run。

| 落地点 | 文件 |
|---|---|
| 折行修复 | `windows/packaging/exe/installer.iss`（L437–438，验证口径仍是 9 个真节标签） |
| L0 | `tool/packaging/packaging_contract.dart`（被测库）+ `tool/packaging/validate_packaging.dart`（CLI） |
| L1–L3 + P2 | `tool/packaging/dry_run/`（独立包，`bin/dry_run_packaging.dart`） |
| 自测 | `test/packaging/packaging_contract_test.dart`（9 个 fixture，跑在 `flutter test` 里） |
| CI | `Packaging contract`、`Validate packaging (windows|linux|macos)` 三个新作业；`package-*` 的 `needs`；`merge_group`；重试短路；失败证据上传 |
| 复用脚本 | `.github/scripts/ensure-inno-setup.ps1`（含 `ISCC /?` 版本打印）、`.github/scripts/install-appimagetool.sh` |
| 去重 | `smoke-test-windows-installer.ps1` 只保留运行时行为 |

### 8.1 偏差一：dry run 用独立包，而不是应用包的 dev_dependency

D3 原本选择 dev_dependency。实施时 `flutter pub get` 直接拒绝：应用依赖 `archive ^4.0.7`，而 `flutter_app_packager` 约束 `archive ^3.6.1`。加 `dependency_overrides` 可以解出依赖，但 0.6.13 新增的 `tar_gz` maker 调用了 archive 3 的 `ArchiveFile.nameOfLinkedFile`，编译期即失败（`dart run` 直接报这个错）。因此 `flutter_app_packager` 被放进独立包 `tool/packaging/dry_run/`，解析出与 fastforge 同构的依赖图；应用包只保留 `path` + `yaml` 给 L0 用。代价：`flutter analyze` 不再覆盖该脚本，改由 `Packaging contract` 作业里的 `dart analyze --fatal-infos` 覆盖。

### 8.2 偏差二：pin 的是 0.6.13，不是 0.6.11

本地 `~/.pub-cache/global_packages/fastforge/pubspec.lock` 写的是 0.6.11，但那是旧缓存。用干净的 `PUB_CACHE` 执行 `dart pub global activate fastforge 0.6.12` 解析到 `flutter_app_packager 0.6.13`（`unified_distributor 0.2.14`）——这也正是 tag 构建在干净 runner 上拿到的版本。因此 dry run 包 pin 0.6.13；§4.6.1-8 的比对在第一次本地执行时就把 0.6.11 拦了下来，说明这条检查有效。`installer.iss` 仅是模板基线注释，`inno_setup_script.dart` 在 0.6.11→0.6.13 之间未变。

### 8.3 顺带清理：`linux/packaging/dev/make_config.yaml`

§4.6.1-1 的孤儿配置检查会在真实仓库上直接失败：`linux/packaging/dev/` 没有任何 matrix 条目调用，fastforge 也没有 `dev` maker。该文件（来自 #13）已删除，检查因此能对真实仓库全绿。

### 8.4 已知边界

- L1（ISCC）与 L2（dpkg-deb / appimagetool）只能在各自的 CI runner 上验证；本地 macOS 只完整跑通了 L3。
- L3 在本地验证到：dmg 生成成功、挂载后卷内有 `SSB Runner.app` 与 `/Applications` 链接、产物名为 `ssb_runner-0.3.0+300007-macos.dmg`（D8 的命名口径一致）。
- 「首次全绿后设为 required check」是仓库设置，不在代码内。
- §5.2 的失败注入（还原 L438 折行）尚未在 GitHub 上跑过；本地等价验证由 `test/packaging/packaging_contract_test.dart` 的同名 fixture 完成，断言行号为 438。
