; Custom Inno Setup template for fastforge's `exe` target.
;
; Why this file exists: fastforge 0.6.12's built-in template always emits the
; `launchAtStartup` task and a {userstartup} shortcut, so `launch_at_startup: false`
; could only default the checkbox to unchecked -- it could not remove it. The built-in
; template also derives [Languages] from `locales` through a locale map that has no
; Traditional Chinese entry, and silently drops language files it cannot find.
;
; Baseline: fastforge 0.6.12 / flutter_app_packager 0.6.13 (inno_setup_script.dart; unchanged since 0.6.11).
; Every line below is copied from that template except:
;   - ShowLanguageDialog=auto
;   - [Languages] is fixed to the four languages the app ships
;   - the launchAtStartup task and the {userstartup} icon are removed
;   - WizardSmallImageFile shows the app logo instead of Inno's stock box image
; Re-check the upstream template diff when upgrading fastforge.
;
; Languages here are independent of the in-app locales (en / zh_Hans / zh_Hant / ja in
; l10n.yaml). Inno matches a language file by its own LanguageID: zh-TW gets Traditional,
; zh-HK / zh-MO fall back to Traditional (Inno explicitly excludes Simplified from the
; primary-language fallback when the user's language is Traditional Chinese), ja gets
; Japanese. Keep this list in sync with lib/l10n when adding an app language.
;
; Paths matter: Inno Setup's own installer ships only official translations under
; Languages\ (Japanese included), while Simplified/Traditional Chinese are still
; unofficial translations that live in the issrc repository (Files\Languages\Unofficial\)
; and are never installed by Inno Setup's setup.exe. fastforge's built-in template looked
; for Chinese under Languages\ only, which is why its `locales: [en, zh]` silently
; produced an English-only installer. The two files are therefore vendored under
; windows/packaging/exe/languages/ (issrc tag is-6_7_3) and copied into the compiler's
; Languages\ directory before packaging -- by CI ("Ensure Inno Setup 6 (language files)")
; and by local Windows builds, which must run the same copy step. That is why the
; entries below use the compiler: prefix -- MessagesFile resolves relative paths
; against the rendered script's directory (a build temp directory), not this file's
; directory.
;
; fastforge renders this file as a Liquid template before compiling it; do not add Inno
; preprocessor #define lines, and keep single-brace constants such as {app} / {cm:...}
; as they are. Only the double-brace placeholders below are substituted.
;
; Upgrade handling (added on top of the upstream template): [CustomMessages] + [InstallDelete]
; + [Code] implement docs/design/windows_installer_upgrade_flow.md -- a wizard page that
; appears only when a previous install is detected, showing the installed version and the
; real target folder; a hard block on downgrades (older package over newer install); and
; removal of stale DLLs / data\ before [Files] runs. Every user-facing string lives in
; [CustomMessages] (four languages, no new .isl). [Code] must not contain Liquid delimiters:
; this file is rendered by Liquid before ISCC runs.

[Setup]
AppId={{APP_ID}}
; Windows 10 1607 (build 14393) is the real floor, not "Windows 10": cnativeapi.dll
; (window_manager -> nativeapi) statically imports user32!GetDpiForWindow, which
; does not exist on 1507/1511, so the app cannot load its window manager there.
; See docs/research/windows-10-rtm-cnativeapi-load-failure.md. The portable zip
; has no installer to gate it, so windows/runner/main.cpp performs the same check
; and shows a bilingual message before Dart starts.
MinVersion=10.0.14393
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
; Inno draws its own generic box in the wizard's upper-right corner unless
; WizardSmallImageFile is set. fastforge injects only a fixed set of Liquid variables,
; so derive the logo path from SETUP_ICON_FILE (same directory) instead of adding a
; second config key: Liquid substitutes the icon path first, then ISCC resolves the
; ISPP StringChange expression at compile time. Listing three sizes (100% / 200% /
; 300%) lets Inno pick the one closest to the current DPI scale.
; The PNGs carry a uniform transparent inset (6px at 100%, 10% of the canvas):
; Inno draws the small image flush against the client area's top-right corner and
; [Setup] has no margin directive, so the padding has to be baked into the image.
; Keep the canvas sizes (58 / 116 / 174) unchanged when re-exporting -- the image
; height also drives the wizard header layout, so a different canvas shifts the
; page title and subtitle.
WizardSmallImageFile={#StringChange("{{SETUP_ICON_FILE}}", "app_icon.ico", "wizard_small_image_58.png")},{#StringChange("{{SETUP_ICON_FILE}}", "app_icon.ico", "wizard_small_image_116.png")},{#StringChange("{{SETUP_ICON_FILE}}", "app_icon.ico", "wizard_small_image_174.png")}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCHITECTURES_ALLOWED}}
ArchitecturesInstallIn64BitMode={{ARCHITECTURES_INSTALL_IN_64BIT_MODE}}
ShowLanguageDialog=auto
; 覆盖安装加固：显式声明，不依赖 Inno 版本默认值。
; CloseApplications=yes 让 Restart Manager 关闭仍占用待替换文件的进程，避免「文件被使用
; 导致写入失败但向导仍显示成功」。RestartApplications=no 表示安装器不自行拉起被关闭的
; 应用：静默更新后的重启由应用内更新流程负责（docs/design/in-app-update.md）。
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[CustomMessages]
; 覆盖安装页与降级提示的全部文案。前缀必须与 [Languages] 的 Name 一一对应，每个键都要
; 有四种语言（CI 会断言）；%1 / %2 由 FmtMessage 在运行时填入。不覆盖官方
; WelcomeLabel*，避免与 Inno 的 .isl 升级冲突。
english.UpgradePageCaption=Upgrade
chinesesimplified.UpgradePageCaption=覆盖安装
chinesetraditional.UpgradePageCaption=覆寫安裝
japanese.UpgradePageCaption=上書きインストール
english.UpgradeVersionLine=Installed: %1　→　This package: %2
chinesesimplified.UpgradeVersionLine=已安装：%1　→　本次安装包：%2
chinesetraditional.UpgradeVersionLine=已安裝：%1　→　本次安裝包：%2
japanese.UpgradeVersionLine=インストール済み：%1　→　このパッケージ：%2
english.UpgradeTargetLine=Target folder: %1
chinesesimplified.UpgradeTargetLine=目标目录：%1
chinesetraditional.UpgradeTargetLine=目標資料夾：%1
japanese.UpgradeTargetLine=インストール先フォルダー：%1
english.UpgradeKeepsDataLine=Settings and training records are stored outside this folder and will be kept.
chinesesimplified.UpgradeKeepsDataLine=设置与训练记录保存在用户数据目录，不会被删除。
chinesetraditional.UpgradeKeepsDataLine=設定與訓練記錄儲存在使用者資料目錄，不會被刪除。
japanese.UpgradeKeepsDataLine=設定とトレーニング記録はユーザーデータフォルダーに保存されるため、削除されません。
english.UpgradeSameVersionLine=Setup will overwrite the installed files even though the version is the same.
chinesesimplified.UpgradeSameVersionLine=即使版本相同，安装也会重新写入并覆盖已安装的文件。
chinesetraditional.UpgradeSameVersionLine=即使版本相同，安裝也會重新寫入並覆寫已安裝的檔案。
japanese.UpgradeSameVersionLine=バージョンが同じでも、インストール済みのファイルを上書きして再インストールします。
english.UpgradeBlockedCaption=Cannot continue
chinesesimplified.UpgradeBlockedCaption=无法继续安装
chinesetraditional.UpgradeBlockedCaption=無法繼續安裝
japanese.UpgradeBlockedCaption=続行できません
english.UpgradeDowngradeBlocked=SSB Runner %1 is already installed and is newer than this package (%2). Setup will exit without changing anything. Use a package at %1 or newer, or uninstall the current version first.
chinesesimplified.UpgradeDowngradeBlocked=已安装的 SSB Runner 为 %1，高于本安装包（%2）。安装已取消，现有安装未做任何修改。请使用不低于 %1 的安装包，或先卸载当前版本。
chinesetraditional.UpgradeDowngradeBlocked=已安裝的 SSB Runner 為 %1，高於本安裝包（%2）。安裝已取消，現有安裝未做任何修改。請使用不低於 %1 的安裝包，或先解除安裝目前版本。
japanese.UpgradeDowngradeBlocked=インストール済みの SSB Runner は %1 で、このパッケージ（%2）より新しいため、インストールを中止しました。既存のインストールは変更されていません。%1 以降のパッケージを使用するか、現在のバージョンを先にアンインストールしてください。

[InstallDelete]
; 在 [Files] 之前清理上一次安装留下的、本次一定会重写的产物（新旧 DLL / 资源混装）。
; 严格限定为 *.dll 与 data\：数据根目录有一个兜底候选是 exe 所在目录
; (lib/common/dirs.dart)，极端情况下 {app}\db、{app}\log 承载真实用户数据，绝不能删。
; 禁止写成 {app}\* 或整目录删除；CI 会对本段做静态断言。
Type: files;          Name: "{app}\*.dll"
Type: filesandordirs; Name: "{app}\data"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}

[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; Tasks: desktopicon

[Run]
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent

[Code]
// 覆盖安装检测与提示，对应 docs/design/windows_installer_upgrade_flow.md。
//
// 为什么需要这段：Inno 在检测到同一 AppId 的既有安装时会复用旧目录，并静默跳过
// 「选择目标位置」页，于是用户既看不到写入位置，也分不清全新安装还是覆盖安装；
// 旧安装包覆盖新版本更是没有任何拦截。这里只做三件事：
//   1. InitializeSetup 读卸载项，判定 none / same / upgrade / downgrade；
//   2. 降级一律中止（数据库迁移只有向前分支，旧版本读高 schema 未定义）；
//   3. 其余情况插入一个只在有旧安装时出现的页面，显示旧版本号与真实写入目录。
//
// 注意：本段不得出现 Liquid 的分隔符（双花括号 / 花括号百分号），fastforge 会先用
// Liquid 渲染本文件再交给 ISCC，且渲染产物编译后即删除。AppId / AppVersion 通过 ISPP
// 的 inline directive 在编译期拼接，运行时不调用 ExpandConstant。

const
  // 用整数常量代替自定义枚举，Pascal Script 的兼容性更稳，行为完全一致。
  DIR_NONE = 0;
  DIR_SAME = 1;
  DIR_UPGRADE = 2;
  DIR_DOWNGRADE = 3;

var
  FPrevVersion: String;   // 已安装版本，空表示卸载项里没有 DisplayVersion
  FPrevDir: String;       // 已安装目录，仅用于日志
  FDirection: Integer;
  FUpgradePage: TWizardPage;
  FVersionLabel: TNewStaticText;
  FTargetLabel: TNewStaticText;
  FKeepDataLabel: TNewStaticText;
  FSameVersionLabel: TNewStaticText;

// Inno 把卸载项命名为 "<AppId>_is1"，这里用同一条 [Setup] 指令在编译期拼接，
// 保证与安装器实际写入的键完全一致，不重复写死 UUID。
function UninstallKey: String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
    '{#SetupSetting("AppId")}_is1';
end;

function ReadUninstallValue(const ValueName: String; var Value: String): Boolean;
begin
  Result := RegQueryStringValue(HKCU, UninstallKey, ValueName, Value);
end;

function PackageVersion: String;
begin
  Result := '{#SetupSetting("AppVersion")}';
end;

// 拆出主版本与预发布后缀：先丢掉构建元数据（"+" 之后），再按第一个 "-" 切分。
procedure SplitVersion(const Version: String; var Core: String; var Pre: String);
var
  S: String;
  P: Integer;
begin
  S := Version;
  P := Pos('+', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);

  P := Pos('-', S);
  if P > 0 then
  begin
    Core := Copy(S, 1, P - 1);
    Pre := Copy(S, P + 1, Length(S));
  end
  else
  begin
    Core := S;
    Pre := '';
  end;
end;

// 主版本逐段数值比较，缺位补 0（"0.3" 与 "0.3.0" 相等）。
function CompareCore(const A, B: String): Integer;
var
  RestA, RestB, SegA, SegB: String;
  P: Integer;
begin
  Result := 0;
  RestA := A;
  RestB := B;
  repeat
    P := Pos('.', RestA);
    if P > 0 then
    begin
      SegA := Copy(RestA, 1, P - 1);
      RestA := Copy(RestA, P + 1, Length(RestA));
    end
    else
    begin
      SegA := RestA;
      RestA := '';
    end;

    P := Pos('.', RestB);
    if P > 0 then
    begin
      SegB := Copy(RestB, 1, P - 1);
      RestB := Copy(RestB, P + 1, Length(RestB));
    end
    else
    begin
      SegB := RestB;
      RestB := '';
    end;

    if StrToIntDef(SegA, 0) < StrToIntDef(SegB, 0) then
    begin
      Result := -1;
      Exit;
    end;
    if StrToIntDef(SegA, 0) > StrToIntDef(SegB, 0) then
    begin
      Result := 1;
      Exit;
    end;
  until (RestA = '') and (RestB = '');
end;

// 预发布后缀按「字母前缀 + 数字」拆开：alpha07 -> alpha / 7。
procedure SplitPreRelease(const Pre: String; var Prefix: String; var Number: Integer);
var
  I: Integer;
begin
  Number := 0;
  for I := 1 to Length(Pre) do
  begin
    if (Pre[I] >= '0') and (Pre[I] <= '9') then
    begin
      Prefix := Copy(Pre, 1, I - 1);
      Number := StrToIntDef(Copy(Pre, I, Length(Pre) - I + 1), 0);
      Exit;
    end;
  end;
  Prefix := Pre;
end;

function ComparePreRelease(const A, B: String): Integer;
var
  PrefixA, PrefixB: String;
  NumA, NumB: Integer;
begin
  SplitPreRelease(A, PrefixA, NumA);
  SplitPreRelease(B, PrefixB, NumB);

  Result := CompareText(PrefixA, PrefixB);
  if Result <> 0 then
    Exit;

  if NumA < NumB then
    Result := -1
  else if NumA > NumB then
    Result := 1
  else
    Result := 0;
end;

// A < B 返回 -1，相等 0，A > B 返回 1。只用于安装器的提示与阻断，不改变应用版本语义。
function CompareVersions(const A, B: String): Integer;
var
  CoreA, CoreB, PreA, PreB: String;
begin
  SplitVersion(A, CoreA, PreA);
  SplitVersion(B, CoreB, PreB);

  Result := CompareCore(CoreA, CoreB);
  if Result <> 0 then
    Exit;

  if (PreA = '') and (PreB = '') then
    Result := 0
  else if PreA = '' then
    Result := 1            // 同主版本的正式版大于预发布
  else if PreB = '' then
    Result := -1
  else
    Result := ComparePreRelease(PreA, PreB);
end;

procedure DetectPreviousInstall;
var
  Dir: String;
begin
  FPrevVersion := '';
  FPrevDir := '';
  FDirection := DIR_NONE;

  if not RegKeyExists(HKCU, UninstallKey) then
    Exit;

  if not ReadUninstallValue('DisplayVersion', FPrevVersion) then
    FPrevVersion := '';

  Dir := '';
  if not ReadUninstallValue('Inno Setup: App Path', Dir) or (Dir = '') then
    ReadUninstallValue('InstallLocation', Dir);
  if Dir = '' then
    // 交叉校验：卸载项存在但目录值缺失时，{app} 已按 UsePreviousAppDir 解析为旧目录。
    Dir := ExpandConstant('{app}');
  FPrevDir := Dir;

  // 目录在、版本值缺失：仍算覆盖安装，按「同版本重写」提示，不阻断。
  if FPrevVersion = '' then
  begin
    FDirection := DIR_SAME;
    Exit;
  end;

  if CompareVersions(FPrevVersion, PackageVersion) < 0 then
    FDirection := DIR_UPGRADE
  else if CompareVersions(FPrevVersion, PackageVersion) = 0 then
    FDirection := DIR_SAME
  else
    FDirection := DIR_DOWNGRADE;
end;

function InitializeSetup: Boolean;
begin
  DetectPreviousInstall;

  if FDirection <> DIR_DOWNGRADE then
  begin
    Result := True;
    Exit;
  end;

  // 降级一律阻止：必须在这里判定（静默模式下页面事件不执行，且进入向导后中止会留下
  // 中途状态）。静默时 /SUPPRESSMSGBOXES 会让 MsgBox 直接返回默认按钮，结果不可信，
  // 因此分支只看 WizardSilent，不依赖 MsgBox。
  if WizardSilent then
    Log('Upgrade refused: installed ' + FPrevVersion + ' (' + FPrevDir + '), package ' +
      PackageVersion + '.')
  else
    MsgBox(FmtMessage(CustomMessage('UpgradeDowngradeBlocked'), [FPrevVersion, PackageVersion]),
      mbError, MB_OK);

  Result := False;
end;

// 参数不能命名为 Label：label 是 Pascal 保留字（Inno 允许 var / label 声明块），
// ISCC 会报 "Identifier expected"。
procedure CreatePageLabel(const Top, Height: Integer; var Target: TNewStaticText);
begin
  Target := TNewStaticText.Create(WizardForm);
  Target.Parent := FUpgradePage.Surface;
  Target.Left := 0;
  Target.Top := ScaleY(Top);
  Target.Height := ScaleY(Height);
  Target.AutoSize := False;
  Target.WordWrap := True;
  Target.Visible := False;
end;

procedure InitializeWizard;
begin
  // 插在 wpSelectDir 之后：目录页被跳过时本页恰好占据它的位置，补上「确认写入位置」
  // 这一步。文案在 CurPageChanged 里填充，不在这里缓存字符串。
  FUpgradePage := CreateCustomPage(wpSelectDir, CustomMessage('UpgradePageCaption'), '');

  CreatePageLabel(0, 40, FVersionLabel);
  CreatePageLabel(44, 40, FTargetLabel);
  CreatePageLabel(88, 50, FKeepDataLabel);
  CreatePageLabel(142, 50, FSameVersionLabel);
end;

procedure CurPageChanged(CurPageID: Integer);
var
  Prev: String;
begin
  if CurPageID <> FUpgradePage.ID then
    Exit;

  Prev := FPrevVersion;
  if Prev = '' then
    Prev := '?';

  // 页面 surface 的宽度在页面显示时才可靠，因此在这里统一设置自动折行宽度。
  FVersionLabel.Width := FUpgradePage.SurfaceWidth;
  FTargetLabel.Width := FUpgradePage.SurfaceWidth;
  FKeepDataLabel.Width := FUpgradePage.SurfaceWidth;
  FSameVersionLabel.Width := FUpgradePage.SurfaceWidth;

  FVersionLabel.Caption := FmtMessage(
    CustomMessage('UpgradeVersionLine'), [Prev, PackageVersion]);
  FVersionLabel.Visible := True;

  // 取 WizardDirValue 而不是 DefaultDirName：旧安装可能位于不同目录，Inno 会沿用旧目录，
  // 页面必须显示真实的写入位置。
  FTargetLabel.Caption := FmtMessage(CustomMessage('UpgradeTargetLine'), [WizardDirValue]);
  FTargetLabel.Visible := True;

  FKeepDataLabel.Caption := CustomMessage('UpgradeKeepsDataLine');
  FKeepDataLabel.Visible := True;

  if FDirection = DIR_SAME then
  begin
    FSameVersionLabel.Caption := CustomMessage('UpgradeSameVersionLine');
    FSameVersionLabel.Visible := True;
  end
  else
    FSameVersionLabel.Visible := False;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = FUpgradePage.ID) and (FDirection = DIR_NONE);
end;

