from pathlib import Path
import csv, random, datetime as dt

REPO = Path(__file__).resolve().parents[1]
OUTDIR = REPO / "Resources" / "Generated"
HEADER = [
  "trip_id","date","start_time","end_time","duration_min","distance_miles",
  "start_lat","start_lng","end_lat","end_lng","label","notes","is_business",
  "start_address","end_address"
]

def fake_trip(seq, day):
    start = dt.datetime.combine(day, dt.time(8, 0)) + dt.timedelta(minutes=random.randint(0, 120))
    dur = random.randint(10, 75)
    end = start + dt.timedelta(minutes=dur)
    # ~25 mph avg + small noise
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

def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    today = dt.date.today()
    first = today.replace(day=1)
    rows = []
    seq = 1
    for d in range(1, min(today.day, 28) + 1):
        day = first.replace(day=d)
        for _ in range(random.randint(0, 2)):
            rows.append(fake_trip(seq, day))
            seq += 1

    out = OUTDIR / f"monthly_{today.strftime('%Y_%m')}.csv"
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=HEADER)
        w.writeheader()
        w.writerows(rows)
    print(f"[ok] wrote {out}")

if __name__ == "__main__":
    main()