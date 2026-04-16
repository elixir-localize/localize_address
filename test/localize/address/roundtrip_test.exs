defmodule Localize.Address.RoundtripTest do
  @moduledoc """
  Roundtrip tests: format → parse → format.

  These tests verify that an address survives a format-parse-format
  cycle with semantic equivalence. Exact text match is not required
  since libpostal normalizes case and may reorder components. Instead,
  we check that key address components are preserved and that the
  reformatted output is structurally similar to the original.
  """

  use ExUnit.Case, async: false

  alias Localize.Address
  alias Localize.Address.Address, as: A

  describe "format → parse → format roundtrip" do
    @describetag :nif
    @describetag :templates

    test "US address preserves components" do
      original = %A{
        house_number: "301",
        road: "Hamilton Avenue",
        city: "Palo Alto",
        state: "CA",
        postcode: "94303",
        territory: "United States of America",
        territory_code: "US"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component(reparsed, :house_number, "301")
      assert_component_contains(reparsed, :road, "hamilton")
      assert_component_contains(reparsed, :city, "palo alto")
      assert_component(reparsed, :postcode, "94303")
      assert_same_structure(original, reformatted)
    end

    @tag :nif
    test "GB address preserves components" do
      original = %A{
        house_number: "10",
        road: "Downing Street",
        city: "London",
        postcode: "SW1A 2AA",
        territory: "United Kingdom",
        territory_code: "GB"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component(reparsed, :house_number, "10")
      assert_component_contains(reparsed, :road, "downing")
      assert_component_contains(reformatted, "london")
      assert_component_contains(reformatted, "sw1a")
    end

    @tag :nif
    test "DE address preserves components" do
      original = %A{
        house_number: "1",
        road: "Unter den Linden",
        city: "Berlin",
        postcode: "10117",
        territory: "Germany",
        territory_code: "DE"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component(reparsed, :house_number, "1")
      assert_component_contains(reparsed, :road, "unter den linden")
      assert_component_contains(reformatted, "berlin")
      assert_component(reparsed, :postcode, "10117")
    end

    @tag :nif
    test "FR address preserves components" do
      original = %A{
        house_number: "5",
        road: "Avenue Anatole France",
        city: "Paris",
        postcode: "75007",
        territory: "France",
        territory_code: "FR"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component(reparsed, :house_number, "5")
      assert_component_contains(reparsed, :road, "anatole france")
      assert_component_contains(reformatted, "paris")
      assert_component(reparsed, :postcode, "75007")
    end

    @tag :nif
    test "AU address preserves components" do
      original = %A{
        house_number: "1",
        road: "Macquarie Street",
        city: "Sydney",
        state: "NSW",
        postcode: "2000",
        territory: "Australia",
        territory_code: "AU"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component(reparsed, :house_number, "1")
      assert_component_contains(reparsed, :road, "macquarie")
      assert_component(reparsed, :postcode, "2000")
      assert_component_contains(reformatted, "2000")
    end

    @tag :nif
    test "CA address preserves components" do
      original = %A{
        house_number: "251",
        road: "McMurchy Avenue South",
        city: "Brampton",
        state: "Ontario",
        postcode: "L6Y 1Z4",
        territory: "Canada",
        territory_code: "CA"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component(reparsed, :house_number, "251")
      assert_component_contains(reparsed, :road, "mcmurchy")
      assert_component_contains(reformatted, "brampton")
    end

    @tag :nif
    test "IT address preserves components" do
      original = %A{
        house_number: "1",
        road: "Via dei Fori Imperiali",
        city: "Roma",
        postcode: "00186",
        territory: "Italia",
        territory_code: "IT"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component(reparsed, :house_number, "1")
      assert_component_contains(reparsed, :road, "fori imperiali")
      assert_component(reparsed, :postcode, "00186")
      assert_component_contains(reformatted, "roma")
    end

    @tag :nif
    test "JP address preserves postcode" do
      original = %A{
        house_number: "1-1",
        road: "Chiyoda",
        city: "Tokyo",
        postcode: "100-0001",
        territory: "Japan",
        territory_code: "JP"
      }

      {_reparsed, reformatted} = roundtrip(original)

      assert_component_contains(reformatted, "tokyo")
      assert_component_contains(reformatted, "100")
    end

    @tag :nif
    test "BR address preserves components" do
      original = %A{
        house_number: "1",
        road: "Avenida Paulista",
        city: "São Paulo",
        state: "SP",
        postcode: "01310-100",
        territory: "Brazil",
        territory_code: "BR"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component_contains(reparsed, :road, "paulista")
      assert_component_contains(reformatted, "paulo")
    end

    @tag :nif
    test "ES address preserves components" do
      original = %A{
        house_number: "1",
        road: "Calle de Alcalá",
        city: "Madrid",
        postcode: "28014",
        territory: "Spain",
        territory_code: "ES"
      }

      {reparsed, reformatted} = roundtrip(original)

      assert_component_contains(reparsed, :road, "alcal")
      assert_component_contains(reformatted, "madrid")
      assert_component(reparsed, :postcode, "28014")
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp roundtrip(%A{} = original) do
    {:ok, formatted} = Address.to_string(original)
    {:ok, reparsed} = Address.parse(formatted, territory: original.territory_code)
    {:ok, reformatted} = Address.to_string(reparsed)
    {reparsed, reformatted}
  end

  defp assert_component(address, field, expected) when is_atom(field) do
    actual = Map.get(address, field)

    assert actual != nil,
           "expected #{field} to be set, got nil"

    assert String.downcase(actual) == String.downcase(expected),
           "expected #{field} to be #{inspect(expected)}, got #{inspect(actual)}"
  end

  defp assert_component_contains(address, field, substring) when is_atom(field) do
    actual = Map.get(address, field)

    assert actual != nil,
           "expected #{field} to be set, got nil"

    assert String.contains?(String.downcase(actual), String.downcase(substring)),
           "expected #{field} to contain #{inspect(substring)}, got #{inspect(actual)}"
  end

  defp assert_component_contains(text, substring) when is_binary(text) do
    assert String.contains?(String.downcase(text), String.downcase(substring)),
           "expected output to contain #{inspect(substring)}, got:\n#{text}"
  end

  defp assert_same_structure(%A{} = original, reformatted) when is_binary(reformatted) do
    {:ok, original_formatted} = Address.to_string(original)
    original_lines = String.split(original_formatted, "\n") |> length()
    reformatted_lines = String.split(reformatted, "\n") |> length()

    assert abs(original_lines - reformatted_lines) <= 1,
           """
           structural mismatch: original has #{original_lines} lines, reformatted has #{reformatted_lines} lines.
           Original: #{original_formatted}
           Reformatted: #{reformatted}
           """
  end
end
