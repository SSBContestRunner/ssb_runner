# Evidence collection shared by the Windows smoke tests.
#
# Why this exists: a crash before the first frame leaves no application log -- the
# file sink is only installed after the first frame -- so a failing smoke test used
# to report nothing but "no window" or "app exited early". Three sources survive a
# startup crash and are collected here:
#
#   * the Windows Error Reporting "Application Error" event (id 1000/1001), which
#     names the faulting module, its version and the fault offset without needing a
#     debugger on the runner;
#   * the native startup timeline in %TEMP%\ssb_runner_boot\boot_<pid>.log written
#     by windows/runner/startup_trace.cpp, which says how far the native startup got;
#   * a user-mode minidump written by the WER LocalDumps registry key, uploaded as an
#     artifact for a real stack trace.
#
# Everything lands in ./smoke-evidence, which the workflow uploads on failure.
# Nothing here runs on a passing scenario except Enable-CrashDumps.

Set-StrictMode -Version Latest

$script:EvidenceDir = Join-Path (Get-Location) 'smoke-evidence'
$script:NativeTraceDir = Join-Path $env:TEMP 'ssb_runner_boot'
$script:CrashDumpDir = Join-Path ([IO.Path]::GetTempPath()) 'ssb-smoke-crashdumps'
$script:AppLogDir = Join-Path $env:APPDATA 'com.ssbrunner\ssb_runner\log'

# Writes a minidump (type 1: module list + thread stacks, a few MB) whenever
# ssb_runner.exe faults. A full dump (type 2) would be hundreds of MB and the
# crash thread's stack is what identifies the faulting code.
function Enable-CrashDumps {
  $key = 'HKCU:\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps\ssb_runner.exe'
  New-Item -Path $key -Force | Out-Null
  New-ItemProperty -Path $key -Name 'DumpFolder' -PropertyType ExpandString `
    -Value $script:CrashDumpDir -Force | Out-Null
  New-ItemProperty -Path $key -Name 'DumpType' -PropertyType DWord -Value 1 `
    -Force | Out-Null
  New-Item -Path $script:CrashDumpDir -ItemType Directory -Force | Out-Null
  Write-Host "   crash dumps -> $script:CrashDumpDir"
}

function Save-EvidenceText([string]$Name, [string]$Text) {
  New-Item -Path $script:EvidenceDir -ItemType Directory -Force | Out-Null
  Set-Content -Path (Join-Path $script:EvidenceDir $Name) -Value $Text
}

function Copy-EvidenceFile([string]$Path) {
  if (-not (Test-Path $Path)) {
    return
  }
  New-Item -Path $script:EvidenceDir -ItemType Directory -Force | Out-Null
  Copy-Item -Path $Path -Destination $script:EvidenceDir -Force
}

# "Application Error" / "Windows Error Reporting" events recorded since the
# process started. Empty when the process did not fault (or WER has not logged
# yet).
function Get-FaultEvents([datetime]$Since) {
  $events = @()
  try {
    $events = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        Id = 1000, 1001
        StartTime = $Since
      } -ErrorAction Stop)
  } catch {
    return ''
  }
  $lines = foreach ($event in $events) {
    "=== $($event.TimeCreated.ToString('o')) id=$($event.Id) ==="
    $event.Message
    ''
  }
  return ($lines -join [Environment]::NewLine)
}

# Prints and saves everything that survives the crash. Safe to call for a
# process that is still running; it only reports what it finds.
function Collect-SmokeEvidence {
  param(
    [string]$Scenario,
    [System.Diagnostics.Process]$Process,
    [datetime]$Since = [datetime]::MinValue
  )

  if ($Since -eq [datetime]::MinValue) {
    $Since = (Get-Date).AddMinutes(-10)
  }

  $state = if ($Process.HasExited) { "exit=$($Process.ExitCode)" } else { 'still-running' }
  Write-Host "   --- evidence: $Scenario ($state) ---"
  Save-EvidenceText -Name "$Scenario.txt" `
    -Text "scenario=$Scenario pid=$($Process.Id) state=$state started=$Since"

  # WER writes the dump and the event asynchronously; poll briefly instead of
  # guessing a delay.
  $dumps = @()
  $deadline = (Get-Date).AddSeconds(20)
  do {
    $dumps = @(Get-ChildItem -Path $script:CrashDumpDir -Filter '*.dmp' -File `
        -ErrorAction SilentlyContinue)
    if ($dumps.Count -gt 0) {
      break
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  foreach ($dump in $dumps) {
    Copy-EvidenceFile $dump.FullName
    Write-Host "   dump: $($dump.FullName) ($([math]::Round($dump.Length / 1MB, 1)) MB)"
  }
  if ($dumps.Count -eq 0) {
    Write-Host '   (no crash dump)'
  }

  $faults = Get-FaultEvents -Since $Since
  if ($faults) {
    Save-EvidenceText -Name 'fault-events.txt' -Text $faults
    Write-Host $faults
  } else {
    Write-Host '   (no WER 1000/1001 event)'
  }

  $trace = Join-Path $script:NativeTraceDir "boot_$($Process.Id).log"
  if (Test-Path $trace) {
    Copy-EvidenceFile $trace
    Write-Host "   --- $trace ---"
    Get-Content $trace | ForEach-Object { Write-Host "   $_" }
  } else {
    Write-Host "   (no native trace at $trace)"
  }

  if (Test-Path $script:AppLogDir) {
    foreach ($file in Get-ChildItem -Path $script:AppLogDir -File -Recurse `
        -ErrorAction SilentlyContinue) {
      Copy-EvidenceFile $file.FullName
    }
    $latest = Join-Path $script:AppLogDir 'latest.log'
    if (Test-Path $latest) {
      Write-Host "   --- tail of $latest ---"
      Get-Content $latest -Tail 40 | ForEach-Object { Write-Host "   $_" }
    }
  } else {
    Write-Host "   (no application log at $script:AppLogDir)"
  }

  Write-Host '   --- end evidence ---'
}
