# SSB Runner 桌面端跨平台 CI/CD 方案调研

> 调研时间：2026-09-30
> 调研范围：**仅桌面端**——为 Flutter 桌面应用（Windows / macOS / Linux）补齐持续集成与持续发布能力，优先采用**零成本**方案；移动端（Android / iOS）与 Web **不在本次范围内**；代码签名/公证**本期不实施**。
> 实施状态：**P0–P2 已落地**，见 `.github/workflows/ci.yml`；落地过程中顺带修复的问题见 §8.1。
> 结论置信度：定价与额度均来自各厂商官方文档（文末附链接），但各家政策变动频繁，正式落地前建议再核对一次。

---

## 0. 结论（TL;DR）

1. **首选方案：GitHub Actions + GitHub 托管标准 Runner。**
   本项目（`SSBContestRunner/ssb_runner`）是 **public 仓库**，而 GitHub 官方明确：*"Use of the standard GitHub-hosted runners is free and unlimited on public repositories."* —— Linux / Windows / macOS 标准 Runner 全部**免费且不限分钟数**，完全覆盖本项目三平台（Windows / macOS / Linux）矩阵构建的需求。
2. **跨平台构建天然匹配：** Windows 产物只能在 Windows 构建、macOS 产物只能在 macOS 构建、Linux 产物只能在 Linux 构建；GitHub Actions 的 `matrix` 正好一台机器一个平台，无需自建任何硬件。
3. **本期不做代码签名/公证**：三平台统一发布**未签名**安装包（macOS 沿用现有 ad-hoc 签名），因此 **CI/CD 全程 $0**。代价是 Windows SmartScreen 会提示"未知发布者"、macOS 首次打开需右键 → 打开；后续如需署名再单独接入（Windows 可用 SignPath Foundation 免费，macOS 公证需 Apple Developer Program $99/年）。
4. **备选（当 GitHub Actions 不可用/需更多并发时）：** Cirrus CI（开源项目每月 50 compute credits）、AppVeyor（公开项目免费，但仅 1 并发）。
5. **不推荐：**
   - **Azure Pipelines**：官方已宣布 *Public projects 退役，2027 年起转为 private*，免费公开项目额度即将消失。
   - **Codemagic**：个人免费档只有 **500 分钟/月、且仅 macOS M2**，Linux/Windows 免费额度为 0。
   - **GitLab.com**：Free 档 400 compute minutes/月，macOS Runner 仍是 Beta 且消耗系数 6~12。
   - **Bitrise**：免费 Hobby 额度小、偏移动端，不适合桌面三平台。
   - **Xcode Cloud**：25 compute hours/月虽"包含"，但前提是已购买 **$99/年** 的 Apple Developer Program，且只能构建 Apple 平台。

---

## 1. 项目现状（CI/CD 视角）

| 维度 | 现状 |
|---|---|
| 应用类型 | Flutter 桌面应用，目标平台 **Windows / macOS / Linux**（仓库中虽保留 Android / iOS / Web 脚手架，但**不在本次 CI/CD 范围内**） |
| 公开仓库 | `github.com/SSBContestRunner/ssb_runner`（public，GPL-3.0，28 stars）；本地 remote 旧名 `ssb_contest_runner` 会 301 重定向到新名 |
| Flutter 版本 | 由 FVM 固定：`.fvmrc` → `3.47.5` |
| 打包/分发工具 | **fastforge**（原 flutter_distributor），配置 `distribute_options.yaml`，输出 `dist/` |
| 打包配置 | macOS `dmg`、Linux `deb` + `dev`、Windows 默认 `zip`（见 `macos/packaging/dmg/make_config.yaml`、`linux/packaging/*/make_config.yaml`） |
| 已发布产物 | `ssb_runner-0.1.0-alpha-macos.dmg`、`ssb_runner_windows_x64_*.zip`、`ssb_runner_linux_x64_*.tar.gz`、`ssb_runner-*.deb` |
| 版本号方案 | `pubspec.yaml` 注释：`MMNNPPBBB`，当前 `0.1.0+100000`；tag 形如 `v0.1.0-alpha` |
| 资源子模块 | `assets` → `git@github.com:SSBContestRunner/ssb_runner_assets.git`（**SSH 地址**，仓库本身是公开的，约 19 MB） |
| 生成代码 | `lib/db/app_database.g.dart` 已入库（drift + build_runner） |
| 现有 CI/CD | **完全没有**：仓库无 `.github/`，历史中也从未出现过 workflow |
| 现有发布方式 | 开发者在各自平台本地执行 fastforge 打包，再手工上传 GitHub Releases（从提交历史 `build: add fastforge`、`fix: fastforge flutter root not exist` 可推断） |

