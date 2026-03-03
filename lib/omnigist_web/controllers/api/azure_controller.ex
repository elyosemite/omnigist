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
end
