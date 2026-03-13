defmodule Omnigist.Azure.Client do
  @base_url "https://dev.azure.com"

  def get(path, token) do
    url = String.to_charlist("#{@base_url}#{path}")

    credentials = Base.encode64(":" <> token)

    headers = [
      { ~c"Authorization", ~c"Basic #{credentials}" },
      { ~c"Accept", ~c"application/json" },
      { ~c"User-Agent", ~c"omnigist" }
    ]

    :httpc.request(:get, {url, headers}, [], [])
    |> handle_response()
  end

  defp handle_response({:ok, {{_, 200, _}, _headers, body}}) do
    {:ok, Jason.decode!(List.to_string(body))}
  end

  defp handle_response({:ok, {{_, status, _}, _headers, body}}) do
    {:error, "Azure DevOps returned #{status}: #{body}"}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end
end
