defmodule JSONRPC2.Service do
  @moduledoc """
  `JSONRPC2.Service` helps to describe methods of service. Each method is a module which use `JSONRPC2.Service.Method`.

  Examples:

      defmodule CalculatorService do
        use JSONRPC2.Service

        method "add", AddMethod
        method "subtract", SubtractMethod
        method "multiply", MultiplyMethod
        method "divide", DivideMethod
      end

      defmodule AddMethod do
        use JSONRPC2.Service.Method
      end

      # and so on...

  It privides `handle` function as a single entry point to the service.

      iex> CalculatorService.handle(%{"jsonrpc" => "2.0", "id" => 2, "method" => "add", "params" => [1, 2]})
      %Result{jsonrpc: "2.0", id: 2, result: 3}

      iex> CalculatorService.handle(%{"jsonrpc" => "2.0", "id" => 2, "method" => "divide", "params" => [10, 0]})
      %Error{jsonrpc: "2.0", id: 2, error: %{code: 12345, message: "divided by zero"}}
  """

  require Logger

  alias JSONRPC2.Spec.Request
  alias JSONRPC2.Spec.Response
  alias JSONRPC2.Telemetry

  defmacro __using__(_) do
    quote location: :keep do
      @__service_methods__ []

      Module.register_attribute(__MODULE__, :__service_methods__, accumulate: true)

      import unquote(__MODULE__), only: [method: 2]

      @before_compile unquote(__MODULE__)

      @doc """
      Handle service requests.

      Example:

          iex> CalculatorService.handle(%{"jsonrpc" => "2.0", "id" => 2, "method" => "add", "params" => [1, 2]})
          %Result{jsonrpc: "2.0", id: 2, result: 3}

          iex> CalculatorService.handle(%{"jsonrpc" => "2.0", "id" => 2, "method" => "divide", "params" => [10, 0]})
          %Error{jsonrpc: "2.0", id: 2, error: %{code: 12345, message: "divided by zero"}}
      """
      def handle(%{"_json" => body_params}, conn) when is_list(body_params) do
        meta = %{req: body_params, ctx: conn}
        Telemetry.span(:service, meta, fn ->
          res = Enum.map(body_params, fn(one) -> handle_one(one, conn) end) |> drop_nils()
          {res, Map.put(meta, :res, res)}
        end)
      end

      def handle(body_params, conn) when is_map(body_params) do
        meta = %{req: body_params, ctx: conn}
        Telemetry.span(:service, meta, fn ->
          res = handle_one(body_params, conn)
          {res, Map.put(meta, :res, res)}
        end)
      end

      defp handle_one(body_params, conn) do
        with {:ok, request} <- Request.parse(body_params) do
          with :ok <- Request.valid?(request),
               {:ok, handler} <- handler_lookup(request.method),
               {:ok, result} <- exec_handler(handler, request, conn) do
            response(request.id, result)
          else
            {:jsonrpc2_error, code_or_tuple} ->
              error(request.id, code_or_tuple)

            {:error, error} ->
              error(request.id, {:internal_error, inspect(error)})

            :error ->
              error(request.id, {:method_not_found, inspect(request.method)})

            :invalid ->
              error(request.id, :invalid_request)

            error ->
              error(request.id, {:internal_error, inspect(error)})
          end
        else
          {:invalid, id} ->
            error(id, :invalid_request)

          error ->
            error
        end
      end

      defp handler_lookup(name) do
        Keyword.fetch(__service_methods__(), String.to_atom(name))
      end

      defp exec_handler(handler, %Request{id: id, method: method, params: params} = request, conn) do
        start_time = System.monotonic_time()

        try do
          if is_nil(id) do
            handler.cast(params, conn)
          else
            handler.call(params, conn)
          end
        rescue
          exception ->
            Telemetry.exception(:service, start_time, :exception, exception, __STACKTRACE__, %{req: request, ctx: conn}, %{count: 1})
            handler.handle_exception(request, exception, __STACKTRACE__)
        catch
          :throw, {:jsonrpc2_error, code_or_tuple} ->
            {:jsonrpc2_error, code_or_tuple}

          kind, payload ->
            Telemetry.exception(:service, start_time, kind, payload, __STACKTRACE__, %{req: request, ctx: conn}, %{count: 1})
            handler.handle_error(request, {kind, payload}, __STACKTRACE__)
        end
      end

      defp drop_nils(responses) do
        Enum.reject(responses, &is_nil/1)
      end

      defp response(nil, _result) do
        nil
      end

      defp response(id, result) do
        Response.result(id, result)
      end

      defp error(nil, _) do
        nil
      end

      defp error(id, {code, message_or_data}) do
        Response.error(id, code, message_or_data)
      end

      defp error(id, {code, message, data}) do
        Response.error(id, code, message, data)
      end

      defp error(id, code) do
        Response.error(id, code)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      def __service_methods__ do
        @__service_methods__
      end
    end
  end

  @doc """
  Define method and handler.

  Example:

      method "add", AddMethod
      method :subtract, SubtractMethod
  """
  @spec method(String.t(), module()) :: term()
  defmacro method(name, handler) when is_binary(name) do
    build_method(String.to_atom(name), handler)
  end

  @spec method(atom(), module()) :: term()
  defmacro method(name, handler) when is_atom(name) do
    build_method(name, handler)
  end

  defp build_method(name, handler) do
    quote location: :keep do
      @__service_methods__ {unquote(name), unquote(handler)}
    end
  end
end
