defmodule ModuleAstContained do
  def dynamic_module_ast() do
    module_name = DynamicModule

    ast =
      quote do
        defmodule unquote(module_name) do
          def hello() do
            :world
          end
        end
      end

    ast
  end
end
