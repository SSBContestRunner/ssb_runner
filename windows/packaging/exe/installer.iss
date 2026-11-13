; Custom Inno Setup template for fastforge's `exe` target.
;
; Why this file exists: fastforge 0.6.12's built-in template always emits the
; `launchAtStartup` task and a {userstartup} shortcut, so `launch_at_startup: false`
; could only default the checkbox to unchecked -- it could not remove it. The built-in
; template also derives [Languages] from `locales` through a locale map that has no
; Traditional Chinese entry, and silently drops language files it cannot find.
;
; Baseline: fastforge 0.6.12 / flutter_app_packager 0.6.11 (inno_setup_script.dart).
; Every line below is copied from that template except:
;   - ShowLanguageDialog=auto
;   - [Languages] is fixed to the four languages the app ships
;   - the launchAtStartup task and the {userstartup} icon are removed
; Re-check the upstream template diff when upgrading fastforge.
;
; Languages here are independent of the in-app locales (en / zh_Hans / zh_Hant / ja in
; l10n.yaml). Inno matches a language file by its own LanguageID: zh-TW gets Traditional,
; zh-HK / zh-MO fall back to Traditional (Inno explicitly excludes Simplified from the
; primary-language fallback when the user's language is Traditional Chinese), ja gets
; Japanese. Keep this list in sync with lib/l10n when adding an app language.
;
; Paths matter: Inno Setup 6.x ships ChineseSimplified.isl / ChineseTraditional.isl as
; unofficial translations under Languages\Unofficial\, and Japanese.isl as an official
; translation under Languages\. fastforge's built-in template looks for Chinese under
; Languages\, which is why its `locales: [en, zh]` silently produced an English-only
; installer. The corresponding files are asserted in CI ("Ensure Inno Setup 6").
;
; fastforge renders this file as a Liquid template before compiling it; do not add Inno
; preprocessor #define lines, and keep single-brace constants such as {app} / {cm:...}
; as they are. Only the double-brace placeholders below are substituted.

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
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCHITECTURES_ALLOWED}}
ArchitecturesInstallIn64BitMode={{ARCHITECTURES_INSTALL_IN_64BIT_MODE}}
ShowLanguageDialog=auto

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\Unofficial\ChineseSimplified.isl"
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\Unofficial\ChineseTraditional.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

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
