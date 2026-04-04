defmodule Localize.Address.Nif do
  @moduledoc """
  NIF interface to the libpostal address parsing library.

  This module provides NIF bindings for parsing unstructured address
  strings into labeled components using libpostal's machine-learning
  models. The NIF is always compiled and loaded as a required
  dependency.

  Requires the libpostal C library to be installed on the system.
  On macOS: `brew install libpostal`.

  """

  @on_load :init

  @doc false
  def init do
    path = :code.priv_dir(:localize_address) ++ ~c"/localize_address_nif"

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc """
  Returns whether the NIF backend is available.

  ### Returns

  * `true` if the NIF shared library was loaded successfully.

  * `false` if the NIF is not compiled or libpostal is missing.

  ### Examples

      iex> is_boolean(Localize.Address.Nif.available?())
      true

  """
  @spec available?() :: boolean()
  def available? do
    case nif_parse("123 Main St", "") do
      {:ok, _components} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Parses an address string into labeled components.

  ### Arguments

  * `address_string` is the unstructured address string to parse.

  * `language` is an optional language hint (ISO 639-1 code) or
    empty string for automatic detection.

  ### Returns

  * `{:ok, components}` where `components` is a list of
    `{label, value}` binary tuples.

  * `{:error, reason}` if parsing fails.

  """
  @spec parse(String.t(), String.t()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, String.t()}
  def parse(address_string, language)
      when is_binary(address_string) and is_binary(language) do
    nif_parse(address_string, language)
  end

  @dialyzer {:no_return, nif_parse: 2}
  defp nif_parse(_address_string, _language) do
    :erlang.nif_error(:nif_library_not_loaded)
  end
end
