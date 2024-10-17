defmodule Rewrite.KeyValueStoreTest do
  use RewriteCase

  alias Rewrite.KeyValueStore

  describe "get" do
    test "returns the default for unset value" do
      rewrite = Rewrite.new()
      assert KeyValueStore.get(rewrite, "foo") == nil
      assert KeyValueStore.get(rewrite, "foo", "bar") == "bar"
    end
  end

  describe "get_and_update" do
    test "returns the default for unset value" do
      rewrite = Rewrite.new()
      assert KeyValueStore.get_and_update(rewrite, :foo, "bar") == nil
    end

    test "sets and updates a value" do
      rewrite = Rewrite.new()
      assert KeyValueStore.get_and_update(rewrite, :foo, "bar", "foo") == "foo"
      assert KeyValueStore.get_and_update(rewrite, :foo, "baz") == "bar"
      assert KeyValueStore.get_and_update(rewrite, :foo, "foo") == "baz"
    end
  end
end