### 1.1 现状痛点

- 一次发布要在 **3 台机器**（Windows / macOS / Linux）上各手动跑一次打包，易漏、易错、版本号不一致。
- `distribute_options.yaml` 里的 `FLUTTER_ROOT: .fvm/versions/3.47.5` 是**写死的本地路径**，每台机器 / 每次升级 Flutter 都要改（历史上已经在 `3.32.8 → 3.35.6 → 3.47.5` 反复修过）。
- 没有 PR 门禁：`flutter analyze`、`flutter test` 全靠开发者自觉。
- 发版完全手工，没有可追溯的"从 tag 到产物"的构建链路。

---

## 2. 需求拆解

| 编号 | 需求 | 优先级 |
|---|---|---|
| R1 | PR / push 时自动跑 `flutter analyze` + `flutter test` | 高 |
| R2 | tag（`v*`）触发 Windows / macOS / Linux 三平台自动构建与打包 | 高 |
| R3 | 产物自动上传到 GitHub Releases | 高 |
| R4 | 构建可复现：Flutter 版本锁定为 `.fvmrc` 中的 `3.47.5` | 高 |
| R5 | 零现金成本（个人/小团队，无预算） | 高 |
| R6 | 预留后续签名/公证的接入点（**本期不实施**） | 低 |

---

## 3. 候选方案总览与对比

> "免费"均指**公开仓库 + 公共/标准 Runner**场景。额度来自官方文档（2026-09 抓取）。

| 方案 | 免费范围 | macOS | Windows | Linux | 并发/限制 | 对本项目的适合度 |
|---|---|---|---|---|---|---|
| **GitHub Actions**（推荐） | public 仓库标准 Runner **免费不限时长**；private 免费档 2,000 分钟/月、500 MB 制品、10 GB 缓存/仓库 | ✅ 免费（`macos-latest` = 3 核 M1 arm64；`macos-15-intel` = Intel） | ✅ 免费（4 核） | ✅ 免费（4 核） | Free 档 20 并发，其中 macOS 5；单 job 上限 6 小时；矩阵上限 256 | ★★★★★ 仓库已在 GitHub，零迁移成本 |
| **Cirrus CI** | 开源项目免费，封顶 **50 compute credits/月**；credits 折算：Linux 3/1000 CPU·分钟、Windows 4/1000、**Apple Silicon 15/1000** | ✅（约 3,300 分钟/月） | ✅（约 12,500 分钟/月） | ✅（约 16,600 分钟/月） | 无排队、无并发上限；支持 FreeBSD / 持久化 worker | ★★★★ 很好的备选/兜底，但需维护 `.cirrus.yml` |
| **AppVeyor** | 开源项目免费：**无限公开项目**，1 并发 job，5 个 self-hosted job；额外并发对 OSS 打 5 折 | ✅ | ✅（老牌强项） | ✅ | 仅 **1 并发**，三平台串行会明显变慢 | ★★★ 备选，可作为 Windows 构建回退 |
| **Codemagic** | 个人免费：**500 分钟/月，且仅 macOS M2**；Linux/Windows **无免费分钟** | ✅（仅免费档） | ❌（$0.045/min） | ❌（$0.045/min） | 免费档不能加协作者 | ★★ 只适合当作"免费 macOS 加速器"，无法承担全部三平台 |
| **Azure Pipelines** | private 免费档 1 job、1,800 分钟/月；**public projects 2027 年退役** | ✅（计费） | ✅ | ✅ | 免费档 1 并发、单次 60 分钟 | ★ 官方明确要退役，不建议新投入 |
| **GitLab.com** | Free 档 **400 compute minutes/月**；macOS M1 系数 6、M2 Pro 系数 12（Beta） | ⚠️ Beta，400 分钟仅够约 33~66 分钟 macOS | ⚠️ Beta | ✅ | 需要把代码迁到 GitLab | ★ 迁移成本高、额度小 |
| **Bitrise** | Hobby 免费，但额度小、按 credit 计，偏移动端 | ✅ | ❌ | ⚠️ | 免费档限制多 | ★ 不适合桌面 |
| **Xcode Cloud** | 25 compute hours/月，**须先加入 $99/年 Apple Developer Program** | ✅ 仅 Apple | ❌ | ❌ | 只能构建 Apple 平台 | ★★ 仅作为未来 Apple 签名/公证的补充 |
| **自托管（GitHub Actions self-hosted / Forgejo / Woodpecker / Jenkins）** | 软件免费，Runner **分钟数永久免费**；成本=自有硬件+运维 | ✅（需有 Mac） | ✅ | ✅ | 自己维护，安全需谨慎 | ★★★ 若有闲置 Mac/PC 可作兜底 |

