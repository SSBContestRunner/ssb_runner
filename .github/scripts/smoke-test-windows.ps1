# Smoke-tests the portable Windows zip by closing the window the way a user does.
#
# Why this exists: the Windows runner destroys the FlutterEngine synchronously inside
# WM_DESTROY and posts WM_QUIT only afterwards (windows/runner/win32_window.cpp). If any
# teardown step blocks there, the window is already gone but the message loop never
# quits, leaving an idle process in Task Manager -- the "zombie process after closing"
# report. PostMessage(WM_CLOSE) is exactly what clicking the X sends, so these scenarios
# assert the user-visible outcome instead of internals.
#
# Limits: the runner lives in Session 0 with no audio device, so SoLoud init fails and
# is swallowed by the startup path; the scenarios therefore exercise the "audio not
# initialized" exit path and cannot reproduce a blocked audio driver by themselves.
# Scenario 2 injects a permanently stuck cleanup through an environment variable and
# proves the 5 s fallback, not the audio driver.
#
# Usage (from the repo root, as CI does): pwsh .github/scripts/smoke-test-windows.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppDataLog = Join-Path $env:APPDATA 'com.ssbrunner\ssb_runner\log\latest.log'
$CloseWaitSeconds = 10

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class Win32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern IntPtr GetParent(IntPtr hWnd);
}
"@

function Fail([string]$Message) {
  Write-Host "::error::$Message"
  exit 1
}

# Top-level visible window owned by the given process. MainWindowHandle is 0 in some
# sessions, so enumerate instead of trusting it.
function Get-TopWindow([int]$TargetId) {
  $script:found = [IntPtr]::Zero
  $callback = [Win32+EnumWindowsProc] {
    param([IntPtr]$hWnd, [IntPtr]$lParam)

    [uint32]$windowPid = 0
    [void][Win32]::GetWindowThreadProcessId($hWnd, [ref]$windowPid)
    if ($windowPid -eq $TargetId -and
        [Win32]::GetParent($hWnd) -eq [IntPtr]::Zero -and
        [Win32]::IsWindowVisible($hWnd)) {
      $script:found = $hWnd
      return $false
    }
    return $true
  }

  [void][Win32]::EnumWindows($callback, [IntPtr]::Zero)
  return $script:found
}

function Wait-ForWindow([int]$ProcessId) {
  $deadline = (Get-Date).AddSeconds(20)
  do {
    $hwnd = Get-TopWindow -TargetId $ProcessId
    if ($hwnd -ne [IntPtr]::Zero) { return $hwnd }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  return [IntPtr]::Zero
}

# Starts the app with the given environment overrides, leaving the parent environment
# untouched so scenario 2 cannot leak its hook into the other scenarios.
function Start-App {
  param(
    [string]$ExePath,
    [hashtable]$Environment = @{}
  )

  $previous = @{}
  foreach ($key in $Environment.Keys) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key)
    [Environment]::SetEnvironmentVariable($key, $Environment[$key])
  }
  try {
    return Start-Process -FilePath $ExePath `
      -WorkingDirectory (Split-Path $ExePath -Parent) -PassThru
  } finally {
    foreach ($key in $previous.Keys) {
      [Environment]::SetEnvironmentVariable($key, $previous[$key])
    }
  }
}

function Assert-ExitLogged([string]$Name) {
  $candidates = @($AppDataLog, (Join-Path $ExtractRoot 'log\latest.log'))
  foreach ($path in $candidates) {
    if (-not (Test-Path $path)) { continue }
    $content = Get-Content -Path $path -Raw
    if ($content -and $content.Contains('exit requested')) {
      Write-Host "   log OK: $path"
      return
    }
  }
  Fail "$Name`: no 'exit requested' entry in latest.log ($($candidates -join ', '))"
}

# The assertion every scenario shares: after WM_CLOSE the process must disappear.
function Invoke-CloseScenario {
  param(
    [string]$Name,
    [string]$ExePath,
    [hashtable]$Environment = @{},
    [int]$SettleSeconds = 0,
    [switch]$ExpectExitLog
  )

  Write-Host "== $Name =="
  $proc = Start-App -ExePath $ExePath -Environment $Environment
  Write-Host "   pid=$($proc.Id)"

  $hwnd = Wait-ForWindow -ProcessId $proc.Id
  if ($hwnd -eq [IntPtr]::Zero) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Fail "$Name`: pid $($proc.Id) never exposed a top-level window"
  }

  if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }
  if ($proc.HasExited) {
    Fail "$Name`: app exited on its own before the window was closed"
  }

  [void][Win32]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  if (-not $proc.WaitForExit($CloseWaitSeconds * 1000)) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Fail "$Name`: process $($proc.Id) still alive $CloseWaitSeconds s after WM_CLOSE (leftover process)"
  }
  Write-Host "   process exited, exit code=$($proc.ExitCode)"

  if ($ExpectExitLog) { Assert-ExitLogged -Name $Name }
}

# --- runner side -------------------------------------------------------------
if (-not (Test-Path 'artifacts')) {
  Fail 'no artifacts/ directory (artifact download failed)'
}
$zip = Get-ChildItem -Path 'artifacts' -Filter '*.zip' -File -Recurse |
  Select-Object -First 1
if (-not $zip) { Fail 'no .zip found under artifacts/' }

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$ExtractRoot = Join-Path $tempRoot 'ssb-smoke'
if (Test-Path $ExtractRoot) { Remove-Item $ExtractRoot -Recurse -Force }
Expand-Archive -Path $zip.FullName -DestinationPath $ExtractRoot -Force

$exe = Get-ChildItem -Path $ExtractRoot -Filter 'ssb_runner.exe' -File -Recurse |
  Select-Object -First 1
if (-not $exe) { Fail "no ssb_runner.exe in $($zip.Name)" }
Write-Host "smoke-testing $($exe.FullName)"

# 1. Idle close: the first frame is painted and the window is opaque by now, so this is
#    the plain "user closes a running app" path.
Invoke-CloseScenario -Name 'window close (idle)' -ExePath $exe.FullName `
  -SettleSeconds 12 -ExpectExitLog

# 2. Injected hang: the Dart side never answers the exit request, so only the 5 s
#    fallback can end the process. Waiting for a settled app first is what makes this a
#    fallback test rather than an early-close one.
Invoke-CloseScenario -Name 'window close with stuck cleanup (fallback)' `
  -ExePath $exe.FullName -Environment @{ SSB_RUNNER_TEST_EXIT_HANG = '1' } `
  -SettleSeconds 12

# 3. Close during startup: the window exists before the first frame, so it is closed
#    while boot is still running.
Invoke-CloseScenario -Name 'window close during startup' -ExePath $exe.FullName

Write-Host 'Windows exit smoke test passed'
