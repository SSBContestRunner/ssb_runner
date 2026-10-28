# SSB Runner Windows 单文件分发方案调研

> 调研时间：2026-10-29
> 调研范围：仅 Windows x64 桌面端。目标是把当前“下载 zip → 解压 → 双击 ssb_runner.exe”的交付方式，评估升级为“一个文件交付”的可行性与技术路线。
> 实施状态：**仅调研，未改动任何代码、CI 或打包配置**。
> 结论置信度：方案能力来自各工具官方文档与本地源码/产物实测；体积为估算值，最终以 Windows 实机打包结果为准。

---

## 0. 结论（TL;DR）

先把“单文件”拆成三个不同目标，避免混为一谈：

| 目标 | 含义 | 可行方案 | 推荐度 |
|---|---|---|---|
| **A. 单文件安装器** | 用户只下载一个文件，双击安装后从开始菜单启动 | **Inno Setup 生成的 `-setup.exe`**（fastforge 已内置 `exe` target） | ★★★★★ 首选 |
| **B. 原生 MSI** | 企业环境用 `.msi` 做 GPO / Intune / SCCM 分发 | **WiX Toolset 自行构建 MSI**（fastforge 无 MSI target） | ★★ 仅在明确需要 MSI 时 |
| **C. 单文件 MSIX** | 一个 `.msix`，走 Microsoft Store / App Installer 自动更新 | fastforge `msix` target + **真实代码签名证书** | ★★★ 受签名前置条件约束 |
| **D. 单 exe 便携** | 用户拿到一个 exe，双击即用，不安装、不产生目录 | **Enigma Virtual Box**（内存虚拟化）或 **7-Zip SFX / IExpress**（自解压） | ★★★ 需 PoC 验证 |
| **E. 真·单 exe** | 把 Flutter 引擎、资源和代码静态链接成一个 exe | **官方不支持，工程上不可行** | ☆ 不建议投入 |

**建议路线：**

1. **P0：先做 A（Inno Setup `-setup.exe`），同时保留现有 zip。** 这是成本最低、风险最小、用户体验提升最明显的方案：只新增一个打包配置文件、CI 的 targets 从 `zip` 改成 `zip,exe`，并在 Windows runner 上确认 `ISCC.exe` 可用。
2. **P1：在 Windows 虚拟机做 D 的 PoC（Enigma Virtual Box）。** 如果“双击一个 exe 就能跑”是硬需求，Enigma 是当前唯一免费且可脚本化的成熟路线；但必须验证 sqlite3 / flutter_soloud 的 DLL 动态加载、杀毒软件误报和启动性能。
3. **P2：MSIX 等代码签名就绪后再做。** MSIX 的自签名证书对最终用户不可接受（要用户手动把证书装进“受信任的根证书颁发机构”）；接入 SignPath Foundation（开源项目免费签名）后，MSIX 才真正可用。
4. **B（MSI）只在出现明确的企业批量分发需求时再做**，不要仅为了“文件后缀是 msi”而承担一套新工具链。

---

## 1. 现状与本项目约束

| 维度 | 现状 |
|---|---|
| Flutter 版本 | FVM 固定 `3.47.5`（`.fvmrc`） |
| 打包工具 | fastforge `0.6.12`，CI 用 `dart pub global run fastforge:main package` |
| 当前 Windows 产物 | `ssb_runner-0.2.0+200006-windows.zip` |
| 产物实测体积 | **30.5 MB**（zip，deflate），解压后 **55.5 MB / 643 个文件** |
| 目录结构 | `ssb_runner.exe` + **16 个 DLL** + `data/`（`app.so` 7.9 MB、`icudtl.dat` 0.86 MB、`flutter_assets` ≈ 18 MB） |
| 关键 DLL | `flutter_windows.dll`(21.3 MB)、`sqlite3.dll`、`flutter_soloud_plugin.dll`、`FLAC/ogg/opus/vorbis*.dll`、`window_manager_plugin.dll`、`file_selector_windows_plugin.dll`、`screen_retriever_windows_plugin.dll`、`dartjni.dll`、VC++ 运行库 |
| 签名 | 无。Windows 首次运行会触发 SmartScreen “未知发布者” |
| 用户数据 | 日志优先写 `%APPDATA%`（`log_paths.dart` 的候选顺序），数据库在“文档”目录下的 `ssb_runner/`；均不在安装目录，安装/卸载无需特殊处理 |
| 仓库性质 | public、GPL-3.0，符合 SignPath Foundation 免费签名条件 |

