from pathlib import Path
import sys, csv, re
from dateutil.parser import isoparse

REPO = Path(__file__).resolve().parents[1]
OUTDIR = REPO / "Resources" / "Generated"

HEADER = [
  "trip_id","date","start_time","end_time","duration_min","distance_miles",
  "start_lat","start_lng","end_lat","end_lng","label","notes","is_business",
  "start_address","end_address"
]

def fail(msg):
    print(f"[lint] {msg}")
    sys.exit(1)

def ok(msg):
    print(f"[ok] {msg}")

def parse_float(x, name):
    try:
        return float(x)
    except:
        fail(f"{name} not a float: {x!r}")

def main():
    if len(sys.argv) < 2:
        fail("Usage: python Scripts/lint_trip_csv.py <path/to/trips.csv>")

    path = Path(sys.argv[1]).resolve()
    if not path.exists():
        fail(f"File not found: {path}")

    with path.open(newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != HEADER:
            fail("CSV header mismatch. Run Scripts/validate_export_schema.py.")
        rows = list(reader)

    # Basic lint checks
    for i, row in enumerate(rows, 1):
        if not row["trip_id"]:
            fail(f"Row {i}: missing trip_id")
        # ISO-ish date/time
        try:
            isoparse(f"{row['date']}T{row['start_time']}")
            isoparse(f"{row['date']}T{row['end_time']}")
        except Exception as e:
            fail(f"Row {i}: bad date/time: {e}")

        dur = parse_float(row["duration_min"], "duration_min")
        dist = parse_float(row["distance_miles"], "distance_miles")
        if dur < 0 or dist < 0:
            fail(f"Row {i}: negative duration or distance")
        # Rounding: distance to 0.01, duration whole minutes
        if round(dist, 2) != float(row["distance_miles"]):
            fail(f"Row {i}: distance_miles not rounded to 0.01")

        # Coords sanity
        for key in ["start_lat","end_lat"]:
            v = parse_float(row[key], key)
            if not (-90 <= v <= 90):
                fail(f"Row {i}: {key} out of range")
        for key in ["start_lng","end_lng"]:
            v = parse_float(row[key], key)
            if not (-180 <= v <= 180):
                fail(f"Row {i}: {key} out of range")

        # is_business ∈ {0,1}
        if row["is_business"] not in ("0","1","",None):
            fail(f"Row {i}: is_business must be 0/1")

    OUTDIR.mkdir(parents=True, exist_ok=True)
    (OUTDIR / "lint_ok.txt").write_text(f"Checked {len(rows)} rows in {path.name}\n")
    ok(f"lint passed: {path.name}")

if __name__ == "__main__":
    main()