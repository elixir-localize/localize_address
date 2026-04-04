defmodule Localize.AddressTest do
  use ExUnit.Case, async: true

  alias Localize.Address
  alias Localize.Address.Address, as: AddressStruct

  describe "available?/0" do
    test "returns a boolean" do
      assert is_boolean(Address.available?())
    end
  end

  describe "parse/2" do
    @tag :nif
    test "parses a US address" do
      assert {:ok, %AddressStruct{} = address} =
               Address.parse("301 Hamilton Avenue, Palo Alto, CA 94303")

      assert address.house_number == "301"
      assert address.road =~ "hamilton"
      assert address.raw_input == "301 Hamilton Avenue, Palo Alto, CA 94303"
    end

    @tag :nif
    test "parses with explicit territory" do
      assert {:ok, %AddressStruct{} = address} =
               Address.parse("10 Downing Street, London SW1A 2AA", territory: "GB")

      assert address.territory_code == "GB"
    end

    @tag :nif
    test "parses with locale option" do
      assert {:ok, %AddressStruct{} = address} =
               Address.parse("10 Downing Street, London", locale: "en-GB")

      assert address.territory_code == "GB"
    end

    @tag :nif
    test "returns error for empty string" do
      assert {:ok, %AddressStruct{}} = Address.parse("")
    end
  end

  describe "to_string/2" do
    @tag :templates
    test "formats a US address" do
      address = %AddressStruct{
        house_number: "301",
        road: "Hamilton Avenue",
        city: "Palo Alto",
        state: "CA",
        postcode: "94303",
        territory: "United States of America",
        territory_code: "US"
      }

      assert {:ok, formatted} = Address.to_string(address)
      assert is_binary(formatted)
      assert formatted =~ "301"
      assert formatted =~ "Hamilton Avenue"
      assert formatted =~ "Palo Alto"
    end

    @tag :templates
    test "formats a UK address" do
      address = %AddressStruct{
        house_number: "10",
        road: "Downing Street",
        city: "London",
        postcode: "SW1A 2AA",
        territory: "United Kingdom",
        territory_code: "GB"
      }

      assert {:ok, formatted} = Address.to_string(address)
      assert is_binary(formatted)
      assert formatted =~ "Downing Street"
    end

    @tag :templates
    test "formats with territory override" do
      address = %AddressStruct{
        house_number: "1",
        road: "Infinite Loop",
        city: "Cupertino",
        state: "CA",
        postcode: "95014",
        territory_code: "US"
      }

      assert {:ok, formatted} = Address.to_string(address, territory: "US")
      assert is_binary(formatted)
    end
  end
end
