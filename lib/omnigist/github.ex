defmodule Omnigist.GitHub do
  alias Omnigist.GitHub.{Client, GitHubRepository}

  def get_repository(owner, repo_name, token) do
    case Client.get("/repos/#{owner}/#{repo_name}", token) do
      {:ok, data} ->
        {:ok, parse_repository(data)}

      error -> error
    end
  end

  def list_user_repositories(username, token) do
    case Client.get("/users/#{username}/repos", token) do
      {:ok, data} -> {:ok, Enum.map(data, &parse_repository/1)}
      error -> error
    end
  end

  defp parse_repository(data) do
    %GitHubRepository{
      id: data["id"],
      name: data["name"],
      full_name: data["full_name"],
      description: data["description"],
      url: data["html_url"],
      private: data["private"],
      stars: data["stargazers_count"]
    }
  end
end
