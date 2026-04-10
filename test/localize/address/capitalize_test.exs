defmodule Localize.Address.CapitalizeTest do
  use ExUnit.Case, async: true

  alias Localize.Address
  alias Localize.Address.Address, as: A

  describe "capitalize/2" do
    test "titlecases place name fields" do
      address = %A{
        road: "hamilton avenue",
        neighbourhood: "crescent park",
        city: "palo alto",
        municipality: "santa clara",
        county: "santa clara county",
        state: "california",
        territory: "united states of america",
        continent: "north america"
      }

      result = Address.capitalize(address)

      assert result.road == "Hamilton Avenue"
      assert result.neighbourhood == "Crescent Park"
      assert result.city == "Palo Alto"
      assert result.municipality == "Santa Clara"
      assert result.county == "Santa Clara County"
      assert result.state == "California"
      assert result.territory == "United States Of America"
      assert result.continent == "North America"
    end

    test "titlecases words starting with i" do
      address = %A{
        attention: "acme international",
        island: "manhattan island",
        archipelago: "indonesian islands"
      }

      result = Address.capitalize(address)

      assert result.attention == "Acme International"
      assert result.island == "Manhattan Island"
      assert result.archipelago == "Indonesian Islands"
    end

    test "uppercases postcode" do
      address = %A{postcode: "sw1a 2aa"}
      result = Address.capitalize(address)
      assert result.postcode == "SW1A 2AA"
    end

    test "leaves house_number unchanged" do
      address = %A{house_number: "301a"}
      result = Address.capitalize(address)
      assert result.house_number == "301a"
    end

    test "leaves territory_code unchanged" do
      address = %A{territory_code: "US"}
      result = Address.capitalize(address)
      assert result.territory_code == "US"
    end

    test "preserves raw_input" do
      address = %A{raw_input: "301 hamilton avenue, palo alto, ca 94303", road: "hamilton avenue"}
      result = Address.capitalize(address)
      assert result.raw_input == "301 hamilton avenue, palo alto, ca 94303"
      assert result.road == "Hamilton Avenue"
    end

    test "handles nil fields" do
      address = %A{road: nil, city: nil, postcode: nil}
      result = Address.capitalize(address)
      assert result.road == nil
      assert result.city == nil
      assert result.postcode == nil
    end

    test "handles empty string fields" do
      address = %A{road: "", city: ""}
      result = Address.capitalize(address)
      assert result.road == ""
      assert result.city == ""
    end

    test "handles hyphenated names" do
      address = %A{city: "saint-germain-des-prés"}
      result = Address.capitalize(address)
      assert result.city =~ "Saint"
      assert result.city =~ "Germain"
    end

    test "handles non-ASCII characters" do
      address = %A{road: "müller straße", city: "münchen"}
      result = Address.capitalize(address)
      assert result.road == "Müller Straße"
      assert result.city == "München"
    end
  end

  describe "parse/2 with capitalize option" do
    @tag :nif
    test "capitalizes parsed US address" do
      {:ok, address} =
        Address.parse("301 hamilton avenue, palo alto, ca 94303", capitalize: true)

      assert address.road =~ "Hamilton"
      assert address.city =~ "Palo"
      assert address.house_number == "301"
    end

    @tag :nif
    test "does not capitalize without option" do
      {:ok, address} = Address.parse("301 hamilton avenue, palo alto, ca 94303")
      assert address.road =~ "hamilton"
    end

    @tag :nif
    test "capitalize with locale option" do
      {:ok, address} =
        Address.parse("10 downing street, london", territory: "GB", capitalize: true)

      assert address.road =~ "Downing"
    end
  end

  describe "roundtrip with capitalize" do
    @tag :nif
    @tag :templates
    test "parse with capitalize produces well-formatted output" do
      {:ok, address} =
        Address.parse("301 hamilton avenue, palo alto, ca 94303", capitalize: true)

      {:ok, formatted} = Address.to_string(address)

      assert formatted =~ "Hamilton"
      assert formatted =~ "Palo Alto"
    end
  end
end
