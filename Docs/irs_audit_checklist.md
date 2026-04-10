# IRS Mileage Log Compliance Audit Checklist
**For automated code audit of a mileage tracking app**
_Sources: IRC §274(d), 26 CFR §1.274-5T, IRS Publication 463 (2025 ed.), IRS Notice 2026-10_

---

## PART 1: Per-Trip Required Fields
> **Statutory basis:** IRC §274(d)(A)–(D) and Pub. 463 Ch. 5.
> **Rule:** ALL five elements below are required for every deductible trip. Missing even one is grounds to deny the entire trip's deduction.

| # | Field | Requirement | Audit Check |
|---|-------|-------------|-------------|
| 1 | **Date** | Exact calendar date (not "week of…" or batch entries) | Does the data model store a `date` timestamp per trip? Is it stored at trip-creation time (not editable retroactively without a flag)? |
| 2 | **Starting location** | Specific address or named business — not vague ("downtown", "home area") | Does the app capture a `start_location` with street-level GPS coordinates or a typed address? Is it displayed back to the user for verification? |
| 3 | **Ending location** | Specific address or named business | Same as above for `end_location`. |
| 4 | **Miles driven** | Exact distance for the specific trip | Is `miles` computed from GPS route (preferred) or odometer delta — not estimated? Is it stored per trip, not as a running total only? |
| 5 | **Business purpose** | Specific reason — e.g., "Q3 budget review with Jane Smith at Acme Corp." Not: "client meeting," "work," "business." | Does the app require a non-empty `purpose` string? Does it warn or block on suspiciously generic strings (< N chars, or matching a blocklist like "meeting", "work", "business")? |

---

## PART 2: Vehicle-Level Annual Records
> **Statutory basis:** Pub. 463 Ch. 5; 26 CFR §1.274-5T(c)(3).
> **Rule:** Odometer readings must be recorded at the start and end of each tax year, and when a vehicle is added or removed from business use.

| # | Field | Requirement | Audit Check |
|---|-------|-------------|-------------|
| 6 | **Year-start odometer** | Reading as of January 1 (or first business use date) | Does the app prompt for and store `odometer_start` per vehicle per tax year? |
| 7 | **Year-end odometer** | Reading as of December 31 (or last business use date) | Does the app prompt for and store `odometer_end`? Does it send a year-end reminder? |
| 8 | **Vehicle identification** | Make, model, year sufficient for IRS; VIN recommended | Does each vehicle record store `make`, `model`, `year`? |
| 9 | **Date placed in service** | When the vehicle was first used for business | Is `business_use_start_date` stored per vehicle? |
| 10 | **Multiple vehicles** | Each vehicle tracked separately | If multiple vehicles exist, are trips unambiguously linked to a specific vehicle record? |

---

## PART 3: Contemporaneous Recording (The Most-Litigated Requirement)
> **Statutory basis:** 26 CFR §1.274-5T(c)(2)(i) — records made "at or near the time" carry higher credibility; retrospective records are a major audit red flag.
> **Rule:** The IRS considers a **weekly** log timely. Daily is stronger. Records created only at tax time are routinely rejected in Tax Court.

| # | Check | Audit Implementation |
|---|-------|----------------------|
| 11 | Trips are timestamped at creation | Does `created_at` exist on every trip record and get set server-side / device-clock at save time (not user-editable)? |
| 12 | Edits are logged | If a user edits a trip after creation, is an `edited_at` or change-log stored? IRS examiners look for post-hoc fabrication. |
| 13 | No large unexplained gaps | Does the app detect and warn when no trips have been logged for >7 days during a period when the user was active? |
| 14 | Business purpose entered promptly | Is the user prompted to enter `purpose` at trip end (not batch-possible for a whole month)? |
| 15 | GPS timestamps on route points | For GPS-tracked trips, are raw waypoints with UTC timestamps stored? This proves the trip was recorded in real time. |

---

## PART 4: Classification & Business-Use Percentage
> **Statutory basis:** Pub. 463 Ch. 4 (Standard Mileage Rate), 26 CFR §1.274-5T(d).
> **Rule:** Only business miles are deductible. Commuting miles (home ↔ regular place of business) are explicitly non-deductible.

| # | Check | Audit Implementation |
|---|-------|----------------------|
| 16 | Trip type classification | Does every trip have a `classification` field: `business`, `personal`, `medical`, `charitable`? |
| 17 | Commute exclusion | Does the app warn users that home-to-office trips are commuting (non-deductible)? Is there a setting or logic to auto-flag these? |
| 18 | Business-use % calculation | Does the app calculate and display `business_miles / total_miles * 100`? This is required if the user also has personal use on the same vehicle. |
| 19 | Mixed-purpose trip handling | Can the user split a trip or mark it as partially business? |

---

## PART 5: Applicable Rates (Must Be Correct for Tax Year)
> **Statutory basis:** IRS Notice 2026-10; IRS Notice 2025-5.

