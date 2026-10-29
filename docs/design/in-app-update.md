# SSB Runner 应用内更新技术方案

> 调研与撰写日期：2026-10-29
> 范围：Windows / macOS / Linux 桌面端
> 关联文件：`.github/workflows/ci.yml`、`windows/packaging/exe/make_config.yaml`、`macos/Runner/Release.entitlements`、`docs/research/cicd-cross-platform.md`
> 状态：方案待评审，本文不包含实现代码

---

## 0. 结论摘要（TL;DR）

1. **更新源按需求固定为 GitHub Releases**，但更新元数据不直接依赖 GitHub API：
   - 用 `releases.atom` 发现最新版本（不消耗 REST API 配额、体积小，实测约 59 KB）；
   - 每个 Release 额外上传 **签名后的 `update-manifest.json`**，客户端用内置 Ed25519 公钥验签后，才信任版本号、资产名、大小和 SHA-256。
2. **稳定版 / 预发布版**通过 SemVer 预发布后缀（`-alpha.N` / `-beta.N` / `-rc.N`）区分；CI 同时把 Release 的 `prerelease` 标志按 tag 自动设置，避免两套判定不一致。
3. **中国网络的关键瓶颈不是 `github.com` 网页，而是 Release 资产的下载主机**：`github.com/.../releases/download/...` 会 302 到 `release-assets.githubusercontent.com`（Azure Blob 后端），该域名在境内可达性明显弱于主站。方案因此内置**多下载源探测与失败切换**（GitHub 直连 + 可配置镜像前缀），并强制校验签名与哈希，镜像只当传输通道，不建立信任。
4. **安装一律由用户触发，不做自动安装**：下载并校验完成后只显示 badge，不打断用户；用户点击后弹出确认框，确认后才执行安装。
   - Windows（Inno Setup 安装版）：确认后静默升级并自动重启；
   - Linux AppImage / 便携 zip：确认后替换文件并自动重启；
   - Linux deb：确认后调起系统授权/安装器；
   - macOS：**不做应用内安装**，点击后仅用 Finder 打开 DMG 所在位置（`open -R`），由用户自行安装。
5. **默认策略**：启动 30 秒后自动检查（24 小时内不重复），发现新版本后自动下载；下载完成只显示 badge，安装永远需要用户点击并确认；比赛进行中安装会有中断警告。

---

## 1. 需求拆解

| 编号 | 需求 | 说明 |
|---|---|---|
| R1 | 自动检查更新 | 启动后与长时间运行时周期性检查 |
| R2 | 手动检查更新 | 设置页按钮，随时可触发 |
| R3 | 下载完成后 badge 提示，用户确认后安装 | 不自动安装；用户点击后弹窗确认；macOS 仅打开 DMG 所在位置 |
| R4 | 更新渠道 | 稳定版 / 预发布版（pre-release） |
| R5 | 下载来源 | GitHub Releases 资产 |
| R6 | 中国大陆可用 | 不依赖单一 GitHub 域名；可切换镜像；失败可回退到下载页 |

---

## 2. 项目现状与约束

| 维度 | 现状 | 对更新的影响 |
|---|---|---|
| 应用框架 | Flutter 桌面端，FVM 固定 Flutter 3.47.5 | 用纯 Dart 实现更新器，避免引入重原生依赖 |
| 版本号 | `pubspec.yaml`：`version: 0.2.0+200006`，构建号方案 `MM_NN_PP_BBB` | 构建号单调递增，可作为版本比较主键 |
| Release 资产 | `-linux.AppImage` / `.deb` / `.zip`、`-macos.dmg`、`-windows.zip` | 下次发版需确认 `-windows-setup.exe` 已上传（v0.2.0 的 Release 中缺失） |
| Windows 安装器 | Inno Setup，per-user 安装到 `%LOCALAPPDATA%\Programs\SSB Runner`，无需 UAC；支持 `script_template` 自定义 | 用户确认后可 `/VERYSILENT` 静默安装 |
| macOS | Release 签名是 ad-hoc，**App Sandbox = true** | 沙箱禁止写 `/Applications`，因此应用内不做安装，仅定位 DMG |
| 签名/公证 | 三平台均未签名，未有 Apple Developer Program | Windows SmartScreen、macOS Gatekeeper 仍会警告首次安装 |
| CI | tag `v*` 触发三平台打包、冒烟测试、创建 draft Release | 需增加清单生成、签名、资产完整性校验 |
| 官网 | `https://ssbrunner.com`，响应头 `server: cloudflare` | 可作为清单的中国可达备用源（需站点侧配合） |
| 现有网络层 | 无 `http` 直接依赖，可用 `dart:io HttpClient`；已有 `xml` 依赖 | 不新增 HTTP 库，新增 Ed25519 校验库即可 |