---

## 4. 推荐方案：GitHub Actions

### 4.1 为什么是它

1. **零成本覆盖全部三平台**：public 仓库的标准 Runner（含 macOS）免费不限时长，这是所有候选里唯一"三个桌面平台全免费且无分钟焦虑"的方案。
2. **零迁移成本**：仓库已经在 GitHub，Release 也已经在 GitHub，天然打通 tag → 构建 → Release 的闭环。
3. **生态成熟**：Flutter 有官方推荐的 `subosito/flutter-action@v2`，且**支持直接读取 `.fvmrc`**，与项目现有 FVM 工作流无缝衔接。
4. **与 fastforge 官方支持的 CI 场景一致**：fastforge README 明确给出 GitHub Actions 集成示例。

### 4.2 Runner 规格与需要知道的硬限制

| 项目 | 说明 |
|---|---|
| 免费条件 | **public 仓库 + 标准 GitHub-hosted Runner**。Larger Runner（macOS 12 核等）即使在 public 仓库也收费。 |
| `ubuntu-latest` | 4 vCPU / 16 GB / x64 |
| `windows-latest` | 4 vCPU / 16 GB / x64 |
| `macos-latest` | 3 核 Apple M1 / 7 GB / arm64 |
| `macos-15-intel` / `macos-26-intel` | Intel macOS（需要 Intel 环境时用） |
| 单 job 上限 | **6 小时**（自托管为 5 天） |
| 矩阵上限 | 256 jobs/workflow run |
| Free 档并发 | 20 个总并发，其中 **macOS 5 个** |
| 若将来转 private | Free 档只有 2,000 分钟/月；超出后按 **Linux $0.006 / Windows $0.010 / macOS $0.062 每分钟**计费 → 2,000 分钟折算 macOS 实际只有约 200 分钟，**成本会立刻失控**。所以"保持 public"是这套零成本方案的前提。 |

### 4.3 流水线设计

```
                     ┌──────────────┐
 push/PR ───────────▶│  analyze     │  ubuntu-latest
 (main/dev)          │  analyze+test│  flutter pub get / analyze / test
                     └──────┬───────┘
                            │ needs
 tag v* ────────────▶┌──────▼───────────────────────────────┐
                     │  package (matrix)                     │
                     │  ├─ ubuntu-latest   → linux  deb,tar.gz
                     │  ├─ windows-latest  → windows zip
                     │  └─ macos-latest    → macos   dmg
                     └──────┬───────────────────────────────┘
                            │ upload-artifact
                     ┌──────▼───────────────┐
                     │  release             │  ubuntu-latest
                     │  softprops/action-    │  download-artifact → GitHub Release
                     │  gh-release           │
                     └──────────────────────┘
```

**触发策略建议**

| 事件 | 动作 |
|---|---|
| `pull_request` → main/dev | `analyze` + `test`（快，几分钟） |
| `push` → main/dev | `analyze` + `test`（可选加 Linux 构建做冒烟） |
| `push tag v*` | `analyze` → 三平台 `package` → `release`（先建 **draft release**，人工确认后再发布） |
| `workflow_dispatch` | 手动补跑打包 |

**建议加的两个保护**

