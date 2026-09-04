defmodule JSONRPC2.Service.MethodTest do
  use ExUnit.Case

  alias JSONRPC2.Service.Method

  # Names the fields it reads, which is what puts them in the atom table: an
  # atom literal in a handler's own compiled code exists from the moment the
  # module is loaded, and the module is loaded before this ever runs.
  defmodule EchoMethod do
    use Method

    def handle_call(params, _conn) do
      {:ok, %{code: params[:code], nested: params[:nested], raw: params}}
    end
  end

  describe "call/2 and the keys it hands the handler" do
    test "a field the handler names arrives as an atom" do
      assert {:ok, result} = EchoMethod.call(%{"code" => "StarFruits-v3"})

      assert result.code == "StarFruits-v3"
      assert Map.has_key?(result.raw, :code)
    end

    # The atom table is not garbage collected, so a key turned into an atom
    # before anything recognised it is a permanent allocation charged to
    # whoever can reach the transport. Enough of them reach `system_limit`,
    # which takes the VM down rather than the request.
    test "a key nothing names does not become an atom" do
      # One call before the count is taken: the first trip loads the modules
      # this path touches, and loading a module adds its own atoms — a cost
      # paid once per VM and unrelated to the request. What is measured is the
      # marginal cost of each further key, which is what a stream multiplies.
      EchoMethod.call(%{"warm_up_key" => 1})

      before = :erlang.system_info(:atom_count)

      for i <- 1..100, do: EchoMethod.call(%{"no_such_key_#{i}" => i})

      assert :erlang.system_info(:atom_count) == before
    end

    test "a key nothing names arrives as the string it was" do
      assert {:ok, result} = EchoMethod.call(%{"quite_certainly_not_an_atom_here" => 1})

      assert result.raw == %{"quite_certainly_not_an_atom_here" => 1}
    end

    # The walk is recursive, so a free-form object nested inside declared
    # params is where the growth actually comes from: one deploy carries as
    # many keys as it carries names.
    test "the rule applies at every level of nesting" do
      params = %{
        "code" => "StarFruits-v3",
        "nested" => %{"deeply_unnamed_key_here" => %{"and_another_unnamed_one" => 1}}
      }

      before = :erlang.system_info(:atom_count)

      assert {:ok, result} = EchoMethod.call(params)

      assert :erlang.system_info(:atom_count) == before
      assert result.nested == %{"deeply_unnamed_key_here" => %{"and_another_unnamed_one" => 1}}
    end

    test "lists inside params are walked as before" do
      assert {:ok, result} = EchoMethod.call(%{"code" => [%{"code" => 1}]})

      assert result.code == [%{code: 1}]
    end
  end
end
