defmodule Rewrite.Issue do
  @moduledoc """
  An `Issue` struct to track findings by the chechers.
  """

  alias Rewrite.Issue

  defstruct [:reporter, :message, :line, :column, :meta]

  @type t :: %Issue{
          reporter: module(),
          message: String.t() | nil,
          line: non_neg_integer() | nil,
          column: non_neg_integer() | nil,
          meta: term()
        }

  @doc """
  Creates a new `%Issue{}`

  ## Examples

      iex> Rewrite.Issue.new(Test, "kaput", line: 1, column: 1)
      %Rewrite.Issue{reporter: Test, message: "kaput", line: 1, column: 1, meta: nil}

      iex> Rewrite.Issue.new(Test, foo: "bar")
      %Rewrite.Issue{reporter: Test, message: nil, line: nil, column: nil, meta: [foo: "bar"]}
  """
  @spec new(module(), String.t() | term() | nil, keyword(), term()) :: Issue.t()
  def new(reporter, message, info \\ [], meta \\ nil)

  def new(reporter, message, info, meta) when is_binary(message) do
    line = Keyword.get(info, :line)
    column = Keyword.get(info, :column)
    struct!(Issue, reporter: reporter, message: message, line: line, column: column, meta: meta)
  end

  def new(reporter, meta, info, nil) do
    line = Keyword.get(info, :line)
    column = Keyword.get(info, :column)
    struct!(Issue, reporter: reporter, line: line, column: column, meta: meta)
  end
end