- `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`：避免同一分支重复排队。
- `strategy.fail-fast: false`：任一平台失败不影响其他平台产出，便于定位问题。

### 4.4 与现有工具链的集成（关键改造点）

**① Flutter 版本：直接复用 `.fvmrc`**

```yaml
- uses: subosito/flutter-action@v2
  with:
    flutter-version-file: .fvmrc   # 官方支持读取 .fvmrc / .fvm/fvm_config.json / pubspec.yaml
    channel: stable
    cache: true                     # 缓存 Flutter SDK；pub-cache 默认随 cache 开启
```

这样 CI 与本地始终使用同一个 `3.47.5`，不需要在 workflow 里再硬编码版本号。

**② 解决 fastforge 的 `FLUTTER_ROOT` 写死问题（已落地）**

当前 `distribute_options.yaml`：

```yaml
output: dist/
variables:
  FLUTTER_ROOT: .fvm/versions/3.47.5   # ← 本地 FVM 路径，CI 里不存在
```

实际采用的方式（已落地）：**保持 `distribute_options.yaml` 不动，在 Runner 上把 `.fvm/versions/<version>` 重建为指向 flutter-action 所装 SDK 的软链接 / 目录 junction**，版本号从 `.fvmrc` 解析。这样本地与 CI 行为一致，也不需要改配置文件。

> ⚠️ 关键点：fastforge 的变量优先级是**配置文件覆盖进程环境变量**，所以"在 CI 里设置 `FLUTTER_ROOT` 环境变量"并不生效，必须让配置里写死的那个路径真实存在。

**③ 修复 assets 子模块的 SSH 地址（已落地）**

已把 `.gitmodules` 的 URL 改为 HTTPS（该仓库是公开的）：`https://github.com/SSBContestRunner/ssb_runner_assets.git`。

> 注意：`flutter test` 会读取 `assets/dxcc/*`，所以 **analyze job 也必须**开启 `submodules: recursive`。

**④ Linux 构建依赖**

`ubuntu-latest` 需补装 GTK/CMake 工具链：

```bash
sudo apt-get update
sudo apt-get install -y ninja-build libgtk-3-dev liblzma-dev libstdc++-12-dev
```

**⑤ 打包命令与 fastforge 版本（重要）**

```bash
dart pub global activate fastforge 0.6.12
fastforge package --platform=<linux|windows|macos> --targets=<appimage,zip|zip|dmg>
```

两个实测结论：

1. **fastforge 必须 ≥ 0.6.11**：0.6.6 等旧版会把版本号以 `--dart-define FLUTTER_BUILD_NAME=...` 传给 `flutter build`，Flutter 3.47 直接报错 `FLUTTER_BUILD_NAME is used by the framework and cannot be set using --dart-define`（fastforge #354 已修复，0.6.11 起改用受支持的 `--build-name/--build-number`，实际改动在 `flutter_app_builder 0.6.2`）。
2. **fastforge 已无 `tar.gz` target**：Linux 可用归档 target 为 `deb / rpm / appimage / zip`，当前实现取 `appimage,zip`；若下载页依赖 `.tar.gz`，需额外自行打包。
3. **macOS 的 `dmg` target 依赖 `appdmg`**：若 Runner 上没有 `appdmg`，fastforge 会回退到 `pnpm install -g appdmg`（pnpm 的全局 bin 未必在 PATH）。实测 `npm install -g appdmg` 更稳，workflow 已采用，并已本地验证 dmg 成功生成。

### 4.5 制品与发布

- 每个平台用 `actions/upload-artifact@v4` 上传 `dist/**`，设置 `if-no-files-found: error`。
- release job 用 `actions/download-artifact@v4`（`merge-multiple: true`）汇聚，再交给 `softprops/action-gh-release@v2` 上传到 Release。
- **只需要仓库自带的 `GITHUB_TOKEN`**：给 release job 设置 `permissions: { contents: write }` 即可，无需 PAT、无需任何付费密钥。
- 若希望完全走 fastforge 发布，也可用它的 `publish_to: github` target（需 `GITHUB_TOKEN` + `repo-owner` / `repo-name`）。
- 建议先发布为 **draft**，人工确认体积/文件名/版本后再点发布，避免自动发错版本。

### 4.6 缓存与加速