> 结论：**Windows 侧不是“一个 exe”，而是“1 个 exe + 16 个 DLL + 一个 55 MB 的数据目录”**。这决定了“单文件”只能通过安装器、打包器或自解压壳实现，不能在 Flutter 构建阶段直接产出。

### 1.1 为什么 Flutter 不能直接编译成一个 exe

Flutter 官方 Windows 部署文档明确：除可执行文件外，还必须随包分发同目录下的全部 `.dll`、`data/` 目录以及 VC++ 运行库。原因：

1. `flutter_windows.dll` 是 Flutter 引擎的**共享库**，Windows runner 在进程启动时加载它；Flutter 不提供静态链接版本。
2. Dart AOT 快照在 `data/app.so`，ICU 数据在 `data/icudtl.dat`，资源在 `data/flutter_assets/`；引擎按“可执行文件所在目录”解析这些路径，均为文件系统路径，不支持从内存加载。
3. 本项目还通过 Dart build hooks 引入原生资产：`sqlite3.dll`（`package:sqlite3`）和 `flutter_soloud_plugin.dll` 等；FFI 在运行时按 DLL 名动态加载。
4. 插件（`window_manager`、`file_selector_windows`、`screen_retriever_windows`）各自带插件 DLL。

因此，“真·单 exe”需要修改 Flutter 引擎/嵌入层，属于不可接受的维护成本。实际可选的只有：

- **安装器**：把一个目录打包成单个安装文件（A / B / C）；
- **运行期打包器**：把目录塞进一个 exe，运行时虚拟化或解压（D）。

---

## 2. 方案 A：Inno Setup 单文件安装器（推荐）

### 2.1 原理与产物

Inno Setup 把整个 `Release/` 目录压缩进一个安装程序，运行时解压到安装目录，并写入开始菜单快捷方式、卸载项和注册表。产物是单个 `ssb_runner-<version>-windows-setup.exe`。

官方特性（与本次需求直接相关）：

- 支持生成**单个 EXE** 安装包，支持 `LZMA/LZMA2` 压缩与固实压缩（SolidCompression）；
- 支持**管理员安装**与**非管理员（per-user）安装**；
- 支持多语言（含简体中文）、静默安装 `/VERYSILENT`、数字签名、卸载；
- 安装器自身开销约 1.78 MB。

### 2.2 fastforge 0.6.12 已内置 `exe` target

本项目不需要引入新工具，fastforge 的 Windows packager 已经包含 Inno Setup maker：

- 命令：`--platform=windows --targets=zip,exe`
- 配置文件：`windows/packaging/exe/make_config.yaml`（与现有 `linux/packaging/deb/make_config.yaml`、`macos/packaging/dmg/make_config.yaml` 的结构一致）
- 产物命名：fastforge 的模板会给安装器加 `-setup` 后缀，即 `ssb_runner-0.2.0+200006-windows-setup.exe`
- 编译器解析顺序：`INNO_SETUP_PATH` 环境变量 → `C:\Program Files (x86)\Inno Setup 6` → `PATH` 里的 `iscc`
- 未安装 Inno Setup 时 fastforge 会直接报错，提示安装 Inno Setup 6

fastforge 0.6.12 生成的默认脚本要点（来自本地包源码 [inno_setup_script.dart]）：

```ini
Compression=lzma
SolidCompression=yes
DefaultDirName={autopf64}\$appName
PrivilegesRequired=none
```

- `{autopf64}` 是 Inno 的“自动”常量：管理员模式下映射到 `Program Files`，非管理员模式映射到 `%LOCALAPPDATA%\Programs`。
- fastforge 默认 `PrivilegesRequired=none`（Inno 的未文档化取值）：普通用户不弹 UAC，管理员用户仍会提权。**这会带来“同一版本装在不同位置”的不一致**，建议显式改成 `lowest` 做纯 per-user 安装。

### 2.3 建议配置（未来落地时新增，本次不改）

```yaml
# windows/packaging/exe/make_config.yaml
app_id: 6F1C1B7E-0B2A-4F2E-9D4C-9C0A6E5B7D31   # 稳定 GUID（不要加花括号），升级必须保持不变
display_name: SSB Runner
executable_name: ssb_runner.exe
publisher_name: SSB Contest Runner
publisher_url: https://ssbrunner.com/
install_dir_name: "{localappdata}\\Programs\\SSB Runner"
privileges_required: lowest
create_desktop_icon: false
launch_at_startup: false
locales:
  - en
  - zh
setup_icon_file: windows/runner/resources/app_icon.ico
```

