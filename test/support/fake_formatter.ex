defmodule FakeFormatter do
  @moduledoc """
  The FakeFormatter does not change anything.
  """

  @behaviour Mix.Tasks.Format

  @impl Mix.Tasks.Format
  def features(_opts) do
    [sigils: [], extensions: [".ex", ".exs"]]
  end

  @impl Mix.Tasks.Format
  def format(contents, _opts) do
    IO.puts("FakeFormatter.format/2")
    contents
  end
end

defmodule FreedomFormatter do
  @moduledoc """
  Fakes the `FreedomFormatter`.
  """

  @behaviour Mix.Tasks.Format

  @impl Mix.Tasks.Format
  def features(_opts) do
    [sigils: [], extensions: [".ex", ".exs"]]
  end

  @impl Mix.Tasks.Format
  def format(contents, _opts) do
    IO.puts("FreedomFormatter.format/2")
    contents
  end

  defmodule Formatter do
    @moduledoc false
    def to_algebra(_quoted, _opts) do
      # Returns always the algbra for:
      # ```elixir
      # [
      #   1,
      # ]
      # ```
      IO.puts("FreedomFormatter.Formatter.to_algebra/2")
      {:doc_group,
       {:doc_group,
        {:doc_cons,
         {:doc_nest,
          {:doc_cons, "[",
           {:doc_cons, {:doc_break, "", :strict},
            {:doc_force, {:doc_group, {:doc_cons, "1", ","}, :self}}}}, 2, :break},
         {:doc_cons, {:doc_break, "", :strict}, "]"}}, :self}, :self}
    end
  end
end
