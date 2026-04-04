defmodule Localize.Address.FormatterTest do
  use ExUnit.Case, async: true

  alias Localize.Address.Address
  alias Localize.Address.Formatter

  describe "format/2" do
    @tag :templates
    test "formats a complete US address" do
      address = %Address{
        house_number: "301",
        road: "Hamilton Avenue",
        city: "Palo Alto",
        state: "CA",
        postcode: "94303",
        territory: "United States of America",
        territory_code: "US"
      }

      assert {:ok, formatted} = Formatter.format(address, "US")
      assert formatted =~ "301"
      assert formatted =~ "Hamilton Avenue"
      assert formatted =~ "Palo Alto"
      assert formatted =~ "94303"
    end

    @tag :templates
    test "formats a partial address using fallback" do
      address = %Address{
        city: "London",
        territory: "United Kingdom",
        territory_code: "GB"
      }

      assert {:ok, formatted} = Formatter.format(address, "GB")
      assert formatted =~ "London"
    end

    @tag :templates
    test "handles missing territory gracefully" do
      address = %Address{
        house_number: "1",
        road: "Main St",
        city: "Springfield"
      }

      assert {:ok, formatted} = Formatter.format(address, "ZZ")
      assert formatted =~ "Main St"
    end

    @tag :templates
    test "cleans up empty lines and extra whitespace" do
      address = %Address{
        city: "Berlin",
        territory: "Germany",
        territory_code: "DE"
      }

      assert {:ok, formatted} = Formatter.format(address, "DE")
      refute formatted =~ "\n\n"
      assert formatted == String.trim(formatted)
    end
  end
end