---

## 3. GitHub Release 在中国境内的连通性调研

### 3.1 方法与重要前提

- 调研时间：**2026-10-29**。
- 本机实测（`curl`、`dig`、DNS over HTTPS）：**不能代表中国大陆网络**。本机 DNS 返回 `198.18.0.0/15` 的 fake-ip，出口 IP 为 `212.87.194.95`（Tokyo, JP），即所有请求经代理出海。因此本机数值仅用于验证“端点拓扑、重定向链、镜像 URL 是否可用”，不能作为境内速度结论。
- 境内可达性补充使用站长工具（chinaz）多节点 Ping；该结果是 ICMP，不能证明大文件吞吐，只能说明主站域名可解析、可连通。

### 3.2 下载链路拓扑（实测重定向）

对真实资产发起 HEAD：

```
https://github.com/SSBContestRunner/ssb_runner/releases/download/v0.2.0/ssb_runner-0.2.0+200006-windows.zip
  -> HTTP 302
  -> https://release-assets.githubusercontent.com/github-production-release-asset/...（带短期签名参数）
  -> HTTP 200, content-length: 30564560
```

结论：**网页/API 在 `github.com`，二进制资产最终在 `release-assets.githubusercontent.com`（Azure Blob）**。旧资料中常见的 `objects.githubusercontent.com` 是早期资产域名。用户能否更新，主要取决于资产主机而不是 `github.com`。

### 3.3 实测结果

| 端点 | 本机结果（经东京代理） | 说明 |
|---|---|---|
| `https://github.com` | 200，TLS 0.09 s，总 0.26 s | 主站可用 |
| `https://api.github.com` | **403** `API rate limit exceeded`，出口 IP `212.87.194.95` | 未认证 API 按 IP 限 60 次/小时；共享出口会直接耗尽 |
| `https://github.com/.../releases.atom` | 200，59,262 B，0.73 s | 不消耗 API 配额，可发现版本 |
| Release 资产直链 | 302 → `release-assets...` → 200 | 资产主机与主站分离 |
| `https://gh-proxy.com/<原始资产 URL>` | 206，Range 生效，约 1.96 MB/s | 镜像可用，支持断点续传 |
| `https://ghfast.top/<原始资产 URL>` | 206，约 1.13 MB/s | 镜像可用 |
| `https://gh.llkk.cc/<原始资产 URL>` | 206，约 1.14 MB/s | 镜像可用 |
| `https://hub.gitmirror.com/<原始资产 URL>` | 连接失败 | 不可用，不应放入默认列表 |

境内多节点 Ping（chinaz，2026-10-29）：

| 域名 | 境内节点结果 |
|---|---|
| `github.com` | 40+ 个电信/联通/移动节点有响应，71–148 ms，绝大多数解析到 `20.205.243.166` |
| `api.github.com` | 该次查询未取得节点数据（工具侧无返回），**不能据此判定被墙** |
| `release-assets.githubusercontent.com` | 同上，无节点数据；结合社区反馈，按“高风险、不可依赖”处理 |

### 3.4 社区与官方证据

- 阿里云开发者社区（2026-09-30）：GitHub 未在中国大陆部署服务器与 CDN，全部走跨境出口，表现为“网页时通时断、图片/Release 下载失败”。
- JetStream 博客：网页 HTML 与 Release 附件走不同域名，附件 CDN 域名在境内的可达性通常比主站更差。
- 2026 年 10 月的镜像实测文章：`ghfast.top`、`gh-proxy.com`、`gh.llkk.cc` 三种方式均可用，偶发超时重试即可。
- GitHub 官方文档：未认证 REST API 为 **60 请求/小时/IP**，超额返回 403/429。

### 3.5 调研结论与设计影响

1. **不要用 `api.github.com` 作为唯一检查入口**：共享出口 IP 很容易 403。首选 `releases.atom`，API 仅作降级。
2. **不要把 GitHub 资产直链当成必然可用**：必须提供镜像候选、自动探测、失败切换和断点续传。
3. **镜像不可信**：第三方镜像可能限速、改写内容或下线。安全性必须由**签名清单 + SHA-256**保证，而不是由下载源保证。
4. **完全依赖 GitHub 仍有单点**：若站点可部署，建议把同一份签名清单同步到 `ssbrunner.com/updates/...`（Cloudflare），作为检查入口的备用源；资产仍可来自 GitHub 或镜像。
5. **系统代理支持是必需项**：国内大量用户通过 Clash/Surge 等系统代理上网，而 Dart `HttpClient` 默认不读取系统代理。更新器需显式支持环境变量、Windows 注册表代理、macOS `scutil --proxy`，否则“浏览器能开、应用更新失败”。

