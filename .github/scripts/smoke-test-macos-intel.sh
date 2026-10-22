#!/usr/bin/env bash
#
# Smoke-tests the macOS .dmg on Intel hardware (macos-15-intel, x86_64): mounts the disk
# image, fails if any binary the bundle loads lacks an x86_64 slice, then launches the app
# and requires it to stay up.
#
# Why this exists: the release .dmg is built on an Apple Silicon (macos-latest) runner and is
# universal only because Xcode's Release configuration defaults to ARCHS_STANDARD (arm64 +
# x86_64). Nothing in the repo pins that, so adding ONLY_ACTIVE_ARCH=YES or EXCLUDED_ARCHS
# would silently drop Intel support -- and building on Apple Silicon would not notice, since
# an arm64-only product builds fine there. This asserts the other direction on a real Intel
# host: the x86_64 slice is present and the app actually runs.
#
# Usage (from the repo root, as CI does): bash .github/scripts/smoke-test-macos-intel.sh
set -euo pipefail

[[ "$(uname -m)" == "x86_64" ]] || {
  echo "::error::expected an x86_64 runner, got $(uname -m)"
  exit 1
}

[[ -d artifacts ]] || { echo "::error::no artifacts/ directory (artifact download failed)"; exit 1; }
dmg=$(find artifacts -name '*.dmg' -print -quit)
[[ -n "$dmg" ]] || { echo "::error::no .dmg found under artifacts/"; exit 1; }
echo "smoke-testing $dmg on Intel (macOS $(sw_vers -productVersion), $(uname -m))"

# `timeout(1)` is GNU coreutils, which macOS runners do not ship. Without a deadline a stuck
# mount or a slow directory scan burns the job's whole timeout-minutes budget, and a job
# cancelled by that limit uploads no log at all (the log blob is missing, not just truncated),
# so the failure arrives with no diagnostics -- exactly what run 39726662271 did. Everything
# that can block goes through here instead, so a hang fails the step with its own message.
bounded() {
  local seconds=$1 label=$2 pid waited=0
  shift 2
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if ((waited >= seconds)); then
      echo "::error::$label did not finish within ${seconds}s"
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
}

