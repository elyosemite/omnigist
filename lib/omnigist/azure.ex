defmodule Omnigist.Azure do
  alias Omnigist.Azure.{Client, Project, Repository}

  def list_projects(org, token) do
    case Client.get("", token) do
      {:ok, %{"value" => items}} -> {:ok, Enum.map(items, &parse_project/1)}
    end
  end

  defp parse_project(data) do
    %Project{
      id:          data["id"],
      name:        data["name"],
      description: data["description"],
      url:         data["url"],
      state:       data["state"],
      visibility:  data["visibility"]
    }
  end
end
