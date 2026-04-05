defmodule Localize.Address.Formatter do
  @moduledoc """
  Formats a `Localize.Address` struct into a human-readable
  string using OpenCageData address formatting templates.

  Templates must be downloaded and compiled before use by
  running `mix localize.address.download_templates`.

  """

  alias Localize.Address.Address

  @templates_path "priv/address_templates.etf"

  if File.exists?(@templates_path) do
    @external_resource @templates_path
    @template_data :erlang.binary_to_term(File.read!(@templates_path))
  else
    @template_data nil
  end

  @doc """
  Formats an address struct as a string for the given territory.

  ### Arguments

  * `address` is a `Localize.Address.Address` struct.

  * `territory_code` is an ISO 3166-1 alpha-2 territory code
    string (e.g., `"US"`, `"GB"`).

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
      iex> {:ok, formatted} = Localize.Address.Formatter.format(address, "US")
      iex> is_binary(formatted)
      true

  """
  @spec format(Address.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def format(%Address{} = address, territory_code) do
    if @template_data do
      do_format(address, String.upcase(territory_code), @template_data)
    else
      {:error, "address templates not compiled; run: mix localize.address.download_templates"}
    end
  end

  @doc """
  Formats an address with additional component bindings.

  Like `format/2` but accepts a map of extra string-keyed bindings
  that supplement the struct fields. This is used when the caller has
  component values that don't map directly to struct fields (e.g.,
  `"suburb"`, `"town"`, `"pedestrian"`) but are referenced by
  templates.

  ### Arguments

  * `address` is a `Localize.Address.Address` struct.

  * `extra_bindings` is a map of `%{String.t() => String.t()}`
    providing additional template variable values.

  * `territory_code` is an ISO 3166-1 alpha-2 territory code string.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, reason}` if formatting fails.

  """
  @spec format_with_bindings(Address.t(), map(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def format_with_bindings(%Address{} = address, extra_bindings, territory_code)
      when is_map(extra_bindings) do
    if @template_data do
      do_format(address, String.upcase(territory_code), @template_data, extra_bindings)
    else
      {:error, "address templates not compiled; run: mix localize.address.download_templates"}
    end
  end

  defp do_format(address, territory_code, data, extra_bindings \\ %{}) do
    country_config = resolve_country_config(territory_code, data)
    address = apply_add_component(address, country_config)
    address = apply_change_country(address, country_config)

    bindings =
      build_bindings(address)
      |> Map.merge(extra_bindings)
      |> apply_component_aliases(data)
      |> apply_component_replace(country_config)
      |> add_state_code(territory_code, data)
      |> add_county_code(territory_code, data)
      |> apply_attention(data)

    # Use fallback template when minimal components (road + postcode) are missing
    {template, first_of} =
      if minimal_components?(bindings) do
        {country_config.address_template, country_config.address_first_of}
      else
        {country_config.fallback_template || country_config.address_template,
         country_config.fallback_first_of || country_config.address_first_of}
      end

    result = render_template(template, first_of, bindings)

    result =
      if empty_result?(result) do
        {alt_template, alt_first_of} =
          if minimal_components?(bindings) do
            {country_config.fallback_template, country_config.fallback_first_of}
          else
            {country_config.address_template, country_config.address_first_of}
          end

        render_template(alt_template, alt_first_of, bindings)
      else
        result
      end

    result = apply_replace(result, country_config.replace)
    result = apply_postformat_replace(result, country_config.postformat_replace)
    result = clean_output(result)

    {:ok, result}
  end

  # ── Country config resolution ──────────────────────────────────

  defp resolve_country_config(territory_code, data) do
    case Map.get(data.countries, territory_code) do
      nil ->
        data.default

      %{use_country: use_code} = config when is_binary(use_code) ->
        parent_config = resolve_country_config(String.upcase(use_code), data)

        Map.merge(parent_config, config, fn
          _key, parent_value, nil -> parent_value
          _key, _parent_value, child_value -> child_value
        end)

      config ->
        config
    end
  end

  # ── Pre-processing ─────────────────────────────────────────────

  defp apply_add_component(address, %{add_component: components}) when is_list(components) do
    Enum.reduce(components, address, fn
      component, acc when is_map(component) ->
        Enum.reduce(component, acc, fn {field, value}, inner_acc ->
          field_atom = safe_to_atom(field)

          if field_atom && Map.has_key?(inner_acc, field_atom) &&
               is_nil(Map.get(inner_acc, field_atom)) do
            Map.put(inner_acc, field_atom, value)
          else
            inner_acc
          end
        end)

      _, acc ->
        acc
    end)
  end

  defp apply_add_component(address, _config), do: address

  defp apply_change_country(address, %{change_country: replacement})
       when is_binary(replacement) do
    # Interpolate $component references in change_country
    new_country =
      Regex.replace(~r/\$(\w+)/, replacement, fn _full, component ->
        case component do
          "state" -> address.state || ""
          "city" -> address.city || ""
          "county" -> address.county || ""
          _ -> ""
        end
      end)

    %{address | territory: new_country}
  end

  defp apply_change_country(address, _config), do: address

  # ── Binding construction ───────────────────────────────────────

  defp build_bindings(%Address{} = address) do
    address
    |> Map.from_struct()
    |> Map.delete(:raw_input)
    |> Map.put(:country, address.territory)
    |> Map.put(:country_code, address.territory_code)
    |> Enum.reject(fn {_key, value} -> is_nil(value) || value == "" end)
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
  end

  # Resolve component aliases: if a binding has an alias name,
  # also set the canonical name (e.g., "suburb" -> also set "neighbourhood")
  defp apply_component_aliases(bindings, data) do
    aliases = Map.get(data, :component_aliases, %{})

    Enum.reduce(bindings, bindings, fn {key, value}, acc ->
      case Map.get(aliases, key) do
        nil -> acc
        ^key -> acc
        canonical -> Map.put_new(acc, canonical, value)
      end
    end)
  end

  # Derive state_code from state name using reverse lookup.
  # Also checks the parent country's codes if the territory uses use_country.
  defp add_state_code(bindings, territory_code, data) do
    state_codes =
      get_in_data(data, [:state_codes, territory_code]) ||
        get_parent_codes(territory_code, data, :state_codes)

    cond do
      Map.has_key?(bindings, "state_code") ->
        # Already has state_code; also populate state name if missing
        if state_codes && !Map.has_key?(bindings, "state") do
          code = bindings["state_code"]
          name = Map.get(state_codes, code)
          if name, do: Map.put(bindings, "state", name), else: bindings
        else
          bindings
        end

      state_codes && Map.has_key?(bindings, "state") ->
        state_name = bindings["state"]
        # Build reverse lookup: name -> code
        code = reverse_lookup(state_codes, state_name)

        if code do
          Map.put(bindings, "state_code", code)
        else
          bindings
        end

      true ->
        bindings
    end
  end

  # Derive county_code from county name using reverse lookup
  defp add_county_code(bindings, territory_code, data) do
    county_codes =
      get_in_data(data, [:county_codes, territory_code]) ||
        get_parent_codes(territory_code, data, :county_codes)

    cond do
      Map.has_key?(bindings, "county_code") ->
        bindings

      county_codes && Map.has_key?(bindings, "county") ->
        county_name = bindings["county"]
        code = reverse_lookup(county_codes, county_name)
        if code, do: Map.put(bindings, "county_code", code), else: bindings

      true ->
        bindings
    end
  end

  # Collect unknown/POI components into "attention" field
  # All known component names plus their aliases. Components not in this set
  # are collected into the "attention" field for POI display.
  @known_components (if @template_data do
                       @template_data.component_aliases
                       |> Map.keys()
                       |> MapSet.new()
                       |> MapSet.union(
                         MapSet.new([
                           "house_number",
                           "house",
                           "road",
                           "neighbourhood",
                           "city",
                           "municipality",
                           "county",
                           "state_district",
                           "state",
                           "postcode",
                           "country",
                           "country_code",
                           "territory",
                           "territory_code",
                           "island",
                           "archipelago",
                           "continent",
                           "state_code",
                           "county_code",
                           "attention"
                         ])
                       )
                     else
                       MapSet.new()
                     end)

  defp apply_attention(bindings, _data) do
    if Map.has_key?(bindings, "attention") do
      bindings
    else
      unknown_values =
        bindings
        |> Enum.reject(fn {key, _} -> MapSet.member?(@known_components, key) end)
        |> Enum.map(fn {_, value} -> value end)
        |> Enum.reject(&(&1 == "" || is_nil(&1)))

      case unknown_values do
        [] -> bindings
        values -> Map.put(bindings, "attention", Enum.join(values, ", "))
      end
    end
  end

  # Apply component-level replace rules (rules prefixed with "key=")
  defp apply_component_replace(bindings, country_config) do
    replacements = Map.get(country_config, :replace, [])

    Enum.reduce(replacements, bindings, fn {pattern, replacement}, acc ->
      case Regex.named_captures(~r/^(?<key>\w+)=(?<re>.+)$/, pattern) do
        %{"key" => key, "re" => regex_str} ->
          if Map.has_key?(acc, key) do
            case Regex.compile(regex_str) do
              {:ok, regex} ->
                new_value = Regex.replace(regex, acc[key], replacement)
                Map.put(acc, key, new_value)

              {:error, _} ->
                acc
            end
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  # ── Template rendering ─────────────────────────────────────────

  defp render_template(nil, _first_of, _bindings), do: ""

  defp render_template(template, first_of, bindings) do
    resolved_bindings = resolve_first_of(first_of, bindings)
    all_bindings = Map.merge(bindings, resolved_bindings)

    Regex.replace(~r/\{\$(\w+)\}/, template, fn _full, var_name ->
      Map.get(all_bindings, var_name, "")
    end)
  end

  defp resolve_first_of(first_of, bindings) when is_map(first_of) do
    for {var_name, candidates} <- first_of, into: %{} do
      value =
        Enum.find_value(candidates, "", fn candidate ->
          case Map.get(bindings, candidate) do
            nil -> nil
            "" -> nil
            value -> value
          end
        end)

      {var_name, value}
    end
  end

  defp resolve_first_of(_, _bindings), do: %{}

  # ── Post-processing ────────────────────────────────────────────

  # Apply replace rules that are NOT component-specific (no "key=" prefix)
  defp apply_replace(text, replacements) when is_list(replacements) do
    Enum.reduce(replacements, text, fn {pattern, replacement}, acc ->
      if String.match?(pattern, ~r/^\w+=/) do
        # Component-specific replace, already handled in apply_component_replace
        acc
      else
        case Regex.compile(pattern) do
          {:ok, regex} -> Regex.replace(regex, acc, replacement)
          {:error, _} -> acc
        end
      end
    end)
  end

  defp apply_replace(text, _), do: text

  defp apply_postformat_replace(text, replacements) when is_list(replacements) do
    Enum.reduce(replacements, text, fn {pattern, replacement}, acc ->
      case Regex.compile(pattern) do
        {:ok, regex} -> Regex.replace(regex, acc, replacement)
        {:error, _} -> acc
      end
    end)
  end

  defp apply_postformat_replace(text, _), do: text

  defp clean_output(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reject(&only_punctuation?/1)
    |> deduplicate_lines()
    |> Enum.join("\n")
    |> String.replace(~r/[ ]{2,}/, " ")
    |> String.replace(~r/,\s*,/, ",")
    |> String.replace(~r/^[,\s]+|[,\s]+$/u, "")
    |> String.trim()
  end

  defp deduplicate_lines(lines) do
    {result, _seen} =
      Enum.reduce(lines, {[], MapSet.new()}, fn line, {acc, seen} ->
        normalized = String.downcase(String.trim(line))

        if MapSet.member?(seen, normalized) do
          {acc, seen}
        else
          {acc ++ [line], MapSet.put(seen, normalized)}
        end
      end)

    result
  end

  defp only_punctuation?(line) do
    String.match?(line, ~r/^[\s,;.\-]+$/)
  end

  # The reference Perl implementation uses the fallback template only
  # when BOTH "road" and "postcode" are missing. If at least one is
  # present, the main address template is used.
  defp minimal_components?(bindings) do
    has_road? =
      Map.has_key?(bindings, "road") || Map.has_key?(bindings, "street") ||
        Map.has_key?(bindings, "pedestrian")

    has_postcode? = Map.has_key?(bindings, "postcode")

    has_road? or has_postcode?
  end

  defp empty_result?(text) do
    text
    |> String.replace(~r/[\s,;.\-]/, "")
    |> String.trim()
    |> String.length() == 0
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp get_parent_codes(territory_code, data, codes_key) do
    case get_in_data(data, [:countries, territory_code, :use_country]) do
      nil -> nil
      parent_code -> get_in_data(data, [codes_key, String.upcase(parent_code)])
    end
  end

  defp reverse_lookup(codes_map, name) when is_map(codes_map) and is_binary(name) do
    upper_name = String.upcase(name)

    Enum.find_value(codes_map, fn {code, full_name} ->
      cond do
        is_binary(full_name) && String.upcase(full_name) == upper_name ->
          code

        is_map(full_name) ->
          names = Map.values(full_name)

          if Enum.any?(names, fn n -> is_binary(n) && String.upcase(n) == upper_name end) do
            code
          end

        true ->
          nil
      end
    end)
  end

  defp reverse_lookup(_, _), do: nil

  defp get_in_data(data, keys) do
    Enum.reduce_while(keys, data, fn key, acc ->
      case acc do
        %{} = map -> {:cont, Map.get(map, key)}
        _ -> {:halt, nil}
      end
    end)
  end

  @address_fields Address.__struct__()
                  |> Map.from_struct()
                  |> Map.keys()
                  |> MapSet.new()

  defp safe_to_atom(string) when is_binary(string) do
    atom = String.to_atom(string)
    if MapSet.member?(@address_fields, atom), do: atom, else: nil
  rescue
    _ -> nil
  end
end