---

## 4. 总体设计

### 4.1 信任链

```
内置 Ed25519 公钥（随 App 编译）
        │ 验签
        ▼
update-manifest.json  ── 版本号/构建号/渠道/资产名/大小/SHA-256
        │ 按清单下载
        ▼
资产字节（GitHub 直链 或 任意镜像）
        │ 校验大小 + SHA-256
        ▼
交给系统安装器（Inno / AppImage 替换 / deb；macOS 仅定位 DMG）
```

- 清单与签名都作为 Release 资产上传：`update-manifest.json`、`update-manifest.json.sig`。
- 镜像只改传输路径，签名和哈希不变；任何被篡改的资产都会被拒绝。
- 没有签名清单的 Release 不提供应用内更新，只提供“打开下载页”入口。

### 4.2 清单格式（草案）

```json
{
  "schemaVersion": 1,
  "keyId": "ssb-update-2026",
  "tag": "v0.2.1",
  "version": "0.2.1",
  "buildNumber": 200007,
  "prerelease": false,
  "publishedAt": "2026-11-01T00:00:00Z",
  "notesUrl": "https://github.com/SSBContestRunner/ssb_runner/releases/tag/v0.2.1",
  "assets": {
    "windows": [
      {
        "kind": "inno-installer",
        "name": "ssb_runner-0.2.1+200007-windows-setup.exe",
        "size": 12345678,
        "sha256": "..."
      },
      {
        "kind": "portable-zip",
        "name": "ssb_runner-0.2.1+200007-windows.zip",
        "size": 30564560,
        "sha256": "..."
      }
    ],
    "macos": [
      {
        "kind": "dmg",
        "name": "ssb_runner-0.2.1+200007-macos.dmg",
        "size": 98765432,
        "sha256": "..."
      }
    ],
    "linux": [
      {
        "kind": "appimage",
        "name": "ssb_runner-0.2.1+200007-linux.AppImage",
        "size": 87654321,
        "sha256": "..."
      },
      {
        "kind": "deb",
        "name": "ssb_runner-0.2.1+200007-linux.deb",
        "size": 65432100,
        "sha256": "..."
      },
      {
        "kind": "portable-zip",
        "name": "ssb_runner-0.2.1+200007-linux.zip",
        "size": 30564560,
        "sha256": "..."
      }
    ]
  }
}
```

- 签名：对清单**原始字节**做 Ed25519 签名，`update-manifest.json.sig` 存储 base64 签名。
- 清单内的 `name` 必须匹配白名单正则，且扩展名必须与 `kind` 一致，防止路径穿越或诱导执行任意文件。
- 清单中的 `tag`、`version`、`buildNumber` 必须与当前 Release 的 tag 和 `pubspec.yaml` 一致，CI 校验后才会生成。

### 4.3 检查流程

```
自动/手动触发
  │
  ├─ 1. 拉取 releases.atom（主站直连 + 镜像候选，逐个超时 5 s）
  │     解析最近 N 条 entry，得到 tag 列表
  │
  ├─ 2. 按渠道筛选并选出最高版本
  │     stable     -> 只取无预发布后缀的 tag
  │     prerelease -> 取所有 tag 中的最高版本（含稳定版）
  │
  ├─ 3. 拉取该 tag 的 update-manifest.json（直连 + 镜像）
  │     验签、校验 schema/tag/version/buildNumber/平台
  │
  ├─ 4. 与 PackageInfo 的 version/buildNumber 比较
  │     仅当候选构建号更大才提示；禁止降级
  │
  └─ 5. 应用“跳过此版本”与“24 小时内已检查”策略
```

降级路径：

1. `releases.atom` 失败 → 用 `api.github.com/repos/.../releases?per_page=20`（带 `User-Agent`、`ETag`，403 时记录并放弃）；
2. API 也失败 → 稳定版尝试 `https://github.com/.../releases/latest/download/update-manifest.json`（单次请求即可）；
3. 全部失败 → 状态标记“检查失败”，UI 提供“打开下载页”，不阻塞应用。

### 4.4 更新渠道语义

| 渠道 | 候选版本 | 默认自动下载 | 下载完成后 |
|---|---|---|---|
| 稳定版（默认） | 仅无预发布后缀的 tag | 是 | 显示 badge，不自动安装 |
| 预发布版 | 稳定版 + 预发布版中构建号最高者 | 是 | 显示 badge，不自动安装 |