# Mount to an explicit, empty directory so the volume name (which may contain spaces) never
# has to be parsed out of hdiutil's output.
mount_point=$(mktemp -d)
cleanup() {
  bounded 60 "unmounting $mount_point" \
    hdiutil detach "$mount_point" -force -quiet >/dev/null 2>&1 || true
  rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT

bounded 120 "mounting $(basename "$dmg")" \
  hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_point" >/dev/null ||
  { echo "::error::hdiutil could not mount $dmg"; exit 1; }

app=$(find "$mount_point" -maxdepth 1 -name '*.app' -print -quit)
[[ -n "$app" ]] || { echo "::error::no .app inside the dmg"; exit 1; }
echo "mounted app: $app"

# (1) Every Mach-O the app loads at startup must carry an x86_64 slice. That covers the main
#     binary, the engine (FlutterMacOS) and the plugins in Contents/Frameworks -- and the
#     Dart AOT snapshot in App.framework, which is compiled per architecture by two separate
#     gen_snapshot runs and lipo'd together, so it is exactly the piece most likely to drift.
status=0
check_x86_64() {
  local bin="$1"
  if lipo -info "$bin" 2>/dev/null | grep -q 'x86_64'; then
    echo "  ok   $(basename "$bin")"
  else
    echo "::error::$(basename "$bin") has no x86_64 slice: $(lipo -info "$bin" 2>&1)"
    status=1
  fi
}

exe="$app/Contents/MacOS/$(basename "$app" .app)"
[[ -x "$exe" ]] || { echo "::error::no executable at $exe"; exit 1; }
check_x86_64 "$exe"

for fw in "$app/Contents/Frameworks"/*.framework; do
  [[ -d "$fw" ]] || continue
  name=$(basename "$fw" .framework)
  # Versioned bundles keep the binary under Versions/A; flat bundles (sqlite3 here) do not.
  bin="$fw/Versions/A/$name"
  [[ -f "$bin" ]] || bin="$fw/$name"
  if [[ -f "$bin" ]]; then
    check_x86_64 "$bin"
  else
    echo "::error::no binary inside $(basename "$fw")"
    status=1
  fi
done
[[ $status -eq 0 ]] || exit 1
echo "architecture check passed: x86_64 present in every bundled binary"

# (2) Actually launch it. An arm64-only bundle fails at exec ("bad CPU type in executable"),
#     which only a real Intel host can observe, so the process must still be alive after a
#     grace period. The runner provides the GUI session the app needs.
#
#     The launch is retried: on run 36989183503 the app aborted mid-startup with a Dart VM
#     heap-corruption crash (rc=134) and then launched fine on a rerun of the very same
#     artifact, so a single early exit is a host flake, not proof the bundle is broken. Only
#     a launch that aborts on every attempt fails the job; each failure is still reported.
#
#     Liveness must not rely on `ps` alone: `ps -o state=` can transiently report no state at
#     all for a process that is still alive, which previously dropped the script into a bare
#     `wait` that blocked for 26+ minutes (run 37142104657). `kill -0` fails only once the pid
#     is truly gone, so it decides liveness; `ps` is consulted only to tell a running process
#     from a zombie that the shell has not reaped yet.
reap() {
  local pid="$1" i state
  # `wait` blocks for as long as the child is alive, so it is only reached once the pid is
  # certainly done -- either `kill -0` fails (the shell has reaped it) or the state is `Z`.
  for ((i = 0; i < 15; i++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null
      return $?
    fi
    state=$(ps -o state= -p "$pid" 2>/dev/null | tr -d ' ') || true
    if [[ "$state" == Z* ]]; then
      wait "$pid" 2>/dev/null
      return $?
    fi
    sleep 1
  done
  echo "::warning::pid $pid still running 15s after it was expected to have exited"
  return 1
}

# The release build keeps its own timeline in a file (lib/logging): stdout and stderr only
# ever carry the engine's two lines, so /tmp/app.log cannot say which boot step died. Print
# the tail of the newest app log after every failed launch, which is the only way to tell a
# crash in `soloud_init` from one after the window was shown.
dump_app_logs() {
  local bundle_id root file found=0
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$app/Contents/Info.plist" 2>/dev/null) || true
  # Mirrors lib/logging/log_paths.dart: application support, temporary dir, next to the
  # executable. Sandboxed releases see those under the app's container, so search both.
  for root in \
    "$HOME/Library/Containers/$bundle_id/Data/Library/Application Support" \
    "$HOME/Library/Containers/$bundle_id/Data/tmp" \
    "$HOME/Library/Application Support" \
    "${TMPDIR:-/tmp}/ssb_runner" \
    "$(dirname "$exe")/log"; do
    [[ -d "$root" ]] || continue
    # Bounded so an unexpectedly deep or slow tree cannot stall the step.
    while IFS= read -r -d '' file; do
      echo "--- app log: $file (last 120 lines) ---"
      tail -n 120 "$file" || true
      found=1
    done < <(bounded 10 "scanning $root" \
      find "$root" -maxdepth 5 -type f -name 'latest.log' -print0 2>/dev/null)
  done
  [[ $found -eq 1 ]] || echo "--- app log: no latest.log found (crash before the log sink opened?) ---"
}

# SoLoud's engine start-up runs on a worker isolate and, on this runner's VM, segfaults inside
# Apple's AVAudioSession (the VM's own audio daemon, audioanalyticsd, dies with an invalid code
# signature at the same moment). A native SIGSEGV cannot be caught by the app's Dart error
# handling, so it says nothing about the x86_64 bundle this job verifies -- the slice check
# above already covers the plugin. Skip audio for the launch check; the app logs that it did.
launch_env=(SSB_RUNNER_DISABLE_AUDIO=1)

attempts=3
rc=1
# Trace the launch section: a job killed by `timeout-minutes` uploads no log, so the xtrace
# in the live log is the only way to see which command a future hang stops on.
set -x
for ((attempt = 1; attempt <= attempts; attempt++)); do
  set +e
  env "${launch_env[@]}" "$exe" > /tmp/app.log 2>&1 &
  pid=$!
  sleep 20
  # `kill -0` succeeds for a not-yet-reaped zombie too, so `ps` is consulted as well -- but it
  # must not be the only signal, since it can come back empty for a process that is still up.
  state=$(ps -o state= -p "$pid" 2>/dev/null | tr -d ' ') || true
  if kill -0 "$pid" 2>/dev/null && [[ "$state" != Z* ]]; then
    echo "launch smoke: app started and stayed up on Intel (attempt $attempt/$attempts)"
    kill "$pid" 2>/dev/null
    sleep 2
    kill -9 "$pid" 2>/dev/null
    reap "$pid"
    rc=0
    set -e
    break
  fi
  reap "$pid"
  rc=$?
  set -e
  echo "::warning::app exited early on Intel (rc=$rc) on attempt $attempt/$attempts"
  sed -n '1,40p' /tmp/app.log
  # Whole-dump deadline, so three attempts cannot add up to more than the step budget.
  bounded 30 "collecting app logs" dump_app_logs || true
done
set +x
if [[ $rc -ne 0 ]]; then
  echo "::error::app exited early on Intel (rc=$rc) after $attempts attempts"
  # A crash leaves a report in DiagnosticReports whose faulting-thread backtrace names
  # the framework that died -- the only way to tell a SIGSEGV in Impeller/Metal from one
  # in a plugin. ReportCrash writes the .ips asynchronously, hence the short wait.
  sleep 5
  for dir in "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports; do
    # Only this app's reports: system daemons (audioanalyticsd etc.) also crash here and
    # their newest report would otherwise hide the one that matters.
    report=$(ls -t "$dir"/"$(basename "$app" .app)"*.ips 2>/dev/null | head -1) || true
    [[ -n "$report" ]] || continue
    echo "--- macOS crash report: $report ---"
    # The .ips is JSON, and the faulting thread's frames are what identify the dying
    # framework; printing the raw file would be truncated before they appear.
    python3 - "$report" <<'PY' || true
import json
import sys

with open(sys.argv[1], errors='replace') as handle:
    header, _, body = handle.read().partition('\n')
report = json.loads(body)

print('exception:', report.get('exception'))
print('termination:', report.get('termination'))
index = report.get('faultingThread', 0)
thread = report['threads'][index]
label = thread.get('name') or thread.get('queue') or '?'
print(f'faulting thread {index}: {label}')
for frame in thread.get('frames', [])[:40]:
    image = report['usedImages'][frame['imageIndex']]
    print(' ', image.get('name'), frame.get('symbol'), f"+{frame.get('imageOffset')}")
PY
  done
  exit 1
fi
