# Windows 安装器技术方案：安装语言与移除开机启动

> 状态：待评审（2026-11-13）
> 适用范围：Windows Inno Setup 单文件安装包（`ssb_runner-<version>-windows-setup.exe`）
> 关联文档：[Windows 单文件打包调研](../research/windows-single-file-packaging.md)
> 本文只定义安装器（Inno Setup）的行为与构建配置，**不涉及** Dart 代码、应用内运行时语言解析和便携 zip 包。

---

## 0. 已确认决策

| 决策 | 结论 |
| --- | --- |
| 安装语言 | 英文 / 简体中文 / 繁体中文 / 日文，共 4 种 |
| 语言选择 | 显式 `ShowLanguageDialog=auto`，按系统语言自动匹配，匹配不到才弹选择框 |
| 开机启动 | 删除任务与 Startup 快捷方式，安装向导中不再出现该选项 |
| 老版本遗留 Startup 快捷方式 | **不清理**（alpha 阶段不考虑升级迁移） |
| 桌面图标任务 | 保留，仍受 `create_desktop_icon: false` 控制（默认不勾选） |
| 实现方式 | 使用 fastforge 的 `script_template` 自定义安装脚本，替代内置模板 |

---

## 1. 问题定义

当前 Windows 安装器存在两个用户可见问题：

1. **安装向导只有英文**：应用内已支持英文 / 简体中文 / 繁体中文 / 日文，但安装器只声明了英文与简体中文，且实际产物经常只剩英文。
2. **“开机启动”勾选框无法去掉**：`make_config.yaml` 里的 `launch_at_startup: false` 只是让复选框默认不勾选，向导中依然显示。

---

## 2. 现状与根因

### 2.1 语言只有英文

配置见 [`windows/packaging/exe/make_config.yaml`](../../windows/packaging/exe/make_config.yaml)：

```yaml
locales:
  - en
  - zh
```

fastforge 0.6.12 的内置 Inno 模板存在三层限制：

