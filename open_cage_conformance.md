# OpenCageData Address Formatting Conformance

## Summary

450/459 test cases passing (98.0%). 242/251 countries at 100%.

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
| BR | 5/5 | 100% |
| NL | 4/4 | 100% |
| CN | 2/3 | 67% |

## Remaining 9 Failures

### CN #2: Tibet extra district line

Components include `district: "Bayi District"` which aliases to `neighbourhood` and appears as an extra output line via the CN template's `{$first_2}` slot. The expected output omits it. The Perl reference's global line deduplication or substring detection likely suppresses this. Our consecutive-only dedup doesn't catch non-adjacent duplicates.

### CC #0: Cocos (Keeling) Islands village/country line merge

CC uses the AU template (`use_country: AU`) which puts `{$first_0} {$first_1} {$postcode}` on a single line. The village "West Island" and state "Cocos (Keeling) Islands" render on the same line as `West Island Cocos (Keeling) Islands`. The expected output has them on separate lines. CC would need its own template or a fallback that separates these components.

### HM #0: Heard Island missing state name

Only `state_code: "HIMI"` provided with no reverse lookup available. The `add_component` for HM should set the state name but HM has no `add_component` in the upstream data. The output renders the code "HIMI" instead of "Heard Island and McDonald Islands".

### AT #1: Politischer Bezirk prefix not stripped

The county value "Politischer Bezirk Schärding" should have the "Politischer Bezirk" prefix stripped, leaving "Schärding". AT has no replace rule for this prefix in the upstream worldwide.yaml. The expected output shows the clean county name.

### IR #1: Extra state_district line

`province: "Tehran Province"` aliases to `state` and appears as an extra line. The expected output has only city + district + country.

### MT #0: Numeric country value not swapped

The test data has `country: "1002"` (should be the postcode) and `state: "Malta"`. The Perl reference's `_fix_country` swaps country and state when country is numeric. Our formatter doesn't implement this swap.

### KW #3: Duplicate POI name

`building: "Kuwait National Library"` maps to both `house` and `attention` (via unknown component detection), appearing twice in the output.

### PH #1: Archipelago not rendered

`archipelago: "Mindanao"` not rendered in the PH fallback template — it has no `{$archipelago}` line, and the default fallback is not used because PH has its own (incomplete) fallback.

### UG #1: Subcounty not rendered

`subcounty: "Ayivuni"` aliases to `municipality`, and `state: "Arua"` is present. The UG fallback template doesn't include municipality in its candidates, and state doesn't appear because the template doesn't reference it in the appropriate position.

## Fixes to Reach 100%

Each remaining failure requires either upstream data changes (add_component/replace rules in worldwide.yaml), territory-specific template overrides, or implementing additional Perl reference behaviors:

| Failure | Fix |
|---------|-----|
| CN #2 | Implement global line deduplication with substring detection, or add CN-specific cleanup |
| CC #0 | Add CC-specific fallback template that separates village from state |
| HM #0 | Add `add_component: state=Heard Island and McDonald Islands` to HM config |
| AT #1 | Add replace rule `county=^Politischer Bezirk ` for AT |
| IR #1 | Filter out `province` → `state` alias when `state` is not expected in template |
| MT #0 | Implement `_fix_country` swap when country value is numeric |
| KW #3 | Prevent `building` from being collected into attention when it already maps to `house` |
| PH #1 | Add `{$archipelago}` to PH fallback template |
| UG #1 | Add municipality/state to UG fallback template candidates |