要点：

- `app_id` 是安装器识别“同一个应用”的唯一键：它决定“升级覆盖旧版本”还是“并存两个版本”，发布后不可更改。
  - Inno 的 `AppId` 允许任意唯一字符串，但花括号会被当作常量解析；因此写裸 GUID（`6F1C...`），不要写成 `{6F1C...}`。
- `privileges_required: lowest` → 安装到 `%LOCALAPPDATA%\Programs\SSB Runner`，不触发 UAC；卸载只需当前用户权限。
- `install_dir_name` 显式写出，避免依赖 `{autopf64}` 的模式差异。
- `setup_icon_file` 用现有的 `app_icon.ico`（256×256）。
- 若后续需要“安装时可选是否创建桌面图标 / 开机启动”，fastforge 模板已经生成了对应 Tasks，默认不勾选。
- 需要更复杂的逻辑（例如卸载时询问是否保留用户数据、检测旧版本进程）再使用 `script_template` 自定义 Liquid 脚本；默认模板已覆盖 `[Files]`、`[Icons]`、`[Run]`。

### 2.4 体积与安装体积

| 项目 | 估算 |
|---|---|
| 安装包 | **约 25–30 MB**（LZMA 固实压缩，通常优于 zip 的 deflate；以实测为准） |
| 安装后磁盘占用 | **约 55.5 MB**（与现 zip 解压后一致） |
| 安装耗时 | 数秒（55 MB 数据解压） |

即：安装包**不比现在的 zip 大**，甚至可能更小。

### 2.5 用户体验与 SmartScreen

- 用户只下载一个 `.exe`，双击 → 下一步 → 完成，从开始菜单启动。
- 未签名时，SmartScreen 会在**运行安装器时**提示一次；安装后的主程序由安装器写入，不再带“来自 Internet”的 Mark-of-the-Web，通常不会再次拦截。
- 相比之下，zip 解压出的每个文件都可能带 MOTW，用户更容易反复看到拦截提示。安装器在未签名场景下也是更好的体验。
- 彻底解决仍需代码签名（见 §8）。

### 2.6 CI 改造点（未来落地）

1. `setup` job 的 Windows matrix：`targets: 'zip,exe'`。
2. `package-windows` 的 fastforge 命令：`--targets=zip,exe`。
3. 确认 Inno Setup 可用：GitHub 官方 `windows-latest` / `windows-2025` 镜像通常预装 Inno Setup 6.6.x；仍建议在 job 里显式检查 `iscc`，不存在时 `choco install innosetup -y` 兜底。
4. 新增一个 Windows 冒烟测试 job（可选但强烈建议）：
   - 静默安装：`setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`
   - 断言 `%LOCALAPPDATA%\Programs\SSB Runner\ssb_runner.exe` 存在
   - 启动程序并等待日志文件产生
   - 静默卸载：`unins000.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`
   - 断言安装目录被删除、用户数据仍在
5. `release` job 已按 `dist/**` 收集并展平，无需改动。

> 注意：Windows CI 仍需处理 `distribute_options.yaml` 里 `FLUTTER_ROOT` 的相对路径问题（现有 workflow 已用绝对路径重写解决），与新增 `exe` target 无冲突。

### 2.7 风险

| 风险 | 说明 | 缓解 |
|---|---|---|
| 未签名 | SmartScreen “未知发布者”仍然存在 | 接入 SignPath Foundation（开源免费）；或在 README/下载页写清放行步骤 |
| 安装位置不一致 | 默认 `PrivilegesRequired=none` 会让管理员装到 Program Files、普通用户装到 LocalAppData | 显式 `privileges_required: lowest` |
| 无自动更新 | Inno 不自带 updater | 先手动下载新安装包覆盖安装；后续可评估 WinSparkle 等 |
| 用户数据清理 | 卸载默认不删除 `%APPDATA%` 和“文档”下的数据 | 产品上视为“保留用户数据”，README 说明即可 |
| 安装器被 AV 误报 | 少见，但未签名安装器可能被启发式拦截 | 代码签名 + 提交误报样本 |
| fastforge 0.6.12 属旧 CLI | 新版 Rust CLI 已把配置迁移到 `.fastforge/`，旧 `distribute_options.yaml`/`release` 标记为 deprecated | 继续锁定 0.6.12；未来迁移时把 `windows/packaging/exe/make_config.yaml` 换成 `.fastforge/packaging/windows/exe/setup.iss` |

