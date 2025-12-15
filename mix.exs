defmodule JSONRPC2.Service.MixProject do
  use Mix.Project

  def project do
    [
      app: :jsonrpc2_service,
      version: "0.1.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      maintainers: ["undr@yandex.ru"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/undr/jsonrpc2_service"}
    ]
  end

  defp description do
    "Provides the ability to create services in accordance with the JSONRPC 2.0 specification. " <>
      "There is no transport layer, but only tools for creating transport-independent JSONRPC 2.0 services."
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gettext, "~> 1.0.2"},
      {:jsonrpc2_spec, "~> 0.1.1"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
