# Parsing and Formatting Addresses

This guide covers the typical workflow for parsing unstructured address strings into structured components and formatting them into locale-appropriate strings.

## Setup

Before using address formatting, download the OpenCageData address templates:

```bash
mix localize.address.download_templates
```

This downloads templates for 267 countries and territories and compiles them into `priv/address_templates.etf`. Re-run this task periodically to pick up upstream template updates.

## Parsing an Address

`Localize.Address.parse/2` takes a free-form address string and uses libpostal's machine-learning models to identify components like house number, road, city, state, and postcode.

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
iex> address.territory_code
"US"
```

Note that libpostal normalizes all text to lowercase. The territory code defaults to the territory derived from `Localize.get_locale/0`.

### Specifying the Territory

When parsing addresses for a specific country, pass the `:territory` or `:locale` option. This sets the `territory_code` on the resulting struct and provides context to the parser:

```elixir
iex> {:ok, address} = Localize.Address.parse("10 Downing Street, London SW1A 2AA", territory: "GB")
iex> address.territory_code
"GB"

iex> {:ok, address} = Localize.Address.parse("5 Avenue Anatole France, Paris", locale: "fr")
iex> address.territory_code
"FR"
```

### Capitalizing Parsed Addresses

Since libpostal returns lowercase text, use `Localize.Address.capitalize/2` to restore proper casing. This applies Unicode-aware titlecase to place names and street names, uppercases postcodes, and leaves house numbers and territory codes unchanged:

```elixir
iex> {:ok, address} = Localize.Address.parse("301 hamilton avenue, palo alto, ca 94303")
iex> address = Localize.Address.capitalize(address)
iex> address.road
"Hamilton Avenue"
iex> address.city
"Palo Alto"
iex> address.postcode
"94303"
```

Or pass `capitalize: true` directly to `parse/2`:

```elixir
iex> {:ok, address} = Localize.Address.parse("301 hamilton avenue, palo alto, ca 94303", capitalize: true)
iex> address.road
"Hamilton Avenue"
iex> address.city
"Palo Alto"
```

### Locale-Aware Capitalization

Some languages have special titlecasing rules that go beyond simple first-letter uppercasing. Pass the `:locale` option to `capitalize/2` to apply these rules. The supported locales are Dutch (`:nl`), Turkish (`:tr`), Azeri (`:az`), Lithuanian (`:lt`), and Greek (`:el`).

#### Dutch — IJ digraph

In Dutch, "IJ" at the start of a word is treated as a single unit. Both letters are capitalized together:

```elixir
iex> address = %Localize.Address.Address{
...>   road: "ijsbaanpad",
...>   neighbourhood: "ijburg",
...>   city: "amsterdam"
...> }
iex> result = Localize.Address.capitalize(address, locale: :nl)
iex> result.road
"IJsbaanpad"
iex> result.neighbourhood
"IJburg"
iex> result.city
"Amsterdam"
```

Without the Dutch locale, these would incorrectly produce "Ijsbaanpad" and "Ijburg".

#### Lithuanian — soft-dotted characters

Lithuanian has special rules for characters with accents above soft-dotted letters. The locale ensures correct casing:

```elixir
iex> address = %Localize.Address.Address{
...>   road: "gedimino prospektas",
...>   city: "vilnius",
...>   territory: "lietuva"
...> }
iex> result = Localize.Address.capitalize(address, locale: :lt)
iex> result.road
"Gedimino Prospektas"
iex> result.city
"Vilnius"
```

#### Greek — titlecase with diacritics

Greek titlecasing preserves diacritics on lowercase letters while uppercasing the initial letter of each word:

```elixir
iex> address = %Localize.Address.Address{
...>   road: "οδός ερμού",
...>   city: "αθήνα",
...>   territory: "ελλάδα"
...> }
iex> result = Localize.Address.capitalize(address, locale: :el)
iex> result.road
"Οδός Ερμού"
iex> result.city
"Αθήνα"
iex> result.territory
"Ελλάδα"
```

## Formatting an Address

`Localize.Address.to_string/2` formats a `Localize.Address.Address` struct into a locale-appropriate multi-line string. The territory code determines which country template is used:

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
iex> IO.puts(formatted)
10 Downing Street
London
SW1A 2AA
United Kingdom
```

