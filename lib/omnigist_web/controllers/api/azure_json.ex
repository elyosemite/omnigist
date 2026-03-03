defmodule OmnigistWeb.API.AzureJSON do
  def projecfts(%{projects: projects}) do
    %{data: Enum.map(projects, &project_data/1)}
  end

  def repositories(%{repositories: repositories}) do
    %{data: Enum.map(repositories, &repository_data/1)}
  end

  defp project_data(project) do
    %{
      id:          project.id,
        name:        project.name,
        description: project.description,
        url:         project.url,
        state:       project.state,
        visibility:  project.visibility
    }
  end

  defp repository_data(repository) do
    %{
      id:              repository.id,
      name:            repository.name,
      url:             repository.url,
      ssh_url:         repository.ssh_url,
      default_branch:  repository.default_branch,
      size:            repository.size,
      project_name:         repository.project_name
    }
  end
end
