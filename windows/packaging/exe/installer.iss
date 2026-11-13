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
; Inno draws its own generic box in the wizard's upper-right corner unless
; WizardSmallImageFile is set. fastforge injects only a fixed set of Liquid variables,
; so derive the logo path from SETUP_ICON_FILE (same directory) instead of adding a
; second config key: Liquid substitutes the icon path first, then ISCC resolves the
; ISPP StringChange expression at compile time. Listing three sizes (100% / 200% /
; 300%) lets Inno pick the one closest to the current DPI scale.
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
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; Tasks: desktopicon

[Run]
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent
