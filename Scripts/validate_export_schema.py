from pathlib import Path
import csv, sys

REPO = Path(__file__).resolve().parents[1]
SCHEMA = REPO / "Docs" / "export_schema.csv"
OUTDIR = REPO / "Resources" / "Generated"
EXPECTED = [
  "trip_id","date","start_time","end_time","duration_min","distance_miles",
  "start_lat","start_lng","end_lat","end_lng","label","notes","is_business",
  "start_address","end_address"
]

def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    if not SCHEMA.exists():
        print(f"[error] schema file missing: {SCHEMA}")
        sys.exit(2)

    with SCHEMA.open(newline="") as f:
        row = next(csv.reader(f))
        header = [c.strip() for c in row if c.strip()]

    missing = [c for c in EXPECTED if c not in header]
    extra   = [c for c in header if c not in EXPECTED]
    order_ok = header == EXPECTED

    report = OUTDIR / "schema_report.txt"
    with report.open("w") as r:
        r.write("EXPECTED:\n" + ", ".join(EXPECTED) + "\n\n")
        r.write("FOUND:\n" + ", ".join(header) + "\n\n")
        r.write(f"MISSING: {', '.join(missing) or 'None'}\n")
        r.write(f"EXTRA:   {', '.join(extra) or 'None'}\n")
        r.write(f"ORDER_MATCH: {order_ok}\n")

    print(f"[ok] wrote {report}")
    # non-zero exit if mismatch to make Codex open a PR fix
    if missing or extra or not order_ok:
        sys.exit(1)

if __name__ == "__main__":
    main()