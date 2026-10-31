# Smoke-tests the Windows single-file installer (Inno Setup, produced by fastforge's `exe`
# target) end to end on a clean windows-latest runner: silent per-user install, assert the
# bundle landed complete, start the app, then silently uninstall and assert everything is
# gone again.
#
# Why this exists: the installer repacks the same Release/ directory the portable zip ships
# (windows/packaging/exe/make_config.yaml + the Inno template's recursesubdirs), so a copy
# that silently drops a file -- most importantly the app-local MSVC runtime DLLs installed
# by windows/CMakeLists.txt -- would still build and package fine, and only fail on a user's
# machine with 0xC0000135 (STATUS_DLL_NOT_FOUND). Untested install *and* uninstall are also
# how a wrong install_dir_name or a leftover shortcut reaches a release.
#
# Usage (from the repo root, as CI does): pwsh .github/scripts/smoke-test-windows-installer.ps1
# Expects the `ssb-runner-windows` artifact unpacked under artifacts/.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string] $Message) {
  Write-Host "::error::$Message"
  exit 1
}

# Files the installed bundle cannot start without. `data/` holds the Dart AOT snapshot,
# ICU data and the assets; the MSVC runtime DLLs are app-local because
# windows/CMakeLists.txt installs them into the bundle next to ssb_runner.exe.
$required = @(
  'ssb_runner.exe',
  'flutter_windows.dll',
  'flutter_soloud_plugin.dll',
  'window_manager_plugin.dll',
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
  'data\icudtl.dat',
  'data\app.so',
  'data\flutter_assets'
)

# --- locate the installer ----------------------------------------------------
if (-not (Test-Path 'artifacts')) { Fail 'no artifacts/ directory (artifact download failed)' }
$installer = Get-ChildItem -Path 'artifacts' -Recurse -File -Filter '*-windows-setup.exe' |
  Select-Object -First 1
if (-not $installer) {
  Fail 'no *-windows-setup.exe under artifacts/ (artifact download failed or the exe target did not run)'
}
Write-Host "smoke-testing $($installer.Name) ($([math]::Round($installer.Length / 1MB, 1)) MB)"

# --- silent install ----------------------------------------------------------
# /VERYSILENT + /SUPPRESSMSGBOXES + /NORESTART: the unattended switches the Inno template
# supports. install_dir_name is {localappdata}\Programs\SSB Runner and privileges_required
# is lowest, so no UAC prompt appears. The [Run] entry is postinstall skipifsilent, so the
# installer does not launch the app and we start it ourselves below.
$installLog = Join-Path (Get-Location) 'installer.log'
$proc = Start-Process -FilePath $installer.FullName -Wait -PassThru -ArgumentList @(
  '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=$installLog"
)
if ($proc.ExitCode -ne 0) {
  Write-Host "installer exited with $($proc.ExitCode); tail of ${installLog}:"
  if (Test-Path $installLog) { Get-Content $installLog -Tail 40 }
  Fail "installer failed (exit code $($proc.ExitCode))"
}

# Resolve the install directory from the installed exe rather than assuming the name, so a
# change to install_dir_name in make_config.yaml does not silently make this test a no-op.
$exeItem = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs') -Recurse -File -Filter 'ssb_runner.exe' |
  Select-Object -First 1
if (-not $exeItem) { Fail 'installation put no ssb_runner.exe under %LOCALAPPDATA%\Programs' }
$installDir = $exeItem.DirectoryName
Write-Host "installed to $installDir"

# --- assert the bundle ------------------------------------------------------
foreach ($rel in $required) {
  if (-not (Test-Path (Join-Path $installDir $rel))) { Fail "installer is missing $rel" }
}

# Inno writes the Start menu entry as {autoprograms}\<display_name>.lnk, i.e. display_name
# ("SSB Runner") under Programs in the user's roaming AppData.
$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\SSB Runner.lnk'
if (-not (Test-Path $shortcut)) { Fail "Start menu shortcut missing: $shortcut" }

Write-Host "bundle and shortcut look complete"

# --- launch ------------------------------------------------------------------
# The static checks above cannot see a runtime-only problem (a DLL that dlopen()s, a broken
# asset, a crash during boot). A missing MSVC runtime or engine library kills the process
# within milliseconds, so "still alive after 15 s" is the assertion. Session 0 has no audio
# device; boot catches SoLoud init failures (lib/ui/main_app/main_app.dart) rather than dying.
$app = Start-Process -FilePath (Join-Path $installDir 'ssb_runner.exe') -WorkingDirectory $installDir -PassThru
Start-Sleep -Seconds 15
if ($app.HasExited) {
  Fail "app exited early (exit code $($app.ExitCode)); logs: $env:APPDATA\com.ssbrunner\ssb_runner\log"
}
Write-Host 'launch smoke: app started and stayed up'
Stop-Process -Id $app.Id -Force
$app.WaitForExit(10000) | Out-Null

# --- silent uninstall --------------------------------------------------------
$uninstaller = Join-Path $installDir 'unins000.exe'
if (-not (Test-Path $uninstaller)) { Fail 'no uninstaller (unins000.exe) in the install directory' }

Start-Process -FilePath $uninstaller -Wait -PassThru -ArgumentList @(
  '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=$installLog"
) | Out-Null

# Inno's uninstaller may relaunch itself from a temp copy, so the launcher process can
# return before the files are actually deleted. Poll instead of trusting that exit alone.
# Generous ceiling: deleting a few hundred MB is not instant on a shared runner disk.
$deadline = (Get-Date).AddSeconds(60)
while ((Test-Path $installDir) -and (Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 500
}
if (Test-Path $installDir) {
  Write-Host "leftovers under $installDir`n"
  Get-ChildItem $installDir -Recurse -File | ForEach-Object { Write-Host "  $($_.FullName)" }
  Fail 'uninstall did not remove the install directory'
}
if (Test-Path $shortcut) { Fail 'uninstall left the Start menu shortcut behind' }

Write-Host 'installer smoke test passed'
exit 0
