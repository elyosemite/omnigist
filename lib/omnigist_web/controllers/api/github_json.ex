defmodule OmnigistWeb.API.GitHubJSON do
  def index(%{repositories: repositories}) do
    %{data: Enum.map(repositories, &data/1)}
  end

  def show(%{repository: repository}) do
    %{data: data(repository)}
  end

  defp data(repo) do
    %{
      id:          repo.id,
      name:        repo.name,
      full_name:   repo.full_name,
      description: repo.description,
      url:         repo.url,
      private:     repo.private,
      stars:       repo.stars
    }
  end
end
