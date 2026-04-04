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

  defp do_format(address, territory_code, data) do
    country_config = resolve_country_config(territory_code, data)
    address = apply_add_component(address, country_config)
    address = apply_change_country(address, country_config)

    bindings = build_bindings(address)

    template = country_config.address_template
    first_of = country_config.address_first_of

    result = render_template(template, first_of, bindings)

    result =
      if empty_result?(result) do
        fallback = country_config.fallback_template
        fallback_first_of = country_config.fallback_first_of
        render_template(fallback, fallback_first_of, bindings)
      else
        result
      end

    result = apply_replace(result, country_config.replace)
    result = apply_postformat_replace(result, country_config.postformat_replace)
    result = clean_output(result)

    {:ok, result}
  end

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
    %{address | territory: replacement}
  end

  defp apply_change_country(address, _config), do: address

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

  defp apply_replace(text, replacements) when is_list(replacements) do
    Enum.reduce(replacements, text, fn {pattern, replacement}, acc ->
      case Regex.compile(pattern) do
        {:ok, regex} -> Regex.replace(regex, acc, replacement)
        {:error, _} -> acc
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
    |> Enum.join("\n")
    |> String.replace(~r/[ ]{2,}/, " ")
    |> String.replace(~r/,\s*,/, ",")
    |> String.replace(~r/^[,\s]+|[,\s]+$/u, "")
    |> String.trim()
  end

  defp only_punctuation?(line) do
    String.match?(line, ~r/^[\s,;.\-]+$/)
  end

  defp empty_result?(text) do
    text
    |> String.replace(~r/[\s,;.\-]/, "")
    |> String.trim()
    |> String.length() == 0
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