- 从预发布版切回稳定版时，若稳定版更旧，不执行降级，UI 显示“当前预发布版比稳定版新”。
- CI 需保证 tag 与 Release 的 `prerelease` 标志一致：tag 含 `-` 时设置 `prerelease: true`。
- 建议统一 tag 格式为 `vX.Y.Z` 或 `vX.Y.Z-alpha.N`，CI 校验；当前 `v0.2.0-alpha05` 这类格式也按 SemVer 预发布处理。

### 4.5 版本比较

- 主键：`buildNumber`（`MM_NN_PP_BBB` 单调递增），候选构建号 > 当前构建号才允许更新。
- 次键：SemVer 比较，用于构建号缺失或相等时的展示与排序。
- 当前版本从 `package_info_plus` 读取，清单构建号必须与之同源（CI 从 `pubspec.yaml` 生成）。

### 4.6 下载策略

1. 生成候选 URL 列表：
   - GitHub 直链：`https://github.com/SSBContestRunner/ssb_runner/releases/download/<tag>/<asset>`
   - 镜像前缀：`https://gh-proxy.com/<直链>`、`https://ghfast.top/<直链>`、`https://gh.llkk.cc/<直链>`
   - 可选自定义镜像（设置项）
2. 逐个探测：连接超时 10 s、首字节超时 15 s；响应必须为 200/206。
3. 选中后下载到 `.../update/<tag>/<asset>.part`，支持 HTTP Range 断点续传；镜像不支持 Range 时从头重下。
4. 下载中监测速度：连续 10 s 低于 50 KB/s 视为劣化，保留 `.part` 并切换下一候选。
5. 完成后校验 `size` 与 `sha256`；失败则删除文件、切换下一源、重试（最多 3 轮）。
6. 全程不上报任何隐私数据；日志仅记录资产名、源编号、耗时、字节数，不记录带签名的完整跳转 URL。

### 4.7 下载与安装时序

```
检查到新版本
  → 下载（后台，可取消，显示进度）
  → 校验通过，状态 ready（已下载）
  → 在“更新”设置项显示 badge，不执行安装、不打断用户
  → 用户点击 badge / “安装更新”
  → 弹窗展示版本、体积、影响说明；用户确认
  → 刷新数据库/日志 → 写 pending-install 标记
  → 启动 detached 安装 helper → 应用退出
  → 安装器/helper 完成替换并拉起新版本
  → 下次启动读取 pending-install：
        版本已变化 → 清理安装包，toast “更新成功”
        版本未变化 → 提示失败并给出安装日志路径
```

- **任何平台都不会自动安装**；只有用户点击并确认后才进入安装流程。
- macOS 不进入安装流程：用户点击后仅用 `open -R <dmg>` 打开 DMG 所在位置，由用户手动安装。
- 若确认安装时比赛正在进行，弹窗明确提示“安装会中断当前比赛”，默认按钮为“取消”；用户必须二次确认才能继续。
- 取消确认或关闭弹窗后保持 `ready` 状态，badge 继续显示，可稍后再次点击。
- 退出前必须完成 `SoLoud.deinit()`、`flushLogs()`，与现有 `AppLifecycleListener.onExitRequested` 保持一致。

### 4.8 状态机

```
idle ──check──▶ checking ──available──▶ available
  ▲                 │                        │
  │                 └─none──────────────────▶ upToDate
  │                                          │
  │                              download    ▼
  │                                       downloading ──cancel──▶ available
  │                                          │
  │                                          ▼
  │                                 ready (badge) ──user confirm──▶ installing ──exit
  │                                          │  ▲
  │                                          └──┘ 取消确认/关闭弹窗
  └──────────────── error ◀──────────────────┘
```

---

## 5. 平台安装实现

### 5.1 能力矩阵

| 平台 / 安装形态 | 检测方式 | 更新资产 | 用户确认后行为 | 备注 |
|---|---|---|---|---|
| Windows Inno 安装版 | 注册表卸载项 / 安装目录 | `-windows-setup.exe` | 静默安装并自动重启 | 使用 `/VERYSILENT` |
| Windows 便携 zip | 非 Inno 安装 | `-windows.zip` | helper 替换并自动重启 | 目录只读时提示手动 |
| Linux AppImage | `APPIMAGE` 环境变量 | `.AppImage` | 替换文件并自动重启 | 需可写 |
| Linux 便携 zip | 非 dpkg/AppImage | `.zip` | helper 替换并自动重启 | |
| Linux deb | `dpkg -S` 判定 | `.deb` | 调起系统授权/安装器 | `pkexec` / 软件中心，不做无提示提权 |
| macOS | 固定 | `.dmg` | **不安装，Finder 定位 DMG** | `open -R <dmg>`，用户手动安装 |

