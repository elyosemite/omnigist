defmodule OmnigistWeb.Api.AzureController do
  use OmnigistWeb, :controller

  alias Omnigist.Azure
  action_fallback OmnigistWeb.FallbackController

  def projects(conn, %{"org" => org}) do
    token = Application.fetch_env!(:omnigist, :azure_token)

    with {:ok, projects} <- Azure.list_projects(org, token) do
      render(conn, :projects, projects: projects)
    end
  end

  def repositories(conn, %{"org" => org, "project" => project}) do
    token = Application.fetch_env!(:omnigist, :azure_token)

    with {:ok, repositories} <- Azure.list_repositories(org, project, token) do
      render(conn, :repositories, repositories: repositories)
    end
  end
end
