defmodule OmnigistWeb.API.GitHubController do
  use OmnigistWeb, :controller

  alias Omnigist.GitHub

  action_fallback OmnigistWeb.FallbackController

  def show(conn, %{"owner" => owner, "repo" => repo}) do
    token = Application.fetch_env!(:omnigist, :github_token)

    with {:ok, repository} <- GitHub.get_repository(owner, repo, token) do
      render(conn, :show, repository: repository)
    end
  end

  def index(conn, %{"username" => username}) do
    token = Application.fetch_env!(:omnigist, :github_token)

    with {:ok, repositories} <- GitHub.list_user_repositories(username, token) do
      render(conn, :index, repositories: repositories)
    end
  end
end
