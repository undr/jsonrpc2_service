# Changelog

## 0.2.1

`not_empty/0` refused every map, not only the empty one.

The rule matched its value against `%{}`, which as a *pattern* means "a map with at least these keys" and names none — so it matched `%{"base" => ...}` exactly as readily as `%{}`, and any field declared `[type(:object), not_empty()]` was unusable: every object a caller could send was answered "is empty". A map is now asked for its size instead. Strings and lists are unchanged, `nil` still passes.

The test only ever passed the rule `%{}`, a value both readings agree on, which is why nothing caught it; it now also asks about a map that carries something.

## 0.2.0

Nothing a request carries is turned into a new atom any more — not the method name, not the keys of `params`.

The atom table is not garbage collected, so a string turned into an atom before anything has recognised it is a permanent allocation charged to whoever can reach the transport. Enough of them reach `system_limit`, and that takes the whole VM down — not the process handling the request, the node, along with everything else running on it. A service is reachable by whoever can reach its transport, which makes these the least trusted strings the library handles.

Two places did it, and both are fixed.

**Method dispatch.** `handler_lookup/1` called `String.to_atom/1` on the method name before checking that such a method exists. Dispatch is now keyed by the name as it arrived, through a string-keyed map that `__before_compile__` builds from the same `method/2` declarations. The lookup stays O(1). `__service_methods__/0` answers exactly what it answered before; `__service_handlers__/0` is new and exposes the same methods under their wire names. A method name that is not a string is answered as an invalid request, as it was before, but now without reaching the lookup at all.

**Parameter keys.** `atomize_keys/1` atomised every key of `params`, recursively, so a free-form object nested in a request contributed one atom per name it carried. Keys are now atomised only when the atom already exists; any other key is handed to the handler as the string it was.

`String.to_atom/1` in `build_method/2` is untouched: it runs at compile time over a literal from the `method/2` macro, not over anything a request carries.

### Breaking: `params` can now reach a handler with mixed key types

This is why the minor version moves rather than the patch. Before this release every key of `params` was an atom by the time a handler saw it. Now a key that no loaded module names stays a binary, so one map can carry both.

Nothing a method **reads** is affected: a field the handler names appears as an atom literal in the handler's own compiled code, and the handler is loaded by the time this runs — `handle/3` has just called `validate/1` on it. So every key worth matching on still arrives as an atom, and `params[:code]`, `%{code: code}` and `Map.take(params, [:code])` behave exactly as before.

What breaks is code that treats the **whole map** as uniformly atom-keyed:

- `Ecto.Changeset.cast/3` **raises** on a map with mixed keys ("expected params to be a map with atoms or string keys"). A handler that passed `params` straight to `cast/3` and used to work will now raise whenever a request carries one unrecognised key.
- `struct/2` and `struct!/2` ignore string keys, so fields that used to be populated from a passthrough map will silently stay at their defaults.
- Anything iterating keys and assuming `is_atom/1` — `Enum.map(params, fn {k, _} -> Atom.to_string(k) end)` and the like.

The fix in each case is to take the fields the handler actually declares rather than passing the map through: `Map.take(params, [:field, ...])` before `cast/3` or `struct/2`. That is also what makes the handler's contract explicit, which is why no compatibility switch is offered.