| 缓存对象 | 方式 | 收益 |
|---|---|---|
| Flutter SDK | `flutter-action` 的 `cache: true` | 避免每次下载 ~1 GB SDK |
| pub 依赖 | 同上（`pub-cache: true`，默认随 `cache` 开启） | 缩短 `pub get` |
| Linux 原生构建 | 可选 ccache | 收益有限，后置 |

由于 public 仓库分钟数免费，缓存的主要收益是**缩短反馈时间**，而不是省钱。

### 4.7 安全基线

- workflow 顶部统一 `permissions: contents: read`，只在 release job 提升为 `write`。
- 第三方 action **固定到 tag/SHA**（至少固定大版本；有精力就固定 SHA）。
- 不使用 `pull_request_target` 执行 PR 代码，避免 secrets 泄露。
- 本期不需要任何签名密钥；若未来接入签名，再把证书/私钥放进 **GitHub Environments + Secrets** 并加人工审批。

### 4.8 参考 workflow（调研草稿；最终实现见 `.github/workflows/ci.yml`）

> ⚠️ 以下为调研阶段草稿，**与最终实现有差异**，请以仓库中的 `.github/workflows/ci.yml` 为准。主要差异：fastforge 固定 0.6.12、Linux 固定 `ubuntu-22.04` runner 且 targets 为 `appimage,zip`、新增 FVM 软链接步骤与 appimagetool 安装、macOS 增加 appdmg 安装、analyze 使用 `--no-fatal-infos`。

```yaml
name: CI

on:
  push:
    branches: [main, dev]
    tags: ['v*']
  pull_request:
    branches: [main, dev]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  analyze:
    name: Analyze & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: subosito/flutter-action@v2
        with:
          flutter-version-file: .fvmrc
          channel: stable
          cache: true
      - run: flutter pub get
      # 生成代码已入库；如需校验是否过期可打开下面一行
      # - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter analyze
      - run: flutter test

  package:
    name: Package (${{ matrix.platform }})
    needs: analyze
    if: startsWith(github.ref, 'refs/tags/v') || github.event_name == 'workflow_dispatch'
    strategy:
      fail-fast: false
      matrix:
        include:
          - { os: ubuntu-latest,  platform: linux,   targets: 'deb,tar.gz' }
          - { os: windows-latest, platform: windows, targets: 'zip' }
          - { os: macos-latest,   platform: macos,   targets: 'dmg' }
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - uses: subosito/flutter-action@v2
        with:
          flutter-version-file: .fvmrc
          channel: stable
          cache: true

      - name: Install Linux dependencies
        if: matrix.platform == 'linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y ninja-build libgtk-3-dev liblzma-dev libstdc++-12-dev

      - name: Install fastforge
        shell: bash
        run: |
          dart pub global activate fastforge
          echo "$HOME/.pub-cache/bin" >> "$GITHUB_PATH"

      - name: Build & package
        # 若 distribute_options.yaml 使用 ${FLUTTER_ROOT}，这里会继承 flutter-action 导出的同名环境变量
        run: fastforge package --platform=${{ matrix.platform }} --targets=${{ matrix.targets }}

      - uses: actions/upload-artifact@v4
        with:
          name: ssb-runner-${{ matrix.platform }}
          path: dist/**
          if-no-files-found: error

  release:
    name: Draft GitHub Release
    needs: package
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: dist
          merge-multiple: true
      - uses: softprops/action-gh-release@v2
        with:
          files: dist/**
          draft: true
          generate_release_notes: true
```

---

## 5. 代码签名与公证（本期不实施，仅备查）

**本期计划不含签名**：三平台均发布未签名产物，CI 不需要任何证书或密钥。macOS 沿用现有 ad-hoc 签名（`CODE_SIGN_IDENTITY = "-"`），Windows 产物无签名。

需要接受的用户侧影响：

- **Windows**：首次运行出现 SmartScreen"未知发布者"提示，需点"更多信息 → 仍要运行"。
- **macOS**：首次打开需右键 → 打开，或在"系统设置 → 隐私与安全性"中放行。

建议在 README / 下载页写清上述放行步骤。

后续若要补签名，方案如下（本期不申请、不排期）：

### 5.1 Windows

