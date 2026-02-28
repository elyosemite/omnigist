defmodule MyApp.Math do
  defmacro __using__(opts) do
    quote do
      def double(n), do: n * 2
      def square(n), do: n * n
    end
  end
end
