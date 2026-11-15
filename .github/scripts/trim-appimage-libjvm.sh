#!/usr/bin/env bash
#
# Removes the build runner's libjvm.so from the packaged AppImages.
#
# flutter_app_packager copies the ldd dependencies of every bundled .so into
# usr/lib. The Linux bundle contains the Android-only libdartjni.so, which links
# libjvm.so; on a runner with a JDK installed that resolves to the host JVM, so
# ~24 MB of Java runtime ships inside the AppImage even though nothing ever
# dlopen()s libdartjni.so on Linux. Both the deb and the zip only carry
# libdartjni.so itself, so this is AppImage-specific.
#
# The AppImage has no exclusion option, so extract the AppDir, drop the file and
# repack with the same appimagetool invocation the packager uses. The smoke test
# (smoke-test-debian.sh) asserts the result no longer contains it and still
# starts; that runs before the release job, so a broken repack cannot ship.
#
# Usage (from the repo root, as CI does, with appimagetool on PATH):
#   bash .github/scripts/trim-appimage-libjvm.sh
set -euo pipefail
shopt -s nullglob

trim_one() {
  local appimage=$1
  local work=$2
  local before after

  cp "$appimage" "$work/app.AppImage"
  chmod +x "$work/app.AppImage"
  # --appimage-extract needs neither FUSE nor a display; it prints the AppDir name.
  ( cd "$work" && ./app.AppImage --appimage-extract > /dev/null )

  local appdir="$work/squashfs-root"
  if [[ ! -f "$appdir/usr/lib/libjvm.so" ]]; then
    # A runner without a JDK, or a packager that stops copying it: nothing to do.
    echo "$(basename "$appimage"): no usr/lib/libjvm.so bundled, leaving it unchanged"
    return 0
  fi

  before=$(stat -c %s "$appimage")
  rm -f "$appdir/usr/lib/libjvm.so"
  ARCH=x86_64 appimagetool --no-appstream "$appdir" "$work/trimmed.AppImage" > /dev/null
  mv "$work/trimmed.AppImage" "$appimage"

  after=$(stat -c %s "$appimage")
  echo "$(basename "$appimage"): dropped usr/lib/libjvm.so, $before -> $after bytes"
}

appimages=(dist/*/*.AppImage dist/*.AppImage)
if [[ ${#appimages[@]} -eq 0 ]]; then
  echo "::error::no .AppImage under dist/ -- nothing to trim"
  exit 1
fi

for appimage in "${appimages[@]}"; do
  work=$(mktemp -d)
  if ! trim_one "$appimage" "$work"; then
    rm -rf "$work"
    exit 1
  fi
  rm -rf "$work"
done
