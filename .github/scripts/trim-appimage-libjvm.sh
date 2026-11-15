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
# Two things this script must not rely on:
#   - --appimage-extract does not restore the directory modes stored in the
#     squashfs: every extracted directory ends up 0700. appimagetool (build 370+)
#     treats "other has no r/x" on a directory as a fatal AppDir error, so the
#     AppDir is normalised with `chmod -R a+rX` before repacking.
#   - an AppImage that did not shrink is a failed repack, not a success. The
#     product assertions below fail the step instead of printing a green line.
#
# Like every "transform/trim a packaged artifact" script here, it asserts both
# that the new artifact exists and that it changed as expected (C3 in
# docs/research/ci-run-43677974432-failure-analysis.md).
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
  [[ -d "$appdir" ]] ||
    { echo "::error::--appimage-extract produced no $appdir for $(basename "$appimage")"; exit 1; }
  # The extraction loses the 0755 modes recorded in the image; appimagetool rejects
  # directories the other user cannot read/traverse. `X` only grants execute where
  # it already exists (directories and executable files), so data files keep 0644.
  chmod -R a+rX "$appdir"

  if [[ ! -f "$appdir/usr/lib/libjvm.so" ]]; then
    # A runner without a JDK, or a packager that stops copying it: nothing to do.
    echo "$(basename "$appimage"): no usr/lib/libjvm.so bundled, leaving it unchanged"
    return 0
  fi

  before=$(stat -c %s "$appimage")
  rm -f "$appdir/usr/lib/libjvm.so"
  ARCH=x86_64 appimagetool --no-appstream "$appdir" "$work/trimmed.AppImage" > /dev/null

  [[ -s "$work/trimmed.AppImage" ]] ||
    { echo "::error::appimagetool produced no AppImage for $(basename "$appimage")"; exit 1; }
  mv "$work/trimmed.AppImage" "$appimage"

  after=$(stat -c %s "$appimage")
  # Dropping a ~24 MB library must make the image smaller; an unchanged size means
  # the repack silently kept the original (which is how run 43677974432 shipped a
  # libjvm.so-free log line with the file still inside).
  [[ "$after" -lt "$before" ]] ||
    { echo "::error::repack did not shrink $(basename "$appimage") ($before -> $after bytes)"; exit 1; }
  echo "$(basename "$appimage"): dropped usr/lib/libjvm.so, $before -> $after bytes"
}

appimages=(dist/*/*.AppImage dist/*.AppImage)
if [[ ${#appimages[@]} -eq 0 ]]; then
  echo "::error::no .AppImage under dist/ -- nothing to trim"
  exit 1
fi

for appimage in "${appimages[@]}"; do
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  # Called directly, not as `if ! trim_one ...`: bash disables errexit for the whole
  # body of a function invoked in a condition, so a failed appimagetool/mv would be
  # swallowed and the script would still exit 0.
  trim_one "$appimage" "$work"
  rm -rf "$work"
  trap - EXIT
done
