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

# Mount to an explicit, empty directory so the volume name (which may contain spaces) never
# has to be parsed out of hdiutil's output.
mount_point=$(mktemp -d)
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_point" >/dev/null
trap 'hdiutil detach "$mount_point" -force -quiet >/dev/null 2>&1 || true; rmdir "$mount_point" 2>/dev/null || true' EXIT

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
#     Reaping must stay bounded: a bare `wait` blocks as long as the process is alive, and
#     run 37142104657 hung for 26+ minutes because the liveness probe below found no state
#     for a process that was in fact still running, so it fell through to `wait`. `ps`
#     reports `Z` for a zombie and nothing once the shell has reaped it; both mean done.
reap() {
  local pid="$1" i state
  for ((i = 0; i < 10; i++)); do
    state=$(ps -o state= -p "$pid" 2>/dev/null | tr -d ' ') || true
    if [[ -z "$state" || "$state" == Z* ]]; then
      wait "$pid" 2>/dev/null
      return $?
    fi
    sleep 1
  done
  echo "::warning::pid $pid still running 10s after it was expected to have exited"
  return 1
}

attempts=3
rc=1
for ((attempt = 1; attempt <= attempts; attempt++)); do
  set +e
  "$exe" > /tmp/app.log 2>&1 &
  pid=$!
  sleep 20
  # `kill -0` also succeeds for a not-yet-reaped zombie, so inspect the process state instead.
  state=$(ps -o state= -p "$pid" 2>/dev/null | tr -d ' ')
  if [[ -n "$state" && "$state" != Z* ]]; then
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
done
if [[ $rc -ne 0 ]]; then
  echo "::error::app exited early on Intel (rc=$rc) after $attempts attempts"
  exit 1
fi
