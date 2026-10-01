#!/usr/bin/env bash
#
# Smoke-tests the Linux .deb on a clean Debian 12 (glibc 2.36), our oldest supported
# target, failing if the package cannot be installed or its libraries cannot load.
#
# Why this exists: the bundle inherits the glibc of whatever machine builds it, and the
# bundled libsqlite3.so is dlopen()ed at runtime (package:sqlite3 -> DynamicLibrary.open),
# so a plain `ldd` of the main binary never sees a version mismatch. Issue #23 was exactly
# that, and it only surfaced on a user's Debian 12 machine.
#
# Usage (from the repo root, as CI does): bash .github/scripts/smoke-test-debian.sh
# The script re-executes itself inside a debian:12 container to run the actual test.
set -euo pipefail

if [[ "${1:-}" == "--in-container" ]]; then
  deb="${2:?usage: $0 --in-container <path-to-deb>}"
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  # apt resolves the Depends field, so an unsatisfiable entry (e.g. a target with
  # libc6 < 2.35) fails here instead of at runtime.
  apt-get install -y --no-install-recommends "$deb"

  # The deb maker's postinst symlinks the binary into /usr/bin.
  test -x /usr/bin/ssb-runner

  # (1) Unresolved shared libraries in the main binary.
  if ldd /opt/ssb-runner/ssb-runner | grep -q 'not found'; then
    echo "::error::ssb-runner has unresolved shared libraries"
    ldd /opt/ssb-runner/ssb-runner | grep 'not found'
    exit 1
  fi

  # (2) Load every bundled shared object the way the app does. A GLIBC/GLIBCXX version
  #     mismatch -- the #23 failure mode -- makes dlopen() fail right here.
  apt-get install -y --no-install-recommends python3
  python3 - <<'PY'
import ctypes
import glob
import sys

libs = sorted(glob.glob("/opt/ssb-runner/lib/*.so*"))
if not libs:
    sys.exit("no bundled shared libraries found under /opt/ssb-runner/lib")

failed = []
for path in libs:
    try:
        ctypes.CDLL(path)
        print(f"ok   {path}")
    except OSError as exc:
        print(f"FAIL {path}: {exc}")
        failed.append(path)

sys.exit(1 if failed else 0)
PY

  echo "Debian 12 link/load checks passed"

  # (3) Best-effort launch under a virtual display. Diagnostic only: a GPU-less container
  #     cannot always bring up GL, so a failure here is reported but never fatal.
  apt-get install -y --no-install-recommends xvfb libgl1-mesa-dri >/dev/null 2>&1 || true
  if command -v xvfb-run >/dev/null; then
    set +e
    timeout 25 xvfb-run -a /opt/ssb-runner/ssb-runner > /tmp/app.log 2>&1
    rc=$?
    set -e
    if [[ $rc -eq 0 || $rc -eq 124 ]]; then
      echo "launch smoke: app stayed up (rc=$rc)"
    else
      echo "::warning::launch smoke did not stay up (rc=$rc); container graphics may be the cause"
      sed -n '1,40p' /tmp/app.log
    fi
  fi

  exit 0
fi

# --- runner side -------------------------------------------------------------
[[ -d artifacts ]] || { echo "::error::no artifacts/ directory (artifact download failed)"; exit 1; }
deb=$(find artifacts -name '*.deb' -print -quit)
[[ -n "$deb" ]] || { echo "::error::no .deb found under artifacts/"; exit 1; }

script_dir=$(cd "$(dirname "$0")" && pwd)
echo "smoke-testing $(basename "$deb") on debian:12"
docker run --rm \
  -v "$PWD/artifacts:/artifacts:ro" \
  -v "$script_dir/$(basename "$0"):/smoke.sh:ro" \
  debian:12 bash /smoke.sh --in-container "/artifacts/$(basename "$deb")"