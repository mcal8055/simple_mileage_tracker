from __future__ import annotations
from pathlib import Path
import csv
import random
import datetime as dt
import os
import argparse

# --- Repository & output locations ---
# Prefer environment variables when available (so Codex can set them),
# otherwise derive paths relative to this script.
REPO = Path(os.environ.get("REPO_ROOT", Path(__file__).resolve().parents[1]))
DEFAULT_OUTDIR = Path(os.environ.get("OUTPUT_DIR", REPO / "Resources" / "Generated"))

HEADER = [
    "trip_id","date","start_time","end_time","duration_min","distance_miles",
    "start_lat","start_lng","end_lat","end_lng","label","notes","is_business",
    "start_address","end_address"
]

# --- Trip generator ---

def fake_trip(seq: int, day: dt.date) -> dict[str, object]:
    start = dt.datetime.combine(day, dt.time(8, 0)) + dt.timedelta(minutes=random.randint(0, 120))
    dur = random.randint(10, 75)
    end = start + dt.timedelta(minutes=dur)
    # ~25 mph avg + small noise; never negative; round to 0.01
    dist = round(max(0.0, dur * (25/60) + random.uniform(-0.8, 0.8)), 2)
    return {
        "trip_id": f"T{day.strftime('%Y%m')}-{seq:03d}",
        "date": day.isoformat(),
        "start_time": start.strftime("%H:%M"),
        "end_time": end.strftime("%H:%M"),
        "duration_min": dur,
        "distance_miles": f"{dist:.2f}",
        "start_lat": 40.7608, "start_lng": -111.8910,
        "end_lat": 40.7000,  "end_lng": -111.9400,
        "label": "Business", "notes": "",
        "is_business": 1,
        "start_address": "", "end_address": ""
    }

# --- CLI & main ---

def parse_args() -> argparse.Namespace:
    today = dt.date.today()
    p = argparse.ArgumentParser(description="Generate a sample monthly mileage CSV matching export schema.")
    p.add_argument("--year", type=int, default=today.year, help="Year to generate (default: this year)")
    p.add_argument("--month", type=int, default=today.month, choices=range(1,13), help="Month 1-12 (default: this month)")
    p.add_argument("--seed", type=int, default=None, help="Random seed for reproducible output")
    p.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR, help="Output directory (default: Resources/Generated)")
    p.add_argument("--max-per-day", type=int, default=2, help="Max trips per day (0..N). Default: 2")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if args.seed is not None:
        random.seed(args.seed)

    # Compute first day and last day (limit to 28 to avoid month-end issues)
    first = dt.date(args.year, args.month, 1)
    # Generate rows
    rows: list[dict[str, object]] = []
    seq = 1
    days_in_month = 28  # keep simple and deterministic
    for day_num in range(1, days_in_month + 1):
        day = first.replace(day=day_num)
        for _ in range(random.randint(0, max(0, args.max_per_day))):
            rows.append(fake_trip(seq, day))
            seq += 1

    # Ensure output directory exists and write CSV
    outdir: Path = args.outdir
    outdir.mkdir(parents=True, exist_ok=True)
    out_path = outdir / f"monthly_{args.year:04d}_{args.month:02d}.csv"

    with out_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=HEADER)
        writer.writeheader()
        writer.writerows(rows)

    print(f"[ok] wrote {out_path} (rows={len(rows)})")


if __name__ == "__main__":
    main()