### 5.2 Windows（Inno Setup）

**安装器改造**：新增 `windows/packaging/exe/inno_setup.iss`，在 `make_config.yaml` 加 `script_template: inno_setup.iss`。关键改动：

```ini
[Setup]
; 静默升级时由 Restart Manager 处理占用文件的进程；重启交给下面的 [Run] 控制
CloseApplications=yes
RestartApplications=no
DisableStartupPrompt=yes

[Run]
; 原有交互式安装的启动项保留
Filename: "{app}\ssb_runner.exe"; Description: "{cm:LaunchProgram,SSB Runner}"; Flags: nowait postinstall skipifsilent
; 静默更新专用：安装完成后自动拉起新版本
Filename: "{app}\ssb_runner.exe"; Flags: nowait; Check: WizardSilent
```

**更新流程（在用户确认后执行）**：

1. 用户确认后，应用先把 `pending-install.json` 写入数据目录，刷新日志与数据库。
2. 用 `Process.start(..., mode: ProcessStartMode.detached)` 启动一个临时 `.cmd` helper；helper 等待当前 PID 退出后执行：
   ```
   setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG="%TEMP%\ssb-update.log"
   ```
3. 应用立即正常退出；安装器完成后由 `[Run]` 的 `WizardSilent` 项拉起 `ssb_runner.exe`。
4. 新版本启动后读取 `pending-install.json` 校验结果，成功则删除安装包与标记。

- 安装器为 per-user、`PrivilegesRequired=lowest`，静默升级不会弹 UAC。
- 便携 zip：同一 helper 先 `robocopy` 到临时目录再整体替换，避免覆盖正在运行的 exe。
- v0.2.0 的 Release 资产中没有 `-windows-setup.exe`，因此清单生成时**必须校验该资产存在**；缺失则本次发布失败，避免用户确认后无法完成更新。

### 5.3 Linux

- **AppImage**：通过 `Platform.environment['APPIMAGE']` 取得当前文件路径。以下 helper 在用户确认后启动：
  ```sh
  while kill -0 "$PID" 2>/dev/null; do sleep 1; done
  mv -f "$NEW" "$TARGET"
  chmod +x "$TARGET"
  nohup "$TARGET" >/dev/null 2>&1 &
  ```
  若目标不可写，提示用户手动替换或改用 deb。
- **便携 zip**：同 Windows 便携思路，helper 等待退出后替换目录并拉起。
- **deb**：检测 `/usr/bin/ssb-runner` 或 `dpkg -S` 归属；用户确认后默认“打开系统安装器”（`xdg-open`），高级设置可启用 `pkexec dpkg -i <deb>`。不做无提示提权，不静默 `sudo`。

### 5.4 macOS

**产品决定：macOS 不做应用内安装。**

技术约束：`macos/Runner/Release.entitlements` 中 `com.apple.security.app-sandbox = true`，沙箱应用不能写 `/Applications`；签名又是 ad-hoc，无法使用需要 Developer ID 的 Sparkle/XPC 方案。即使关闭沙箱，也需要迁移旧沙箱数据，成本与风险都不适合本次更新功能。

**实现方式**：

1. 下载 `.dmg`，校验 size 与 SHA-256；
2. 校验通过后显示 badge；
3. 用户点击“打开 DMG 所在位置”或 badge 后，执行 `open -R <dmg 路径>`，由 Finder 选中该文件；
4. 用户自行双击 DMG、拖拽安装，应用不做挂载、复制、提权，也不退出。

- macOS 的 badge 在用户重新安装并启动新版本前保持显示。
- 不新增 `-macos.zip` 资产，不修改沙箱配置。

---

## 6. 客户端实现

### 6.1 模块划分

```
lib/update/
  update_channel.dart        // stable / prerelease
  update_version.dart        // SemVer + buildNumber 比较
  update_manifest.dart       // 清单模型、JSON 解析、Ed25519 验签
  update_source.dart         // releases.atom 解析、候选版本选择、清单拉取
  update_downloader.dart     // 多源探测、Range 续传、SHA-256 校验
  update_installer.dart      // 抽象接口 + 平台分派
  install/windows_installer.dart
  install/linux_installer.dart
  install/macos_reveal.dart      // 仅用 Finder 定位 DMG，不安装
  update_store.dart          // lastCheckAt / skippedTag / pending-install 持久化
  update_service.dart        // 编排、定时、状态流
  update_state.dart          // sealed 状态
  trusted_keys.dart          // 内置公钥（keyId -> base64）
```

