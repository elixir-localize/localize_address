# Localize.Address

Address parsing and locale-aware formatting for Elixir.

Parses unstructured address strings into structured components using [libpostal](https://github.com/openvenues/libpostal) via NIF, and formats structured addresses into locale-appropriate string representations using templates from the [OpenCageData address-formatting](https://github.com/OpenCageData/address-formatting) project.

## Installation

Add `localize_address` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:localize_address, path: "../localize_address"}
  ]
end
```

### System Dependencies

* **libpostal** is required for address parsing. Install with:

  ```bash
  brew install libpostal    # macOS
  ```

* **Address templates** must be downloaded before formatting. Run once after install and whenever upstream templates are updated:

  ```bash
  mix localize.address.download_templates
  ```

## Usage

### Parsing an address

`Localize.Address.parse/2` takes an unstructured address string and returns a struct with labeled components.

```elixir
iex> {:ok, address} = Localize.Address.parse("301 Hamilton Avenue, Palo Alto, CA 94303")
iex> address.house_number
"301"
iex> address.road
"hamilton avenue"
iex> address.city
"palo alto"
iex> address.state
"ca"
iex> address.postcode
"94303"
```

Note that libpostal normalizes text to lowercase. The territory defaults to the current locale; pass `:territory` or `:locale` to override:

```elixir
iex> {:ok, address} = Localize.Address.parse("10 Downing Street, London", territory: "GB")
iex> address.territory_code
"GB"
```

### Formatting an address

`Localize.Address.to_string/2` formats a struct into a locale-appropriate string using OpenCageData templates for the address's territory.

```elixir
iex> address = %Localize.Address.Address{
...>   house_number: "10",
...>   road: "Downing Street",
...>   city: "London",
...>   postcode: "SW1A 2AA",
...>   territory: "United Kingdom",
...>   territory_code: "GB"
...> }
iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> formatted
"10 Downing Street\nLondon\nSW1A 2AA\nUnited Kingdom"
```

The territory code determines which template is used. Different countries have different conventions:

```elixir
# United States: city, STATE postcode
iex> Localize.Address.to_string(%Localize.Address.Address{
...>   house_number: "1600", road: "Pennsylvania Avenue NW",
...>   city: "Washington", state: "District of Columbia",
...>   postcode: "20500", territory: "United States of America",
...>   territory_code: "US"
...> })
{:ok, "1600 Pennsylvania Avenue NW\nWashington, DC 20500\nUnited States of America"}

# Germany: street number / postcode city
iex> Localize.Address.to_string(%Localize.Address.Address{
...>   house_number: "1", road: "Unter den Linden",
...>   city: "Berlin", postcode: "10117",
...>   territory: "Germany", territory_code: "DE"
...> })
{:ok, "Unter den Linden 1\n10117 Berlin\nGermany"}
```

### Address struct

`Localize.Address.Address` has the following fields:

| Field | Description |
|-------|-------------|
| `attention` | Business or building name (POI) |
| `house` | Building name |
| `house_number` | Street number |
| `road` | Street name |
| `neighbourhood` | Suburb, district, or quarter |
| `city` | City or town |
| `municipality` | Local administrative area |
| `county` | County or department |
| `state_district` | State subdivision |
| `state` | State or province |
| `postcode` | Postal code |
| `territory` | Country name |
| `territory_code` | ISO 3166-1 alpha-2 country code |
| `island` | Island name |
| `archipelago` | Archipelago name |
| `continent` | Continent name |
| `raw_input` | Original input string (set by `parse/2`) |

## Source References

* **[libpostal](https://github.com/openvenues/libpostal)** — C library for parsing and normalizing street addresses using statistical NLP and open geo data. Powers `Localize.Address.parse/2`.

* **[OpenCageData address-formatting](https://github.com/OpenCageData/address-formatting)** — Templates and rules for formatting addresses according to local conventions, covering 267 countries and territories. Powers `Localize.Address.to_string/2`.

* **[Localize](https://github.com/kipcole9/localize)** — Provides territory validation, locale resolution, and subdivision name lookups (e.g., "California" ↔ "CA") used for state/county code resolution.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  Localize.Address                     │
│              parse/2      to_string/2                 │
└──────┬───────────────────────────┬───────────────────┘
       │                           │
       ▼                           ▼
┌──────────────┐      ┌────────────────────────┐
│ Localize.    │      │ Localize.Address.      │
│ Address.Nif  │      │ Formatter              │
│ (libpostal)  │      │                        │
└──────────────┘      │ * Template resolution  │
                      │ * Territory remapping  │
                      │ * Component aliases    │
                      │ * State code lookup    │
                      │ * First-of resolution  │
                      │ * Replace rules        │
                      │ * Postformat rules     │
                      │ * Output cleanup       │
                      └────────┬───────────────┘
                               │
                      ┌────────▼───────────────┐
                      │ priv/address_templates  │
                      │        .etf             │
                      │ (compiled templates,    │
                      │  state codes,           │
                      │  component aliases,     │
                      │  county codes)          │
                      └────────────────────────┘
```

### NIF layer (`c_src/`)

A C NIF wrapping libpostal's `libpostal_parse_address`. Initializes the libpostal parser and language classifier on NIF load. Returns `{:ok, [{label, component}, ...]}` tuples.

### Formatter pipeline

When formatting an address, the formatter applies these steps in order:

1. **Territory remapping** — detect dependent territories (NL → CW for Curaçao, CN → default for Macau).
2. **Config resolution** — look up the territory's template, inheriting from parent via `use_country` chains.
3. **Component preparation** — merge struct fields with extra bindings, apply `add_component` rules, interpolate `change_country` templates.
4. **Alias resolution** — map alternate component names to canonical names (e.g., `suburb` → `neighbourhood`).
5. **Sanity cleaning** — reject garbage values (URLs, overly long postcodes, semicolon ranges).
6. **Component replace** — apply territory-specific regex rules to individual component values (e.g., strip "Città Metropolitana di" prefix for IT).
7. **State/county code lookup** — derive abbreviations from full names using OpenCageData state_codes data with Localize subdivision fallback.
8. **Attention collection** — collect unknown/POI component names (restaurants, hotels, etc.) into the attention field.
9. **Template selection** — use the main template when road or postcode is present; fall back otherwise.
10. **Template rendering** — resolve `{{#first}}` candidates (including compound multi-variable options), substitute variables.
11. **Post-processing** — apply output-level replace and postformat rules, clean empty lines, deduplicate consecutive lines, clean punctuation.

### Data download (`mix localize.address.download_templates`)

Downloads from the OpenCageData GitHub repository:

* `conf/countries/worldwide.yaml` — address templates for 267 territories
* `conf/components.yaml` — component name aliases
* `conf/state_codes.yaml` — state name ↔ code mappings
* `conf/county_codes.yaml` — county name ↔ code mappings
* `testcases/countries/*.yaml` — 459 conformance test cases

Converts mustache templates to a simplified `{$variable}` format with `{{#first}}` blocks stored as candidate lists (including compound multi-variable candidates). Compiles everything into `priv/address_templates.etf`.

## Conformance

Validated against the full OpenCageData test suite (459 test cases across 251 countries and territories).

**450/459 tests passing (98.0%). 242/251 countries at 100%.**

All major countries pass at 100%: US, GB, DE, FR, CA, AU, IT, ES, IE, JP, SG, IN, BR, NL.

The 9 remaining failures are documented with root causes and specific fixes in the [conformance document](open_cage_conformance.md).
