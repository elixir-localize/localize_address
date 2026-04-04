defmodule Localize.Address.TerritoryTest do
  use ExUnit.Case, async: true

  alias Localize.Address.Territory

  describe "resolve/1" do
    test "resolves explicit territory string" do
      assert Territory.resolve(territory: "GB") == "GB"
    end

    test "resolves explicit territory atom" do
      assert Territory.resolve(territory: :GB) == "GB"
    end

    test "resolves territory from locale string" do
      assert Territory.resolve(locale: "en-AU") == "AU"
    end

    test "resolves territory from locale atom" do
      assert Territory.resolve(locale: :en_AU) == "AU"
    end

    test "territory option takes precedence over locale" do
      assert Territory.resolve(territory: "GB", locale: "en-AU") == "GB"
    end

    test "falls back to default locale when no options" do
      result = Territory.resolve([])
      assert is_binary(result)
      assert String.length(result) == 2
    end

    test "falls back to US for invalid territory" do
      assert Territory.resolve(territory: "INVALID") == "US"
    end
  end
end
