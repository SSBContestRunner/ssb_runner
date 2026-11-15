# CI run 43714728174 失败分析：契约夹具写死行号 + AppImage dry-run 无法推断架构

> 分析时间：2026-11-15
> 关联 CI run：[43714728174](https://github.com/SSBContestRunner/ssb_runner/actions/runs/43714728174)（`pull_request` #74，分支 `feat/windows-installer-upgrade-flow`，2026-11-15 12:36:39Z 起）
> 被验证提交：`d71186f fix(packaging): clear the dry-run gate's three CI failures`
> 结论置信度：CI 日志 + 模板行号逐行核对 + 锁定版本 appimagetool 源码，三重互证。
> 实施状态：**方案已固化（见 §6），未修改任何代码或工作流**（2026-11-15）。

---

## 0. 结论

本轮有 **两个互不相关的失败**，都不是产品代码缺陷：

| # | 作业 | 现象 | 性质 |
|---|---|---|---|
| 1 | Analyze & Test | 497 通过、1 失败：[packaging_contract_test.dart#L63](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/test/packaging/packaging_contract_test.dart#L42-L65) 期望 `line == 438`，实际 `440` | **假红**：夹具把模板的绝对物理行号当契约，模板上方加了 2 行就失效 |
| 2 | Validate packaging (linux) | `Dry-run the AppImage maker` 失败：appimagetool 无法推断 AppDir 架构 | **门禁缺陷**：dry-run 的 stub 缺少真实 bundle 具备的可执行 ELF，工具无从判断 `e_machine` |

附带一个尚未致命的规范偏差（同一份日志里 appimagetool 已明确标注“将来会致命”）：desktop entry 的 `Categories=Audio;HamRadio` 缺少 `AudioVideo`。

**影响面**：契约检查器（L0）本身的判断全部正确，四平台打包验证的 macOS / Windows 分支均通过。因为这两个作业红，`Compile (windows)` 及其后的 `Package` / `Smoke test` / `Draft GitHub Release` 全部被跳过。

---

## 1. 本轮作业结果

| 作业 | 结果 | 起止（UTC） | 耗时 |
|---|---|---|---|
| Packaging contract | 通过 | 12:36:39–12:37:11 | 32s |
| Analyze & Test | **失败**（Test 步骤） | 12:36:39–12:41:03 | 4m24s |
| Resolve build matrix | 通过 | 12:36:39–12:36:42 | 3s |
| Validate packaging (macos) | 通过 | 12:37:13–12:38:44 | 1m31s |
| Validate packaging (windows) | 通过 | 12:37:13–12:38:58 | 1m45s |
| Validate packaging (linux) | **失败**（AppImage dry-run） | 12:37:18–12:37:56 | 38s |
| Compile / Package / Smoke test (×4) / Draft GitHub Release | 跳过 | — | 0s |

`Validate packaging (linux)` 内部步骤：`dpkg-deb` dry-run 通过（12:37:44–12:37:49），紧接着的 `appimagetool` dry-run 失败（12:37:49–12:37:54）。

环境：Flutter **3.47.9**、fastforge **0.6.12**、`flutter_app_packager` **0.6.13**、appimagetool `continuous build (git 11d54c9), build 370 built on 2026-11-06`。

---

## 2. 失败一：契约测试断言了绝对行号

### 2.1 失败输出

```text
❌ test/packaging/packaging_contract_test.dart:
   a wrapped statement that starts a line with "[" fails at its line (failed)
Expected: <438>
  Actual: <440>
test/packaging/packaging_contract_test.dart 63:5
```

### 2.2 链路

1. 用例 [packaging_contract_test.dart#L42-L65](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/test/packaging/packaging_contract_test.dart#L42-L65) 用 `replaceFirst` 把 [installer.iss#L439-L440](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/packaging/exe/installer.iss#L439-L440) 的两行语句改成“参数数组折到下一行、续行以 `[` 开头”的形状，复现 run 43702798064 的故障；
2. 被测逻辑 [_checkInnoSectionTags](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/tool/packaging/packaging_contract.dart#L617-L634) 逐行扫描，用 `i + 1` 报出 1 基行号 —— **行为正确**，报的就是续行所在行；
3. 用例第 63 行把期望值写死为 `438`。

### 2.3 为什么是 440 而不是 438

模板在同一分支上被连续改过两次：

| 提交 | `FVersionLabel.Caption := FmtMessage(` | 续行 `CustomMessage(...), [Prev, PackageVersion]);` |
|---|---|---|
| `c55c713`（用例落地时） | 437 | **438** |
| `d71186f`（本轮 HEAD） | 439 | **440** |

`d71186f` 在约 396 行处插入了 2 行注释（“参数不能命名为 Label：label 是 Pascal 保留字…”）并把形参 `Label` 改名为 `Target`，该 hunk 净增 2 行，其后所有行号 +2。用例里的 `replaceFirst` 仍然命中（被折叠的语句本身没变），所以夹具没有失效，失效的只有那个字面量。

### 2.4 判断

- 契约检查器无缺陷，产品代码无缺陷；
- 缺陷在**夹具的断言方式**：它断言“模板第 438 行”，而语义应是“报告指向被折叠的那一行”。任何人在 `[Code]` 段上方加两行都会让它变红，这与该文件头注释宣称的“夹具是真实文件的定点变异、不写手搓近似”自相矛盾。

### 2.5 修复方案（不改产品代码）

1. 期望行号改为从变异后的文本推导：在 `wrapped` 上取
   `wrapped.split('\n').indexWhere((l) => l.trimLeft().startsWith('[Prev')) + 1`，再用它断言 `reported.single.line`，并继续断言 `toAnnotation()` 含 `line=<该值>`；
2. 保留 `hasLength(1)` 与 `file == _templatePath`，让断言语义仍为“只报一次、且指向续行”；
3. 保留 `isNot(template)` 守卫，防止模板措辞变化后夹具静默变成空操作。

**不建议**直接把 438 改成 440：下一次编辑模板会以同样的方式再次失效。

---

## 3. 失败二：AppImage dry-run 推断不出架构

### 3.1 失败输出

```text
appimagetool, continuous build (git version 11d54c9), build 370 built on 2026-11-06 00:47:16 UTC
.../ssb_runner.AppDir/ssb_runner.desktop: error: (will be fatal in the future): value item "Audio"
    in key "Categories" ... requires another category to be present among: AudioVideo
##[error]Unable to guess the architecture of the AppDir source directory
    ".../dist/0.3.0+300007/ssb_runner-0.3.0+300007-linux_appimage/ssb_runner.AppDir"
##[error]A valid architecture with the ARCH environmental variable should be provided, e.g. ARCH=x86_64
##[error]packaging dry run (linux-appimage) failed: MakeError: ...
```

调用栈落在 `AppPackageMakerAppImage._make (app_package_maker_appimage.dart:287)`，即 maker 调用 `appimagetool --no-appstream <AppDir> <output>` 的返回值检查处；maker 本身没有传 `ARCH`（[源码](file:///Users/wafer-li/.pub-cache/hosted/pub.dev/flutter_app_packager-0.6.13/lib/src/makers/appimage/app_package_maker_appimage.dart#L275-L289)），架构必须由 appimagetool 自己推断。

### 3.2 锁定版本 appimagetool 的推断规则

仓库按 sha256 锁定 build 370（[install-appimagetool.sh#L19-L25](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/scripts/install-appimagetool.sh#L19-L25)，锁定依据见 `ci-run-43677974432-failure-analysis.md` §7）。其 `src/appimagetool.c`（`11d54c9`）的规则是：

1. 先读环境变量 `ARCH`；
2. 没有则 `find_arch(source, "*.so.*", archs)`：**递归** AppDir，跳过符号链接，对满足以下任一条件的普通文件读取 ELF 头偏移 `0x12` 的 `e_machine`（3=i686、62=x86_64、40=armhf、183=aarch64）：
   - 文件带可执行位，**或**
   - 文件名匹配 `*.so.*`；
3. 命中恰好 1 种架构才继续；0 种 → `Unable to guess the architecture...` 并 `die`；多于 1 种 → `More than one architectures were found...`。

### 3.3 为什么 stub 命中 0 种

[dry_run_packaging.dart#L240-L266](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/tool/packaging/dry_run/bin/dry_run_packaging.dart#L240-L266) 生成的 linux stub，经 maker `cp -r` 成为 AppDir 后的全貌：

| AppDir 内文件 | 真实内容 | 可执行位 | 名字匹配 `*.so.*` | 结果 |
|---|---|---|---|---|
| `ssb_runner`（根） | `writeAsStringSync` 写的纯文本 | 否（0644） | 否 | 不参与推断 |
| `lib/libflutter_linux_gtk.so` | `libm.so.6` 的真 ELF 拷贝 | **否**（Dart `File.copySync` 新建为 0644，不继承源权限） | **否**（`.so` 后没有版本段） | 不参与推断 |
| `AppRun`（maker 写入并 `chmod +x`） | bash 脚本 | 是 | 否 | 参与推断，但 `0x12` 处不是合法 `e_machine` |
| `data/icudtl.dat`、desktop、图标 | 文本/PNG | 否 | 否 | 不参与推断 |

因此 `count_archs == 0`，直接失败。

### 3.4 为什么真实 tag 构建不会遇到

真实 bundle（`build/linux/x64/release/bundle`）根目录的 `ssb_runner` 本身就是 **可执行 ELF**，`e_machine=62` 一次命中；`libflutter_linux_gtk.so` 在真实构建里通常也是 0755。也就是说推断逻辑本身没问题，**是 dry-run 的 stub 没复现真实 bundle 的关键形状**。

这也解释了为什么这个失败直到本轮才出现：上一轮 run 43710059911 在更前面的 `deb` 步骤就失败（见 `d71186f` 提交说明），`appimage` 步骤按顺序被跳过，这是它第一次真正执行 —— **属于新门禁首次运行暴露的 stub 保真度问题，不是回归**。

### 3.5 修复方案

按推荐顺序：

| 方案 | 做法 | 评价 |
|---|---|---|
| A（首选） | 让 AppImage 目标的 stub 复现真实形状：根目录的可执行文件写成真 ELF（复用已有的 `libm.so.6` 查找逻辑）并 `chmod +x` | 与真实 bundle 的推断路径完全一致；对“可执行 ELF 在根目录”的后续启发式变化也稳 |
| B（次选，最小改动） | 仅给已拷贝的 `lib/libflutter_linux_gtk.so` 补 `+x`（真实 so 通常是 0755，属于还原真实权限） | 一行改动即可让候选数变为 1；依赖“so 可执行”这一事实 |
| C（不推荐，只能临时止血） | CI 步骤里加 `ARCH=x86_64`（[trim-appimage-libjvm.sh#L60](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/scripts/trim-appimage-libjvm.sh#L60) 就是这么做的） | dry-run 与 tag 构建的调用方式分叉，恰好绕过本次唯一暴露的差异，门禁价值被削弱 |

注意不要反向“修” maker 或 `make_config.yaml`：maker 不传 `ARCH` 是上游行为，真实 bundle 下工作正常。

---

## 4. 预警项：desktop `Categories` 违反 freedesktop 规范

appimagetool 在本轮打出的另一条信息（当前是警告，工具已声明“will be fatal in the future”）：

```text
value item "Audio" in key "Categories" ... requires another category to be present among: AudioVideo
```

- 来源：[appimage/make_config.yaml#L15-L18](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/linux/packaging/appimage/make_config.yaml#L15-L18) 与 [deb/make_config.yaml#L48-L50](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/linux/packaging/deb/make_config.yaml#L48-L50) 都只写了 `Audio` + `HamRadio`；
- 规则：主分类出现 `Audio` / `Video` 时必须同时出现主分类 `AudioVideo`；`HamRadio` 是合法的 Additional 分类，本身不是问题；
- deb 的 desktop entry 内容与 AppImage 相同，只是 `dpkg-deb` 不做这项校验，问题被隐藏。

**修复方案**：

1. 两个 linux 配置的 `categories` 都补 `AudioVideo`，保持两份 desktop entry 一致（避免再引入一次跨平台漂移）；
2. 在 L0 契约 [_checkIconAndCategories](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/tool/packaging/packaging_contract.dart#L1169-L1206) 增加配对校验：含 `Audio` 或 `Video` 而缺 `AudioVideo` 时报 error；白名单 `_freedesktopCategories` 已包含 `AudioVideo`，无需扩展。

---

## 5. 成本与影响

- 本轮没有产生任何错误产物，也没有发布行为；失败发生在合并前的验证阶段，属于该门禁的设计目标；
- 代价是整条发布矩阵被跳过：两个失败都出现在“秒级~分钟级”的验证作业里，修复成本低，但重跑要等一次完整 CI；
- 两个失败彼此独立，可并行修复、互不影响，也可拆成两个提交/PR。

---

## 6. 实施计划（方案已固化，未动代码）

**决策**：三项按推荐方案执行，不做“改数字 / 传 `ARCH`”这类止血式处理。

| # | 位置 | 选定方案 | 不选项 |
|---|---|---|---|
| 1 | 契约夹具 | §2.5：期望行号由变异文本推导 | 不把 438 改成 440 |
| 2 | AppImage stub | §3.5 方案 A：根目录二进制写成真 ELF 并 `+x` | 不用 B（仅补 so 的 `+x`）、不用 C（CI 传 `ARCH`） |
| 3 | linux desktop `Categories` | 两份 `make_config.yaml` 补 `AudioVideo` + L0 配对校验 | 不只改 yaml（否则下次仍靠外部工具兜底） |

### 6.1 逐项动作

1. [packaging_contract_test.dart#L42-L65](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/test/packaging/packaging_contract_test.dart#L42-L65)
   - 在 `wrapped` 中定位唯一变异续行 `    [Prev, PackageVersion]);`（`split('\n')` + `indexWhere`，结果 +1 得 1 基行号），先断言其 > 0 作为“夹具已命中断言点”的守卫；
   - 用该值断言 `reported.single.line` 与 `reported.single.toAnnotation()` 中的 `line=`；
   - 保留 `hasLength(1)`、`file == _templatePath`、`isNot(template)` 三项语义断言。
2. [dry_run_packaging.dart#L240-L266](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/tool/packaging/dry_run/bin/dry_run_packaging.dart#L240-L266)
   - 仅在 `options.target == 'appimage'` 分支：把已写好的根目录 `_linuxBinaryName()` 覆盖为与 `lib/libflutter_linux_gtk.so` 同一个 `libm.so.6` 拷贝，并 `chmod +x`；
   - `deb` 分支保持纯文本 stub 不变，避免牵动 `_verifyDeb` 的载荷路径断言；
   - 不修改 maker、不在调用处补 `ARCH`。
3. 两个 linux 配置 + 契约
   - [appimage/make_config.yaml#L15-L18](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/linux/packaging/appimage/make_config.yaml#L15-L18) 与 [deb/make_config.yaml#L48-L50](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/linux/packaging/deb/make_config.yaml#L48-L50) 的 `categories` 在首位补 `AudioVideo`，两份保持一致；
   - [_checkIconAndCategories](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/tool/packaging/packaging_contract.dart#L1169-L1206) 在现有白名单循环之后加配对规则：含 `Audio` 或 `Video` 而缺 `AudioVideo` 报 error；白名单 `_freedesktopCategories` 已含 `AudioVideo`，不用扩展。

**范围外**：不改 `_checkInnoSectionTags` 的报行逻辑、不改 `make_config` 的 maker 调用方式、不新增 CI 步骤或环境变量。

### 6.2 验收标准

| 层级 | 命令 / 观察点 | 通过标准 |
|---|---|---|
| L0 本地 | `flutter test test/packaging/packaging_contract_test.dart` | 全绿；在模板 `[Code]` 段上方临时增删行后用例仍绿（验证后还原） |
| 静态 | `dart analyze tool/packaging` | 无新增 issue |
| Linux dry-run | appimage | 日志出现 `Using architecture x86_64`，以 `dry run: AppImage is an ELF image` 结束；`Categories` 校验提示消失 |
| Linux dry-run | deb | 仍输出 `dry run: deb contains opt/... and desktop entry`（stub 改动未波及） |
| CI 全链路 | 推送后复跑 | `Validate packaging (linux)` 通过；`Compile (windows)` → `Package (*)` → `Smoke test (*)` → `Draft GitHub Release` 恢复执行（本轮全被跳过） |

### 6.3 提交划分

三项彼此独立。建议两个提交：① 夹具派生行号；② stub 复现 ELF 形状 + `AudioVideo` 配对校验（同属“打包门禁保真度”）。也可合并为单个 `fix(packaging):` 提交；若 CI 再次失败，两项可单独定位。

---

## 7. 经验

1. **夹具不能断言绝对物理行号**：只要断言对象是“某个被变异文件里的位置”，期望值就必须从同一份变异文本推导，否则任何无关插入都会造成假红。这类失败会被误读成产品回归。
2. **dry-run 的 stub 必须复现“工具会读的”那部分形状**：stub 只要求“maker 能接受”不够，还要满足下游工具的前置探测（这里是 ELF 可执行位 / `*.so.*` 命名）。stub 与真实 bundle 的形状差异只会在该工具第一次真正执行时暴露。
3. **外部工具的行为要按源码确认**：`Unable to guess the architecture` 不是配置错误也不是环境缺失，而是锁定版本的启发式规则与 stub 不匹配；只读日志容易误判为“缺 `ARCH` 环境变量”。
4. **规范校验的警告要当作待修项**：`(will be fatal in the future)` 这类提示会随工具升级变成失败，且同一份内容在 deb desktop entry 中同样存在，只是没有校验器盯着。

---

## 8. 参考

- 本轮日志：`Analyze & Test`（job 132813662682）、`Validate packaging (linux)`（job 132813806147）
- appimagetool 源码（锁定提交 `11d54c9`，`src/appimagetool.c`）：`find_arch()`、`guess_arch_of_file()`、`read_elf_e_machine_field()`，以及 `main()` 中 `ARCH` → `find_arch` → `die` 的分支
- 相关历史分析：[ci-run-43677974432-failure-analysis.md](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/docs/research/ci-run-43677974432-failure-analysis.md)（appimagetool 版本固定与 build 370 的权限校验）、[ci-run-43702798064-failure-analysis.md](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/docs/research/ci-run-43702798064-failure-analysis.md)（L0/L1-L3 打包验证层的设计来源）