### Country-specific Formatting

Each country has its own conventions for address layout. The formatter automatically handles these differences:

```elixir
# United States: house road / city, STATE postcode / country
iex> {:ok, us} = Localize.Address.to_string(%Localize.Address.Address{
...>   house_number: "1600", road: "Pennsylvania Avenue NW",
...>   city: "Washington", state: "District of Columbia",
...>   postcode: "20500", territory: "United States of America",
...>   territory_code: "US"
...> })
iex> IO.puts(us)
1600 Pennsylvania Avenue NW
Washington, DC 20500
United States of America

# Germany: road number / postcode city / country
iex> {:ok, de} = Localize.Address.to_string(%Localize.Address.Address{
...>   house_number: "1", road: "Unter den Linden",
...>   city: "Berlin", postcode: "10117",
...>   territory: "Germany", territory_code: "DE"
...> })
iex> IO.puts(de)
Unter den Linden 1
10117 Berlin
Germany

# Japan: road number / city, postcode / country
iex> {:ok, jp} = Localize.Address.to_string(%Localize.Address.Address{
...>   house_number: "1-1", road: "Chiyoda",
...>   city: "Tokyo", postcode: "100-0001",
...>   territory: "Japan", territory_code: "JP"
...> })
iex> IO.puts(jp)
1-1 Chiyoda
Tokyo, 100-0001
Japan
```

### Overriding the Territory

Pass the `:territory` option to format an address using a different country's template:

```elixir
iex> {:ok, formatted} = Localize.Address.to_string(address, territory: "US")
```

## Parse-Format Roundtrip

A common workflow is to parse, capitalize, then format:

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "301 Hamilton Avenue, Palo Alto, CA 94303",
...>   capitalize: true
...> )
iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
301 Hamilton Avenue
Palo Alto, CA 94303
```

Note that the parsed territory defaults to the process locale. For best results, always specify the territory when parsing addresses for a known country.

## Constructing Addresses Manually

You can also build an address struct directly without parsing:

```elixir
iex> address = %Localize.Address.Address{
...>   attention: "Acme Corporation",
...>   house_number: "42",
...>   road: "Wallaby Way",
...>   city: "Sydney",
...>   state: "NSW",
...>   postcode: "2000",
...>   territory: "Australia",
...>   territory_code: "AU"
...> }
iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
Acme Corporation
42 Wallaby Way
Sydney NSW 2000
Australia
```

The `attention` field is used for business names, building names, or other points of interest that should appear at the top of the formatted address.

## Address Struct Fields

The `Localize.Address.Address` struct has fields for all common address components. Only populate the fields that are relevant — nil fields are omitted from the formatted output.

| Field | Description | Example |
|-------|-------------|---------|
| `attention` | Business or POI name | `"Acme Corporation"` |
| `house` | Building name | `"The Shard"` |
| `house_number` | Street number | `"42"` |
| `road` | Street name | `"Wallaby Way"` |
| `neighbourhood` | Suburb, district, quarter | `"Crescent Park"` |
| `city` | City or town | `"Sydney"` |
| `municipality` | Local administrative area | `"City of London"` |
| `county` | County or department | `"Santa Clara County"` |
| `state_district` | State subdivision | `"Greater London"` |
| `state` | State or province | `"California"` |
| `postcode` | Postal code | `"94303"` |
| `territory` | Country name | `"Australia"` |
| `territory_code` | ISO 3166-1 alpha-2 code | `"AU"` |
| `island` | Island name | `"Manhattan"` |
| `archipelago` | Archipelago name | `"Hawaiian Islands"` |
| `continent` | Continent name | `"North America"` |
| `raw_input` | Original input (set by `parse/2`) | `"42 Wallaby Way, Sydney"` |
