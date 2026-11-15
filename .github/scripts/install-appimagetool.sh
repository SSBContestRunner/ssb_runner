#!/usr/bin/env bash
# Installs the appimagetool build the packager must use.
#
# Pinned by sha256 instead of following `continuous`: build 370 changed the
# AppDir permission check from warnings to a fatal error and broke the libjvm
# trim (docs/research/ci-run-43677974432-failure-analysis.md). The packager and
# the trim script both run this binary, so an unpinned update changes what
# ships. If upstream republishes `continuous`, this script fails on the checksum
# instead of drifting silently; to upgrade, verify the new build and update the
# digest below.
#
# One copy for both jobs (Package (linux) and Validate packaging (linux)): two
# copies would be two pins that silently disagree.
#
# Usage (from the repository root): bash .github/scripts/install-appimagetool.sh

set -euo pipefail

APPIMAGETOOL_SHA256=e8c1169c4af66c3184d7ee110713d4be04befe671fa358e2c1591ee840553b03

curl -fsSL --retry 3 --retry-delay 2 -o appimagetool \
  https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
echo "$APPIMAGETOOL_SHA256  appimagetool" | sha256sum -c -
chmod +x appimagetool
sudo mv appimagetool /usr/local/bin/appimagetool
