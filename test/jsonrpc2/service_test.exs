defmodule JSONRPC2.ServiceTest do
  use ExUnit.Case

  alias JSONRPC2.Spec.Error
  alias JSONRPC2.Spec.Result
  alias JSONRPC2.Service.Method
  alias JSONRPC2.Service

  setup(data) do
    {
      :ok,
      error: setup_error(data),
      response: setup_response(data)
    }
  end

  def setup_response(%{response: {id, result}}),
    do: Result.new(id, result)

  def setup_response(_data),
    do: nil

  def setup_error(%{error: {id, type, payload}}),
    do: Error.new(id, type, payload)

  def setup_error(%{error: {id, type}}),
    do: Error.new(id, type)

  def setup_error(%{error: {id, code, message, payload}}),
    do: Error.new(id, code, message, payload)

  def setup_error(_data),
    do: nil

  defmodule Method1 do
    use Method

    def handle_call(_params, _conn),
      do: error(54321, "Error Message", %{some: "payload"})
  end

  defmodule Method2 do
    use Method

    def handle_call(_params, _conn),
      do: raise "exception message"
  end

  defmodule Method3 do
    use Method

    def handle_call(_params, _conn),
      do: {:ok, "result"}

    def validate(%{"invalid" => true}),
      do: {:invalid, %{key: ["error 1", "error 2"]}}

    def validate(params),
      do: {:ok, params}
  end

  defmodule TestService do
    use Service

    method "method1", Method1
    method "method2", Method2
    method "method3", Method3
  end

  describe ".handle" do
    test "invalid request" do
      assert nil == TestService.handle(%{"invalid" => "request"}, :conn)
    end

    @tag error: {"123", :invalid_request}
    test "invalid request with id", %{error: error} do
      assert ^error = TestService.handle(%{"id" => "123"}, :conn)
      assert ^error = TestService.handle(%{
        "id" => "123", "method" => 123, "params" => "params", "jsonrpc" => "2.0"
      }, :conn)
    end

    @tag error: {"123", :method_not_found, inspect("method0")}
    test "method not found", %{error: error} do
      assert ^error = TestService.handle(%{
        "id" => "123", "method" => "method0", "params" => %{}, "jsonrpc" => "2.0"
      }, :conn)
    end

    @tag error: {"123", :invalid_params, %{key: ["error 1", "error 2"]}}
    test "invalid params", %{error: error} do
      assert ^error = TestService.handle(%{
        "id" => "123", "method" => "method3", "params" => %{"invalid" => true}, "jsonrpc" => "2.0"
      }, :conn)
    end

    @tag error: {"123", 54321, "Error Message", %{some: "payload"}}
    test "custom error", %{error: error} do
      assert ^error = TestService.handle(%{
        "id" => "123", "method" => "method1", "params" => %{}, "jsonrpc" => "2.0"
      }, :conn)
    end

    @moduletag capture_log: true
    test "exception" do
      result = TestService.handle(%{
        "id" => "123", "method" => "method2", "params" => %{}, "jsonrpc" => "2.0"
      }, :conn)

      assert "123" = result.id
      assert %{message: "Server error", code: -32000} = result.error
    end

    @tag response: {"123", "result"}
    test "success", %{response: result} do
      assert ^result = TestService.handle(%{
        "id" => "123", "method" => "method3", "params" => %{}, "jsonrpc" => "2.0"
      }, :conn)
    end

    @tag response: {"123", "result"}, error: {"124", :method_not_found, inspect("method0")}
    test "batch", %{response: success, error: error} do
      result = TestService.handle(%{"_json" => [
        %{"id" => "123", "method" => "method3", "params" => %{}, "jsonrpc" => "2.0"},
        %{"id" => "124", "method" => "method0", "params" => %{}, "jsonrpc" => "2.0"}
      ]}, :conn)

      assert ^success = Enum.at(result, 0)
      assert ^error = Enum.at(result, 1)
    end
  end

  # The atom table is never garbage collected, so a name turned into an atom
  # before it has been recognised is a permanent cost paid by whoever can reach
  # the transport. Enough of them reach `system_limit` and take the VM down —
  # not the process handling the request, the node.
  describe ".handle and the atom table" do
    test "an unknown method name does not become an atom" do
      # One trip through the not-found path before the count is taken. The first
      # one loads the modules that path touches, and loading a module adds its
      # own atoms — a cost paid once per VM and unrelated to the request. What
      # this test is about is the marginal cost of each further name, which is
      # what a stream of them multiplies.
      miss("warm_up")

      before = :erlang.system_info(:atom_count)

      for i <- 1..100, do: miss("no_such_method_#{i}")

      assert :erlang.system_info(:atom_count) == before
    end

    test "a declared method still reaches its handler" do
      assert %Result{result: "result"} =
               TestService.handle(
                 %{"id" => "123", "method" => "method3", "params" => %{}, "jsonrpc" => "2.0"},
                 :conn
               )
    end

    # The wire name is what dispatch is keyed by; the atom list stays as it was,
    # because it is public and callers read it.
    test "handlers are exposed under their wire names, beside the atom list" do
      assert TestService.__service_handlers__() == %{
               "method1" => Method1,
               "method2" => Method2,
               "method3" => Method3
             }

      assert Keyword.fetch(TestService.__service_methods__(), :method3) == {:ok, Method3}
    end

    # A method name of the wrong type is a malformed request, not a lookup.
    test "a non-binary method name is not looked up at all" do
      assert %Error{error: %{code: -32600}} =
               TestService.handle(
                 %{"id" => "123", "method" => 123, "params" => %{}, "jsonrpc" => "2.0"},
                 :conn
               )
    end

    defp miss(name) do
      TestService.handle(
        %{"id" => "123", "method" => name, "params" => %{}, "jsonrpc" => "2.0"},
        :conn
      )
    end
  end
end
