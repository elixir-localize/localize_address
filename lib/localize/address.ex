defmodule Localize.Address do
  @moduledoc """
  Parses unstructured address strings and formats structured
  addresses into locale-appropriate string representations.

  Address parsing is powered by libpostal via NIF. Address formatting
  uses templates from the OpenCageData address-formatting project,
  compiled to Erlang term format.

  The primary functions are `parse/2` for parsing raw address strings
  and `to_string/2` for formatting an `Address` struct.

  """

  alias Localize.Address.Address
  alias Localize.Address.Formatter
  alias Localize.Address.Nif
  alias Localize.Address.Territory

  @type t :: Address.t()

  @libpostal_label_map %{
    "house" => :attention,
    "house_number" => :house_number,
    "road" => :road,
    "suburb" => :neighbourhood,
    "city_district" => :neighbourhood,
    "city" => :city,
    "state" => :state,
    "state_district" => :state_district,
    "postcode" => :postcode,
    "country" => :territory,
    "country_region" => :state,
    "island" => :island,
    "neighbourhood" => :neighbourhood,
    "village" => :city,
    "municipality" => :municipality,
    "county" => :county
  }

  @doc """
  Returns whether the NIF backend is available.

  ### Returns

  * `true` if the NIF shared library was loaded successfully.

  * `false` if the NIF is not compiled or libpostal is missing.

  ### Examples

      iex> is_boolean(Localize.Address.available?())
      true

  """
  @spec available?() :: boolean()
  defdelegate available?(), to: Nif

  @doc """
  Parses an unstructured address string into a `Localize.Address.Address` struct.

  Uses libpostal's machine-learning models to identify address
  components such as house number, road, city, state, and postcode.

  ### Arguments

  * `address_string` is the unstructured address string to parse.

  ### Options

  * `:territory` is an explicit ISO 3166-1 alpha-2 territory code
    (e.g., `"US"`, `"GB"`, or an atom like `:US`). Used as the
    territory code on the resulting struct and as context for parsing.

  * `:locale` is a locale identifier used to derive the territory.
    Accepts a string (e.g., `"en-US"`), an atom (e.g., `:en_US`), or a
    `Localize.LanguageTag.t()` struct.

  When neither `:territory` nor `:locale` is given, the territory is
  derived from `Localize.get_locale/0`.

  ### Returns

  * `{:ok, address}` where `address` is a `Localize.Address.Address` struct.

  * `{:error, reason}` if the address cannot be parsed.

  ### Examples

      iex> {:ok, address} = Localize.Address.parse("301 Hamilton Avenue, Palo Alto, CA 94303")
      iex> address.house_number
      "301"

      iex> {:ok, address} = Localize.Address.parse("10 Downing Street, London", territory: "GB")
      iex> address.territory_code
      "GB"

  """
  @spec parse(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def parse(address_string, options \\ []) when is_binary(address_string) do
    territory_code = Territory.resolve(options)

    case Nif.parse(address_string, "") do
      {:ok, components} ->
        address = build_address(components, address_string, territory_code)
        {:ok, address}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Formats an address struct into a locale-appropriate string.

  Uses OpenCageData address formatting templates to produce a
  properly formatted address for the territory associated with
  the address.

  ### Arguments

  * `address` is a `Localize.Address.Address` struct.

  ### Options

  * `:territory` overrides the territory code used for template
    selection. Defaults to `address.territory_code`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, reason}` if formatting fails.

  ### Examples

      iex> address = %Localize.Address.Address{
      ...>   house_number: "301",
      ...>   road: "Hamilton Avenue",
      ...>   city: "Palo Alto",
      ...>   state: "CA",
      ...>   postcode: "94303",
      ...>   territory: "United States of America",
      ...>   territory_code: "US"
      ...> }
      iex> {:ok, formatted} = Localize.Address.to_string(address)
      iex> is_binary(formatted)
      true

  """
  @spec to_string(t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def to_string(%Address{} = address, options \\ []) do
    territory_code =
      case Keyword.get(options, :territory) do
        nil -> address.territory_code || Territory.resolve(options)
        territory -> Territory.resolve(territory: territory)
      end

    Formatter.format(address, territory_code)
  end

  defp build_address(components, raw_input, territory_code) do
    fields =
      Enum.reduce(components, %{}, fn {label, value}, acc ->
        case Map.get(@libpostal_label_map, label) do
          nil ->
            acc

          field ->
            Map.update(acc, field, value, fn existing ->
              existing <> " " <> value
            end)
        end
      end)

    struct(
      Address,
      Map.merge(fields, %{
        raw_input: raw_input,
        territory_code: territory_code
      })
    )
  end
end
