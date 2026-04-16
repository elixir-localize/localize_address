# Localize.Address

Address parsing and locale-aware formatting for Elixir.

Parses unstructured address strings into structured components using [libpostal](https://github.com/openvenues/libpostal) via NIF, and formats structured addresses into locale-appropriate string representations using templates from the [OpenCageData address-formatting](https://github.com/OpenCageData/address-formatting) project. Supports Unicode-aware capitalization via [Unicode.String](https://hex.pm/packages/unicode_string).

## Installation

Add `localize_address` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:localize_address, "~> 0.1"}
  ]
end
```

### System Dependencies

* **libpostal** is required for address parsing. Install with:

  ```bash
  brew install libpostal    # macOS
  apt-get install libpostal-dev   # Debian/Ubuntu
  ```

* **Address templates** must be downloaded before formatting. Run once after install and whenever upstream templates are updated:

  ```bash
  mix localize.address.download_templates
  ```

## Quick Start

Parse an address, capitalize it, and format for its territory:

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "301 Hamilton Avenue, Palo Alto, CA 94303",
...>   capitalize: true
...> )
iex> address.road
"Hamilton Avenue"
iex> address.city
"Palo Alto"

iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
301 Hamilton Avenue
Palo Alto, CA 94303
```

Different countries format addresses differently:

```elixir
# United States: house road / city, STATE postcode / country
iex> Localize.Address.to_string(%Localize.Address.Address{
...>   house_number: "1600", road: "Pennsylvania Avenue NW",
...>   city: "Washington", state: "District of Columbia",
...>   postcode: "20500", territory: "United States of America",
...>   territory_code: "US"
...> })
{:ok, "1600 Pennsylvania Avenue NW\nWashington, DC 20500\nUnited States of America"}

# Germany: road number / postcode city / country
iex> Localize.Address.to_string(%Localize.Address.Address{
...>   house_number: "1", road: "Unter den Linden",
...>   city: "Berlin", postcode: "10117",
...>   territory: "Germany", territory_code: "DE"
...> })
{:ok, "Unter den Linden 1\n10117 Berlin\nGermany"}
```

See the [Parsing and Formatting guide](https://hexdocs.pm/localize_address/parsing_and_formatting.html) for detailed usage including territory options, capitalization, and manual struct construction.

## Primary API

* `Localize.Address.parse/2` — parse an unstructured address string into a struct.

* `Localize.Address.to_string/2` — format a struct into a locale-appropriate string.

* `Localize.Address.capitalize/2` — titlecase text fields and uppercase postcodes.

* `Localize.Address.available?/0` — check if the libpostal NIF is loaded.

## Source References

* **[libpostal](https://github.com/openvenues/libpostal)** — C library for parsing and normalizing street addresses using statistical NLP and open geo data. Powers `Localize.Address.parse/2`.

* **[OpenCageData address-formatting](https://github.com/OpenCageData/address-formatting)** — Templates and rules for formatting addresses according to local conventions, covering 267 countries and territories. Powers `Localize.Address.to_string/2`.

* **[Localize](https://hex.pm/packages/localize)** — Provides territory validation, locale resolution, and subdivision name lookups (e.g., "California" ↔ "CA") used for state/county code resolution.

* **[Unicode.String](https://hex.pm/packages/unicode_string)** — Unicode-aware titlecase, used by `Localize.Address.capitalize/2`.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  Localize.Address                     │
│         parse/2    to_string/2    capitalize/2        │
└──────┬──────────────────┬────────────────────────────┘
       │                  │
       ▼                  ▼
┌──────────────┐ ┌────────────────────────┐
│ Localize.    │ │ Localize.Address.      │
│ Address.Nif  │ │ Formatter              │
│ (libpostal)  │ │                        │
└──────────────┘ │ * Template resolution  │
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
                 │        .etf            │
                 │ (compiled templates,   │
                 │  state/county codes,   │
                 │  component aliases)    │
                 └────────────────────────┘
```

The formatter pipeline is documented in detail in the [Parsing and Formatting guide](https://hexdocs.pm/localize_address/parsing_and_formatting.html).

## Conformance

Validated against the full [OpenCageData test suite](https://github.com/OpenCageData/address-formatting/tree/master/testcases) (459 test cases across 251 countries and territories).

**450/459 tests passing (98.0%). 242/251 countries at 100%.**

All major countries pass at 100%: US, GB, DE, FR, CA, AU, IT, ES, IE, JP, SG, IN, BR, NL.

The 9 remaining failures are documented with root causes in the [conformance document](https://hexdocs.pm/localize_address/open_cage_conformance.html).

## License

Apache License 2.0. See [LICENSE.md](https://github.com/elixir-localize/localize_address/blob/v0.1.0/LICENSE.md) for details.
