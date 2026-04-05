defmodule LocalizeAddress.MixProject do
  use Mix.Project

  def project do
    [
      app: :localize_address,
      version: "0.1.0",
      elixir: "~> 1.19",
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_makefile: "c_src/Makefile",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:localize, path: "../localize"},
      {:unicode_string, path: "../unicode_string"},
      {:elixir_make, "~> 0.4", runtime: false},
      {:yaml_elixir, "~> 2.9", runtime: false}
    ]
  end
end