- 依赖：`xml`（已有）解析 Atom；`crypto`（已有传递依赖，提为直接依赖）做 SHA-256；新增 `cryptography` 做 Ed25519 验签；HTTP 用 `dart:io HttpClient`，不引入新网络库。
- 状态通过 `Stream<UpdateState>` 或 Cubit 暴露，UI 只订阅，不直接发网络/进程调用。

### 6.2 初始化位置

- `AppSettings` 在 `_MainAppCubit.load()` 中创建；`HomePage` 再创建 `ContestManager`。
- 在 `HomePage` 的 `MultiRepositoryProvider` 中，`ContestManager` 之后新增 `UpdateService`，注入 `AppSettings`、`PackageInfo`、`ContestManager.isContestRunning` 与平台安装/定位回调。
- `UpdateService.start()` 在首帧后触发 30 秒延迟检查；`dispose()` 取消定时器与下载。

### 6.3 设置项（`AppSettings`）

| 键 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `setting_update_channel` | string | `stable` | `stable` / `prerelease` |
| `setting_update_auto_check` | bool | `true` | 自动检查 |
| `setting_update_last_check_at` | int | 0 | 毫秒时间戳 |
| `setting_update_skipped_tag` | string? | null | 跳过此版本 |
| `setting_update_source_mode` | string | `auto` | `auto` / `github` / `mirror` |
| `setting_update_custom_mirror` | string? | null | 自定义前缀（高级） |

运行态（`update/state.json`，放在应用支持目录）：

```json
{
  "lastCheckAt": 0,
  "lastError": null,
  "downloaded": {
    "tag": "v0.2.1",
    "version": "0.2.1",
    "buildNumber": 200007,
    "asset": "ssb_runner-0.2.1+200007-windows-setup.exe",
    "path": "...",
    "size": 12345678,
    "sha256": "...",
    "downloadedAt": 0
  },
  "pendingInstall": {
    "tag": "v0.2.1",
    "asset": "ssb_runner-0.2.1+200007-windows-setup.exe",
    "installerPath": "...",
    "startedAt": 0
  }
}
```

- `downloaded` 用于在应用重启后恢复 badge；发现更高版本时清理旧文件并替换该字段。
- macOS 的 `downloaded` 记录 `.dmg` 路径，badge 一直保留到用户重新安装。

### 6.4 检查调度

- 启动后 30 秒检查一次（若 `now - lastCheckAt < 24h` 则跳过）。
- 应用持续运行时每 24 小时检查一次。
- 失败后 1 小时重试，最多 3 次/天；手动检查不受限制。
- 网络失败不弹窗，只写日志；下载完成并校验通过后才显示 badge。

### 6.5 UI 与本地化

- 设置面板（固定侧边栏）新增 `SettingItem`：**更新（Updates）**，放在“诊断”之后。
- 内容：
  - 当前版本 `0.2.0 (200006)`；
  - 渠道下拉：稳定版 / 预发布版；
  - 开关：自动检查更新；
  - 按钮：立即检查；
  - 状态行：上次检查时间 / 已是最新 / 发现新版本并下载中 x% / 已下载待安装；
  - 失败时显示“打开下载页”。
- **下载完成后的 badge**：
  - 在“更新”`SettingItem` 标题右侧显示 badge（小圆点 + “新版本”标记），不弹打断式对话框、不自动安装；
  - badge 状态来自 `state.json` 的 `downloaded`，应用重启后仍然显示；
  - 用户点击 badge、状态行或“安装更新”按钮进入确认流程。
- 确认弹窗（仅 Windows / Linux）：“安装 v0.2.1 将重启应用”；若比赛进行中，追加“安装会中断当前比赛”，默认按钮为“取消”；确认按钮为“安装并重启”。
- macOS：点击 badge 或“打开 DMG 所在位置”后直接执行 `open -R`，不弹确认框、不安装。
- 下载中：设置项内进度 + 可取消；完成后仅更新 badge，不自动安装。
- l10n：`app_en.arb`、`app_zh_Hans.arb`、`app_zh_Hant.arb`、`app_ja.arb`（以及 `app_zh.arb`）新增约 18 个键，例如 `settingsUpdates`、`updateCheckNow`、`updateUpToDate`、`updateAvailable`、`updateDownloading`、`updateReady`、`updateBadgeNewVersion`、`updateInstallNow`、`updateInstallConfirmTitle`、`updateInstallConfirmBody`、`updateContestWarning`、`updateOpenDmgLocation`、`updateLater`、`updateSkipVersion`、`updateFailed`、`updateChannelStable`、`updateChannelPrerelease`、`updateOpenDownloadPage`。

### 6.6 网络与代理

