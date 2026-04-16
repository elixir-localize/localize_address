# Famous Addresses

This guide demonstrates `Localize.Address` parsing and formatting with some well-known addresses. Each example uses deliberately mixed-case input to show how libpostal normalizes the text and `capitalize: true` restores proper casing.

## Buckingham Palace

The official London residence of the British monarch.

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "BUCKINGHAM palace, london sw1a 1aa, UNITED KINGDOM",
...>   territory: "GB", capitalize: true
...> )
iex> address.attention
"Buckingham Palace"
iex> address.city
"London"
iex> address.postcode
"SW1A 1AA"

iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
Buckingham Palace
London
SW1A 1AA
United Kingdom
```

The parser identifies "Buckingham Palace" as a named place (the `attention` field) rather than a street address, and the UK template places it above the city and postcode.

## The White House

The official residence and workplace of the President of the United States.

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "1600 pennsylvania AVENUE nw, washington, dc 20500, united states",
...>   territory: "US", capitalize: true
...> )
iex> address.house_number
"1600"
iex> address.road
"Pennsylvania Avenue NW"
iex> address.city
"Washington"
iex> address.state
"DC"
iex> address.postcode
"20500"

iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
1600 Pennsylvania Avenue NW
Washington, DC 20500
United States of America
```

The US template places the city and state code on the same line with the postcode. Note how "united states" is normalized to "United States of America" by the postformat rules. The formatter also derives the "DC" state code and formats the city-state-postcode line in the standard US convention.

## The Forbidden City, Beijing

The imperial palace complex in the heart of Beijing, now the Palace Museum.

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "4 jingshan FRONT street, dongcheng, BEIJING 100009, china",
...>   territory: "CN", capitalize: true
...> )
iex> address.road
"Jingshan Front Street"
iex> address.neighbourhood
"Dongcheng"
iex> address.city
"Beijing"

iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
100009 China
Beijing
Dongcheng
Jingshan Front Street 4
```

Chinese addresses follow a large-to-small ordering: country and postcode first, then city, district, and street. This is the reverse of Western conventions and the formatter handles it automatically based on the CN template.

## The Imperial Palace, Tokyo

The primary residence of the Emperor of Japan, in the Chiyoda ward of Tokyo.

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "1-1 CHIYODA, chiyoda-ku, tokyo 100-8111, JAPAN",
...>   territory: "JP", capitalize: true
...> )
iex> address.city
"Tokyo"
iex> address.postcode
"100-8111"

iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
1-1
Chiyoda Chiyoda-Ku
Tokyo, 100-8111
Japan
```

Japanese addresses include the ward (ku) as part of the neighbourhood hierarchy.

## 221B Baker Street

The fictional London residence of Sherlock Holmes, as described by Arthur Conan Doyle. Today a real museum occupies the address.

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "221b BAKER street, LONDON nw1 6xe, united kingdom",
...>   territory: "GB", capitalize: true
...> )
iex> address.house_number
"221b"
iex> address.road
"Baker Street"
iex> address.postcode
"NW1 6XE"

iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
221b Baker Street
London
NW1 6XE
United Kingdom
```

Even the fictional "221B" is parsed correctly — the "B" suffix on the house number is preserved. The UK postcode is uppercased while the house number is left as-is, since postcodes follow a strict alphabetic convention.

## 742 Evergreen Terrace

The fictional home of the Simpson family in Springfield. Despite the chaotic input casing, the parser and capitalizer produce a clean, properly formatted US address.

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "742 evergreen TERRACE, springfield, ILLINOIS 62704, usa",
...>   territory: "US", capitalize: true
...> )
iex> address.road
"Evergreen Terrace"
iex> address.city
"Springfield"
iex> address.state
"Illinois"
iex> address.postcode
"62704"

iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
742 Evergreen Terrace
Springfield, IL 62704
United States of America
```

The input `"evergreen TERRACE"` becomes `"Evergreen Terrace"`, `"ILLINOIS"` becomes `"Illinois"`, and `"usa"` is normalized to `"United States of America"`. The formatter derives the "IL" state code from the full state name "Illinois" for the compact city-state-postcode line.

## 12 Grimmauld Place

The ancestral home of the Black family and headquarters of the Order of the Phoenix in J.K. Rowling's Harry Potter series. Hidden by a Fidelius Charm, the house is invisible to Muggles — but not to the address parser.

```elixir
iex> {:ok, address} = Localize.Address.parse(
...>   "12 GRIMMAULD place, london, UNITED kingdom",
...>   territory: "GB", capitalize: true
...> )
iex> address.house_number
"12"
iex> address.road
"Grimmauld Place"
iex> address.city
"London"

iex> {:ok, formatted} = Localize.Address.to_string(address)
iex> IO.puts(formatted)
12 Grimmauld Place
London
United Kingdom
```

Despite the erratic casing of the input (perhaps typed in a hurry while dodging hexes), the parser correctly identifies the house number, street, and city. The UK template formats it cleanly with the city on its own line and the country below.
