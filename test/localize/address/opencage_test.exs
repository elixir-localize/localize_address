defmodule Localize.Address.OpenCageTest do
  @moduledoc """
  Validation tests generated from OpenCageData address-formatting
  test cases. These test the formatter against the canonical expected
  output for addresses from 251 territories.
  """

  use ExUnit.Case, async: true

  alias Localize.Address.Address
  alias Localize.Address.Formatter

  @templates_path "priv/address_templates.etf"

  if File.exists?(@templates_path) do
    @external_resource @templates_path
    @data :erlang.binary_to_term(File.read!(@templates_path))

    @component_aliases @data.component_aliases
    @state_codes @data.state_codes

    @canonical_to_struct %{
      "house_number" => :house_number,
      "house" => :house,
      "road" => :road,
      "neighbourhood" => :neighbourhood,
      "city" => :city,
      "municipality" => :municipality,
      "county" => :county,
      "state_district" => :state_district,
      "state" => :state,
      "postcode" => :postcode,
      "country" => :territory,
      "country_code" => :territory_code,
      "island" => :island,
      "archipelago" => :archipelago,
      "continent" => :continent
    }

    # Additional direct mappings for fields the formatter uses
    # that aren't canonical component names but appear in templates
    @extra_bindings [
      "attention",
      "suburb",
      "city_district",
      "town",
      "village",
      "hamlet",
      "place",
      "postal_city",
      "state_code",
      "quarter",
      "region",
      "local_administrative_area",
      "county_code"
    ]

    for {country_code, testcases} <- @data.testcases,
        {testcase, index} <- Enum.with_index(testcases) do
      description = testcase.description
      components = testcase.components
      expected = testcase.expected

      @tag :opencage
      @tag country: country_code

      test "#{country_code} ##{index}: #{description}" do
        components = unquote(Macro.escape(components))
        expected = unquote(expected)
        country_code = unquote(country_code)

        address = build_address_from_components(components, country_code)
        bindings = build_extended_bindings(components)

        result = format_with_bindings(address, bindings, country_code)

        assert result == expected,
               """
               #{country_code}: #{unquote(description)}

               Expected:
               #{expected}

               Got:
               #{result}

               Components: #{inspect(components)}
               """
      end
    end

    defp build_address_from_components(components, country_code) do
      # First pass: map direct (non-aliased) component names to struct fields
      direct_fields =
        Enum.reduce(components, %{}, fn {key, value}, acc ->
          struct_field = Map.get(@canonical_to_struct, key)
          if struct_field, do: Map.put(acc, struct_field, value), else: acc
        end)

      # Second pass: map aliased component names, but only if the struct
      # field was not already set by a direct mapping
      fields =
        Enum.reduce(components, direct_fields, fn {key, value}, acc ->
          canonical = Map.get(@component_aliases, key, key)
          struct_field = Map.get(@canonical_to_struct, canonical)

          if struct_field do
            Map.put_new(acc, struct_field, value)
          else
            acc
          end
        end)

      fields = Map.put_new(fields, :territory_code, country_code)
      struct(Address, fields)
    end

    defp build_extended_bindings(components) do
      # First pass: store all components under their original key
      direct = Map.new(components)

      # Second pass: add canonical aliases, but only if the canonical
      # key was not already provided directly in the components
      Enum.reduce(components, direct, fn {key, value}, acc ->
        canonical = Map.get(@component_aliases, key, key)

        if canonical != key do
          Map.put_new(acc, canonical, value)
        else
          acc
        end
      end)
    end

    defp format_with_bindings(%Address{} = address, extra_bindings, territory_code) do
      # Use the formatter but with extended bindings that include
      # all the raw component names the templates might reference
      case Formatter.format_with_bindings(address, extra_bindings, territory_code) do
        {:ok, formatted} -> formatted
        {:error, reason} -> "ERROR: #{reason}"
      end
    end
  end
end
