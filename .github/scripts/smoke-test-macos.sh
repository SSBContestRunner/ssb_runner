#!/usr/bin/env bash
#
# Smoke-tests the packaged macOS app (.dmg): closing the window must end the process.
#
# Why this exists: on Windows the runner destroys the engine inside WM_DESTROY and only
# then posts WM_QUIT, so a blocked teardown left the window gone but the process alive
# (docs/design/desktop_exit_design.md). The macOS runner has its own teardown order, and
# this asserts the same user-visible outcome: after the close, nothing is left running.
#
# The close comes from inside the app: SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER seconds after
# startup it calls window_manager.close(), which is [NSWindow performClose] -- the exact
# path of the red button. There is no reliable external equivalent on macOS in CI
# (AppleScript would need Accessibility/automation permissions that a runner cannot grant).
#
# Two scenarios: a plain close, and one where the Dart side never answers the exit request
# (SSB_RUNNER_TEST_EXIT_HANG), which only the in-app fallback can end.
#
# Usage (from the repo root, as CI does): bash .github/scripts/smoke-test-macos.sh
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

# Waits for the process to disappear, either by exiting or by becoming a zombie.
wait_for_exit() {
  local pid="$1" deadline="$2"
  while ((SECONDS < deadline)); do
    if ! kill -0 "$pid" 2>/dev/null; then return 0; fi
    if [[ "$(ps -p "$pid" -o state= 2>/dev/null | tr -d '[:space:]')" == Z* ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

[[ -d artifacts ]] || fail 'no artifacts/ directory (artifact download failed)'
dmg=$(find artifacts -name '*.dmg' -print -quit)
[[ -n "$dmg" ]] || fail 'no .dmg found under artifacts/'

mount=/tmp/ssb-macos-dmg
work=/tmp/ssb-macos-app
rm -rf "$mount" "$work"
mkdir -p "$mount" "$work"
hdiutil attach "$dmg" -nobrowse -quiet -mountpoint "$mount"
trap 'hdiutil detach "$mount" -quiet || true' EXIT

src_app=$(find "$mount" -maxdepth 1 -name '*.app' -print -quit)
[[ -n "$src_app" ]] || fail "no .app on $dmg"
ditto "$src_app" "$work/"
hdiutil detach "$mount" -quiet
trap - EXIT

app=$(find "$work" -maxdepth 1 -name '*.app' -print -quit)
exe_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")
exe="$app/Contents/MacOS/$exe_name"
[[ -x "$exe" ]] || fail "no executable at $exe"
echo "smoke-testing $exe"

# The app closes its window at 12 s; 6 s gives it time to boot, and the whole scenario
# gets 40 s (12 + 5 s fallback + margin). Staying alive past that is the regression.
run_close_scenario() {
  local name="$1" extra_env="$2" pid rc=0
  echo "== $name =="

  # shellcheck disable=SC2086 # $extra_env is a list of VAR=value words, empty is fine.
  env SSB_RUNNER_DISABLE_AUDIO=1 SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER=12 $extra_env \
    "$exe" >"/tmp/$name.log" 2>&1 &
  pid=$!

  sleep 6
  kill -0 "$pid" 2>/dev/null || fail "$name: app exited before the close hook ran"

  if ! wait_for_exit "$pid" $((SECONDS + 34)); then
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    sed -n '1,40p' "/tmp/$name.log"
    fail "$name: process still alive 40 s after launch (window close did not end it)"
  fi

  wait "$pid" 2>/dev/null || rc=$?
  case "$rc" in
    0) echo '   process exited' ;;
    143) echo '   process terminated by the 5 s fallback' ;;
    *) echo "   process exited, code=$rc" ;;
  esac
}

run_close_scenario 'macos-window-close' ''
run_close_scenario 'macos-window-close-hang' 'SSB_RUNNER_TEST_EXIT_HANG=1'

echo 'macOS exit smoke test passed'