| 选项 | 成本 | 说明 |
|---|---|---|
| **SignPath Foundation** | **免费**（面向开源项目） | 提供代码签名证书 + HSM 托管私钥，可直接集成进 CI；官方定位就是 "Free Code Signing for Open Source software" |
| Azure Trusted Signing | 付费（约 $9.99/月起） | 微软官方服务 |
| 商业 OV/EV 证书 | 数百美元/年 | 传统 CA，私钥常在 USB Token，不便 CI |

### 5.2 macOS

| 选项 | 成本 | 说明 |
|---|---|---|
| 保持现状：ad-hoc 签名 | 免费 | 用户首次打开需"右键 → 打开"或手动放行；本项目当前发布方式即如此 |
| Developer ID 签名 + 公证 | 需 **Apple Developer Program $99/年** | 可在 CI 中用证书 + `notarytool` 完成签名与公证 |
| Xcode Cloud | $99/年基础上 25 compute hours/月 | 只能构建 Apple 平台，对三平台方案无帮助；可作为未来 Apple 侧补充 |

---

## 6. 成本核算

| 项目 | 零成本方案 | 可选升级 | 年成本 |
|---|---|---|---|
| CI 计算（Linux/Windows/macOS） | GitHub Actions public 仓库标准 Runner | — | **$0** |
| 制品存储 / Release 托管 | GitHub Releases | — | **$0** |
| 代码签名 / 公证 | 本期不做，发布未签名产物 | 见第 5 节（后续可选） | **$0** |
| **合计** | — | — | **$0** |

签名/公证已明确排除在本期计划外；后续若要补，Windows 可零成本走 SignPath Foundation，macOS 需 $99/年。

---

## 7. 备选与兜底

1. **Cirrus CI**：如果哪天真需要 FreeBSD，或 GitHub Actions 的 macOS 并发（5 个）不够用，可挂一份 `.cirrus.yml`，开源项目 50 credits/月 ≈ 3,300 分钟 Apple Silicon。适合作为"第二构建源"。
2. **AppVeyor**：公开项目免费但**只有 1 并发**，可作为 Windows 专属回退；对 OSS 额外并发有 5 折。
3. **自托管 Runner**：若团队有闲置 Mac / Windows PC，注册为 GitHub Actions self-hosted runner，分钟数永久免费（GitHub 官方文档明确"self-hosted runners 免费"）。代价是安全与运维。macOS 自托管还能顺带解决"没有 Apple 机器就无法构建 macOS"的问题。
4. **Forgejo / Gitea Actions、Woodpecker CI、Jenkins**：免费开源、可自托管，但都需要自己的机器，且失去了 GitHub Releases 的天然集成，仅在"要脱离 GitHub"时才考虑。
5. **Build 加速类商业服务**（Blacksmith / Depot / Namespace / WarpBuild / BuildJet）：多为付费，部分对 OSS 有免费额度，对本项目收益不明显，暂不考虑。

---

## 8. 实施路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0 基础 CI** | `.github/workflows/ci.yml`：checkout（含子模块）+ flutter-action 读 `.fvmrc` + `flutter analyze --no-fatal-infos` + `flutter test` | ✅ 已落地，本地两关通过（14 tests passed） |
| **P1 自动打包** | tag 触发的三平台 matrix + fastforge；解决 `FLUTTER_ROOT`（FVM 软链接）与子模块 HTTPS | ✅ 已落地（macOS dmg 本地实测通过；Linux / Windows 待 CI 首跑） |
| **P2 自动发布** | release job 汇聚产物并创建 draft GitHub Release | ✅ 已落地 |
| **P3 扩展（可选）** | 接入 Dependabot 自动升级依赖；增加产物体积/完整性校验 | 待办 |

> 路线图**不含签名/公证**：P0–P2 完成后即为完整可用的零成本发版链路（未签名产物 + draft Release）。

### 8.1 落地过程中顺带修复的问题