---

## 3. 方案 B：原生 MSI（WiX）

### 3.1 结论

技术上完全可行，但**不建议作为首选**：fastforge 没有 MSI target，需要为 Windows 单独引入一套 WiX 构建链；对最终用户而言，MSI 相对 `-setup.exe` 没有体验优势，主要价值在企业批量分发。

### 3.2 技术路径

- 工具：WiX Toolset v5（MS-RL，免费）或 v6；CI 用 `dotnet tool install --global wix`，`wix build` 生成 `.msi`。
- 文件收集：WiX 4+ 支持 `<Files Include="build\windows\x64\runner\Release\**">` 自动生成组件；643 个文件可直接纳入，CAB 内嵌到 MSI（`MediaTemplate EmbedCab="yes"`）。
- 安装范围：`<Package Scope="perUser">` 可做免管理员安装；`perMachine` 需要 UAC。
- 升级：固定 `UpgradeCode` + `MajorUpgrade`，保证覆盖升级。
- 快捷方式 / 图标 / 卸载项：WiX 原生支持。
- 体积：与 Inno 接近（约 28–33 MB，CAB 压缩），安装后 55.5 MB。

### 3.3 代价与限制

1. **新工具链**：CI 需 .NET SDK + WiX；还要维护 `.wxs` / `.wixproj`，与现有 fastforge 流程并行。
2. **WiX v6 的 Open Source Maintenance Fee**：官方规定，使用 WiX v6 且项目年收入超过 1 万美元时需要付费订阅；低于阈值（含无收入的开源项目）免费。若想完全规避，使用 v5。
3. **MSI 的 per-user 支持有历史包袱**：快捷方式、ARP 展示、ICE 校验都比 per-machine 麻烦，且不同 Windows 版本行为不完全一致。
4. **仍然未签名**：MSI 同样会触发 SmartScreen。
5. **Intune/GPO 并非只能装 MSI**：Intune 的 Win32 App 可以直接封装 Inno Setup 的 exe（带静默参数），所以“企业分发”本身不构成必须做 MSI 的充分理由。

### 3.4 何时才做

- 客户明确要求 `.msi`（例如只允许 MSI 的软件分发平台、需要 MSI 的补丁/修复语义、需要 GPO 的 Assigned/Published 部署）；
- 或者未来需要 MSIX 之外的企业级管理能力。

---

## 4. 方案 C：MSIX

### 4.1 技术路径

- fastforge 已有 `msix` target（底层是 `msix` 3.18.0 包）：`--targets=msix`，配置文件 `windows/packaging/msix/make_config.yaml`。
- 依赖 Windows SDK 的 `makeappx` 与 `signtool`；`windows-latest` 已包含。
- MSIX 全信任桌面应用（`runFullTrust`）可以正常运行 Flutter 应用；应用安装在 `WindowsApps`（只读），日志/数据库在 `%APPDATA%` / 文档目录，不受影响。
- 附带能力：App Installer 自动更新、Store / winget 分发、干净卸载。

### 4.2 关键前置条件：签名

这是 MSIX 的**硬门槛**：

- 从 Windows 10 2004 / Windows 11 起，侧载（sideloading）默认开启；但**仍要求安装包由受信任的证书签名**。
- `msix` 包默认用内置的**自签名测试证书**签名，并尝试把该证书装到**构建机**上。对最终用户无效：用户要自己把证书导入“本地计算机 → 受信任的根证书颁发机构”，需要管理员权限，等于劝退。
- 公开分发必须使用真实证书（OV/EV），或走 Microsoft Store（由 Store 签名）。
- 对本项目最现实的路径：**SignPath Foundation**（开源项目免费签名，含 HSM 托管私钥）→ 在 CI 中 `signtool` 签名 MSIX；这也是现有 CI 调研文档中已列出的后续选项。

### 4.3 项目相关的命名与版本约束

