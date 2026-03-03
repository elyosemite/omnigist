defmodule Omnigist.Azure do
  alias Omnigist.Azure.{Client, Project, Repository}

  def list_projects(org, token) do
    case Client.get("/#{org}/_apis/projects?api-version=7.1", token) do
      {:ok, %{"value" => items}} -> {:ok, Enum.map(items, &parse_project/1)}
      {:error, reason} -> {:error, reason }
    end
  end

  def list_repositories(org, project, token) do
    case Client.get("/#{org}/#{project}/_apis/git/repositories?api-version=7.1", token) do
      {:ok, %{"value" => items}} -> {:ok, Enum.map(items, &parse_repository/1)}
      {:error, reason} -> {:error, reason }
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

  defp parse_repository(data) do
    %Repository{
      id: data["id"],
      name: data["name"],
      url: data["url"],
      ssh_url: data["sshUrl"],
      default_branch: data["defaultBranch"],
      size: data["size"],
      project_name: get_in(data, ["project", "name"])
    }
  end
end
