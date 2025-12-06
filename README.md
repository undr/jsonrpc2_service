# JSONRPC2.Service

Provides the ability to create services in accordance with the JSONRPC 2.0 specification. There is no transport layer, but only tools for creating transport-independent JSONRPC 2.0 services.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `jsonrpc2_service` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jsonrpc2_service, "~> 0.1.0"}
  ]
end
```

## How to use

### Defining Services

Services should use `JSONRPC2.Service`, which allows to describe methods of service. Each method is a module which uses `JSONRPC2.Service.Method`.

Examples:

```elixir
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
```

### Defining Methods

There are two possible ways to execute a request: `call` and `cast`. The first assumes the response which the service will return, the second does not. The module should implement at least one `handle_call` or `handle_cast` callback function to handle requests.

```elixir
defmodule AddMethod do
  use JSONRPC2Plug.Method

  # It handles requests like this:
  # {"id": "123", "method": "add", "params": {"x": 10, "y": 20}, "jsonrpc": "2.0"}
  def handle_call(%{"x" = > x, "y" => y}, _conn) do
    {:ok, x + y}
  end
end
```

The first argument is the `params` data comes from JSONRPC 2.0 request. According to JSONRPC 2.0 spec, it must be either object or an array of arguments.

The second argument is the map with context data. Sometimes it could be useful to send some additional data into the service, eg. HTTP connection data (`Plug.Conn`)

The module implements behaviour `JSONRPC2.Service.Method` which consists of five callbacks: `handle_call`, `handle_cast`, `validate`, `handle_error` and, `handle_exception`.

#### `handle_call` and `handle_cast` callbacks

This callbacks should return `{:ok, term()}`, `{:jsonrpc2_error, term()}` or `{:error, term()}` tuples. There are two helpers for errors: `error` and `error!` functions.

use `error` function to return error:

```elixir
def handle_call([a, b], _) do
  if b != 0 do
    {:ok, a / b}
  else
    error(12345, "divided by zero")
  end
end
```

use `error!` function to abort function execution and return error:

```elixir
def handle_call([a, b], _) do
  if(b == 0, do: error!(12345, "divided by zero"))

  {:ok, a / b}
end
```

#### `validate` callback

This function is for the validation of the input dataset.

```elixir
import JSONRPC2.Service.Validator, only: [type: 1, required: 0]

def validate(params) do
  params
  |> Validator.validate("x", [type(:integer), required()])
  |> Validator.validate("y", [type(:integer), required()])
  |> Validator.unwrap()
end
```

The library has its own validator. It has 8 built-in validations: `type`, `required`, `not_empty`, `exclude`, `include`, `len`, `number` and `format`. However, you can write custom validations and extend existing ones.

Moreover, you can use any preferred validator (eg. `valdi`), but you should respect the following requirements: the `validate` function should return either `{:ok, params}` or `{:invalid, errors}`. Where errors could be any type that can be safely encoded to JSON and `params` is parameters to pass into `handle_call` or `handle_cast` functions.

#### `handle_error` and `handle_exception` callbacks

This callbacks are used to define way how to deal with errors and exceptions. The method handler catches all errors, throws, exits and exceptions and invoke error or exception handler.

```elixir
def handle_error(request, {:exit, reason}, stacktrace) do
  ...
  error(...)
end

def handle_error(request, {:throw, reason}, stacktrace) do
  ...
  error(...)
end

def handle_exception(request, %ArithmeticError{} = ex, stacktrace) do
  ...
  error(...)
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jsonrpc2_service>.