- **Identity Name**：必须是 3–50 个 ASCII 字母/数字/点/横线，不能有下划线。建议 `com.ssbrunner.app`（与 macOS/Linux 的标识一致），不要沿用 `ssb_runner`。
- **Publisher**：必须与签名证书的 Subject 完全一致，否则安装时报错。
- **Version**：四段 `a.b.c.d`，每段 0–65535；`msix` 包会取 `pubspec.yaml` 的 `major.minor.patch` 并补 `0`，所以当前会生成 `0.2.0.0`（build number `200006` 被丢弃）。
  - 若要进 Microsoft Store，第一段不能为 0，需要显式设置 `msix_version`（例如 `1.0.0.0`）。
  - 同一 `major.minor.patch` 多次发版时，MSIX 不感知 build number，需要显式递增 `msix_version`，否则不会触发更新。
- **升级连续性**：Identity Name 一旦发布不可更改，否则会被视为另一个应用，无法覆盖升级。

### 4.4 结论

- 技术上可行，且是“单文件 + 自动更新”体验最好的方案；
- **但必须先解决代码签名**，否则不建议对公众发布；
- 建议作为 P2：等 SignPath 接入后再同时产出 `.msix`（或仅用于 Store / winget）。

---

## 5. 方案 D：单文件便携 exe（不安装）

### 5.1 Enigma Virtual Box

**能力**（官方说明）：

- 免费（freeware），支持 x86 / x64；
- 把应用文件与注册表项**合并进单个 exe**；
- **不向磁盘释放虚拟文件**，文件读写由进程内拦截、在内存中模拟；
- 支持压缩虚拟文件以减小体积；
- 通过在主模块中嵌入 loader、拦截文件系统 API 实现。

**CI 可脚本化**：`enigmavirtualbox` npm 包提供 `gen`（生成 .evb 配置）与 `cli`（执行打包）；Flutter 社区已有项目在 GitHub Actions 中用这条路径产出单文件 exe（`flut-renamer`），说明对 Flutter 产物是可行的。

**操作步骤（PoC）**：

1. `flutter build windows --release`，得到 `build/windows/x64/runner/Release/`。
2. 生成 `.evb` 配置：主程序 `ssb_runner.exe`，加入 16 个 DLL，加入 `data/` 目录（递归），开启压缩。
3. `enigmavirtualbox cli ssb_runner.evb` → 单个 `ssb_runner.exe`。
4. 在干净的 Windows 10/11 虚拟机上验证（见 §7 验收清单）。

**预期结果**：

| 项目 | 估算 |
|---|---|
| 单 exe 体积 | 约 30–40 MB（取决于压缩级别） |
| 启动 | 首次/每次启动都要把虚拟文件解压到内存，可能比安装版慢；55 MB 数据会占用额外内存 |
| 磁盘 | 不产生安装目录（这是它相对 SFX 的最大优势） |

**必须验证的风险点**：

1. **静态导入的 `flutter_windows.dll`**：EVB 需要把原本由 Windows loader 解析的导入转换为自己的加载逻辑；需实测能否正常启动。
2. **FFI 动态加载**：`sqlite3.dll` 由 Dart FFI 在运行时 `LoadLibrary`，`flutter_soloud_plugin.dll` 及 FLAC/ogg/opus/vorbis 由插件加载；虚拟文件系统对 `LoadLibrary` 的拦截是否完整，是成败关键。
3. **杀毒/EDR**：所有“加壳/打包”类工具都容易被启发式误报；需要 Defender 与至少一款第三方 AV 实测，必要时提交误报。
4. **签名**：必须在 EVB 打包**之后**用 `signtool` 签名最终 exe；先签名原 exe 会被打包过程破坏。
5. **崩溃/日志**：日志默认写 `%APPDATA%`，不依赖虚拟 FS，风险低；但仍需验证 `catcher_2` 崩溃对话框和导出日志。
6. **更新**：单 exe 无自动更新，用户需手动替换文件；无法注册文件关联/开始菜单。
7. **Windows on ARM**：本项目只承诺 x64；EVB 对 ARM 的支持不在验证范围。

**结论**：如果“一个 exe 双击即用”是产品硬需求，Enigma 是最省事的免费方案，但**必须先在 Windows 虚拟机做完整 PoC**，不能仅凭构建成功就发布。

### 5.2 自解压 SFX（7-Zip / IExpress）

**做法**：把现有 `Release/` 目录打成 7z，套上 7-Zip SFX 模块（或 Windows 自带的 IExpress），生成单个 exe；运行时先解压到 `%LOCALAPPDATA%\SSB Runner\<version>`，再启动其中的 `ssb_runner.exe`。

