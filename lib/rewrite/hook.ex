defmodule Rewrite.Hook do
  @moduledoc """
  A `behaviour` for hooking into the `Rewrite` processes.

  The callback `handle/2` is called by `Rewrite` with an `t:action` and the 
  current `%Rewrite{}`. The return value is either `:ok` or `{:ok, rewrite}`.

  If the `%Rewrite{}` project is updated inside the hook, the hook will not be 
  called again.

  ## Actions

    * `:new` - invoked when a new `%Rewrite{}` is created.

    * `{:added, paths}` - invoked when new sources were added. `paths` is the a 
      list of `t:Path.t()`.

    * `{:updated, path}` - invoked when a source was updated. `path` contains 
      the path of the updated source. Also called when a source was succesfull 
      formatted.

  """

  @type action :: atom() | {atom(), Path.t() | [Path.t()]}

  @callback handle(action(), rewrite :: Rewrite.t()) :: :ok | {:ok, Rewrite.t()}
end