- 更新器需要支持：
  - 环境变量 `HTTPS_PROXY` / `HTTP_PROXY`（`HttpClient.findProxyFromEnvironment`）；
  - Windows 系统代理（注册表 `ProxyEnable` / `ProxyServer`，`win32_registry` 目前是传递依赖，使用时需提为直接依赖）；
  - macOS 系统代理（`scutil --proxy` 解析）；
  - 直连回退。
- 所有请求带 `User-Agent: SSB-Runner/<version>`；GitHub 要求 UA。
- 设置 `connectionTimeout`、空闲读取超时，避免代理挂起导致界面卡死。

---

## 7. CI/CD 改造

### 7.1 新增 Release 资产

每次 tag 发布额外上传：

- `update-manifest.json`
- `update-manifest.json.sig`
- （可选）`SHA256SUMS`

### 7.2 新增签名工具

`tool/update/generate_manifest.dart`：

1. 读取 `release/` 下实际资产，计算 size 与 SHA-256；
2. 读取 `GITHUB_REF_NAME`、`pubspec.yaml` 的 version/buildNumber；
3. 校验必需资产（Windows setup exe、macOS dmg、Linux AppImage/deb/zip）齐全；
4. 生成 `update-manifest.json`；
5. 用 `UPDATE_SIGNING_KEY`（GitHub Secret，base64 Ed25519 seed）签名，输出 `.sig`；
6. 用内置公钥自验一次，失败即中止发布。

一次性密钥生成可通过 `tool/update/keygen.dart` 在本地执行，公钥写入 `lib/update/trusted_keys.dart`，私钥离线备份并只放 GitHub Secrets。建议同时保留两个 keyId，便于轮换。

### 7.3 工作流改动

```yaml
release:
  steps:
    - name: Generate update manifest
      env:
        UPDATE_SIGNING_KEY: ${{ secrets.UPDATE_SIGNING_KEY }}
      run: dart run tool/update/generate_manifest.dart

    - uses: softprops/action-gh-release@v3
      with:
        files: release/*
        draft: true
        prerelease: ${{ contains(github.ref_name, '-') }}
        generate_release_notes: true
```

- 在 `analyze` 或 release 前增加 tag 与 `pubspec.yaml` 版本一致性校验，避免清单版本与 tag 不一致。
- 发布仍需人工从 draft 点发布；**draft 不会被 `releases.atom`/`latest` 看到**，可避免半成品被客户端发现。

### 7.4 资产命名约束

- 保持 fastforge 现有命名：`ssb_runner-<version>-<platform>.<ext>`。
- 版本中的 `+` 在 URL 中必须编码为 `%2B`（实测直接使用 `%2B` 可正常 302）。
- 清单只按文件名引用，不拼接用户输入；下载 URL 用 `Uri.encodeComponent` 处理资产名。

---

## 8. 安全设计

| 风险 | 对策 |
|---|---|
| 第三方镜像篡改资产 | 清单 Ed25519 验签 + 资产 SHA-256；失败立即终止 |
| 清单被镜像替换 | 公钥内置 App，签名不通过即拒绝；公钥不通过网络获取 |
| 降级攻击 | 只接受 buildNumber 更大的版本；拒绝同版本重装 |
| 路径穿越 / 任意执行 | 资产名白名单 + 扩展名与 kind 匹配；只交给预期安装器 |
| 假更新/钓鱼 Release | 仓库固定为 `SSBContestRunner/ssb_runner`，只认该仓库的 tag 与签名 |
| 私钥泄露 | 私钥仅存 GitHub Secrets；支持双 keyId 轮换；泄露后吊销旧 key 并发布新版 |
| 日志泄露 | 不记录带签名的资产跳转 URL、代理认证信息、私钥 |
| 安装器被中断 | pending-install 标记 + 启动校验 + 安装日志路径提示 |
| 比赛中执行安装 | 确认弹窗提示会中断比赛，默认取消，需二次确认 |

补充：未签名产物的首次安装仍会遇到 SmartScreen / Gatekeeper；应用自行下载的文件通常不带 Mark-of-the-Web，静默升级链本身不会额外触发 SmartScreen，但用户手动下载仍会。

---

## 9. 测试计划

### 9.1 单元测试

- SemVer + buildNumber 比较：稳定版、预发布、跨版本、降级拒绝。
- 渠道筛选：stable 排除预发布；prerelease 包含稳定版与预发布版。
- 清单解析与验签：正确签名通过；篡改一个字节失败；错误 keyId 失败；schemaVersion 不支持失败。
- SHA-256 / size 校验：截断文件、错误 hash、空文件。
- 镜像选择：首个超时切换第二个；206 续传；不支持 Range 时重下。
- 跳过版本与 24 小时节流逻辑。

### 9.2 集成测试

