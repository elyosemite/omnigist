defmodule MyApp.Greetings do
  defmacro __using__(opts) do
    quote do
      def hello(name), do: "Hello, #{name}!"
      def goodbye(name), do: "Goodbye, #{name}!"
    end
  end
end
