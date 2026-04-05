# OpenCageData Address Formatting Conformance

## Summary

446/459 test cases passing (97.2%). 240/251 countries at 100%.

## Key Country Compliance

| Country | Pass/Total | Status |
|---------|-----------|--------|
| US | 19/19 | 100% |
| GB | 17/17 | 100% |
| DE | 20/20 | 100% |
| FR | 9/9 | 100% |
| CA | 9/9 | 100% |
| AU | 6/6 | 100% |
| IT | 7/7 | 100% |
| ES | 4/4 | 100% |
| IE | 8/8 | 100% |
| JP | 1/1 | 100% |
| SG | 4/4 | 100% |
| IN | 3/3 | 100% |
| CN | 1/3 | 33% |

## CN (China) — 1/3 passing

### CN #0 (Shanghai building): passing

### CN #1 (Macau): failing

Components: `country_code: "cn"`, `region: "Macau"`. The CN template renders country first (Chinese large-to-small ordering), producing `China\nMacau` instead of `Macau\nChina`. The Perl reference detects Macau/Hong Kong under CN and redirects to the MO/HK template. Fix: detect SAR regions under CN and use the appropriate territory template.

### CN #2 (Tibet): failing

Components include `district: "Bayi District"` which aliases to `neighbourhood` and appears as an extra output line. The expected output omits it. Also `town: "Bayi"` duplicates information. Fix: add CN-specific cleanup or limit the number of administrative levels rendered.

## Remaining 13 Failures

| Country | Pass/Total | Issue |
|---------|-----------|-------|
| CN | 1/3 | Macau SAR detection; extra district line |
| NL | 2/4 | Curaçao (CW) and Aruba (AW) rendered as "The Netherlands" instead of territory name |
| BR | 4/5 | Missing comma separator between road and quarter in compound template |
| UG | 1/2 | Subcounty not rendered — `subcounty` alias maps to `municipality` but fallback template doesn't reference it |
| IR | 1/2 | Extra `state_district` line ("Tehran Province") from Localize subdivision lookup |
| MT | 0/1 | Postcode "1002" appearing instead of town name — `postal_city` not mapping to template |
| PH | 4/5 | `archipelago` not on its own line — template puts it inline |
| CC | 0/1 | `village: "West Island"` rendered inline with country instead of separate line |
| KW | 4/5 | POI name appearing twice — attention and original component both in output |
| HM | 0/1 | Only `state_code: "HIMI"` provided, no state name — no reverse lookup available |
| AT | 1/2 | `county: "Politischer Bezirk Schärding"` replace rule should strip "Politischer Bezirk" prefix |

## Avenues of Work for Remaining Failures

### NL territories (2 failures)

NL #2 (Curaçao) and NL #3 (Aruba): the Perl reference detects these territories under NL and redirects to the CW/AW template. Requires detecting `country_code` subterritories of NL.

### BR comma in compound template (1 failure)

BR template has `{{{house_number}}} {{{road}}}, {{{quarter}}}` where the comma between road and quarter is a literal separator within a compound `{{#first}}` option. The compound template extraction preserves it but it gets lost when `road` is present but `quarter` renders as a separate `{$variable}`.

### AT county prefix (1 failure)

AT has no replace rule for "Politischer Bezirk" prefix on county names. The Perl reference may have this as a default global cleanup.
