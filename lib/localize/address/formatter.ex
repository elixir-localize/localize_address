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

    bindings =
      build_bindings(address)
      |> Map.merge(extra_bindings)
      |> apply_add_component_bindings(country_config)
      |> apply_change_country_bindings(country_config)
      |> apply_component_aliases(data)
      |> sanitize_components()
      |> sanitize_postcode()
      |> apply_component_replace(country_config)
      |> normalize_washington_dc(territory_code)
      |> add_state_code(territory_code, data)
      |> add_county_code(territory_code, data)
      |> apply_attention(data)

    # Use fallback template when minimal components (road + postcode) are missing
    {template, first_of} =
      if minimal_components?(bindings) do
        {country_config.address_template, country_config.address_first_of}
      else
        fallback_t = country_config.fallback_template
        fallback_fo = country_config.fallback_first_of

        if fallback_t && fallback_t != "" do
          {fallback_t, fallback_fo || %{}}
        else
          {country_config.address_template, country_config.address_first_of}
        end
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
    result = clean_output(result)
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
          _key, parent_value, [] -> parent_value
          _key, parent_value, %{} -> parent_value
          _key, _parent_value, child_value -> child_value
        end)

      config ->
        config
    end
  end

  # ── Pre-processing (operates on bindings map) ───────────────────

  # Apply add_component rules to the bindings map. Only sets values
  # for keys that are not already present.
  defp apply_add_component_bindings(bindings, %{add_component: components})
       when is_list(components) do
    Enum.reduce(components, bindings, fn
      component, acc when is_map(component) ->
        Enum.reduce(component, acc, fn {field, value}, inner_acc ->
          Map.put_new(inner_acc, field, value)
        end)

      _, acc ->
        acc
    end)
  end

  defp apply_add_component_bindings(bindings, _config), do: bindings

  # Apply change_country by interpolating $component references in
  # the country binding value. Operates on bindings so it has access
  # to all component values including extra_bindings.
  defp apply_change_country_bindings(bindings, %{change_country: replacement})
       when is_binary(replacement) do
    new_country =
      Regex.replace(~r/\$(\w+)/, replacement, fn _full, component ->
        Map.get(bindings, component, "")
      end)

    Map.put(bindings, "country", new_country)
  end

  defp apply_change_country_bindings(bindings, _config), do: bindings

  # ── Binding construction ───────────────────────────────────────

  defp build_bindings(%Address{} = address) do
    address
    |> Map.from_struct()
    |> Map.delete(:raw_input)
    |> Map.delete(:territory)
    |> Map.delete(:territory_code)
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

  # Clean component values per the Perl reference's _sanity_cleaning:
  # reject postcodes that are too long or contain semicolons, and
  # remove values that contain URLs or other obvious garbage.
  defp sanitize_components(bindings) do
    bindings
    |> Map.new(fn {key, value} ->
      if is_binary(value) && String.match?(value, ~r{https?://}) do
        {key, ""}
      else
        {key, value}
      end
    end)
    |> Map.reject(fn {_key, value} -> value == "" end)
  end

  defp sanitize_postcode(bindings) do
    case Map.get(bindings, "postcode") do
      nil ->
        bindings

      postcode ->
        cond do
          String.length(postcode) > 20 ->
            Map.delete(bindings, "postcode")

          String.match?(postcode, ~r/\d+;\d+/) ->
            Map.delete(bindings, "postcode")

          match = Regex.run(~r/^(\d{5}),\d{5}/, postcode) ->
            Map.put(bindings, "postcode", Enum.at(match, 1))

          true ->
            bindings
        end
    end
  end

  # Washington DC is both a city and a state. When the state field contains
  # "Washington DC" or "Washington, D.C.", split it into city + state_code.
  defp normalize_washington_dc(bindings, territory_code)
       when territory_code in ["US", "VI", "GU", "AS", "MP", "PR"] do
    case Map.get(bindings, "state") do
      "Washington DC" ->
        bindings
        |> Map.put_new("city", "Washington")
        |> Map.put("state_code", "DC")
        |> Map.put("state", "District of Columbia")

      "Washington, D.C." ->
        bindings
        |> Map.put_new("city", "Washington")
        |> Map.put("state_code", "DC")
        |> Map.put("state", "District of Columbia")

      "District of Columbia" ->
        bindings
        |> Map.put_new("city", "Washington")
        |> Map.put("state_code", "DC")

      _ ->
        bindings
    end
  end

  defp normalize_washington_dc(bindings, _territory_code), do: bindings

  # Derive state_code from state name using reverse lookup.
  # Also checks the parent country's codes if the territory uses use_country.
  defp add_state_code(bindings, territory_code, data) do
    state_codes =
      get_in_data(data, [:state_codes, territory_code]) ||
        get_parent_codes(territory_code, data, :state_codes)

    cond do
      Map.has_key?(bindings, "state_code") ->
        # Already has state_code; also populate state name if missing
        bindings = populate_state_name(bindings, state_codes, territory_code)
        bindings

      Map.has_key?(bindings, "state") ->
        state_name = bindings["state"]

        # Try OpenCageData state_codes first. Only use Localize fallback
        # when the territory has state_codes data (meaning it actually
        # uses abbreviated state codes in addresses).
        code =
          if state_codes do
            reverse_lookup(state_codes, state_name) ||
              subdivision_code_from_name(territory_code, state_name)
          end

        if code do
          Map.put(bindings, "state_code", code)
        else
          bindings
        end

      true ->
        bindings
    end
  end

  # If state_code is set but state name is not, look up the full name
  defp populate_state_name(bindings, state_codes, territory_code) do
    if Map.has_key?(bindings, "state") do
      bindings
    else
      code = bindings["state_code"]

      name =
        if state_codes do
          case Map.get(state_codes, code) do
            name when is_binary(name) -> name
            %{"default" => name} -> name
            _ -> nil
          end
        end

      name = name || subdivision_name_from_code(territory_code, code)
      if name, do: Map.put(bindings, "state", name), else: bindings
    end
  end

  # Use Localize to look up subdivision name from code
  defp subdivision_name_from_code(territory_code, code) when is_binary(code) do
    subdivision_atom =
      String.to_atom(String.downcase(territory_code) <> String.downcase(code))

    case Localize.Territory.subdivision_name(subdivision_atom, locale: :en) do
      {:ok, name} -> name
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # Use Localize to find subdivision code from name
  defp subdivision_code_from_name(territory_code, name) when is_binary(name) do
    territory_lower = String.downcase(territory_code)
    prefix_len = String.length(territory_lower)

    subdivisions =
      Localize.SupplementalData.territory_subdivisions()
      |> Map.get(String.to_atom(territory_code), [])

    upper_name = String.upcase(name)

    Enum.find_value(subdivisions, fn sub_atom ->
      sub_str = Atom.to_string(sub_atom)
      code_part = String.slice(sub_str, prefix_len..-1//1) |> String.upcase()

      case Localize.Territory.subdivision_name(sub_atom, locale: :en) do
        {:ok, sub_name} ->
          if String.upcase(sub_name) == upper_name, do: code_part

        _ ->
          nil
      end
    end)
  rescue
    _ -> nil
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

  # Apply replace rules to component values. Rules with "key=" prefix
  # apply only to the named component. Rules without a prefix apply
  # to ALL component values (the Perl reference behavior).
  defp apply_component_replace(bindings, country_config) do
    replacements = Map.get(country_config, :replace, [])

    Enum.reduce(replacements, bindings, fn {pattern, replacement}, acc ->
      case Regex.named_captures(~r/^(?<key>\w+)=(?<re>.+)$/, pattern) do
        %{"key" => key, "re" => regex_str} ->
          apply_regex_to_key(acc, key, regex_str, replacement)

        _ ->
          apply_regex_to_all(acc, pattern, replacement)
      end
    end)
  end

  defp apply_regex_to_key(bindings, key, regex_str, replacement) do
    if Map.has_key?(bindings, key) do
      case Regex.compile(regex_str, [:caseless]) do
        {:ok, regex} ->
          new_value = Regex.replace(regex, bindings[key], convert_backreferences(replacement))
          Map.put(bindings, key, new_value)

        {:error, _} ->
          bindings
      end
    else
      bindings
    end
  end

  defp apply_regex_to_all(bindings, pattern, replacement) do
    case Regex.compile(pattern, [:caseless]) do
      {:ok, regex} ->
        converted = convert_backreferences(replacement)

        Map.new(bindings, fn {key, value} ->
          if is_binary(value) do
            {key, Regex.replace(regex, value, converted)}
          else
            {key, value}
          end
        end)

      {:error, _} ->
        bindings
    end
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
          resolve_candidate(candidate, bindings)
        end)

      {var_name, value}
    end
  end

  defp resolve_first_of(_, _bindings), do: %{}

  # Simple candidate: single variable name
  defp resolve_candidate(candidate, bindings) when is_binary(candidate) do
    case Map.get(bindings, candidate) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  # Compound candidate: a mini-template with multiple variables.
  # Resolves all variables; returns nil if ANY required variable is missing.
  defp resolve_candidate({:compound, template}, bindings) do
    # Extract all variable names from the template
    vars = Regex.scan(~r/\{\$(\w+)\}/, template) |> Enum.map(fn [_, name] -> name end)

    # Check that at least one variable has a value
    if Enum.any?(vars, fn var -> Map.get(bindings, var) not in [nil, ""] end) do
      result =
        Regex.replace(~r/\{\$(\w+)\}/, template, fn _full, var_name ->
          Map.get(bindings, var_name, "")
        end)
        |> String.trim()

      if result == "", do: nil, else: result
    end
  end

  defp resolve_candidate(_, _bindings), do: nil

  # ── Post-processing ────────────────────────────────────────────

  # Apply replace rules that are NOT component-specific (no "key=" prefix)
  defp apply_replace(text, replacements) when is_list(replacements) do
    Enum.reduce(replacements, text, fn {pattern, replacement}, acc ->
      if String.match?(pattern, ~r/^\w+=/) do
        # Component-specific replace, already handled in apply_component_replace
        acc
      else
        case Regex.compile(pattern) do
          {:ok, regex} ->
            Regex.replace(regex, acc, convert_backreferences(replacement))

          {:error, _} ->
            acc
        end
      end
    end)
  end

  defp apply_replace(text, _), do: text

  defp apply_postformat_replace(text, replacements) when is_list(replacements) do
    Enum.reduce(replacements, text, fn {pattern, replacement}, acc ->
      case Regex.compile(pattern) do
        {:ok, regex} ->
          Regex.replace(regex, acc, convert_backreferences(replacement))

        {:error, _} ->
          acc
      end
    end)
  end

  defp apply_postformat_replace(text, _), do: text

  # OpenCageData uses Perl-style backreferences ($1, $2) but Elixir's
  # Regex.replace/4 uses \\1, \\2. Convert at application time.
  defp convert_backreferences(replacement) do
    Regex.replace(~r/\$(\d+)/, replacement, "\\\\\\1")
  end

  defp clean_output(text) do
    text
    |> String.split("\n")
    |> Enum.map(&clean_line/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reject(&only_punctuation?/1)
    |> deduplicate_lines()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp clean_line(line) do
    line
    |> String.trim()
    |> String.replace(~r/[ ]{2,}/, " ")
    |> String.replace(~r/,\s*,+/, ",")
    |> deduplicate_within_line()
    |> String.replace(~r/^[,\s\-]+/, "")
    |> String.replace(~r/[,\s\-]+$/, "")
    |> String.trim()
  end

  # Remove duplicate comma-separated segments within a single line.
  # E.g., "Alhambra, Ermita, Ermita" → "Alhambra, Ermita"
  # Exception: "New York" is allowed to repeat (per Perl reference).
  defp deduplicate_within_line(line) do
    parts = String.split(line, ",") |> Enum.map(&String.trim/1)

    {result, _seen} =
      Enum.reduce(parts, {[], MapSet.new()}, fn part, {acc, seen} ->
        normalized = String.downcase(part)

        cond do
          normalized == "" ->
            {acc, seen}

          normalized == "new york" ->
            {acc ++ [part], seen}

          MapSet.member?(seen, normalized) ->
            {acc, seen}

          true ->
            {acc ++ [part], MapSet.put(seen, normalized)}
        end
      end)

    Enum.join(result, ", ")
  end

  # Only remove CONSECUTIVE duplicate lines, not all duplicates globally.
  # This preserves valid repetitions like "New York" (city) and "New York"
  # (state) on non-adjacent lines, while removing true adjacent duplicates
  # like "Berlin" appearing twice in a row.
  defp deduplicate_lines(lines) do
    lines
    |> Enum.chunk_while(
      nil,
      fn line, prev ->
        normalized = String.downcase(String.trim(line))
        prev_normalized = if prev, do: String.downcase(String.trim(prev)), else: nil

        if prev_normalized && normalized == prev_normalized do
          {:cont, prev}
        else
          if prev, do: {:cont, prev, line}, else: {:cont, line}
        end
      end,
      fn
        nil -> {:cont, nil}
        acc -> {:cont, acc, nil}
      end
    )
    |> Enum.reject(&is_nil/1)
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
end
