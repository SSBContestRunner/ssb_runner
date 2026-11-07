"""Rebuild the bundled callsign pool from SCP.DB plus the existing pool.

Data sources
------------
* SCP.DB: the Supercheck Partial database (SQLite) published by
  https://www.supercheckpartial.com/ . The ``callsigns`` table carries
  ``annual_rate`` (sightings per year) and a ``modes`` bitmask where bit 1
  (value 2) means Phone. The ``metadata`` table carries ``generated`` (ISO-8601
  UTC timestamp of the snapshot), ``callsigns`` (row count) and
  ``total_qsos``.
* Existing pool: the previously bundled ``assets/callsign/callsigns.txt``.
  It is unioned in so portable variants (``/P``, ``/M`` ...) and callsigns
  below the SCP rate threshold are not lost.

Selection rules (agreed defaults)
---------------------------------
* Union of SCP and the existing pool.
* SCP side: Phone only (``modes & 2 != 0``) unless ``--all-modes`` is given.
* SCP side: ``annual_rate >= --min-rate`` (default 100).
* Every entry is normalised (trim, uppercase, drop anything outside
  ``A-Z0-9/``), deduplicated and sorted, one callsign per line, no header.

The snapshot date of the SCP database is read from ``metadata.generated`` and
echoed in the summary so a future refresh can be checked against the file.

Pipeline
--------
1. This script builds the raw union of SCP and the existing pool.
2. ``dart run tool/prune_callsigns.dart`` drops the callsigns that the DXCC
   prefix table cannot resolve, using the app's own lookup implementation.
3. The pruned file is the bundled ``assets/callsign/callsigns.txt``.

Always run both steps in that order, and point ``--existing`` at the pool as it
was before pruning (for the bundled file that is the submodule HEAD copy,
``git -C assets show HEAD:callsign/callsigns.txt``). Feeding the already pruned
file back in loses callsigns that only ever existed in the old pool, because
SCP does not carry them. With the pre-prune baseline the pair is repeatable:
a second run produces a byte-identical file and the prune step removes nothing.

Usage
-----
    python3 tool/generate_callsign_pool.py \
        --scp /path/to/SCP.DB \
        --existing assets/callsign/callsigns.txt \
        --min-rate 100 \
        --phone-only \
        --out assets/callsign/callsigns.txt
    dart run tool/prune_callsigns.dart assets/callsign/callsigns.txt
"""

import argparse
import datetime as dt
import re
import sqlite3
import sys

PHONE_BIT = 2
ILLEGAL_RE = re.compile(r"[^A-Z0-9/]")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--scp", required=True, help="path to SCP.DB (SQLite)")
    parser.add_argument(
        "--existing",
        required=True,
        help="existing callsign pool used as the union baseline",
    )
    parser.add_argument(
        "--min-rate",
        type=int,
        default=100,
        help="minimum SCP annual_rate for inclusion (default: 100)",
    )
    parser.add_argument(
        "--phone-only",
        dest="phone_only",
        action="store_true",
        default=True,
        help="keep only SCP callsigns seen on Phone (modes & 2), default on",
    )
    parser.add_argument(
        "--all-modes",
        dest="phone_only",
        action="store_false",
        help="keep SCP callsigns regardless of mode",
    )
    parser.add_argument("--out", required=True, help="output pool path")
    return parser.parse_args(argv)


def normalise(raw):
    """Return (normalised_callsign, had_illegal_chars)."""
    cleaned = raw.strip().upper()
    fixed = ILLEGAL_RE.sub("", cleaned)
    return fixed, fixed != cleaned


def load_existing(path, stats):
    entries = []
    for line in open(path, encoding="utf-8"):
        raw = line.strip()
        if not raw:
            continue
        fixed, dirty = normalise(raw)
        if dirty:
            stats["illegal_cleaned"] += 1
        if fixed:
            entries.append(fixed)
        else:
            stats["empty_dropped"] += 1
    return entries


def load_scp(path, min_rate, phone_only, stats):
    conn = sqlite3.connect(path)
    try:
        meta = dict(conn.execute("select key, value from metadata"))
        stats["scp_generated"] = meta.get("generated", "unknown")
        stats["scp_callsigns"] = meta.get("callsigns", "unknown")
        stats["scp_total_qsos"] = meta.get("total_qsos", "unknown")

        rows = conn.execute(
            "select callsign, annual_rate, modes from callsigns"
        ).fetchall()
    finally:
        conn.close()

    selected = []
    for callsign, rate, modes in rows:
        stats["scp_total"] += 1
        if phone_only and (modes & PHONE_BIT) == 0:
            stats["scp_non_phone_excluded"] += 1
            continue
        if rate < min_rate:
            stats["scp_low_rate_excluded"] += 1
            continue
        fixed, dirty = normalise(callsign)
        if dirty:
            stats["illegal_cleaned"] += 1
        if fixed:
            selected.append(fixed)
        else:
            stats["empty_dropped"] += 1
    stats["scp_selected"] = len(selected)
    return selected


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    stats = {
        "scp_total": 0,
        "scp_non_phone_excluded": 0,
        "scp_low_rate_excluded": 0,
        "scp_selected": 0,
        "illegal_cleaned": 0,
        "empty_dropped": 0,
    }

    scp_entries = load_scp(args.scp, args.min_rate, args.phone_only, stats)
    existing_entries = load_existing(args.existing, stats)

    existing_set = set(existing_entries)
    scp_set = set(scp_entries)
    stats["scp_duplicated_with_existing"] = len(scp_set & existing_set)
    union = sorted(existing_set | scp_set)

    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        for callsign in union:
            fh.write(f"{callsign}\n")

    slash = sum("/" in callsign for callsign in union)
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")

    print(f"generated at            : {now}")
    print(f"SCP metadata.generated  : {stats['scp_generated']}")
    print(f"SCP metadata.callsigns  : {stats['scp_callsigns']}")
    print(f"SCP metadata.total_qsos : {stats['scp_total_qsos']}")
    print(f"SCP rows read           : {stats['scp_total']}")
    print(
        "  non-Phone excluded    : "
        f"{stats['scp_non_phone_excluded']} (phone_only={args.phone_only})"
    )
    print(
        f"  annual_rate < {args.min_rate} excluded : "
        f"{stats['scp_low_rate_excluded']}"
    )
    print(f"  selected              : {stats['scp_selected']}")
    print(f"existing pool entries   : {len(existing_entries)}")
    print(f"SCP dup of existing     : {stats['scp_duplicated_with_existing']}")
    print(f"union total             : {len(union)}")
    print(f"  contains slash        : {slash}")
    print(f"illegal chars cleaned   : {stats['illegal_cleaned']}")
    print(f"empty after normalise   : {stats['empty_dropped']}")
    print(f"written                 : {args.out}")


if __name__ == "__main__":
    main()
