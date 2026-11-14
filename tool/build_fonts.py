#!/usr/bin/env python3
"""Rebuild the bundled font subsets from the UI character inventory.

The app ships subsetted Iosevka (Latin/digits/symbols) and Noto Sans SC (CJK)
so text renders with the same typefaces on every platform. Any character the UI
can show must exist in one of the shipped subsets, otherwise the text engine
falls back to a platform font per glyph: on Windows that is usually Microsoft
YaHei, which looks visibly different from Noto Sans SC (and only ships Regular
and Bold, so a Medium request is resolved to a different weight as well).

Inventory = printable ASCII + every non-ASCII character in lib/**/*.dart
(string literals, comments and the generated l10n files) + every string value
in lib/l10n/*.arb. Scanning whole files instead of parsing string literals is
deliberate: over-including a few comment-only characters costs a couple of
hundred bytes, while missing one costs a visual defect on Windows.

Pinned sources (do not change without re-checking the rendering):
  Noto Sans SC 2.004 (SIL OFL, see fonts/LICENSE-NotoSansSC.txt)
    https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/18_NotoSansSC.zip
  Iosevka 34.9.1 (SIL OFL, see fonts/LICENSE-Iosevka.txt)
    https://github.com/be5invis/Iosevka/releases/download/v34.9.1/PkgTTC-Iosevka-34.9.1.zip
    Face "Iosevka" Regular (searched by name, not by index).

Usage:
  pip install fonttools
  python3 tool/build_fonts.py --noto-dir <dir with NotoSansSC-*.otf> \
      --iosevka-ttc <Iosevka.ttc>

Run test/font_coverage_test.dart afterwards (or `flutter test`) to verify the
result and to keep future UI strings from drifting outside the subsets.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTCollection, TTFont

REPO = Path(__file__).resolve().parents[1]
FONTS = REPO / "fonts"

# Symbols the UI renders as text instead of an icon. Kept on Iosevka so they
# match the data typeface; every one of them must be present in the source.
IOSEVKA_SYMBOLS = {
    0x00A7,  # §
    0x00B7,  # ·
    0x00D7,  # ×
    0x2013,  # –
    0x2014,  # —
    0x2026,  # …
    0x2192,  # →
    0x2715,  # ✕ (only Iosevka has it, Noto Sans SC does not)
}

NOTO_WEIGHTS = {
    "Regular": ("NotoSansSC-Regular.otf", "NotoSansSC-Regular-sub.otf"),
    "Medium": ("NotoSansSC-Medium.otf", "NotoSansSC-Medium-sub.otf"),
    "Bold": ("NotoSansSC-Bold.otf", "NotoSansSC-Bold-sub.otf"),
}


def cmap_of(font: TTFont) -> set[int]:
    codepoints: set[int] = set()
    for table in font["cmap"].tables:
        if table.isUnicode():
            codepoints |= set(table.cmap.keys())
    return codepoints


def arb_strings(node: object) -> list[str]:
    if isinstance(node, str):
        return [node]
    if isinstance(node, dict):
        return [s for value in node.values() for s in arb_strings(value)]
    if isinstance(node, list):
        return [s for item in node for s in arb_strings(item)]
    return []


def inventory() -> set[int]:
    chars: set[int] = set(range(0x20, 0x7F))
    for path in sorted((REPO / "lib" / "l10n").glob("*.arb")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for text in arb_strings(data):
            chars |= {ord(ch) for ch in text}
    for path in sorted((REPO / "lib").rglob("*.dart")):
        chars |= {ord(ch) for ch in path.read_text(encoding="utf-8") if ord(ch) > 0x7F}
    # Control characters never get a glyph and must not enter the subset.
    return {c for c in chars if not (c < 0x20 or 0x7F <= c <= 0x9F)}


def unicodes_arg(codepoints: set[int]) -> str:
    parts: list[str] = []
    ordered = sorted(codepoints)
    start = previous = ordered[0]
    for codepoint in ordered[1:]:
        if codepoint == previous + 1:
            previous = codepoint
            continue
        parts.append(_range(start, previous))
        start = previous = codepoint
    parts.append(_range(start, previous))
    return ",".join(parts)


def _range(start: int, end: int) -> str:
    return f"U+{start:04X}" if start == end else f"U+{start:04X}-{end:04X}"


def find_iosevka_face(ttc: Path) -> int:
    collection = TTCollection(str(ttc), lazy=True)
    for index, font in enumerate(collection.fonts):
        names = {
            record.nameID: record.toUnicode()
            for record in font["name"].names
            if record.platformID == 3 and record.nameID in (2, 6)
        }
        if (
            names.get(6) == "Iosevka"
            and names.get(2) == "Regular"
            and font["OS/2"].usWeightClass == 400
        ):
            return index
    raise SystemExit(f'No "Iosevka" Regular face in {ttc}')


def subset(source: Path, output: Path, codepoints: set[int], face: int | None) -> None:
    command = [
        sys.executable,
        "-m",
        "fontTools.subset",
        str(source),
        f"--unicodes={unicodes_arg(codepoints)}",
        f"--output-file={output}",
    ]
    if face is not None:
        command.append(f"--font-number={face}")
    subprocess.run(command, check=True)
    print(f"  {output.name}: {output.stat().st_size / 1024:.0f} KiB")


def patch_typographic_names(path: Path, family: str, style: str) -> None:
    """Add name IDs 16/17 so every platform groups the weights as one family.

    Non-RIBBI weights keep a legacy family name of their own, which is what
    DirectWrite and the OpenType style-linking rules expect.
    """
    ribbi = style in ("Regular", "Bold")
    legacy_family = family if ribbi else f"{family} {style}"
    legacy_style = style if ribbi else "Regular"
    font = TTFont(path)
    for name_id, value in (
        (1, legacy_family),
        (2, legacy_style),
        (16, family),
        (17, style),
    ):
        font["name"].setName(value, name_id, 3, 1, 0x0409)
        font["name"].setName(value, name_id, 1, 0, 0)
    font.save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--noto-dir", required=True, type=Path)
    parser.add_argument("--iosevka-ttc", required=True, type=Path)
    args = parser.parse_args()

    chars = inventory()
    print(f"Inventory: {len(chars)} code points")

    noto_source = TTFont(str(args.noto_dir / "NotoSansSC-Regular.otf"))
    noto_covered = cmap_of(noto_source)
    iosevka_face = find_iosevka_face(args.iosevka_ttc)
    iosevka_source = TTCollection(str(args.iosevka_ttc), lazy=True).fonts[iosevka_face]
    iosevka_covered = cmap_of(iosevka_source)

    unavailable_symbols = sorted(IOSEVKA_SYMBOLS - iosevka_covered)
    if unavailable_symbols:
        raise SystemExit(
            "Iosevka cannot render: " + " ".join(f"U+{c:04X}" for c in unavailable_symbols)
        )

    # Ownership rule: Iosevka keeps ASCII and the UI symbol set; everything else
    # (CJK, kana, any remaining symbol the source provides) belongs to Noto.
    iosevka_chars = ({c for c in chars if c < 0x7F} | IOSEVKA_SYMBOLS) & iosevka_covered
    noto_chars = (chars | IOSEVKA_SYMBOLS) & noto_covered

    uncovered = sorted(c for c in chars if c not in noto_covered and c not in iosevka_covered)
    if uncovered:
        raise SystemExit(
            "Source fonts cannot render: " + " ".join(f"U+{c:04X}" for c in uncovered)
        )

    print("Iosevka subset:")
    subset(args.iosevka_ttc, FONTS / "Iosevka-Regular-sub.ttf", iosevka_chars, iosevka_face)

    print("Noto Sans SC subsets:")
    for style, (source_name, output_name) in NOTO_WEIGHTS.items():
        output = FONTS / output_name
        subset(args.noto_dir / source_name, output, noto_chars, face=None)
        patch_typographic_names(output, "Noto Sans SC", style)

    # Verify the regenerated assets, not the sources.
    shipped = cmap_of(TTFont(str(FONTS / "Iosevka-Regular-sub.ttf")))
    for _, output_name in NOTO_WEIGHTS.values():
        shipped |= cmap_of(TTFont(str(FONTS / output_name)))
    missing = sorted(chars - shipped)
    if missing:
        raise SystemExit(
            "Regenerated subsets still miss: " + " ".join(f"U+{c:04X}" for c in missing)
        )
    print(f"Coverage OK: all {len(chars)} code points are in the shipped subsets")


if __name__ == "__main__":
    main()
