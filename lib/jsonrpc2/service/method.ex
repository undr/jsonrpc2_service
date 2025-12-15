defmodule JSONRPC2.Service.Method do
  alias JSONRPC2.Spec

  @type result :: {:ok, any()} | {:error, any()} | {:jsonrpc2_error, any()}

  @callback handle_call(Spec.params(), Plug.Conn.t()) :: result()
  @callback handle_cast(Spec.params(), Plug.Conn.t()) :: result()
  @callback validate(Spec.params()) :: {:ok, Spec.params()} | {:invalid, keyword() | map()}
  @callback handle_exception(map(), Exception.t(), list()) :: {:jsonrpc2_error, any()}
  @callback handle_error(map(), {Exception.kind(), any()}, list()) :: {:jsonrpc2_error, any()}

  defmacro __using__(_) do
    quote location: :keep, generated: true do
      @behaviour unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      @type result :: unquote(__MODULE__).result()

      require Logger

      alias JSONRPC2.Spec
      alias JSONRPC2.Spec.Request

      @doc """
      Call service method.

      Example:

          iex> DivideMethod.call(%{"x" => 13, "y" => 5})
          {:ok, 3}

          iex> DivideMethod.call(%{"x" => 13, "y" => "5"})
          {:jsonrpc2_error, {:invalid_params, %{"y" => ["is not a integer"]}}}

          iex> DivideMethod.call(%{"x" => 13, "y" => 0})
          {:jsonrpc2_error, {12345, "bad argument in arithmetic expression"}}
      """
      @spec call(Spec.params(), map()) :: result()
      def call(params, conn \\ %{}) do
        unquote(__MODULE__).handle({__MODULE__, :handle_call}, params, conn)
      end

      @doc """
      Cast service method.

      Example:

          iex> DivideMethod.cast(%{"x" => 13, "y" => 5})
          {:ok, 3}

          iex> DivideMethod.cast(%{"x" => 13, "y" => "5"})
          {:jsonrpc2_error, {:invalid_params, %{"y" => ["is not a integer"]}}}

          iex> DivideMethod.cast(%{"x" => 13, "y" => 0})
          {:jsonrpc2_error, {12345, "bad argument in arithmetic expression"}}
      """
      @spec cast(Spec.params(), map()) :: result()
      def cast(params, conn \\ %{}) do
        unquote(__MODULE__).handle({__MODULE__, :handle_cast}, params, conn)
      end

      defp error!(code) do
        throw error(code)
      end

      defp error!(code, message_or_data) do
        throw error(code, message_or_data)
      end

      defp error!(code, message, data) do
        throw error(code, message, data)
      end

      defp error(code) do
        {:jsonrpc2_error, code}
      end

      defp error(code, message_or_data) do
        {:jsonrpc2_error, {code, message_or_data}}
      end

      defp error(code, message, data) do
        {:jsonrpc2_error, {code, message, data}}
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep, generated: true do
      def handle_call(params, conn) do
        error(:invalid_params)
      end

      def handle_cast(params, conn) do
        handle_call(params, conn)
      end

      def validate(params) do
        {:ok, params}
      end

      def handle_exception(request, ex, stacktrace) do
        {:jsonrpc2_error, {:server_error, %{ex: inspect(ex), message: Exception.format(:error, ex, stacktrace)}}}
      end

      def handle_error(request, {kind, payload}, stacktrace) do
        {:jsonrpc2_error, {:internal_error, %{kind: inspect(kind), payload: inspect(payload)}}}
      end
    end
  end

  @spec handle({module(), atom()}, Spec.params(), map()) :: result()
  def handle({module, func}, params, conn) do
    with {:ok, params} <- module.validate(params),
         {:ok, result} <- apply(module, func, [atomize_keys(params), conn]) do
      {:ok, result}
    else
      {:invalid, errors} ->
        {:jsonrpc2_error, {:invalid_params, errors}}

      error ->
        error
    end
  end

  defp atomize_keys(params) when is_map(params) do
    params
    |> Enum.map(fn {k, v} -> {String.to_atom(k), atomize_keys(v)} end)
    |> Enum.into(%{})
  end

  defp atomize_keys([head | rest]) do
    [atomize_keys(head) | atomize_keys(rest)]
  end

  defp atomize_keys(value) do
    value
  end
end
