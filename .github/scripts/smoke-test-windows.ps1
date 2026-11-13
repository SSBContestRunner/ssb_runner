# Smoke-tests the portable Windows zip by closing the window the way a user does.
#
# Why this exists: the Windows runner destroys the FlutterEngine synchronously inside
# WM_DESTROY and posts WM_QUIT only afterwards (windows/runner/win32_window.cpp). If any
# teardown step blocks there, the window is already gone but the message loop never
# quits, leaving an idle process in Task Manager -- the "zombie process after closing"
# report. PostMessage(WM_CLOSE) is exactly what clicking the X sends, so these scenarios
# assert the user-visible outcome instead of internals.
#
# Limits: scenario 3 is the racy one. Closing the window while SoLoud is still
# initialising used to skip the deinit and leave the process waiting inside
# ExitProcess for a thread that no longer exists (docs/design/desktop_exit_design.md
# §2.3); the init lasts 28-411 ms, so the scenario sweeps a few close delays instead
# of sampling the window once. Scenario 2 injects a permanently stuck cleanup through
# an environment variable and proves the 5 s fallback, not the audio driver.
#
# Usage (from the repo root, as CI does): pwsh .github/scripts/smoke-test-windows.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'smoke-evidence.ps1')

$AppDataLog = Join-Path $env:APPDATA 'com.ssbrunner\ssb_runner\log\latest.log'
$ExitTraceDir = Join-Path $env:TEMP 'ssb_runner_boot'
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

# Waits for the first visible top-level window, giving up as soon as the process
# dies. Without the exit check a startup crash and a startup hang both surfaced
# as "never exposed a window", which hid the 0xC0000005 in earlier runs.
function Wait-ForWindow([System.Diagnostics.Process]$Process) {
  $deadline = (Get-Date).AddSeconds(20)
  do {
    $hwnd = Get-TopWindow -TargetId $Process.Id
    if ($hwnd -ne [IntPtr]::Zero) { return $hwnd }
    if ($Process.HasExited) { return [IntPtr]::Zero }
    # 25 ms, not 250 ms: "close during startup" has to win the race against the
    # boot sequence, and the audio init it must overlap lasts only tens of ms.
    Start-Sleep -Milliseconds 25
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

function Assert-ExitLogged([string]$Name, [System.Diagnostics.Process]$Process) {
  $candidates = @($AppDataLog, (Join-Path $ExtractRoot 'log\latest.log'))
  foreach ($path in $candidates) {
    if (-not (Test-Path $path)) { continue }
    $content = Get-Content -Path $path -Raw
    if ($content -and $content.Contains('exit requested')) {
      Write-Host "   log OK: $path"
      return
    }
  }
  Collect-SmokeEvidence -Scenario $Name -Process $Process
  Fail "$Name`: no 'exit requested' entry in latest.log ($($candidates -join ', '))"
}

# The assertion every scenario shares: after WM_CLOSE the process must disappear.
function Invoke-CloseScenario {
  param(
    [string]$Name,
    [string]$ExePath,
    [hashtable]$Environment = @{},
    [int]$SettleSeconds = 0,
    [int]$CloseDelayMs = 0,
    [switch]$ExpectExitLog
  )

  Write-Host "== $Name =="
  $startedAt = Get-Date
  $proc = Start-App -ExePath $ExePath -Environment $Environment
  Write-Host "   pid=$($proc.Id)"

  $hwnd = Wait-ForWindow -Process $proc
  if ($hwnd -eq [IntPtr]::Zero) {
    $reason = if ($proc.HasExited) {
      "process exited with code $($proc.ExitCode)"
    } else {
      'process still running'
    }
    if (-not $proc.HasExited) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Collect-SmokeEvidence -Scenario $Name -Process $proc -Since $startedAt
    Fail "$Name`: pid $($proc.Id) never exposed a top-level window ($reason)"
  }

  if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }
  if ($CloseDelayMs -gt 0) { Start-Sleep -Milliseconds $CloseDelayMs }
  if ($proc.HasExited) {
    Collect-SmokeEvidence -Scenario $Name -Process $proc -Since $startedAt
    Fail "$Name`: app exited on its own before the window was closed (exit code $($proc.ExitCode))"
  }

  [void][Win32]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  if (-not $proc.WaitForExit($CloseWaitSeconds * 1000)) {
    # Ask for the dump while the process is still alive: WER only writes one for
    # a fault, and this is a hang.
    Save-HangDump -Process $proc
    Collect-SmokeEvidence -Scenario $Name -Process $proc -Since $startedAt
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Fail "$Name`: process $($proc.Id) still alive $CloseWaitSeconds s after WM_CLOSE (leftover process)"
  }
  Write-Host "   process exited, exit code=$($proc.ExitCode)"
  Show-ExitTrace -ProcessId $proc.Id

  if ($ExpectExitLog) { Assert-ExitLogged -Name $Name -Process $proc }
}

# Prints the Dart exit trace written synchronously next to the native one, so
# every attempt says how far the exit got and which BOOT step was in flight.
# (`$PID` is a read-only automatic variable, hence `ProcessId`.)
function Show-ExitTrace([int]$ProcessId) {
  $path = Join-Path $ExitTraceDir "exit_$ProcessId.log"
  if (-not (Test-Path $path)) {
    Write-Host '   (no exit trace)'
    return
  }
  Write-Host "   --- exit trace (pid $ProcessId) ---"
  Get-Content $path | ForEach-Object { Write-Host "   $_" }
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

# A startup crash produces no application log; keep the dump and the WER event so
# the failure report names the faulting module instead of only "no window".
Enable-CrashDumps

# 1. Idle close: the first frame is painted and the window is opaque by now, so this is
#    the plain "user closes a running app" path.
Invoke-CloseScenario -Name 'window close (idle)' -ExePath $exe.FullName `
  -SettleSeconds 12 -ExpectExitLog

# 2. Injected hang: the Dart side never answers the exit request, so only the exit
#    bounds can end the process -- the 5 s Dart fallback or the 5 s native watchdog.
#    Waiting for a settled app first is what makes this a fallback test rather than an
#    early-close one.
Invoke-CloseScenario -Name 'window close with stuck cleanup (fallback)' `
  -ExePath $exe.FullName -Environment @{ SSB_RUNNER_TEST_EXIT_HANG = '1' } `
  -SettleSeconds 12

# 3. Close during startup: the window exists before "application ready", so it is
#    closed while boot is still running.
#
#    This is the racy one: the audio init that must be overlapped lasts 28-411 ms,
#    so one delay value is one sample of that window. Sweep a few of them. Both
#    lists are overridable for a targeted local run.
$startupCloseDelaysMs = @(0, 20, 40, 80, 160)
if ($env:SSB_SMOKE_STARTUP_CLOSE_DELAYS_MS) {
  $startupCloseDelaysMs = @(
    $env:SSB_SMOKE_STARTUP_CLOSE_DELAYS_MS -split ',' |
      ForEach-Object { [int]$_.Trim() }
  )
}
$startupCloseRounds = 2
if ($env:SSB_SMOKE_STARTUP_CLOSE_ROUNDS) {
  $startupCloseRounds = [int]$env:SSB_SMOKE_STARTUP_CLOSE_ROUNDS
}

for ($round = 1; $round -le $startupCloseRounds; $round++) {
  foreach ($delay in $startupCloseDelaysMs) {
    Invoke-CloseScenario `
      -Name "window close during startup (delay=${delay}ms round $round)" `
      -ExePath $exe.FullName -CloseDelayMs $delay
  }
}

Write-Host 'Windows exit smoke test passed'