1. **`test/dxcc_loader_test.dart` 长期失败**：用例读取的是 `assets/dxcc/cty.xml`，而资源仓库里只有 `cty.xml.gz`（应用运行时也是加载 `.gz` 再解压）。已把该用例改为按 `.gz` 解码后再解析，与 `DxccManager.loadDxcc()` 保持一致。
2. **`flutter analyze` 会因一条历史 info 失败**：`lib/contest_run/score_manager.dart:7` 的 `CQ_WPX` 触发 `constant_identifier_names`。本期用 `--no-fatal-infos` 放行，后续可选择重命名常量或收紧 lint 配置。
3. **fastforge 0.6.6 与 Flutter 3.47 不兼容**：见 4.4 ⑤，需升级到 ≥ 0.6.11。
4. **子模块 SSH 地址**：已改为 HTTPS，本地克隆执行 `git submodule sync assets` 同步。

---

## 9. 风险与注意事项

1. **"免费"绑定在 public 仓库上**：一旦仓库转 private，GitHub Free 只有 2,000 分钟/月，macOS 按 $0.062/min 计费，成本会迅速上升。若未来要闭源，应改用 Cirrus / AppVeyor / 自托管。
2. **macOS 标准 Runner 是 arm64（M1）**：本项目已迁移到 Swift Package Manager，需在 CI 上实测 Xcode + SPM 构建；若遇插件兼容问题，可临时切 `macos-15-intel`。
3. **fastforge 版本必须 ≥ 0.6.11**：旧版与 Flutter 3.47 不兼容（`FLUTTER_BUILD_NAME` 报错）。CI 已固定 0.6.12，本地开发执行 `dart pub global activate fastforge 0.6.12`。
4. **子模块已改为 HTTPS**：本地已有克隆若仍指向 SSH，执行一次 `git submodule sync assets` 即可同步。
5. **analyze job 也必须拉子模块**：`flutter test` 会读取 `assets/dxcc/*`，因此不能省略 `submodules: recursive`。
6. **版本号一致性**：tag（`v0.1.0-alpha`）与 `pubspec.yaml`（`0.1.0+100000`）目前是人工维护，容易不一致；建议在 CI 里校验 tag 与 pubspec 版本匹配，或统一以 tag 为准注入 `--build-name/--build-number`。
7. **Draft release 优先**：自动发布直接公开容易出错，先 draft 再人工确认。
8. **未签名产物的用户体验**：Windows SmartScreen 与 macOS Gatekeeper 都会拦截未签名包，必须在 README 提供放行步骤——这是本期"不签名"决定的直接代价，属于已知且有意的取舍。
9. **定价政策变动**：本文所有额度均为 2026-09 抓取的官方数据，落地前请复核。

---

## 10. 参考链接

**GitHub Actions**

- 计费与免费额度：<https://docs.github.com/en/billing/managing-billing-for-your-products/about-billing-for-github-actions>
- Runner 规格与"public 仓库免费不限量"：<https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
- 用量限制（6 小时/256 矩阵/并发）：<https://docs.github.com/en/actions/reference/limits>
- 各平台每分钟价格：<https://docs.github.com/en/billing/reference/actions-minute-multipliers>
- Flutter 安装 action（支持 `.fvmrc`）：<https://github.com/subosito/flutter-action>

**其他 CI 厂商**

- Cirrus CI 开源免费与 50 credits 上限：<https://cirrus-ci.org/features/> / <https://cirrus-ci.org/pricing/>
- AppVeyor 定价（公开项目免费）：<https://www.appveyor.com/pricing/>
- Codemagic 定价（500 分钟 macOS M2）：<https://docs.codemagic.io/billing/pricing/>
- Azure Pipelines 并发与免费额度（含 public 项目退役说明）：<https://learn.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs>
- GitLab.com compute minutes（Free 400 分钟）：<https://docs.gitlab.com/ci/pipelines/compute_minutes/>
- Bitrise 定价：<https://bitrise.io/pricing>
- Xcode Cloud（25 compute hours + Apple Developer Program）：<https://developer.apple.com/xcode-cloud/>

**签名（本期不做，后续可选参考）**

- SignPath Foundation（开源免费代码签名）：<https://signpath.org/>
- Apple Developer Program 对比：<https://developer.apple.com/support/compare-memberships/>

**打包工具**

- fastforge 仓库与 CI 示例：<https://github.com/fastforgedev/fastforge>
- fastforge GitHub Releases publisher：<https://fastforge.dev/publishers/github>