**优点**：

- 不依赖 API hook，行为可预测；
- 可直接复用现有 zip 内容；
- 解压目录可缓存，后续启动不必重复解压。

**缺点**：

- 首次启动需要解压 55 MB，明显慢于安装版；
- 磁盘上仍会出现一份完整目录（55 MB），只是用户“看到”的是一个文件；
- 每次升级要处理旧版本目录清理；
- 自解压壳同样容易被 AV 误报；
- 若解压到可被其他用户写入的目录，存在 DLL 劫持风险，必须使用 per-user 且权限受控的目录。

**结论**：是 Enigma 的“保守替代”。如果 Enigma 在 Flutter 上出现兼容性问题，SFX 更容易做对，但体验（首次启动、磁盘占用）不如 Enigma。

### 5.3 商业打包器

- BoxedApp Packer、Turbo Studio（原 ThinApp 同类）、Cameyo 等都能做“单 exe + 虚拟化”，兼容性通常更好，但均为付费且授权成本不低；对本项目（开源、零预算）不优先考虑。

### 5.4 真·单 exe（不可行）

除非 fork Flutter 引擎并把 `data/` 与 `flutter_windows.dll` 静态编译进 runner（没有官方支持，且每次 Flutter 升级都要重新维护），否则无法做到。**不建议投入。**

---

## 6. 其他分发渠道

| 渠道 | 可行性 | 说明 |
|---|---|---|
| **winget** | 可行 | 支持 `inno`、`zip`（portable）、`msix` 等 installer type。可以先发 zip/portable，后续发 inno 安装器；需要向 `microsoft/winget-pkgs` 提交 manifest，能显著提升可发现性和升级体验。 |
| **Scoop** | 可行 | 现有 zip 即可；写一个 manifest（`checkver` + `autoupdate`）即可自动跟随 GitHub Release。 |
| **Microsoft Store** | 可行但门槛高 | 需要 MSIX、Partner Center 开发者账号（有一次性注册费，以官网为准），且 Identity/Publisher 必须与 Store 后台一致；Store 会代为签名。 |
| **Intune / SCCM** | 可行 | 可直接用 Inno 安装器做 Win32 App（静默参数 `/VERYSILENT`）；不必为此专门做 MSI。 |

---

## 7. 方案对比与验收

### 7.1 对比矩阵

| 方案 | 交付物 | 是否安装 | 免管理员 | 体积（估） | CI 改造量 | 签名要求 | 自动更新 | 主要风险 |
|---|---|---|---|---|---|---|---|---|
| **现状 zip** | `.zip` | 否（解压即用） | 是 | 30.5 MB | 无 | 无 | 无 | 解压步骤、MOTW 反复拦截、易缺文件 |
| **A. Inno exe** | `-setup.exe` | 是 | 是（`lowest`） | 25–30 MB | **小**（配置 + targets） | 建议签名 | 无（手动覆盖安装） | SmartScreen、安装位置一致性 |
| **B. WiX MSI** | `.msi` | 是 | 可（perUser） | 28–33 MB | 大（新工具链） | 建议签名 | 无 | 工具链维护、per-user MSI 复杂度 |
| **C. MSIX** | `.msix` | 是 | 可（per-user 包） | 30–35 MB | 中 | **必须**真实证书 | **有**（App Installer） | 证书、Identity/版本约束 |
| **D1. Enigma** | 单 `.exe` | 否 | 是 | 30–40 MB | 中（npm + 配置 + 签名） | 建议签名 | 无 | DLL 动态加载、AV 误报、启动性能 |
| **D2. SFX** | 单 `.exe` | 否（自解压） | 是 | 30 MB + 解压 55 MB | 中 | 建议签名 | 无 | 首次启动慢、磁盘占用、AV |
| **E. 原生单 exe** | 单 `.exe` | 否 | 是 | — | 极大（改引擎） | — | — | **不可行** |

### 7.2 验收清单（Windows 10/11 干净虚拟机）

**安装器 / MSIX / 便携包通用：**

