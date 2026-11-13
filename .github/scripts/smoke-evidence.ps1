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
#   * the Dart exit trace in the same directory (`exit_<pid>.log`), written
#     synchronously so it survives a process that hangs while exiting;
#   * a user-mode minidump written by the WER LocalDumps registry key, uploaded as an
#     artifact for a real stack trace. A process that hangs (rather than faults) never
#     gets one from WER, so the smoke test asks for a dump before killing it.
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

# Captures a dump of a process that is still alive after WM_CLOSE.
#
# WER only writes a dump for a fault, so a hang leaves nothing behind unless the
# test asks for one while the process is still breathing. `mini` (MiniDumpNormal)
# keeps every thread's stack and the module list without the heap, which is what
# is needed to see who is blocked and small enough to upload.
function Save-HangDump([System.Diagnostics.Process]$Process) {
  New-Item -Path $script:EvidenceDir -ItemType Directory -Force | Out-Null
  $dump = Join-Path $script:EvidenceDir "hang_$($Process.Id).dmp"
  Write-Host "   --- capturing hang dump: $dump ---"

  # Thread bookkeeping is always available and already narrows down who is
  # blocked (state / wait reason) even before the dump is read.
  try {
    $threads = $Process.Threads |
      Select-Object Id, ThreadState, WaitReason, StartTime, TotalProcessorTime
    Save-EvidenceText -Name "hang_$($Process.Id)-threads.txt" `
      -Text ($threads | Format-Table -AutoSize | Out-String -Width 200)
  } catch {
    Write-Host "   thread snapshot failed: $_"
  }

  $procdump = Get-Command procdump -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  try {
    if ($procdump) {
      & $procdump.Source -accepteula -ma $Process.Id $dump 2>&1 | Out-Null
    } else {
      $rundll = Join-Path $env:WINDIR 'System32\rundll32.exe'
      & $rundll 'C:\Windows\System32\comsvcs.dll,MiniDump' `
        $Process.Id $dump mini 2>&1 | Out-Null
    }
  } catch {
    Write-Host "   hang dump failed: $_"
  }

  if (-not (Test-Path $dump)) {
    Write-Host '   (no hang dump produced)'
    return
  }
  Write-Host "   hang dump: $dump ($([math]::Round((Get-Item $dump).Length / 1MB, 1)) MB)"

  # Symbolised stacks make the dump readable without a Windows debugger at hand.
  $cdb = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Debuggers\x64\cdb.exe'
  if (-not (Test-Path $cdb)) {
    $cdb = Join-Path $env:ProgramFiles 'Windows Kits\10\Debuggers\x64\cdb.exe'
  }
  if (-not (Test-Path $cdb)) {
    Write-Host '   (no cdb; stacks must be read from the dump)'
    return
  }
  $stacks = Join-Path $script:EvidenceDir "hang_$($Process.Id)-stacks.txt"
  try {
    & $cdb -z $dump `
      -y "srv*$env:TEMP\ssb-symbols*https://msdl.microsoft.com/download/symbols" `
      -c '~*kn;q' 2>&1 | Set-Content -Path $stacks
    Write-Host "   --- thread stacks ($stacks) ---"
    Get-Content $stacks | ForEach-Object { Write-Host "   $_" }
  } catch {
    Write-Host "   stack walk failed: $_"
  }
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

  # The Dart exit-path trace (`exit_<pid>.log`) sits next to the native one and
  # is written synchronously, so it survives a process that never finishes
  # exiting.
  $exitTrace = Join-Path $script:NativeTraceDir "exit_$($Process.Id).log"
  if (Test-Path $exitTrace) {
    Copy-EvidenceFile $exitTrace
    Write-Host "   --- $exitTrace ---"
    Get-Content $exitTrace | ForEach-Object { Write-Host "   $_" }
  } else {
    Write-Host "   (no exit trace at $exitTrace)"
  }

  $appLogs = Join-Path $script:AppLogDir 'latest.log'
  if (Test-Path $appLogs) {
    Write-Host "   --- full $appLogs ---"
    Get-Content $appLogs | ForEach-Object { Write-Host "   $_" }
  }

  if (Test-Path $script:AppLogDir) {
    foreach ($file in Get-ChildItem -Path $script:AppLogDir -File -Recurse `
        -ErrorAction SilentlyContinue) {
      Copy-EvidenceFile $file.FullName
    }
  } else {
    Write-Host "   (no application log at $script:AppLogDir)"
  }

  Write-Host '   --- end evidence ---'
}
