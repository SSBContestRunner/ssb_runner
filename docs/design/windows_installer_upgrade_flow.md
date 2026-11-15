# Windows 安装器覆盖安装提示技术方案

> 状态：已实施（2026-11-15），待 Windows CI 冒烟验证
> 决策：**方案 A（自定义向导页）+ §4.6 覆盖安装加固**
> 适用范围：Windows Inno Setup 单文件安装包（`ssb_runner-<version>-windows-setup.exe`）
> 关联文档：[安装语言与移除开机启动](windows_installer_languages_and_autostart.md)、[应用内更新](in-app-update.md)、[Windows 单文件打包调研](../research/windows-single-file-packaging.md)
> 本文只定义安装器（Inno Setup）行为，**不涉及** Dart 代码与便携 zip 包。

---

## 0. 决策摘要

| 决策 | 结论 |
| --- | --- |
| 提示形式 | 新增一个自定义向导页（`CreateCustomPage`），仅在检测到既有安装时出现；不改 Welcome 页文案 |
| 页面位置 | `wpSelectDir` 之后 —— 正好补上被 Inno 静默跳过的「选择目标位置」页 |
| 版本方向 | 区分 `none / same / upgrade / downgrade` 四种，文案与按钮行为分别处理 |
| 降级处理 | **一律阻止**：交互模式弹一次不可继续的错误提示后退出；静默模式不弹框、写日志后以非零码退出 |
| 静默路径 | 自定义页在 `/SILENT`、`/VERYSILENT` 下不显示，行为与现状一致 |
| 加固 | 显式 `CloseApplications=yes` / `RestartApplications=no`；新增 `[InstallDelete]` 清理旧 DLL 与 `data` 目录 |
| 语言 | 新增文案全部走 `[CustomMessages]`，覆盖现有 4 种安装语言，不新增 `.isl` |
| 改动面 | 只改 `windows/packaging/exe/installer.iss`（CI 静态断言与冒烟脚本如不扩展则无需改动） |

---

## 1. 问题定义

手动双击 `*-windows-setup.exe` 做覆盖安装时，向导既不提示「已存在旧版本」，也不说明「程序文件会被替换」，更不显示实际写入目录。用户无法区分自己是在全新安装还是覆盖安装，也无法判断是否会丢数据。

同时存在两个未暴露的风险：

1. 拿旧安装包覆盖新版本时属于静默降级，安装器不做任何拦截；
2. 旧版本已移除的 DLL / 资源不会被清理，形成新旧文件混装。

---

## 2. 根因

当前模板 [installer.iss](../../windows/packaging/exe/installer.iss) 只有 `[Setup] / [Languages] / [Tasks] / [Files] / [Icons] / [Run]`，**没有 `[Code]` 段，也没有任何注册表探测**，安装器在逻辑上不知道本机是否装过。

| # | 机制 | 用户可见后果 |
| --- | --- | --- |
| 1 | Inno 的 `DisableDirPage` 默认为 `auto`，检测到同一 `AppId` 的既有安装并复用旧目录时（`UsePreviousAppDir` 默认 yes），「选择目标位置」页不显示 | 唯一能暴露写入路径的页面被跳过，向导反而比全新安装更短 |
| 2 | Welcome 页使用官方 `WelcomeLabel1/2`，文案为 “This will install …” | 全新安装与覆盖安装文字相同，既无旧版本号也无「文件将被替换」 |
| 3 | `AppVersion={{APP_VERSION}}` 只写入注册表，从不与已装版本比较 | 旧包覆盖新版本 = 静默降级 |
| 4 | 无 `[InstallDelete]` | 旧产物残留，新旧混装 |
| 5 | 未显式声明 `CloseApplications` / `RestartApplications` | 应用运行中覆盖时依赖 Inno 的版本默认值，行为不可预期 |

---

## 3. 约束

