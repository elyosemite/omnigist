# US-001 — Registro e Gerenciamento de Repositórios

## Descrição

**Como** desenvolvedor usando a ferramenta desktop,
**Quero** registrar repositórios git locais no sistema por caminho absoluto no filesystem,
**Para que** eu possa referenciá-los por UUID nas chamadas subsequentes da API sem repetir o caminho a cada request.

---

## Contexto Técnico

Repositórios não são clonados nem gerenciados pelo Omnigist — eles já existem no filesystem. O sistema apenas registra o caminho e atribui um UUID para referência futura. Não há autenticação nesta fase.

---

## Estrutura de Arquivos

```
priv/repo/migrations/
  YYYYMMDDHHMMSS_create_repositories.exs

lib/omnigist/
  repositories/
    repository.ex             ← Schema Ecto
  repositories.ex             ← Context (CRUD)

lib/omnigist_web/controllers/api/
  repository_controller.ex
  repository_json.ex

lib/omnigist_web/
  router.ex                   ← adicionar rotas /api/v1/repositories
```

---

## Implementação Esperada

### 1. Migration

```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_create_repositories.exs
defmodule Omnigist.Repo.Migrations.CreateRepositories do
  use Ecto.Migration

  def change do
    create table(:repositories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :path, :string, null: false
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:repositories, [:path])
  end
end
```

### 2. Schema

```elixir
# lib/omnigist/repositories/repository.ex
defmodule Omnigist.Repositories.Repository do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "repositories" do
    field :name, :string
    field :path, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:name, :path, :description])
    |> validate_required([:name, :path])
    |> unique_constraint(:path)
  end
end
```

### 3. Context

```elixir
# lib/omnigist/repositories.ex
defmodule Omnigist.Repositories do
  import Ecto.Query, warn: false
  alias Omnigist.Repo
  alias Omnigist.Repositories.Repository

  def list_repositories, do: Repo.all(Repository)

  def get_repository!(id), do: Repo.get!(Repository, id)

  def create_repository(attrs \\ %{}) do
    %Repository{}
    |> Repository.changeset(attrs)
    |> Repo.insert()
  end

  def update_repository(%Repository{} = repository, attrs) do
    repository
    |> Repository.changeset(attrs)
    |> Repo.update()
  end

  def delete_repository(%Repository{} = repository) do
    Repo.delete(repository)
  end

  def change_repository(%Repository{} = repository, attrs \\ %{}) do
    Repository.changeset(repository, attrs)
  end
end
```

### 4. Controller

```elixir
# lib/omnigist_web/controllers/api/repository_controller.ex
defmodule OmnigistWeb.API.RepositoryController do
  use OmnigistWeb, :controller

  alias Omnigist.Repositories
  alias Omnigist.Repositories.Repository

  action_fallback OmnigistWeb.FallbackController

  def index(conn, _params) do
    repositories = Repositories.list_repositories()
    render(conn, :index, repositories: repositories)
  end

  def create(conn, %{"repository" => repository_params}) do
    with {:ok, %Repository{} = repository} <- Repositories.create_repository(repository_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/repositories/#{repository}")
      |> render(:show, repository: repository)
    end
  end

  def show(conn, %{"id" => id}) do
    repository = Repositories.get_repository!(id)
    render(conn, :show, repository: repository)
  end

  def update(conn, %{"id" => id, "repository" => repository_params}) do
    repository = Repositories.get_repository!(id)

    with {:ok, %Repository{} = repository} <-
           Repositories.update_repository(repository, repository_params) do
      render(conn, :show, repository: repository)
    end
  end

  def delete(conn, %{"id" => id}) do
    repository = Repositories.get_repository!(id)

    with {:ok, %Repository{}} <- Repositories.delete_repository(repository) do
      send_resp(conn, :no_content, "")
    end
  end
end
```

### 5. JSON View

```elixir
# lib/omnigist_web/controllers/api/repository_json.ex
defmodule OmnigistWeb.API.RepositoryJSON do
  alias Omnigist.Repositories.Repository

  def index(%{repositories: repositories}) do
    %{data: Enum.map(repositories, &data/1)}
  end

  def show(%{repository: repository}) do
    %{data: data(repository)}
  end

  defp data(%Repository{} = repository) do
    %{
      id: repository.id,
      name: repository.name,
      path: repository.path,
      description: repository.description,
      inserted_at: repository.inserted_at,
      updated_at: repository.updated_at
    }
  end
end
```

### 6. Router

```elixir
# lib/omnigist_web/router.ex — adicionar dentro do scope existente /api
scope "/api/v1", OmnigistWeb.API, as: :api do
  pipe_through :api

  resources "/repositories", RepositoryController, except: [:new, :edit]
end
```

---

## Critérios de Aceite

