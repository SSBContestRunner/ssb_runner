#!/usr/bin/env bash
#
# Smoke-tests the Linux artifacts on a clean Debian 12 (glibc 2.36) container:
#
#   1. the .deb installs (apt resolves its Depends) and every bundled object links;
#   2. every shipped object -- the .deb bundle as well as the extracted .AppImage,
#      including the libraries its maker copied into usr/lib -- stays within the
#      declared runtime floor;
#   3. both the installed app and the AppImage start under Xvfb and exit when the
#      window closes.
#
# Why the floor is compared against fixed versions (glibc 2.35 / GLIBCXX_3.4.30,
# i.e. Ubuntu 22.04) instead of the container's own: Debian 12 is newer (2.36)
# and would happily accept an artifact that no longer runs on our oldest
# supported target. That is exactly how issue #23 happened, and how the AppImage
# silently picked up GLIBC_2.35 through the libgcc_s.so.1 that
# flutter_app_packager copies out of the build runner. The bundled
# libsqlite3.so is a prebuilt download rather than something we compile, and it
# is dlopen()ed at runtime (package:sqlite3 -> DynamicLibrary.open), so `ldd` of
# the main binary cannot see drift either.
#
# Usage (from the repo root, as CI does): bash .github/scripts/smoke-test-debian.sh
# The script re-executes itself inside a debian:12 container to run the actual test.
set -euo pipefail
shopt -s nullglob

# Keep in sync with README.md and linux/packaging/deb/make_config.yaml.
declared_glibc=2.35
declared_glibcxx=3.4.30

# True if version $1 is strictly newer than $2 (both dotted numeric).
newer_than() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | sed -n '$p')" == "$1" ]]
}

# Highest version of family $2 (GLIBC / GLIBCXX) referenced by object $1.
max_version() {
  readelf --version-info --wide "$1" 2>/dev/null \
    | grep -oE "${2}_[0-9]+(\.[0-9]+)*" \
    | sed "s/^${2}_//" | sort -Vu | sed -n '$p' || true
}

# check_floors <label> <object>...
check_floors() {
  local label=$1
  local status=0 obj max
  shift
  for obj in "$@"; do
    [[ -f "$obj" ]] || continue
    max=$(max_version "$obj" GLIBC)
    if [[ -n "$max" ]] && newer_than "$max" "$declared_glibc"; then
      echo "::error::[$label] $(basename "$obj") needs GLIBC_$max but the declared floor is $declared_glibc"
      status=1
    fi
    max=$(max_version "$obj" GLIBCXX)
    if [[ -n "$max" ]] && newer_than "$max" "$declared_glibcxx"; then
      echo "::error::[$label] $(basename "$obj") needs GLIBCXX_$max but the declared floor is $declared_glibcxx"
      status=1
    fi
  done
  return $status
}