| 层 | 行为 | 后果 |
| --- | --- | --- |
| 配置 | `locales` 只列了 `en` / `zh` | 缺 `ja` 与繁体中文 |
| 映射表 | `_localeToLanguageFile` 没有 `zh_Hant`（也没有任何繁体条目） | 即使写进 `locales` 也无法生成 `[Languages]` 条目 |
| 语言文件过滤 | `_getAvailableLocales()` 在 `Languages\` 下找 `.isl`，找不到就**静默跳过** | 中文语言文件不在安装目录里（见下），因此 `zh` 被丢掉，最终只剩英文 |

也就是说，`zh` 丢失与 Inno Setup 版本无关：Inno Setup 的安装包只装 `Languages\` 下的**官方翻译**（`Japanese.isl` 在其中），简体/繁体中文始终是**非官方翻译**，只存在于 issrc 源码仓库的 `Files\Languages\Unofficial\`，安装包不会带；而 fastforge 的内置模板只在 `Languages\` 下查找。CI 的 “Ensure Inno Setup 6” 步骤（[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)）只在 `ISCC.exe` 不存在时才安装、也不检查语言文件，因此这个降级既不会报错也不会被 CI 发现。

### 2.2 开机启动勾选框去不掉

fastforge 0.6.12 内置模板（`inno_setup_script.dart`）中：

```iss
[Tasks]
Name: "launchAtStartup"; Description: "{cm:AutoStartProgram,{{DISPLAY_NAME}}}"; ... Flags: unchecked
[Icons]
Name: "{userstartup}\{{DISPLAY_NAME}}"; ...; Tasks: launchAtStartup
```

`[Tasks]` 与 `[Icons]` 两处都是**无条件生成**的，`launch_at_startup` 只控制 `unchecked` / `checkedonce`。因此仅改 YAML 无法移除该勾选项，必须替换模板。

---

## 3. 目标与非目标

### 目标

1. 安装向导支持 4 种语言，并按系统语言自动选择。
2. 安装向导不再出现“开机启动”选项，新安装不写入 Startup 快捷方式。
3. 构建期能明确发现语言文件缺失，不再静默退化成英文。

### 非目标

- 不修改应用内语言设置与语言解析逻辑。
- 不处理老版本已写入的 Startup 快捷方式（alpha 阶段）。
- 不改动 zip 便携包、macOS / Linux 打包流程。
- 不改动安装目录、权限（`lowest`）、AppId 等既有契约。

---

## 4. 方案

### 4.1 新增自定义安装脚本 `windows/packaging/exe/installer.iss`

fastforge 支持 `script_template`：读取 `windows/packaging/exe/<script_template>` 并先做 Liquid 渲染。脚本以 0.6.12 内置模板为基线，仅做必要修改，其余行逐字保留：

- 新增 `ShowLanguageDialog=auto`；
- `[Languages]` 固定 4 条；
- 删除 `[Tasks]` 的 `launchAtStartup`；
- 删除 `[Icons]` 的 `{userstartup}` 行。

建议内容（`{{...}}` / `{%...%}` 为 fastforge Liquid 占位符，会由打包时替换）：

```iss
[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
; 右上角小图：由 SETUP_ICON_FILE 同目录的 logo PNG 提供，见下方“实现注意”。
WizardSmallImageFile={#StringChange("{{SETUP_ICON_FILE}}", "app_icon.ico", "wizard_small_image_58.png")},{#StringChange("{{SETUP_ICON_FILE}}", "app_icon.ico", "wizard_small_image_116.png")},{#StringChange("{{SETUP_ICON_FILE}}", "app_icon.ico", "wizard_small_image_174.png")}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCHITECTURES_ALLOWED}}
ArchitecturesInstallIn64BitMode={{ARCHITECTURES_INSTALL_IN_64BIT_MODE}}
ShowLanguageDialog=auto

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}

[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; Tasks: desktopicon

[Run]
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent
```

实现注意：

- 应用内用户可选语言是 `en` / `zh_Hans` / `zh_Hant` / `ja`；`app_zh.arb` 只是解析兜底，安装器不需要单独条目。
- 中文语言文件由仓库内置（`windows/packaging/exe/languages/`，取自 issrc `is-6_7_3`），打包前复制到 Inno 安装目录的 `Languages\`，因此 `.iss` 里用 `compiler:Languages\ChineseSimplified.isl`；日文是 `Languages\` 下的官方翻译。路径写错时 ISCC 会在构建期直接报错，不会再静默退化成英文。
- Inno 按各 `.isl` 的 `LanguageID` 自动匹配；其内置规则保证简体/繁体互斥，`zh-TW` 命中繁体、`zh-HK` / `zh-MO` 会回落到繁体、`ja` 命中日文。
- `Name:` 使用 `english` / `chinesesimplified` / `chinesetraditional` / `japanese`，后续可用 `/LANG=` 指定。
- 模板会被 Liquid 解析：不要写 Inno 预处理器 `#define`；也不要在注释里写双花括号示例（会被当作占位符解析）。`{app}`、`{cm:...}` 等单花括号常量不受影响。
- 右上角小图由 `windows/runner/resources/wizard_small_image_{58,116,174}.png`（与 `app_icon.ico` 同目录，取自 macOS `app_icon_1024.png`）提供。fastforge 只注入固定变量集，无法新增路径变量，所以用 ISPP 内联 `{#StringChange(...)}` 从 `SETUP_ICON_FILE` 推导绝对路径：Liquid 先替换占位符，ISCC 编译期再求值。这样既不依赖渲染后 `.iss` 所在的 `dist/<version>/` 层级，也不需要 `#define`。三档尺寸供 Inno 按当前 DPI 选择。三张图都在画布内预留了均匀透明边距（100% 档 6px，等比 10%；图形 46 / 92 / 138px）：Inno 把这张小图贴着客户区右上角绘制，`[Setup]` 没有 margin 指令，留白只能烘进 PNG，否则蓝色方块会顶到标题栏和右边框。重新导出时画布尺寸必须保持 58 / 116 / 174 —— 图片高度同时决定向导头部高度，改画布会把页面标题和副标题一起顶偏。
- 不引入 `[InstallDelete]`：alpha 阶段不清理旧版 Startup 快捷方式。

### 4.2 修改 `windows/packaging/exe/make_config.yaml`

| 变更 | 说明 |
| --- | --- |
| 新增 `script_template: installer.iss` | 启用自定义模板 |
| 删除 `launch_at_startup` | 已无对应任务 |
| 删除 `locales` | 语言列表改由 `.iss` 唯一维护，避免 fastforge 静默丢语言造成配置与产物不一致 |
| 其余键保持不变 | `create_desktop_icon` / `install_dir_name` / `privileges_required` / `setup_icon_file` 等 |

代价：语言清单与 `l10n.yaml` 不再自动联动，新增应用语言时需同步 `.iss`（在文件头部注释说明对应关系）。

### 4.3 CI 前置检查语言文件

修改 [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) 的 “Ensure Inno Setup 6” 步骤：

1. 安装/定位 `ISCC.exe`（`ISCC.exe` 的版本资源是 0.0.0.0，不能用它判断版本，语言文件兼容性交给 ISCC 编译期报错）；
2. 把仓库内置的 `windows/packaging/exe/languages/ChineseSimplified.isl`、`ChineseTraditional.isl` 复制到 Inno 安装目录的 `Languages\`；
3. 断言 `Default.isl`、`Languages\Japanese.isl`、`Languages\ChineseSimplified.isl`、`Languages\ChineseTraditional.isl` 均存在，缺失则带明确信息失败；
4. 打印 `Languages\**` 下的清单，便于排查 runner 镜像的 Inno 安装内容。

注意：中文语言文件不在安装包里（Inno Setup 的 `setup.exe` 只装 `Languages\*.isl` 官方翻译），`winget` 重装无法补齐，必须由仓库内置文件复制进去。

本地 Windows 打包同样需要先执行第 2 步；否则 ISCC 会以 “Cannot find language file” 失败。

### 4.4 扩展安装器冒烟测试

修改 [`.github/scripts/smoke-test-windows-installer.ps1`](../../.github/scripts/smoke-test-windows-installer.ps1)：

1. 安装完成后断言 `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\SSB Runner.lnk` **不存在**（全新安装不应再产生该快捷方式）；
2. 对仓库中的 `windows/packaging/exe/installer.iss` 与 `make_config.yaml` 做静态断言（fastforge 编译成功后会把渲染出的 `.iss` 删除，产物里没有可断言的脚本）：
   - `make_config.yaml` 的 `script_template` 指向 `installer.iss`；
   - `[Languages]` 含 4 个语言条目且覆盖 4 个 `.isl`；
   - 不包含 `launchAtStartup` 与 `{userstartup}`。
3. 原有的开始菜单快捷方式、安装完整性、启动存活、静默卸载断言保持不变。

静默安装命令加上 `/LANG=chinesetraditional`，作为“该语言已编入安装包”的运行时金丝雀：若安装包缺少繁体语言文件，安装会失败而不是静默按英文继续。

### 4.5 文档同步

- 更新 [`docs/research/windows-single-file-packaging.md`](../research/windows-single-file-packaging.md) §2.3：改成自定义模板、4 种安装语言、中文 `.isl` 由仓库内置并在打包前复制到 `Languages\`、无开机启动；
- 发布说明补充“Windows 安装器支持英文 / 简体中文 / 繁体中文 / 日文”。

---

## 5. 验收标准

1. 在 `zh-CN`、`zh-TW`、`zh-HK`、`ja-JP`、`en-US` 系统上运行安装器，向导语言分别为简体、繁体、繁体、日文、英文；系统语言不匹配时弹出的选择框包含且仅包含 4 种上述语言。
2. “选择附加任务”页只剩“创建桌面图标”，不存在“开机启动”复选框；`create_desktop_icon: false` 时仍默认不勾选。
3. 全新安装后 Startup 目录不存在 `SSB Runner.lnk`。
4. 开始菜单快捷方式、卸载清理、安装后启动应用等既有冒烟断言全部通过。
5. `package-windows` 与 `smoke-test-windows-installer` 两个 CI 任务全绿；语言文件缺失时构建或 CI 前置检查必须显式失败。
6. zip 便携包产物与行为不变；macOS / Linux 打包不受影响。

---

## 6. 风险与注意事项

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 自定义模板与 fastforge 上游模板脱钩 | 升级 fastforge 后内置模板的修复不会自动生效 | CI 已 pin 0.6.12；在 `.iss` 头部注明基线版本，升级时对比上游 diff |
| 本地 Inno 缺中文语言文件 | 编译期报错（路径写对后不会再静默退化） | 中文 `.isl` 已内置在仓库，打包前复制到 Inno 安装目录的 `Languages\`，CI 与本地同一步骤 |
| 安装器语言与应用内语言相互独立 | 用户可能预期“装英文版 = 应用英文” | 明确为非目标；应用仍按系统语言 / 设置解析 |
| alpha 老用户已勾选开机启动 | 升级后旧 Startup 快捷方式仍存在 | 已确认本期不处理，可手动删除或卸载 |
| Liquid 与 Inno 语法混用 | 模板渲染异常 | 仅保留既有占位符写法，不新增 `{% %}` / `#define` 逻辑 |

---

## 7. 实施清单

1. 新增 `windows/packaging/exe/installer.iss`（§4.1 内容）。
2. 更新 `windows/packaging/exe/make_config.yaml`（§4.2）。
3. 更新 CI 的 Inno 语言文件检查（§4.3）。
4. 更新安装器冒烟测试（§4.4）。
5. 更新打包调研文档与发布说明（§4.5）。
6. 跑一次 Windows 打包 + 安装器冒烟测试，按 §5 手工验收 4 种语言与附加任务页。
