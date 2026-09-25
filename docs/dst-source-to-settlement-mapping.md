# Power Simulator — DST Source-to-Settlement Mapping Rule

## 1. Purpose

This document defines the canonical rule for mapping hourly workbook source cells to `core.settlement_interval`.

The rule applies to all hourly source domains that use Romanian local market time, including:

- hourly physical volumes;
- procurement schedules;
- PZU / day-ahead market prices;
- other hourly market observations derived from the workbook.

The purpose is to ensure that daylight-saving-time transitions are handled consistently and without inventing source evidence.

---

## 2. Canonical Time Model

`core.settlement_interval` is the authoritative physical-time dimension.

Each row represents one real physical UTC hour.

Romanian local market attributes are derived from:

`Europe/Bucharest`

Each settlement interval contains:

- `interval_id`
- `market_code`
- `interval_start_utc`
- `interval_end_utc`
- `local_date`
- `local_hour_label`
- `local_occurrence`
- `duration_hours`

The canonical identity of a local settlement interval is:

```text
market_code
+ local_date
+ local_hour_label
+ local_occurrence
```

UTC remains the unambiguous physical representation.

---

## 3. Workbook Hour Convention

The monthly workbook sheets use a calendar-day × hour matrix.

For the PZU block:

```text
columns B:AF   = calendar day 1..31
rows 177:200  = local hour label 1..24
```

Example:

```text
Martie!AD177
```

means:

```text
month      = March
day        = 29
hour label = 1
```

The source coordinates therefore determine:

```text
local_date
local_hour_label
source_cell_id
```

They do not independently determine `local_occurrence`.

---

## 4. Normal-Day Mapping

For a normal Romanian local day, every local hour label from 1 through 24 maps to exactly one physical settlement interval.

The mapping key is:

```text
market_code      = 'RO'
local_date       = source local date
local_hour_label = source hour label
```

If exactly one `core.settlement_interval` row matches, the mapping is valid and deterministic.

The resulting `interval_id` may be used by the downstream core fact.

---

## 5. Spring DST Transition

For 2026, the Romanian spring DST transition occurs on:

```text
2026-03-29
```

The physical settlement calendar contains:

```text
23 intervals
```

The workbook also reflects the missing local hour.

For the PZU matrix on 29 March:

```text
Martie!AD177  hour 1
Martie!AD178  hour 2
Martie!AD179  hour 3
Martie!AD180  absent
Martie!AD181  hour 5
...
Martie!AD200  hour 24
```

Therefore:

```text
local_hour_label = 4
```

has no workbook source value and no physical settlement interval.

Canonical behaviour:

```text
Do not synthesize hour 4.
Do not insert a zero.
Do not copy another hour.
Do not shift later source rows.
```

The 23 populated source cells map naturally to the 23 physical settlement intervals.

---

## 6. Autumn DST Transition

For 2026, the Romanian autumn DST transition occurs on:

```text
2026-10-25
```

The physical settlement calendar contains:

```text
25 intervals
```

The repeated local hour is represented as:

```text
local_hour_label = 4
local_occurrence = 1

local_hour_label = 4
local_occurrence = 2
```

However, the workbook PZU matrix contains only one source cell for hour 4 on that date.

For example:

```text
Octombrie!Z180
```

provides one source value for:

```text
2026-10-25
local_hour_label = 4
```

but contains no evidence identifying whether that value belongs to:

```text
local_occurrence = 1
```

or:

```text
local_occurrence = 2
```

Therefore the source is DST-ambiguous.

---

## 7. Canonical Mapping Algorithm

For every hourly source cell:

### Step 1 — Derive local coordinates

Derive from workbook structure:

```text
market_code
local_date
local_hour_label
source_cell_id
```

For Romanian workbook data:

```text
market_code = 'RO'
```

### Step 2 — Find physical settlement candidates

Query `core.settlement_interval` using:

```text
market_code
local_date
local_hour_label
```