if [[ "${1:-}" == "--in-container" ]]; then
  deb="${2:?usage: $0 --in-container <path-to-deb> [path-to-AppImage]}"
  appimage="${3:-}"
  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  # apt resolves the Depends field, so an unsatisfiable entry (e.g. a target with
  # libc6 < 2.35) fails here instead of at runtime.
  apt-get install -y --no-install-recommends "$deb"
  apt-get install -y --no-install-recommends binutils   # readelf / strings

  # Resolve the install dir from the package's file list rather than assuming a name: the
  # deb maker copies the bundle to /opt/<binary> and postinst symlinks
  # /opt/<binary>/<binary> into /usr/bin.
  # No `head -1` here: closing the pipe early SIGPIPEs the upstream process, and
  # `set -o pipefail` would turn that into a fatal exit.
  app_dir=$(dpkg -L ssb-runner | sed -n 's#^\(/opt/[^/]*\)\(/\|$\)#\1#p' | sort -u | sed -n '1p')
  [[ -n "$app_dir" ]] || { echo "::error::ssb-runner installed nothing under /opt"; exit 1; }
  exe="$app_dir/$(basename "$app_dir")"
  [[ -x "$exe" ]] || { echo "::error::no executable at $exe"; exit 1; }
  echo "installed: $exe"

  # (1) The main binary declares RUNPATH=$ORIGIN/lib, so ldd needs that on the search path
  #     before it can resolve the bundled engine/plugins; it then covers their transitive
  #     deps too.
  missing=$(LD_LIBRARY_PATH="$app_dir/lib" ldd "$exe" | grep 'not found' || true)
  if [[ -n "$missing" ]]; then
    echo "::error::unresolved shared libraries:"
    echo "$missing"
    exit 1
  fi

  # (2) glibc / libstdc++ floor of every bundled object. Read-only: no object is
  #     executed, so the Android-only libdartjni.so and its libjvm dependency never
  #     come into play, and it does not depend on RUNPATH.
  host_glibc=$(ldd --version | sed -n '1s/.* //p')
  host_glibcxx=$(strings /usr/lib/*/libstdc++.so.6 2>/dev/null \
    | grep -oE 'GLIBCXX_[0-9.]+' | sort -Vu | sed -n '$p') || true
  host_glibcxx=${host_glibcxx#GLIBCXX_}
  echo "container provides: glibc $host_glibc, GLIBCXX_$host_glibcxx"
  echo "declared floor:     glibc $declared_glibc, GLIBCXX_$declared_glibcxx"
  if newer_than "$declared_glibc" "$host_glibc"; then
    echo "::error::container glibc $host_glibc is older than the declared floor $declared_glibc"
    exit 1
  fi
  if newer_than "$declared_glibcxx" "$host_glibcxx"; then
    echo "::error::container GLIBCXX_$host_glibcxx is older than the declared floor GLIBCXX_$declared_glibcxx"
    exit 1
  fi

  check_floors deb "$exe" "$app_dir"/lib/*.so*
  echo "deb floor checks passed"

  # The AppImage carries its own copies of libstdc++/libgcc_s (they are not part of
  # what we build, see the header comment), so it needs the same check, including
  # usr/lib.
  appimage_work=""
  if [[ -n "$appimage" ]]; then
    appimage_work=/tmp/appimage-smoke
    rm -rf "$appimage_work"
    mkdir -p "$appimage_work"
    cp "$appimage" "$appimage_work/app.AppImage"
    chmod +x "$appimage_work/app.AppImage"
    # --appimage-extract unpacks the squashfs and exits; it needs neither FUSE nor a display.
    ( cd "$appimage_work" && ./app.AppImage --appimage-extract > /dev/null )

    appimage_root="$appimage_work/squashfs-root"
    [[ -x "$appimage_root/ssb_runner" ]] ||
      { echo "::error::no executable ssb_runner inside the AppImage"; exit 1; }
    # Guards the packaging step that drops the JVM the Android-only libdartjni.so drags in.
    if [[ -e "$appimage_root/usr/lib/libjvm.so" ]]; then
      echo "::error::AppImage still bundles usr/lib/libjvm.so (trim-appimage-libjvm.sh did not run)"
      exit 1
    fi

    check_floors appimage "$appimage_root/ssb_runner" "$appimage_root"/lib/*.so* "$appimage_root"/usr/lib/*.so*
    echo "AppImage floor checks passed"
  fi

  # (3) Actually start the app. The checks above are static and would not notice a
  #     missing runtime dlopen() target, which is how libegl1/libgles2 were found to
  #     be absent from Depends. xvfb/xauth and the software rasteriser are
  #     harness-only: a real desktop supplies its own display and GL driver through
  #     the graphics stack.
  apt-get install -y --no-install-recommends xvfb xauth libgl1-mesa-dri

  set +e
  timeout 25 xvfb-run -a "$exe" > /tmp/app.log 2>&1
  rc=$?
  set -e
  # 124 = still running when the timeout fired, i.e. it started and stayed up. A container
  # has no sound card, so ALSA warnings on stderr are expected and not a failure.
  if [[ $rc -ne 124 && $rc -ne 0 ]]; then
    echo "::error::app exited early under Xvfb (rc=$rc)"
    sed -n '1,40p' /tmp/app.log
    exit 1
  fi
  echo "launch smoke: app started and stayed up (rc=$rc)"

  # (4) Closing the window must end the process (docs/design/desktop_exit_design.md). The
  #     app closes its own window at SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER seconds through
  #     window_manager (gtk_window_close), which is the same path as the window manager's
  #     close button; the container has no window manager to send that request from outside.
  #     124 here means the process outlived the whole run -- the "window gone, process stays"
  #     regression this guards against.
  set +e
  SSB_RUNNER_DISABLE_AUDIO=1 SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER=12 \
    timeout 40 xvfb-run -a "$exe" > /tmp/app-close.log 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 124 ]]; then
    echo "::error::process still alive 40 s after launch (window close did not end it)"
    sed -n '1,40p' /tmp/app-close.log
    exit 1
  fi
  echo "close smoke: process exited after window close (rc=$rc)"

  # (5) Same two launch checks for the AppImage. It runs through --appimage-extract-and-run
  #     because the container has no FUSE; the packaged AppRun then execs ssb_runner from
  #     the extracted directory, exactly as a mounted AppImage would.
  if [[ -n "$appimage_work" ]]; then
    set +e
    timeout 25 xvfb-run -a "$appimage_work/app.AppImage" --appimage-extract-and-run \
      > /tmp/appimage.log 2>&1
    rc=$?
    set -e
    if [[ $rc -ne 124 && $rc -ne 0 ]]; then
      echo "::error::AppImage exited early under Xvfb (rc=$rc)"
      sed -n '1,40p' /tmp/appimage.log
      exit 1
    fi
    echo "AppImage launch smoke: started and stayed up (rc=$rc)"

    set +e
    SSB_RUNNER_DISABLE_AUDIO=1 SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER=12 \
      timeout 40 xvfb-run -a "$appimage_work/app.AppImage" --appimage-extract-and-run \
      > /tmp/appimage-close.log 2>&1
    rc=$?
    set -e
    if [[ $rc -eq 124 ]]; then
      echo "::error::AppImage process still alive 40 s after launch (window close did not end it)"
      sed -n '1,40p' /tmp/appimage-close.log
      exit 1
    fi
    echo "AppImage close smoke: exited after window close (rc=$rc)"
  fi

  exit 0
fi

# --- runner side -------------------------------------------------------------
[[ -d artifacts ]] || { echo "::error::no artifacts/ directory (artifact download failed)"; exit 1; }
deb=$(find artifacts -name '*.deb' -print -quit)
appimage=$(find artifacts -name '*.AppImage' -print -quit)
[[ -n "$deb" ]] || { echo "::error::no .deb found under artifacts/"; exit 1; }
[[ -n "$appimage" ]] || { echo "::error::no .AppImage found under artifacts/"; exit 1; }

# Keep the paths relative to artifacts/: fastforge writes dist/<version>/<file>, so the
# artifacts are not at the mount root.
deb_rel=${deb#artifacts/}
appimage_rel=${appimage#artifacts/}
script_dir=$(cd "$(dirname "$0")" && pwd)
echo "smoke-testing $deb_rel and $appimage_rel on debian:12"
# The packages are amd64 (built on the x86_64 Linux runner), so pin the container too.
docker run --rm --platform linux/amd64 \
  -v "$PWD/artifacts:/artifacts:ro" \
  -v "$script_dir/$(basename "$0"):/smoke.sh:ro" \
  debian:12 bash /smoke.sh --in-container "/artifacts/$deb_rel" "/artifacts/$appimage_rel"
