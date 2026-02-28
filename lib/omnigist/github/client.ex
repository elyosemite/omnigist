defmodule Omnigist.GitHub.Client do
  @base_url "https://api.github.com"

  def get(path, token) do
    url = String.to_charlist("#{@base_url}#{path}")

    headers = [
      {~c"Authorization", ~c"Bearer #{token}"},
      {~c"Accept", ~c"application/vnd.github.v3+json"},
      {~c"User-Agent", ~c"omnigist"}
    ]

    :httpc.request(:get, {url, headers}, [], [])
    |> handle_response()

  end

  defp handle_response({:ok, {{_, 200, _}, _headers, body} }) do
    {:ok, Jason.decode!(body)}
  end

  defp handle_response({:ok, {{_, status, _}, _headers, body}}) do
    {:error, "GitHub returned #{status}: #{body}"}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end
end