1. `AppId`（`367C747B-BCE1-4BB0-B8DD-F402E9056B64`）是安装身份唯一契约，发布后不可改。
2. 安装为 per-user（`PrivilegesRequired=lowest`），卸载项固定在 `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{AppId}_is1`。
3. 数据与安装在物理上分离：程序写 `%LOCALAPPDATA%\Programs\SSB_Runner`，设置/训练记录写 `%APPDATA%\com.ssbrunner\ssb_runner`（见 [smoke-test-windows-installer.ps1](../../.github/scripts/smoke-test-windows-installer.ps1#L149)）。覆盖安装不会触碰用户数据。
   - 例外：应用的数据根目录有一个兜底候选是 exe 所在目录（[dirs.dart](../../lib/common/dirs.dart#L23-L39)），当应用支持目录与临时目录都不可写时，用户的 `db/`、`log/` 会落在 `{app}\db`、`{app}\log`。安装器必须把这两个目录当作用户数据对待。
4. 安装器有 4 种语言（`english` / `chinesesimplified` / `chinesetraditional` / `japanese`），文案必须带语言前缀，不能新增 `.isl`。
5. 模板先经 fastforge 的 Liquid 渲染再交给 ISCC：[installer.iss](../../windows/packaging/exe/installer.iss#L36-L38) 要求 `[Code]` 中不得出现 `{{` / `{%`；单花括号 `{app}`、`{#...}`（ISPP）安全。
6. 两条入口必须分开处理：
   - 交互式：用户双击安装包；
   - 静默式：应用内更新执行 `setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=...`（[in-app-update.md](in-app-update.md#L327-L334)）。后者不得出现任何新增页面或弹框。
7. `/SUPPRESSMSGBOXES` 会让 `MsgBox` 直接返回默认按钮，因此**静默模式的分支判断必须显式基于 `WizardSilent`，不能依赖 MsgBox 的结果**。

---

## 4. 方案

### 4.1 检测层（`[Code]`）

新增以下全局状态与函数：

```
FPrevVersion : String;   // 已安装版本，空表示未检测到
FPrevDir     : String;   // 已安装目录
FDirection   : (dirNone, dirSame, dirUpgrade, dirDowngrade);
```

`DetectPreviousInstall()` 按下列顺序取值，命中即止：

| 顺序 | 来源 | 说明 |
| --- | --- | --- |
| 1 | `HKCU\...\Uninstall\{AppId}_is1` 的 `DisplayVersion` | per-user 安装的权威版本号，由 Inno 写入；0.3.0 之前没有 Inno 安装方式，因此不存在其他地方写入的版本 |
| 2 | 同上键的 `Inno Setup: App Path`，其次 `InstallLocation` | 旧目录；为空则回落到 `WizardDirValue` |
| 3 | `WizardForm.PrevAppDir`（Inno 5.5.7+） | 交叉校验：目录存在但版本值缺失时，仍可判定为「覆盖安装」并按 `dirSame` 处理 |

键名用 ISPP 拼接，避免 UUID 写两遍：

```
'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1'
```

> 注意：不要在运行时对该字符串调用 `ExpandConstant`，`{367C...}` 会被当作常量解析而报错。ISPP 已在编译期完成替换。

调用时机：`InitializeSetup`（早于向导创建），以便降级阻断在建页面前就能生效。

### 4.2 页面层（方案 A）

```
FUpgradePage := CreateCustomPage(wpSelectDir, CustomMessage('UpgradePageCaption'), '');
```

- 位置：`wpSelectDir` 之后。Inno 的 `CreateCustomPage` 语义是「插在指定页之后」，因此当目录页被跳过时，本页恰好占据它的位置，形成「确认写入位置」的自然一步。
- 控件：4 个 `TNewStaticText`（版本行、目标目录行、保留数据行、降级警告行），按 `FDirection` 控制可见性。
- 文案刷新：在 `CurPageChanged(FUpgradePage.ID)` 里用 `FmtMessage(CustomMessage(...), [...])` 实时填充，不在 `InitializeWizard` 里缓存字符串（避免语言对话框晚于向导创建时文案粘在默认语言，也便于将来支持运行中切换语言）。
- 目标目录取 `WizardDirValue`，而不是配置里的 `DefaultDirName`：当旧安装位于不同目录（例如 0.3.0-alpha07 把 `SSB Runner` 改成 `SSB_Runner`）时，Inno 会沿用**旧目录**，页面必须显示真实写入位置。
- 跳过规则：`ShouldSkipPage` 中 `if PageID = FUpgradePage.ID then Result := FDirection = dirNone;`。
- 静默模式：自定义页本身不会显示，无需额外分支。

`FDirection` 对应的页面形态：

| 方向 | 版本行 | 额外行 | 下一步 |
| --- | --- | --- | --- |
| `dirUpgrade` | 已安装 A → 本次 B | 目标目录 + 数据保留 | 直接通过 |
| `dirSame` | 已安装 A → 本次 A | 「当前已是该版本，将重新覆盖写入」 | 直接通过 |
| `dirDowngrade` | — | — | **不会进入向导**，在 `InitializeSetup` 阶段中止，见 §4.4 |
| `dirNone` | — | — | 页面跳过，流程与现状一致 |

### 4.3 版本比较规则

`AppVersion` 形如 `0.3.0-alpha07`，可能带 `+<build>`。`CompareVersions(A, B)` 定义：

1. 丢弃 `+` 之后的构建元数据；
2. 主版本按 `.` 拆段逐段做数值比较，缺位补 0；
3. 主版本相同时，带 `-` 预发布后缀的一方**小于**同主版本的正式版；
4. 预发布后缀内部按「字母前缀 + 数字」比较（`alpha07 < beta02`，`alpha07 < alpha10`）；
5. 完全相等返回 0。

判定：`A < B → dirUpgrade`，`A = B → dirSame`，`A > B → dirDowngrade`。

> 该规则只服务于安装器提示与阻断，不改变应用自身的版本语义。

### 4.4 降级：一律阻止

依据：数据库迁移只有向前分支（[app_database.dart](../../lib/db/app_database.dart#L20-L60)，当前 `_schemaVersion = 7`，只有 `from < n` 的加列逻辑），旧版本读到更高 `user_version` 的行为未定义。因此**任何形式的降级都不允许**，也不提供「强制继续」入口。

| 模式 | 行为 |
| --- | --- |
| 交互 + `dirDowngrade` | `InitializeSetup` 中弹一次 `MsgBox(FmtMessage(CustomMessage('UpgradeDowngradeBlocked'), [FPrevVersion, NewVersion]), mbError, MB_OK)`，随后返回 `False`。向导不会被创建，§4.2 的页面不参与 |
| 静默 + `dirDowngrade` | 不弹框（`/SUPPRESSMSGBOXES` 下 `MsgBox` 会直接返回默认值，结果不可信），只 `Log()` 记录旧/新版本后返回 `False`，以非零退出码结束；安装目录不做任何修改 |
| 静默 + 其他方向 | 与现状完全一致，无新增输出 |

判定必须放在 `InitializeSetup`，不能放在页面事件或 `NextButtonClick`：静默模式下页面事件不会执行，且进入向导后中止会留下中途状态。

> 应用内更新路径不会触发此分支：更新清单只会指向更高版本。

### 4.5 本地化文案

新增 `[CustomMessages]`，每条给 4 个语言前缀。以下为初稿：

| 键 | english | chinesesimplified |
| --- | --- | --- |
| `UpgradePageCaption` | Upgrade | 覆盖安装 |
| `UpgradeVersionLine` | Installed: %1　→　This package: %2 | 已安装：%1　→　本次安装包：%2 |
| `UpgradeTargetLine` | Target folder: %1 | 目标目录：%1 |
| `UpgradeKeepsDataLine` | Settings and training records are stored outside this folder and will be kept. | 设置与训练记录保存在用户数据目录，不会被删除。 |
| `UpgradeSameVersionLine` | This version is already installed; Setup will overwrite it. | 当前已是该版本，安装将重新覆盖写入。 |
| `UpgradeBlockedCaption` | Cannot continue | 无法继续安装 |
| `UpgradeDowngradeBlocked` | SSB Runner %1 is already installed and is newer than this package (%2). Setup will exit without changing anything. Use a package at %1 or newer, or uninstall the current version first. | 已安装的 SSB Runner 为 %1，高于本安装包（%2）。安装已取消，现有安装未做任何修改。请使用不低于 %1 的安装包，或先卸载当前版本。 |

| 键 | chinesetraditional | japanese |
| --- | --- | --- |
| `UpgradePageCaption` | 覆寫安裝 | 上書きインストール |
| `UpgradeVersionLine` | 已安裝：%1　→　本次安裝包：%2 | インストール済み：%1　→　このパッケージ：%2 |
| `UpgradeTargetLine` | 目標資料夾：%1 | インストール先フォルダー：%1 |
| `UpgradeKeepsDataLine` | 設定與訓練記錄儲存在使用者資料目錄，不會被刪除。 | 設定とトレーニング記録はユーザーデータフォルダーに保存されるため、削除されません。 |
| `UpgradeSameVersionLine` | 目前已是該版本，安裝將重新覆寫。 | このバージョンは既にインストールされています。上書きインストールします。 |
| `UpgradeBlockedCaption` | 無法繼續安裝 | 続行できません |
| `UpgradeDowngradeBlocked` | 已安裝的 SSB Runner 為 %1，高於本安裝包（%2）。安裝已取消，現有安裝未做任何修改。請使用不低於 %1 的安裝包，或先解除安裝目前版本。 | インストール済みの SSB Runner は %1 で、このパッケージ（%2）より新しいため、インストールを中止しました。既存のインストールは変更されていません。%1 以降のパッケージを使用するか、現在のバージョンを先にアンインストールしてください。 |

说明：

- 段落换行用 `%n`，不使用 Liquid 的 `{{` / `{%`；
- 不覆盖官方 `WelcomeLabel*`，避免与 `.isl` 升级冲突；
- 文案长度按「现代向导」页宽（约 460px @100%）控制，日文/繁体不再额外折行。

### 4.6 覆盖安装加固

在 `[Setup]` 中显式声明（不依赖 Inno 版本默认值，避免升级 Inno 后行为漂移）：

```
CloseApplications=yes
RestartApplications=no
```

- `CloseApplications=yes`：由 Restart Manager 关闭占用待替换文件的进程，避免「exe 被占用导致写入失败但向导仍显示成功」。之前依赖默认值，未写入模板。
- `RestartApplications=no`：重启由应用内更新的 `[Run] WizardSilent` 项负责（[in-app-update.md](in-app-update.md#L313-L324)），安装器不再自行拉起，避免重复启动。

新增 `[InstallDelete]`（在 `[Files]` 之前执行）：

```
Type: files;          Name: "{app}\*.dll"
Type: filesandordirs; Name: "{app}\data"
```

删除的到底是什么：

| 匹配 | 内容 | 归属 |
| --- | --- | --- |
| `{app}\*.dll` | `flutter_windows.dll`、`flutter_soloud_plugin.dll`、`cnativeapi.dll`、`msvcp140.dll` / `vcruntime140*.dll` 等 | 安装包产物，每次安装都会重写 |
| `{app}\data` | `data\app.so`、`data\icudtl.dat`、`data\flutter_assets\*` | Flutter 构建产物，每次安装都会重写 |

明确**不删**：`{app}\db`（训练记录数据库）、`{app}\log`（日志）、`{app}\unins000.*`、`{app}\ssb_runner.exe` 之外的用户自建文件。

硬性约束：`[InstallDelete]` 不得使用 `{app}\*`、`filesandordirs; Name: "{app}"`，也不得匹配 `db` / `log`。原因是数据根目录存在兜底候选（见 §3 第 3 条），极端情况下用户真实的训练记录就写在 `{app}\db` 下；整目录清空等于删用户数据。该约束由 CI 静态断言守护（见 §5）。

- 副作用：若安装在 `[Files]` 阶段失败，安装目录会处于「已删除旧文件、未写入新文件」的中间态。当前安装包为单文件、无网络依赖，失败概率低，接受该风险。

---

## 5. 实施清单

### 5.1 安装器模板（1 个文件）

[windows/packaging/exe/installer.iss](../../windows/packaging/exe/installer.iss)

1. `[Setup]` 追加 `CloseApplications` / `RestartApplications`。
2. 新增 `[CustomMessages]` 段（7 键 × 4 语言）。
3. 新增 `[InstallDelete]` 段（2 条，见 §4.6）。
4. 新增 `[Code]` 段：
   - `ReadUninstallValue` / `DetectPreviousInstall` / `CompareVersions`；
   - `InitializeSetup`：检测 + 降级一律中止（交互弹提示、静默只写日志）；
   - `InitializeWizard`：`CreateCustomPage` + `TNewStaticText`；
   - `CurPageChanged`：填充文案；
   - `ShouldSkipPage`：非升级时跳过。
5. 文件头注释补充「为什么有 `[Code]` 段」与新文案所在段落，保持既有「改动理由写在模板里」的惯例。

### 5.2 CI（[smoke-test-windows-installer.ps1](../../.github/scripts/smoke-test-windows-installer.ps1)）

现有静态断言（4 语言、无 `launchAtStartup`、无 `{userstartup}`）保留，新增：

1. **模板静态断言**（渲染产物编译后被删除，只能查源模板）：
   - `[Code]` 段内不得出现 `{{` 或 `{%`；
   - `[CustomMessages]` 中每个键必须有 4 个语言前缀；
   - `[InstallDelete]` 不得出现 `{app}\*`、`Name: "{app}"`、`\db`、`log`（守护 §4.6 的用户数据边界）。
2. **重复安装**：首次静默安装并校验通过后，用同一个包再静默安装一次，断言退出码 0 且 `$required` 文件仍完整（第二次走 `dirSame`，覆盖检测代码与 `[InstallDelete]` 的静默路径）。
3. **降级阻断**：把 `HKCU\...\Uninstall\{AppId}_is1` 的 `DisplayVersion` 改成 `99.0.0`，再静默执行一次安装，断言退出码非零且安装目录文件清单未变化；随后恢复原 `DisplayVersion`，让后续卸载步骤正常执行。

> Inno 对 `InitializeSetup` 返回 `False` 的退出码不保证固定值，断言只判断「非零」。

---

## 6. 验证矩阵（Windows 本地 + CI）

| 场景 | 期望 |
| --- | --- |
| 全新安装（无卸载项） | 不出现覆盖页，流程与现状一致 |
| 同版本重装 | 出现页面，显示「当前已是该版本，将重新覆盖写入」 |
| 旧 → 新（目录相同） | 出现页面，版本行正确，Next 直接通过 |
| 旧 → 新（目录不同） | 页面显示**旧目录**（真实写入位置），与 `%LOCALAPPDATA%` 下的实际路径一致 |
| 新 → 旧（交互） | 弹出「无法继续安装」错误提示后退出，安装目录内容不变 |
| 新 → 旧（`/VERYSILENT`） | 无弹窗，退出码非零，日志含旧/新版本，安装目录内容不变 |
| `/VERYSILENT /SUPPRESSMSGBOXES` 正常升级 | 无新增页面/弹窗，退出码 0，文件完整 |
| 同一安装包连续静默安装两次 | 两次退出码均为 0，文件完整（CI 覆盖） |
| 应用运行中覆盖安装 | Restart Manager 关闭应用后继续，无「文件正在使用」死循环 |
| 覆盖安装后检查残留 | `{app}\*.dll` 与 `{app}\data` 只含本次安装包内容 |
| `{app}\db`、`{app}\log` 存在时覆盖安装 | 内容保留，不被 `[InstallDelete]` 删除 |
| 4 种语言（含系统语言中文/日文） | 页面文案跟随所选安装语言 |
| 现有 CI 冒烟脚本 | 静默安装 → 校验文件 → 启动 → 静默卸载，全流程通过 |

---

## 7. 风险与边界

- **卸载项缺失**（用户手删安装目录、绿色迁移）→ 判为 `dirNone`，不显示提示，按全新安装处理。可接受。
- **数据兜底路径**：`{app}\db`、`{app}\log` 可能承载真实用户数据，`[InstallDelete]` 的范围必须严格限定（§4.6），并有 CI 静态断言守护。
- **`/SUPPRESSMSGBOXES` 语义**：静默分支禁止用 `MsgBox` 做判断，必须 `WizardSilent`；降级提示只在交互模式出现。
- **Liquid 渲染**：`[Code]` 中一旦出现 `{{` / `{%` 会被模板引擎吃掉；渲染产物编译后即删除，因此由 CI 对源模板的 `[Code]` 段做静态断言（§5.2）。
- **静默降级中止的退出码**：Inno 对 `InitializeSetup` 返回 `False` 的退出码未固定，调用方一律按「非零」判定。
- **`[InstallDelete]` 的中间态**：见 §4.6。

---

## 8. 决策记录

原 8 项未决事项已于 2026-11-15 全部关闭，无剩余未决事项。

| # | 事项 | 结论 |
| --- | --- | --- |
| 1 | 遗留安装（AppId 不同） | **不适用**：0.3.0 尚未正式发布，此前不存在 Inno Setup 安装方式 |
| 2 | 是否允许强制降级 | **不允许**，交互与静默两种模式都中止，见 §4.4 |
| 3 | `[InstallDelete]` 范围 | 只删 `{app}\*.dll` 与 `{app}\data`；`{app}\db`、`{app}\log` 属用户数据，明确排除，见 §4.6 |
| 4 | 静默降级退出码约定 | 安装器只保证「非零 + 日志」，调用方按非零判定 |
| 5 | CI 重复安装用例 | **纳入**，见 §5.2 第 2 项 |
| 6 | CI Liquid 残留断言 | **纳入**，见 §5.2 第 1 项 |
| 7 | 旧文档「alpha 阶段不考虑升级迁移」表述 | **修订**：[安装语言与移除开机启动](windows_installer_languages_and_autostart.md) 已改为指向本文 |
| 8 | 繁中 / 日文文案 | 按 §4.5 初稿定稿 |
