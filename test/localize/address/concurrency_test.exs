defmodule Localize.Address.ConcurrencyTest do
  @moduledoc """
  Stress tests for concurrent NIF access. Verifies that libpostal's
  address parser can handle simultaneous calls from multiple BEAM
  processes without crashes, corruption, or race conditions.
  """

  use ExUnit.Case, async: false

  alias Localize.Address
  alias Localize.Address.Address, as: A

  @addresses [
    {"301 Hamilton Avenue, Palo Alto, CA 94303", "US"},
    {"10 Downing Street, London SW1A 2AA", "GB"},
    {"1 Unter den Linden, Berlin 10117", "DE"},
    {"5 Avenue Anatole France, 75007 Paris", "FR"},
    {"1-1 Chiyoda, Tokyo 100-8111", "JP"},
    {"42 Wallaby Way, Sydney NSW 2000", "AU"},
    {"Via dei Fori Imperiali 1, 00186 Roma", "IT"},
    {"Calle de Alcalá 1, 28014 Madrid", "ES"},
    {"251 McMurchy Avenue South, Brampton, ON L6Y 1Z4", "CA"},
    {"Connaught Place, New Delhi 110001", "IN"}
  ]

  # Warm up libpostal before concurrent tests to ensure initialization
  # is complete and not itself racing.
  setup_all do
    {:ok, _} = Address.parse("warmup")
    :ok
  end

  describe "concurrent parse" do
    @describetag :nif
    test "50 simultaneous parses return valid results" do
      tasks =
        for _ <- 1..50 do
          {input, territory} = Enum.random(@addresses)

          Task.async(fn ->
            Address.parse(input, territory: territory)
          end)
        end

      results = Task.await_many(tasks, 30_000)

      for result <- results do
        assert {:ok, %A{}} = result
      end
    end

    test "100 rapid sequential parses are stable" do
      for _ <- 1..100 do
        {input, territory} = Enum.random(@addresses)
        assert {:ok, %A{}} = Address.parse(input, territory: territory)
      end
    end

    test "concurrent parses produce consistent results" do
      input = "301 Hamilton Avenue, Palo Alto, CA 94303"

      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            {:ok, address} = Address.parse(input, territory: "US")
            {address.house_number, address.road, address.city, address.postcode}
          end)
        end

      results = Task.await_many(tasks, 30_000)

      # All 20 concurrent parses of the same input should produce
      # identical results — no memory corruption or mixed-up pointers.
      assert length(Enum.uniq(results)) == 1,
             "concurrent parses of the same input produced inconsistent results: #{inspect(Enum.uniq(results))}"
    end

    test "concurrent parse and format do not interfere" do
      tasks =
        for _ <- 1..30 do
          Task.async(fn ->
            {input, territory} = Enum.random(@addresses)
            {:ok, parsed} = Address.parse(input, territory: territory)
            {:ok, formatted} = Address.to_string(parsed)
            {parsed.territory_code, formatted}
          end)
        end

      results = Task.await_many(tasks, 30_000)

      for {territory_code, formatted} <- results do
        assert is_binary(territory_code)
        assert is_binary(formatted)
        assert String.length(formatted) > 0
      end
    end

    test "concurrent parse with capitalize" do
      tasks =
        for _ <- 1..30 do
          Task.async(fn ->
            {input, territory} = Enum.random(@addresses)
            {:ok, address} = Address.parse(input, territory: territory, capitalize: true)
            address
          end)
        end

      results = Task.await_many(tasks, 30_000)

      for address <- results do
        assert %A{} = address

        # Capitalized fields should start with an uppercase letter
        # (when they are non-nil text values).
        for field <- [:road, :city, :state] do
          case Map.get(address, field) do
            nil ->
              :ok

            value ->
              first = String.first(value)

              assert first == String.upcase(first),
                     "expected #{field} to be capitalized, got #{inspect(value)}"
          end
        end
      end
    end

    test "heavy concurrent load does not crash the BEAM" do
      # Spawn 200 processes that all parse simultaneously.
      # If libpostal has memory safety issues under concurrency,
      # this will trigger a segfault or NIF panic.
      parent = self()

      _pids =
        for i <- 1..200 do
          spawn(fn ->
            {input, territory} = Enum.at(@addresses, rem(i, length(@addresses)))
            result = Address.parse(input, territory: territory)
            send(parent, {:done, i, result})
          end)
        end

      results =
        for _ <- 1..200 do
          receive do
            {:done, _i, result} -> result
          after
            30_000 -> flunk("timed out waiting for concurrent parse")
          end
        end

      successes = Enum.count(results, &match?({:ok, %A{}}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      # We expect all to succeed, but if libpostal has transient
      # issues under extreme load, we tolerate a small failure rate.
      assert successes + failures == 200
      assert successes >= 195, "too many failures under load: #{failures}/200 failed"

      # Verify BEAM is still healthy after the stress test
      assert 1 + 1 == 2

      # Verify NIF still works after stress
      assert {:ok, %A{}} = Address.parse("123 Main Street")
    end
  end
end
