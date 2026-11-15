# Installs Inno Setup 6 when the runner image lacks it, then copies the two
# vendored unofficial translations into the compiler's Languages\ directory.
#
# Why this exists as a script: windows/packaging/exe/installer.iss compiles four
# languages. Inno Setup's own setup.exe ships only official translations under
# Languages\ (Japanese included); Simplified/Traditional Chinese are unofficial
# translations that exist only in the issrc repository
# (Files\Languages\Unofficial\), so neither a fresh winget install nor a forced
# reinstall can provide them. The two files are vendored under
# windows/packaging/exe/languages/ and referenced with the compiler: prefix --
# the only way to hand ISCC a file outside the rendered script's own directory.
#
# Both the tag package build (Package (windows)) and the PR dry run
# (Validate packaging (windows)) must see the identical compiler layout, so the
# step lives here instead of being copied into two workflow jobs that can drift.
#
# Usage (from the repo root): pwsh .github/scripts/ensure-inno-setup.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) {
  Write-Host 'Inno Setup 6 not found; installing via winget'
  winget install --id JRSoftware.InnoSetup -e --silent --accept-package-agreements --accept-source-agreements
}
if (-not (Test-Path $iscc)) { throw "ISCC.exe not found at $iscc" }

$innoDir = Split-Path $iscc -Parent
$languagesDir = Join-Path $innoDir 'Languages'

# The vendored files come from jrsoftware/issrc tag is-6_7_3:
#   ChineseSimplified.isl  7d544b9bb1d142cfa11f2e5d3cc8abe2e55f8e066c5124e3772675aa236e1278
#   ChineseTraditional.isl ab22b0ebf82969d1c9a7208e0e9f60e5119c0c95b9dacc00eb8e5582c7d3c604
foreach ($name in @('ChineseSimplified.isl', 'ChineseTraditional.isl')) {
  $source = Join-Path 'windows/packaging/exe/languages' $name
  if (-not (Test-Path $source)) { throw "missing vendored language file: $source" }
  Copy-Item -Path $source -Destination (Join-Path $languagesDir $name) -Force
}

$requiredLanguageFiles = @(
  'Default.isl',
  'Languages\Japanese.isl',
  'Languages\ChineseSimplified.isl',
  'Languages\ChineseTraditional.isl'
)
$missing = @($requiredLanguageFiles | Where-Object { -not (Test-Path (Join-Path $innoDir $_)) })
if ($missing.Count -gt 0) {
  throw "Inno Setup at $innoDir is missing language files required by windows/packaging/exe/installer.iss: $($missing -join ', ')"
}
Write-Host "ISCC -> $iscc"

# Record the compiler version in the log: runner images change Inno Setup on
# their own schedule, and a version line is what tells a template bug apart from
# a compiler behaviour change.
& $iscc /? | Select-Object -First 3

Write-Host 'Inno Setup language files:'
Get-ChildItem -Path $languagesDir -Recurse -Filter '*.isl' |
  ForEach-Object { Write-Host "  $($_.FullName.Substring($innoDir.Length + 1))" }
