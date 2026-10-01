#!/usr/bin/env bash
#
# Smoke-tests the Linux .deb on a clean Debian 12 (glibc 2.36), our oldest supported
# target, failing if the package cannot be installed or if any bundled object needs a
# newer glibc/libstdc++ than Debian 12 provides.
#
# Why this exists: the bundle inherits the glibc of whatever machine builds it, and the
# bundled libsqlite3.so is a prebuilt download rather than something we compile, so its
# floor can silently drift above our targets -- that was issue #23. It is also dlopen()ed
# at runtime (package:sqlite3 -> DynamicLibrary.open), so `ldd` of the main binary cannot
# see the mismatch either.
#
# Usage (from the repo root, as CI does): bash .github/scripts/smoke-test-debian.sh
# The script re-executes itself inside a debian:12 container to run the actual test.
set -euo pipefail

# True if version $1 is strictly newer than $2 (both dotted numeric).
newer_than() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | sed -n '$p')" == "$1" ]]
}

if [[ "${1:-}" == "--in-container" ]]; then
  deb="${2:?usage: $0 --in-container <path-to-deb>}"
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

  # (2) glibc / libstdc++ floor of every bundled object. This is the #23 guard: it is
  #     read-only (no object is executed, so the Android-only libdartjni.so and its
  #     libjvm dependency never come into play) and it does not depend on RUNPATH.
  host_glibc=$(ldd --version | sed -n '1s/.* //p')
  host_glibcxx=$(strings /usr/lib/*/libstdc++.so.6 2>/dev/null \
    | grep -oE 'GLIBCXX_[0-9.]+' | sort -Vu | sed -n '$p') || true
  echo "target provides: glibc $host_glibc, $host_glibcxx"

  status=0
  for obj in "$exe" "$app_dir"/lib/*.so*; do
    for pair in "GLIBC:$host_glibc" "GLIBCXX:$host_glibcxx"; do
      name=${pair%%:*}
      host=${pair#*:}
      [[ -n "$host" ]] || continue
      # `|| true`: grep exits 1 when an object needs no version of this family (a C-only
      # library has no GLIBCXX entries), which pipefail would otherwise treat as fatal.
      max=$(readelf --version-info --wide "$obj" 2>/dev/null \
        | grep -oE "${name}_[0-9]+(\.[0-9]+)*" | sed "s/^${name}_//" | sort -Vu | sed -n '$p') || true
      [[ -n "$max" ]] || continue
      if newer_than "$max" "$host"; then
        echo "::error::$(basename "$obj") requires ${name}_${max} but Debian 12 only provides ${name}_${host}"
        status=1
      fi
    done
  done
  [[ $status -eq 0 ]] || exit 1

  echo "Debian 12 link/floor checks passed"

  # (3) Actually start the app. The checks above are static and would not notice a missing
  #     runtime dlopen() target, which is how libegl1/libgles2 were found to be absent from
  #     Depends. xvfb/xauth and the software rasteriser are harness-only: a real desktop
  #     supplies its own display and GL driver through the graphics stack.
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

  exit 0
fi

# --- runner side -------------------------------------------------------------
[[ -d artifacts ]] || { echo "::error::no artifacts/ directory (artifact download failed)"; exit 1; }
deb=$(find artifacts -name '*.deb' -print -quit)
[[ -n "$deb" ]] || { echo "::error::no .deb found under artifacts/"; exit 1; }

# Keep the path relative to artifacts/: fastforge writes dist/<version>/<file>.deb and
# upload-artifact preserves that layout, so the .deb is not at the mount root.
deb_rel=${deb#artifacts/}
script_dir=$(cd "$(dirname "$0")" && pwd)
echo "smoke-testing $deb_rel on debian:12"
# The package is amd64 (built on the x86_64 Linux runner), so pin the container too.
docker run --rm --platform linux/amd64 \
  -v "$PWD/artifacts:/artifacts:ro" \
  -v "$script_dir/$(basename "$0"):/smoke.sh:ro" \
  debian:12 bash /smoke.sh --in-container "/artifacts/$deb_rel"