| # | Rate | Value | Audit Check |
|---|------|-------|-------------|
| 20 | 2026 Business rate | **$0.725/mile** | Is this the active rate in the app for trips on/after Jan 1, 2026? |
| 21 | 2025 Business rate | **$0.700/mile** | Are trips from 2025 correctly calculated at $0.70? |
| 22 | 2026 Medical/moving rate | **$0.21/mile** | Is this stored and applied to medical/moving trips? |
| 23 | Charitable rate | **$0.14/mile** (set by statute, does not change annually) | Is this stored and applied to charitable trips? |
| 24 | Rate applied at trip date | The rate in effect on the **trip date** must be used, not the filing-year rate | Does the deduction calculation use `rate_for_year(trip.date)` rather than a hardcoded current rate? |

---

## PART 6: Export / Report Requirements
> **Statutory basis:** Pub. 463 Ch. 5 — records must be producible; 26 CFR §1.274-5T(c)(2)(i).
> **Rule:** The IRS does not require a specific format, but the export must contain all five per-trip elements plus vehicle-level odometer data.

| # | Check | Audit Implementation |
|---|-------|----------------------|
| 25 | PDF export available | Does the app export a human-readable, non-editable PDF? |
| 26 | CSV/spreadsheet export available | Does the app export a CSV or Excel file (preferred by accountants for reconciliation)? |
| 27 | All five §274(d) fields present in export | Run a column check: date ✓, start location ✓, end location ✓, miles ✓, business purpose ✓ |
| 28 | Odometer readings in export | Are year-start and year-end odometer readings included in the summary section? |
| 29 | Business-use percentage in export | Is total business miles, total miles, and % business use shown in the report summary? |
| 30 | Deduction amount calculated and shown | Does the report show `business_miles × applicable_rate = $deduction`? |
| 31 | Monthly and annual summaries | Does the report break down totals by month AND provide an annual total? |
| 32 | Tax year filter | Can the user export by tax year (Jan 1–Dec 31)? |
| 33 | GPS route included (optional but strong) | Are GPS coordinates or a route map included to prove contemporaneous recording? This is a significant audit-defense differentiator. |

---

## PART 7: Audit Red-Flag Detection (App-Level Warnings)
> These patterns are specifically listed in IRS audit technique guides and Tax Court cases as triggers for disallowance.

| # | Red Flag | App-Level Check to Implement |
|---|----------|-------------------------------|
| 34 | Rounded mileage figures | Warn if a manually-entered trip distance ends in 0 or 5 and is >10 miles (suggests estimation, not GPS measurement) |
| 35 | 100% business use claimed | Warn user if business-use % is 100% — the IRS scrutinizes this heavily |
| 36 | Vague business purpose | Warn or block if `purpose` is <15 characters or matches a generic-term list ("meeting", "work", "business", "errand") |
| 37 | Trips created in batch | Flag if >5 trips are created within 60 seconds of each other (suggests retroactive reconstruction) |
| 38 | Weekends/holidays all marked business | Alert if the user has flagged >90% of weekend trips as business without any personal trips on record |
| 39 | No personal trips ever recorded | Warn that a log showing zero personal miles is an audit red flag (IRS assumes some personal use) |
| 40 | Retroactive editing | Flag trips whose `purpose` or `classification` was edited more than 7 days after `created_at` |
| 41 | Missing odometer readings | Block report generation / warn prominently if year-start or year-end odometer is absent |
| 42 | Commuting trips marked business | If start/end location matches a stored "home" address, flag the trip for user review |

---

## PART 8: Record Retention Requirements
> **Statutory basis:** IRC §6001; Pub. 463 Ch. 5.

| # | Requirement | App Implementation |
|---|-------------|-------------------|
| 43 | Minimum 3-year retention | Records must be kept for 3 years from the return filing date for that tax year | Display retention guidance in the app; do not auto-delete records |
| 44 | Extended retention scenarios | 6 years if income understated by >25%; 7 years if a loss deduction claimed | Inform users of this in documentation/onboarding |
| 45 | Data export before deletion | If a user deletes the app or data, warn them to export records first | |

---

## PART 9: TCJA / Eligibility Scope Warning
> **Statutory basis:** TCJA §11045 (Pub. L. 115-97); IRS Notice 2025-5.

| # | Check |
|---|-------|
| 46 | The app should clarify (in onboarding or docs) that the business standard mileage rate is primarily for **self-employed individuals (Schedule C/F filers)**. W-2 employees cannot deduct unreimbursed mileage under the TCJA suspension, which was in effect through at least tax year 2025. Note: Certain exceptions exist (Armed Forces reservists, fee-basis government officials, performing artists, qualified educators — Form 2106). |

---

## Quick Summary: Minimum Viable Compliant Trip Record

```
{
  trip_id:          UUID,
  vehicle_id:       FK → vehicles table,
  created_at:       UTC timestamp (device clock, immutable),
  edited_at:        UTC timestamp (null if never edited),
  trip_date:        DATE,
  start_location:   { address: string, lat: float, lng: float },
  end_location:     { address: string, lat: float, lng: float },
  miles:            DECIMAL(8,2),   // GPS-computed preferred
  purpose:          STRING,         // min 15 chars, not generic
  classification:   ENUM(business, personal, medical, charitable),
  gps_waypoints:    [ {lat, lng, timestamp}, ... ]  // optional but strongly recommended
}
```

```
{
  vehicle_id:              UUID,
  make / model / year:     STRING,
  business_use_start_date: DATE,
  odometer_start:          INT,   // Jan 1 (or first use date)
  odometer_end:            INT,   // Dec 31 (or last use date)
  tax_year:                INT
}
```