1. 从开始菜单（或双击单 exe）启动，工作目录为 `C:\Windows\System32` 时仍能找到资源与数据。
2. 音频：所有语音包、噪声底、QSB、音量设置正常；`flutter_soloud` 无 DLL 缺失。
3. 数据库：首次建库、已有库迁移、写入与读取正常（`sqlite3.dll` 加载成功）。
4. 日志：写入 `%APPDATA%`；`Diagnostics → Export logs` 可导出 zip；崩溃对话框可弹出。
5. `window_manager` 窗口尺寸/最小尺寸正常；`file_selector` 对话框正常。
6. 安装器：免 UAC 安装、开始菜单图标正确、卸载项存在、静默安装/卸载成功。
7. 覆盖升级：新旧版本同 `AppId` / 同 Identity，升级后用户数据保留、无重复卸载项。
8. 卸载：安装目录删除，`%APPDATA%` 与文档数据保留。
9. 安全：Defender 扫描无威胁；记录 SmartScreen 的实际提示与放行步骤。

**Enigma 单 exe 额外验证：**

10. 确认没有向磁盘释放文件（进程运行期间检查临时目录与安装目录）。
11. 确认 `sqlite3.dll`、`flutter_soloud_plugin.dll`、`FLAC/ogg/opus/vorbis*.dll` 均从虚拟 FS 成功加载（可用 Process Monitor 观察）。
12. 记录冷启动耗时与内存占用，与安装版对比。
13. 最终 exe 的签名在打包后完成，签名校验通过。

---

## 8. 代码签名（所有“单文件”方案的共同短板）

| 方案 | 成本 | 适用性 |
|---|---|---|
| **SignPath Foundation** | 免费（开源项目） | 最契合本项目：public、GPL-3.0；提供证书 + HSM，可集成 GitHub Actions |
| Azure Trusted Signing | 约 $9.99/月起 | 微软官方，需企业资质审核 |
| 商业 OV/EV 证书 | 数百美元/年 | 私钥常在 USB Token，CI 集成麻烦；EV 对新发布者的 SmartScreen 信誉更友好 |
| 不签名 | $0 | 保留现状：SmartScreen 提示 + README 放行说明 |

> 签名只解决“发布者可信”，不等于“立即没有 SmartScreen 提示”：OV 证书仍需要积累下载信誉，EV 证书通常更快建立信誉。无论哪种，安装器的体验都优于 zip。

---

## 9. 推荐实施顺序

| 阶段 | 内容 | 预估改动 | 状态 |
|---|---|---|---|
| **P0** | 新增 Inno Setup `-setup.exe`，保留 zip；CI targets 改为 `zip,exe`；增加 Windows 静默安装冒烟测试 | `windows/packaging/exe/make_config.yaml` + CI 2 处 | 待实施 |
| **P1** | Enigma Virtual Box 单 exe PoC（Windows VM），通过 §7.2 第 10–13 项后再决定是否发布 | 打包脚本 + CI job | 待验证 |
| **P2** | 接入 SignPath，签名安装器；评估 MSIX + App Installer | CI secrets + MSIX 配置 | 待签名就绪 |
| **P3** | winget / Scoop manifest；README 下载矩阵更新 | 仓库外 manifest + 文档 | 可选 |
| **按需** | WiX MSI（仅在企业分发需求出现时） | 新工具链 | 不做 |

### 9.1 不做的事

- 不修改 Flutter 引擎、不尝试静态链接 `flutter_windows.dll`；
- 不在 P0 阶段引入 MSI；
- 不在没有真实证书的情况下公开发布 MSIX。

### 9.2 需要产品侧确认的问题

1. Windows 的“单文件”目标到底是 **一个安装包**（A）还是 **一个免安装的便携 exe**（D）？两者的实现与风险完全不同。
2. 是否接受 per-user 安装（装到 `%LOCALAPPDATA%\Programs`、不弹 UAC），还是必须装到 `Program Files`？
3. 是否有企业批量分发（Intune/GPO/SCCM）需求？如果有，是接受 Inno 安装器，还是必须原生 MSI？
4. 是否愿意为代码签名投入（SignPath 免费 / 商业证书付费）？这决定 MSIX 是否值得做。

---

## 10. 风险与注意事项

