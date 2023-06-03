defmodule Rewrite.Filetype do
  @moduledoc """
  The behaviour for filetypes.
  """

  # TODO: add docs

  alias Rewrite.Source

  @type t :: map()

  @type updates :: keyword()

  @type key :: atom()

  @type value :: any()

  @type extension :: String.t()

  @type opts :: keyword()

  @callback from_string(Source.content()) :: Source.t()
  @callback from_string(Source.content(), Path.t() | nil) :: Source.t()
  @callback from_string(Source.content(), Path.t() | nil, opts()) :: Source.t()

  @callback read!(Path.t()) :: Source.t()
  @callback read!(Path.t(), opts()) :: Source.t()

  @callback update(Source.t(), key()) :: :ok | {:ok, t()} | :error
  @callback update(Source.t(), key(), value()) :: :ok | {:ok, updates()} | :error

  @callback extensions :: [extension] | :any
end
