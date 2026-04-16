defmodule Localize.Address.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :localize_address,
      version: @version,
      name: "Localize.Address",
      source_url: "https://github.com/elixir-localize/localize_address",
      docs: docs(),
      description: description(),
      package: package(),
      elixir: "~> 1.19",
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_makefile: "c_src/Makefile",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_apps: ~w(mix yaml_elixir inets)a,
        flags: [
          :error_handling,
          :unknown
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    """
    Address parsing and locale-aware formatting for Elixir.
    Parses unstructured address strings via libpostal NIF and formats
    addresses using OpenCageData templates for 267 countries.
    """
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "c_src/localize_address_nif.c",
        "c_src/Makefile",
        "priv/address_templates.etf",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  defp links do
    %{
      "GitHub" => "https://github.com/elixir-localize/localize_address",
      "Readme" =>
        "https://github.com/elixir-localize/localize_address/blob/v#{@version}/README.md",
      "Changelog" =>
        "https://github.com/elixir-localize/localize_address/blob/v#{@version}/CHANGELOG.md"
    }
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      formatters: ["html", "markdown"],
      extras:
        [
          "README.md",
          "LICENSE.md",
          "CHANGELOG.md"
        ] ++ Path.wildcard("guides/*.md"),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      skip_undefined_reference_warnings_on:
        ["CHANGELOG.md", "open_cage_conformance.md"] ++ Path.wildcard("guides/*.md")
    ]
  end

  defp groups_for_modules do
    [
      "Public API": [Localize.Address, Localize.Address.Address],
      Internal: [Localize.Address.Nif, Localize.Address.Formatter, Localize.Address.Territory]
    ]
  end

  defp groups_for_extras do
    [
      Guides: Path.wildcard("guides/*.md"),
      Reference: ["open_cage_conformance.md"]
    ]
  end

  defp deps do
    [
      {:localize, "~> 0.14"},
      {:unicode_string, "~> 2.0"},
      {:elixir_make, "~> 0.4", runtime: false},
      {:yaml_elixir, "~> 2.9", runtime: false},
      {:ex_doc, "~> 0.34", only: [:release, :dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