1. **“单文件”不等于“单目录”**：安装器和 MSIX 安装后仍是完整目录；只有 Enigma/SFX 能给用户“一个 exe”的观感，但代价是兼容性/性能/AV 风险。
2. **未签名是当前最大体验短板**，与打包格式无关；SignPath 是本项目最划算的解法。
3. **fastforge 版本锁定 0.6.12**：旧 CLI 仍可用，但配置格式（`distribute_options.yaml`、`windows/packaging/*/make_config.yaml`）已被官方标记为 deprecated；未来迁移到 Rust CLI 时，Inno 配置要改为 `.fastforge/packaging/windows/exe/setup.iss`，MSIX 改为原生 manifest。
4. **`FLUTTER_ROOT` 仍是 Windows CI 的已知坑**：现有 workflow 在 Runner 上重写为绝对路径；新增 target 不会改变这一点。
5. **版本号一致性**：安装器 `AppVersion`、tag、`pubspec.yaml`、MSIX `msix_version` 需要统一；MSIX 会丢弃 build number，必要时显式指定四段版本。
6. **MSIX Identity 不可变**：一旦发布，改名等于换应用；发布前确定 `com.ssbrunner.app`。
7. **Inno Setup 许可**：license.txt 允许包括商业用途在内的使用；官网只是“请求”商业用户购买支持许可。对本 GPL 项目无额外成本。
8. **WiX v6 的 OSMF**：年收入低于 1 万美元（含无收入）免费；若未来项目产生收入，需评估订阅费用，或改用 WiX v5。
9. **AV 误报**：Enigma/SFX 产出的“打包 exe”比普通安装器更容易被启发式拦截；发布前至少跑 Defender + 一款第三方 AV，并准备误报提交流程。
10. **用户数据策略**：卸载不删除 `%APPDATA%` 与“文档/ssb_runner”；如需“彻底卸载”，应在安装器脚本里增加可选项，而不是默认删除。
11. **分发渠道一致性**：同一版本应同时提供 `-setup.exe` 与 zip（以及未来的 msix），避免用户在不同页面下载到行为不同的包。

---

## 11. 参考资料

**Flutter 官方**

- 构建 Windows 应用（产物必须包含 DLL 与 `data/`）：<https://docs.flutter.dev/platform-integration/windows/building>
- Windows 发布/打包（MSIX 与 Store）：<https://docs.flutter.dev/deployment/windows>

**打包工具**

- fastforge Windows packagers（EXE/MSIX/ZIP，Inno Setup 解析顺序）：<https://github.com/fastforgedev/fastforge/blob/main/docs/en/packagers/windows.md>
- fastforge 仓库与 Rust CLI 迁移说明：<https://github.com/fastforgedev/fastforge>
- Inno Setup 官方介绍（单 EXE、per-user、LZMA2、多语言）：<https://jrsoftware.org/isinfo.php>
- Inno Setup 下载（6.7.3 / 7.1.0）：<https://jrsoftware.org/isdl.php>
- Inno Setup 常量（`{autopf64}` 的自动映射）：<https://jrsoftware.org/ishelp/topic_consts.htm>
- Inno Setup 许可证：<https://jrsoftware.org/files/is/license.txt>
- msix Dart 包（CLI、签名与配置项）：<https://pub.dev/packages/msix>
- msix 版本推导规则：<https://github.com/YehudaKremer/msix/blob/main/doc/msix_version.md>
- WiX Toolset 项目与许可：<https://dotnetfoundation.org/projects/project-detail/wix-toolset>
- WiX v6 的 Open Source Maintenance Fee 说明：<https://docs.firegiant.com/wix/whatsnew/>

**MSIX / Windows 签名**

- MSIX 签名与自签名测试证书：<https://learn.microsoft.com/en-us/windows/msix/package/sign-msix-package-guide>
- 侧载企业应用（受信任证书要求）：<https://learn.microsoft.com/en-us/windows/application-management/sideload-apps-in-windows>
- 包版本号规则（四段、65535）：<https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/package-version-numbering>
- winget manifest / installer type：<https://learn.microsoft.com/en-us/windows/package-manager/package/manifest>

**单 exe / 虚拟化**

- Enigma Virtual Box 官方说明（免费、x64、内存虚拟化、压缩）：<https://www.enigmaprotector.com/en/aboutvb.html>
- Enigma Virtual Box 下载：<https://www.enigmaprotector.com/en/downloads.html>
- Node 版 EVB CLI（CI 脚本化）：<https://www.npmjs.com/package/enigmavirtualbox>
- Flutter 项目用 EVB 产出单文件 exe 的 CI 先例：<https://github.com/sun-jiao/flut-renamer/blob/master/.github/workflows/main.yml>
- GitHub 托管 Runner 预装软件清单（Inno Setup 等）：<https://github.com/actions/runner-images>

**签名（可选）**

- SignPath Foundation（开源免费代码签名）：<https://signpath.org/>