- 用 `dart:io HttpServer` 搭建本地假 GitHub：
  - `/releases.atom`、`/releases/download/<tag>/update-manifest.json`、资产文件；
  - 模拟 403、超时、连接重置、206 分段、错误哈希。
- 用固定 fixture 跑完整“检查 → 下载 → 校验 → ready”流程，不触达真实网络。

### 9.3 平台验收

| 场景 | 断言 |
|---|---|
| Windows Inno 安装版升级 | 用户确认后静默安装，新版本启动、版本号变化、设置与数据库保留、旧安装目录无残留 exe |
| Windows 便携 zip 升级 | 用户确认后替换成功、自动重启、无 `.part` 残留 |
| Linux AppImage 升级 | 用户确认后文件替换、可执行位保留、自动重启 |
| Linux deb 升级 | 用户确认后正确识别安装形态、调起系统安装器或 pkexec |
| macOS 定位 DMG | 下载校验通过、badge 显示、点击后 Finder 定位文件；不执行安装 |
| badge 持久化 | 应用重启后 badge 仍显示；确认弹窗取消后 badge 保留、不安装 |
| 断网 / 镜像全挂 | 提示检查失败，提供下载页，不崩溃 |
| 磁盘不足 / 下载取消 | 明确错误提示，可恢复重试 |

### 9.4 CI

- `flutter test` 覆盖上述单元与集成测试。
- release job 增加“清单自验”步骤，签名失败即失败发布。
- Windows 冒烟测试可扩展为：安装旧版本 → 本地 fixture 清单下载完成 → 模拟用户确认 → 静默安装 → 断言新版本；可作为 P2。

---

## 10. 实施阶段

| 阶段 | 内容 | 交付物 |
|---|---|---|
| P0 基础设施 | 清单 schema、签名工具、CI 上传清单/签名、prerelease 标志、tag 校验 | 每次 Release 带可验证清单 |
| P1 检查与下载 | 更新模块、设置项、检查/下载 UI、badge、确认弹窗、代理支持、镜像切换、Windows Inno 安装 | Windows 可检查/下载并确认安装 |
| P2 Linux | AppImage/zip 替换、deb 识别与引导、helper 脚本 | Linux 可检查/下载并确认安装 |
| P3 macOS 与增强 | macOS 下载 + badge + Finder 定位；`ssbrunner.com` 清单镜像；自定义镜像；CI 升级冒烟 | macOS 可下载并定位 DMG，境内可达性提升 |

> 首个带更新器的版本无法由旧版本通过应用内更新升级，用户需手动安装一次；从该版本之后才能形成闭环。

---

## 11. 待决策项

已确定：

- **不做自动安装**：下载并校验完成后只显示 badge，用户点击并确认后才安装。
- **macOS 不做应用内安装**：点击后仅用 `open -R` 打开 DMG 所在位置，由用户手动安装。

仍需确认：

1. **是否将签名清单同步到 `ssbrunner.com`**：可显著降低对 GitHub 检查接口的依赖，但需要站点部署权限与 CI 上传通道。
2. **默认镜像列表**：是否接受在客户端内置社区镜像（`gh-proxy.com`、`ghfast.top`、`gh.llkk.cc`）；镜像可能变更或下线，需可远程/手动更新。
3. **Linux deb 是否允许 `pkexec` 自动安装**：涉及提权，建议默认关闭，只调起系统安装器。
4. **签名密钥保管人与轮换流程**：私钥备份、Secret 权限、keyId 轮换责任人。

---

## 12. 参考资料

- GitHub REST API 速率限制（未认证 60 次/小时/IP）：<https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api>
- GitHub 连通性排障：<https://docs.github.com/en/get-started/using-github/troubleshooting-connectivity-problems>
- 阿里云开发者社区：GitHub Release 下载慢、老中断（2026-09-30）：<https://developer.aliyun.com/article/1767403>
- JetStream：GitHub 中国访问加速指南（附件域名与主站不同）：<https://jetstream.fit/blog/github-china-access-acceleration-guide>
- GH-Proxy 文档（Release / Raw / Archive 前缀代理）：<https://gh-proxy.com/docs/github-accelerator>
- 2026 年 10 月镜像实测：<https://zachthinking.github.io/posts/github-proxy-mirror/>
- Inno Setup 命令行参数：<https://jrsoftware.org/ishelp/topic_setupcmdline.htm>
- Inno Setup `CloseApplications`：<https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm>
- fastforge Windows EXE 打包与自定义模板：<https://fastforge.dev/makers/exe>
- Sparkle 沙箱说明（仅作 macOS 备选参考）：<https://sparkle-project.org/documentation/sandboxing/>