### Step 3 — Evaluate candidate count

#### Exactly one candidate

If exactly one settlement interval matches:

```text
mapping = resolved
```

Use that row's `interval_id`.

#### Zero candidates

If no settlement interval matches:

```text
mapping = unresolved_no_physical_interval
```

Do not fabricate a settlement interval.

Do not insert the source value into an hourly core fact requiring a valid `interval_id`.

Preserve the original source evidence in the raw layer.

#### More than one candidate

If multiple settlement intervals match:

```text
mapping = unresolved_ambiguous_occurrence
```

Do not:

- choose occurrence 1 arbitrarily;
- choose occurrence 2 arbitrarily;
- duplicate the source value into both intervals;
- average or split the source value;
- derive occurrence from row position;
- infer occurrence from neighbouring values.

The source remains unresolved until authoritative evidence identifies the physical occurrence.

---

## 8. Source Evidence Rule

A mapping must never contain more temporal precision than the source itself provides.

If the workbook identifies only:

```text
local_date + local_hour_label
```

the transformation must not invent:

```text
local_occurrence
```

when more than one occurrence exists.

Likewise, missing physical hours must not be synthesized merely to create a rectangular 24-hour dataset.

---

## 9. Lineage Rule

Every successfully mapped hourly fact must preserve the originating:

```text
source_cell_id
```

The lineage relationship is:

```text
raw.source_cell
    ↓
source local date/hour
    ↓
core.settlement_interval
    ↓
hourly core fact
```

If mapping is unresolved, the original `raw.source_cell` remains the authoritative evidence.

No artificial source-cell lineage may be created.

---

## 10. DST Behaviour Summary

### Normal day

```text
Workbook source slots:       24
Physical intervals:          24
Resolved mappings:           24
Unresolved mappings:          0
```

### Spring DST day — 2026-03-29

```text
Workbook populated slots:    23
Physical intervals:          23
Missing local hour:           4
Resolved mappings:           23
Unresolved mappings:          0
Synthetic intervals:          0
```

### Autumn DST day — 2026-10-25

```text
Workbook source slots:       24
Physical intervals:          25
Repeated local hour:          4
Workbook hour-4 values:       1
Physical hour-4 intervals:    2
Unambiguous mappings:        23
Ambiguous source mappings:    1
Unrepresented physical rows:  2 candidates for the same source value
```

The hour-4 source value must remain unresolved until an authoritative occurrence convention is supplied.

---

## 11. Prohibited Transformations

The following transformations are explicitly prohibited unless supported by an authoritative source:

```text
24 workbook rows → positional 24 UTC rows
```

on DST transition days.

Also prohibited:

```text
copy one autumn hour-4 value to both occurrences
```

```text
assign autumn hour 4 to occurrence 1 by default
```

```text
assign autumn hour 4 to occurrence 2 by default
```

```text
drop one physical autumn interval to preserve 24 rows
```

```text
create a synthetic spring hour 4
```

```text
shift rows after the missing spring hour
```

Any such operation would introduce information that is not present in the workbook.

---

## 12. Implementation Requirement

Every transformation that loads hourly workbook data into a core fact table must use this same mapping rule.

Individual transformations must not implement their own DST assumptions.

The transformation must fail or quarantine unresolved mappings rather than silently choosing a physical interval.

---

## 13. Validation Requirements

Every hourly transformation must validate at minimum:

```text
source-cell count
resolved mapping count
zero-candidate count
multi-candidate count
duplicate interval mappings
source_cell_id preservation
```

For ordinary dates:

```text
multi-candidate count = 0
zero-candidate count  = 0
```

For known DST dates, deviations must agree with the source evidence described in this document.

---

## 14. Authoritative Rule

The canonical principle is:

> Map a workbook source cell to a physical settlement interval only when the workbook coordinates identify exactly one interval.

Where source evidence is insufficient:

> preserve the ambiguity; do not resolve it by inference.

This rule is common to all Power Simulator hourly transformations.