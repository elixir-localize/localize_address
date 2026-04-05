defmodule Mix.Tasks.Localize.Address.DownloadTemplates do
  @shortdoc "Downloads and compiles address formatting templates from OpenCageData"

  @moduledoc """
  Downloads address formatting templates from the OpenCageData
  address-formatting repository and compiles them into an Erlang
  term file for fast runtime loading.

  ## Usage

      mix localize.address.download_templates

  The compiled templates are written to `priv/address_templates.etf`.
  This task should be run whenever the upstream templates are updated.

  """

  use Mix.Task

  @worldwide_url "https://raw.githubusercontent.com/OpenCageData/address-formatting/master/conf/countries/worldwide.yaml"
  @components_url "https://raw.githubusercontent.com/OpenCageData/address-formatting/master/conf/components.yaml"
  @state_codes_url "https://raw.githubusercontent.com/OpenCageData/address-formatting/master/conf/state_codes.yaml"
  @county_codes_url "https://raw.githubusercontent.com/OpenCageData/address-formatting/master/conf/county_codes.yaml"
  @testcases_index_url "https://api.github.com/repos/OpenCageData/address-formatting/contents/testcases/countries"
  @testcases_raw_base "https://raw.githubusercontent.com/OpenCageData/address-formatting/master/testcases/countries"

  @output_path "priv/address_templates.etf"

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    Mix.shell().info("Downloading address formatting templates...")

    worldwide_yaml = download!(@worldwide_url)
    components_yaml = download!(@components_url)
    state_codes_yaml = download!(@state_codes_url)
    county_codes_yaml = download!(@county_codes_url)

    Mix.shell().info("Parsing YAML...")

    worldwide = YamlElixir.read_from_string!(worldwide_yaml)
    components_list = YamlElixir.read_all_from_string!(components_yaml)
    state_codes = YamlElixir.read_from_string!(state_codes_yaml)
    county_codes = YamlElixir.read_from_string!(county_codes_yaml)

    Mix.shell().info("Compiling templates...")

    component_aliases = build_component_aliases(components_list)

    {generics, fallbacks, countries} = partition_templates(worldwide)

    compiled_countries =
      for {code, config} <- countries, into: %{} do
        {String.upcase(code), compile_country(config, generics, fallbacks)}
      end

    default_config = Map.get(worldwide, "default", %{})
    compiled_default = compile_country(default_config, generics, fallbacks)

    Mix.shell().info("Downloading test cases...")
    testcases = download_testcases()

    data = %{
      countries: compiled_countries,
      default: compiled_default,
      component_aliases: component_aliases,
      state_codes: state_codes,
      county_codes: county_codes,
      testcases: testcases
    }

    File.mkdir_p!(Path.dirname(@output_path))
    File.write!(@output_path, :erlang.term_to_binary(data))

    total_tests = Enum.reduce(testcases, 0, fn {_, cases}, acc -> acc + length(cases) end)

    Mix.shell().info(
      "Wrote #{map_size(compiled_countries)} country templates and #{total_tests} test cases to #{@output_path}"
    )
  end

  defp download!(url) do
    case :httpc.request(:get, {String.to_charlist(url), []}, [{:ssl, ssl_options()}], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        IO.iodata_to_binary(body)

      {:ok, {{_, status, _}, _headers, _body}} ->
        Mix.raise("Failed to download #{url}: HTTP #{status}")

      {:error, reason} ->
        Mix.raise("Failed to download #{url}: #{inspect(reason)}")
    end
  end

  defp ssl_options do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp build_component_aliases(components_list) do
    Enum.reduce(components_list, %{}, fn component_map, acc ->
      name = Map.get(component_map, "name")
      aliases = Map.get(component_map, "aliases", [])

      if name do
        acc = Map.put(acc, name, name)

        Enum.reduce(aliases, acc, fn alias_name, inner_acc ->
          Map.put(inner_acc, alias_name, name)
        end)
      else
        acc
      end
    end)
  end

  defp partition_templates(worldwide) do
    generics =
      for {key, value} <- worldwide,
          String.starts_with?(key, "generic"),
          into: %{} do
        {key, value}
      end

    fallbacks =
      for {key, value} <- worldwide,
          String.starts_with?(key, "fallback"),
          into: %{} do
        {key, value}
      end

    countries =
      for {key, value} <- worldwide,
          is_map(value),
          not String.starts_with?(key, "generic"),
          not String.starts_with?(key, "fallback"),
          key != "default",
          into: %{} do
        {key, value}
      end

    {generics, fallbacks, countries}
  end

  defp compile_country(config, generics, fallbacks) when is_map(config) do
    address_template = resolve_template(config, "address_template", generics)
    fallback_template = resolve_template(config, "fallback_template", fallbacks)

    {mf2_address, address_first_of} = convert_template(address_template)
    {mf2_fallback, fallback_first_of} = convert_template(fallback_template)

    %{
      address_template: mf2_address,
      address_first_of: address_first_of,
      fallback_template: mf2_fallback,
      fallback_first_of: fallback_first_of,
      replace: compile_replace(Map.get(config, "replace", [])),
      postformat_replace: compile_replace(Map.get(config, "postformat_replace", [])),
      use_country: Map.get(config, "use_country"),
      add_component: compile_add_component(Map.get(config, "add_component")),
      change_country: Map.get(config, "change_country")
    }
  end

  defp compile_country(_config, _generics, _fallbacks), do: nil

  defp resolve_template(config, key, named_templates) do
    case Map.get(config, key) do
      nil ->
        nil

      template when is_binary(template) ->
        case Map.get(named_templates, template) do
          nil -> template
          resolved when is_binary(resolved) -> resolved
          _other -> template
        end
    end
  end

  defp convert_template(nil), do: {nil, %{}}

  defp convert_template(template) when is_binary(template) do
    {converted, first_of_map, _counter} =
      template
      |> String.split("\n")
      |> Enum.reduce({"", %{}, 0}, fn line, {acc_text, acc_first_of, counter} ->
        {new_line, new_first_of, new_counter} =
          convert_line(line, acc_first_of, counter)

        separator = if acc_text == "", do: "", else: "\n"
        {acc_text <> separator <> new_line, new_first_of, new_counter}
      end)

    {converted, first_of_map}
  end

  defp convert_line(line, first_of_map, counter) do
    case Regex.scan(~r/\{\{#first\}\}(.*?)\{\{\/first\}\}/s, line, return: :index) do
      [] ->
        {convert_variables(line), first_of_map, counter}

      matches ->
        {new_line, new_map, new_counter} =
          Enum.reduce(matches, {line, first_of_map, counter}, fn match_indices,
                                                                 {current_line, current_map,
                                                                  current_counter} ->
            [{full_start, full_len}, {inner_start, inner_len}] = match_indices
            full_match = String.slice(line, full_start, full_len)
            inner = String.slice(line, inner_start, inner_len)

            candidates =
              inner
              |> String.split("||")
              |> Enum.map(&extract_candidate/1)
              |> Enum.reject(&is_nil/1)

            var_name = "first_#{current_counter}"

            replaced = String.replace(current_line, full_match, "{$#{var_name}}", global: false)

            {replaced, Map.put(current_map, var_name, candidates), current_counter + 1}
          end)

        {convert_variables(new_line), new_map, new_counter}
    end
  end

  defp convert_variables(text) do
    Regex.replace(~r/\{\{\{(\w+)\}\}\}/, text, "{$\\1}")
  end

  # Extract candidate from a first-of option. A candidate can be a single
  # variable name (string) or a compound candidate (list of {var, separator}
  # tuples) when multiple variables appear in one option like
  # `{{{house_number}}} {{{road}}}`.
  defp extract_candidate(text) do
    trimmed = String.trim(text)
    vars = Regex.scan(~r/\{\{\{(\w+)\}\}\}/, trimmed) |> Enum.map(fn [_, name] -> name end)

    case vars do
      [] -> nil
      [single] -> single
      _multiple -> {:compound, extract_compound_template(trimmed)}
    end
  end

  # Preserve the template structure for compound candidates so that
  # separators between variables are maintained at render time.
  defp extract_compound_template(text) do
    Regex.replace(~r/\{\{\{(\w+)\}\}\}/, text, "{$\\1}")
    |> String.trim()
  end

  defp compile_replace(replacements) when is_list(replacements) do
    Enum.flat_map(replacements, fn
      # Two-element list: [pattern, replacement]
      [pattern, replacement] when is_binary(pattern) ->
        [{pattern, replacement || ""}]

      # Map format: %{pattern => replacement}
      replacement when is_map(replacement) ->
        Enum.map(replacement, fn {pattern, replacement_text} ->
          {pattern, replacement_text || ""}
        end)

      _ ->
        []
    end)
  end

  defp compile_replace(_), do: []

  defp compile_add_component(nil), do: []

  defp compile_add_component(value) when is_binary(value) do
    parse_add_component_string(value)
  end

  defp compile_add_component(values) when is_list(values) do
    Enum.flat_map(values, fn
      value when is_binary(value) -> parse_add_component_string(value)
      value when is_map(value) -> [value]
      _ -> []
    end)
  end

  defp compile_add_component(_), do: []

  defp parse_add_component_string(string) do
    case String.split(string, "=", parts: 2) do
      [key, value] -> [%{key => value}]
      _ -> []
    end
  end

  defp download_testcases do
    headers = [
      {~c"User-Agent", ~c"localize-address"}
    ]

    {:ok, {{_, 200, _}, _, body}} =
      :httpc.request(
        :get,
        {String.to_charlist(@testcases_index_url), headers},
        [{:ssl, ssl_options()}],
        []
      )

    entries =
      body
      |> IO.iodata_to_binary()
      |> :json.decode()
      |> Enum.map(fn entry -> entry["name"] end)
      |> Enum.filter(fn name -> String.ends_with?(name, ".yaml") end)

    Mix.shell().info("Found #{length(entries)} test case files")

    for file <- entries, reduce: %{} do
      acc ->
        country_code =
          file
          |> String.trim_trailing(".yaml")
          |> String.upcase()

        url = "#{@testcases_raw_base}/#{file}"

        case :httpc.request(:get, {String.to_charlist(url), []}, [{:ssl, ssl_options()}], []) do
          {:ok, {{_, 200, _}, _, file_body}} ->
            yaml_content = IO.iodata_to_binary(file_body)
            cases = parse_testcases(yaml_content, country_code)
            Map.put(acc, country_code, cases)

          _ ->
            acc
        end
    end
  end

  defp parse_testcases(yaml_content, country_code) do
    yaml_content
    |> YamlElixir.read_all_from_string!()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn testcase ->
      components = Map.get(testcase, "components", %{})

      %{
        description: Map.get(testcase, "description", ""),
        components: normalize_component_values(components),
        expected: String.trim(Map.get(testcase, "expected", "")),
        country_code: country_code
      }
    end)
  end

  defp normalize_component_values(components) do
    Map.new(components, fn {key, value} ->
      {key, to_string(value)}
    end)
  end
end