- [ ] `POST /api/v1/repositories` cria um repositório e retorna 201 com o UUID gerado
- [ ] `GET /api/v1/repositories` retorna lista de todos os repositórios registrados
- [ ] `GET /api/v1/repositories/:id` retorna um repositório pelo UUID
- [ ] `PUT /api/v1/repositories/:id` atualiza `name` e/ou `description` (não `path`)
- [ ] `DELETE /api/v1/repositories/:id` remove o registro e retorna 204
- [ ] Registrar dois repositórios com o mesmo `path` retorna erro 422 com mensagem clara
- [ ] Campos `name` e `path` são obrigatórios — omiti-los retorna 422
- [ ] O campo `path` **não** é validado contra o filesystem nesta US (apenas unicidade no DB)

---

## Testes

### Arquivo: `test/omnigist/repositories_test.exs`

```elixir
defmodule Omnigist.RepositoriesTest do
  use Omnigist.DataCase

  alias Omnigist.Repositories

  describe "list_repositories/0" do
    test "returns all repositories" do
      repo = repository_fixture()
      assert Repositories.list_repositories() == [repo]
    end
  end

  describe "get_repository!/1" do
    test "returns the repository with given id" do
      repo = repository_fixture()
      assert Repositories.get_repository!(repo.id) == repo
    end

    test "raises if id does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Repositories.get_repository!("00000000-0000-0000-0000-000000000000")
      end
    end
  end

  describe "create_repository/1" do
    test "with valid data creates a repository" do
      valid_attrs = %{name: "my-project", path: "/home/user/projects/my-project"}
      assert {:ok, repo} = Repositories.create_repository(valid_attrs)
      assert repo.name == "my-project"
      assert repo.path == "/home/user/projects/my-project"
    end

    test "with missing name returns error changeset" do
      assert {:error, changeset} = Repositories.create_repository(%{path: "/some/path"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "with duplicate path returns error changeset" do
      repository_fixture(%{path: "/same/path"})
      assert {:error, changeset} = Repositories.create_repository(%{name: "other", path: "/same/path"})
      assert %{path: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_repository/2" do
    test "with valid data updates the repository" do
      repo = repository_fixture()
      assert {:ok, updated} = Repositories.update_repository(repo, %{description: "new desc"})
      assert updated.description == "new desc"
    end
  end

  describe "delete_repository/1" do
    test "deletes the repository" do
      repo = repository_fixture()
      assert {:ok, _} = Repositories.delete_repository(repo)
      assert_raise Ecto.NoResultsError, fn -> Repositories.get_repository!(repo.id) end
    end
  end
end
```

### Arquivo: `test/omnigist_web/controllers/api/repository_controller_test.exs`

```elixir
defmodule OmnigistWeb.API.RepositoryControllerTest do
  use OmnigistWeb.ConnCase

  import Omnigist.RepositoriesFixtures

  @create_attrs %{name: "my-project", path: "/home/user/projects/my-project"}
  @update_attrs %{description: "Updated description"}
  @invalid_attrs %{name: nil, path: nil}

  describe "GET /api/v1/repositories" do
    test "lists all repositories", %{conn: conn} do
      repository_fixture()
      conn = get(conn, ~p"/api/v1/repositories")
      assert %{"data" => [_]} = json_response(conn, 200)
    end
  end

  describe "POST /api/v1/repositories" do
    test "creates repository and returns 201", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/repositories", repository: @create_attrs)
      assert %{"data" => %{"id" => id, "name" => "my-project"}} = json_response(conn, 201)
      assert get_resp_header(conn, "location") == ["/api/v1/repositories/#{id}"]
    end

    test "returns 422 with invalid attrs", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/repositories", repository: @invalid_attrs)
      assert %{"errors" => _} = json_response(conn, 422)
    end

    test "returns 422 on duplicate path", %{conn: conn} do
      repository_fixture(%{path: "/dup/path"})
      conn = post(conn, ~p"/api/v1/repositories", repository: %{name: "other", path: "/dup/path"})
      assert json_response(conn, 422)
    end
  end

  describe "GET /api/v1/repositories/:id" do
    test "shows a repository", %{conn: conn} do
      repo = repository_fixture()
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}")
      assert %{"data" => %{"id" => id}} = json_response(conn, 200)
      assert id == repo.id
    end
  end

  describe "PUT /api/v1/repositories/:id" do
    test "updates repository", %{conn: conn} do
      repo = repository_fixture()
      conn = put(conn, ~p"/api/v1/repositories/#{repo.id}", repository: @update_attrs)
      assert %{"data" => %{"description" => "Updated description"}} = json_response(conn, 200)
    end
  end

  describe "DELETE /api/v1/repositories/:id" do
    test "deletes repository and returns 204", %{conn: conn} do
      repo = repository_fixture()
      conn = delete(conn, ~p"/api/v1/repositories/#{repo.id}")
      assert response(conn, 204)
    end
  end
end
```

### Arquivo: `test/support/fixtures/repositories_fixtures.ex`

```elixir
defmodule Omnigist.RepositoriesFixtures do
  alias Omnigist.Repositories

  def repository_fixture(attrs \\ %{}) do
    {:ok, repository} =
      attrs
      |> Enum.into(%{
        name: "some-repo-#{System.unique_integer([:positive])}",
        path: "/tmp/repos/repo-#{System.unique_integer([:positive])}",
        description: "some description"
      })
      |> Repositories.create_repository()

    repository
  end
end
```
