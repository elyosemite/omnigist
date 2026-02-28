# US-003 — API de Commits

## Descrição

**Como** cliente desktop,
**Quero** consultar o histórico de commits de um repositório registrado,
**Para que** eu possa exibir o log de commits, filtrar por autor ou mensagem, e inspecionar detalhes de um commit específico.

---

## Contexto Técnico

Todos os endpoints de commits são aninhados sob `/api/v1/repositories/:repository_id/`. O `repository_id` é o UUID gerado na US-001. A operação git é executada no `path` do repositório recuperado do banco.

---

## Estrutura de Arquivos

```
lib/omnigist_web/controllers/api/
  commit_controller.ex
  commit_json.ex
```

Rotas aninhadas em `resources "/repositories"` no router.

---

## Rotas

| Método | Caminho | Ação | Descrição |
|--------|---------|------|-----------|
| `GET` | `/api/v1/repositories/:repository_id/commits` | `:index` | Lista commits (suporta filtros) |
| `GET` | `/api/v1/repositories/:repository_id/commits/authors` | `:authors` | Lista autores únicos |
| `GET` | `/api/v1/repositories/:repository_id/commits/:hash` | `:show` | Detalhe de um commit |

**Query params do `:index`:** `limit` (integer), `author` (string), `search` (string — grep na mensagem).

---

## Implementação Esperada

### Router

```elixir
# lib/omnigist_web/router.ex
scope "/api/v1", OmnigistWeb.API, as: :api do
  pipe_through :api

  resources "/repositories", RepositoryController, except: [:new, :edit] do
    get "/commits",         CommitController, :index
    get "/commits/authors", CommitController, :authors
    get "/commits/:hash",   CommitController, :show
  end
end
```

> **Atenção:** A rota `/commits/authors` deve aparecer **antes** de `/commits/:hash` no router para que "authors" não seja interpretado como um hash.

### Controller

```elixir
# lib/omnigist_web/controllers/api/commit_controller.ex
defmodule OmnigistWeb.API.CommitController do
  use OmnigistWeb, :controller

  alias Omnigist.{Repositories, Git}

  action_fallback OmnigistWeb.FallbackController

  def index(conn, %{"repository_id" => repo_id} = params) do
    repo = Repositories.get_repository!(repo_id)

    opts = [
      limit: parse_int(params["limit"], 50),
      author: params["author"],
      grep: params["search"]
    ]

    with {:ok, commits} <- Git.list_commits(repo.path, opts) do
      render(conn, :index, commits: commits)
    end
  end

  def authors(conn, %{"repository_id" => repo_id}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, authors} <- Git.list_authors(repo.path) do
      render(conn, :authors, authors: authors)
    end
  end

  def show(conn, %{"repository_id" => repo_id, "hash" => hash}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, commit} <- Git.get_commit(repo.path, hash) do
      render(conn, :show, commit: commit)
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
```

### JSON View

```elixir
# lib/omnigist_web/controllers/api/commit_json.ex
defmodule OmnigistWeb.API.CommitJSON do
  def index(%{commits: commits}) do
    %{data: Enum.map(commits, &data/1)}
  end

  def show(%{commit: commit}) do
    %{data: data(commit)}
  end

  def authors(%{authors: authors}) do
    %{data: authors}
  end

  defp data(commit) do
    %{
      hash: commit.hash,
      short_hash: commit.short_hash,
      message: commit.message,
      body: commit.body,
      author_name: commit.author_name,
      author_email: commit.author_email,
      date: commit.date
    }
  end
end
```

### FallbackController (shared, criado uma vez)

```elixir
# lib/omnigist_web/controllers/fallback_controller.ex
defmodule OmnigistWeb.FallbackController do
  use OmnigistWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: OmnigistWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: OmnigistWeb.ErrorJSON)
    |> render(:error, changeset: changeset)
  end

  # Erros git — string de stderr
  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: reason})
  end
end
```

---

## Exemplo de Responses

### `GET /api/v1/repositories/:id/commits?limit=2&author=alice`

```json
{
  "data": [
    {
      "hash": "a1b2c3d4e5f6...",
      "short_hash": "a1b2c3d",
      "message": "Fix login bug",
      "body": "",
      "author_name": "Alice",
      "author_email": "alice@example.com",
      "date": "2024-01-15T10:30:00+00:00"
    }
  ]
}
```

### `GET /api/v1/repositories/:id/commits/authors`

```json
{
  "data": [
    { "name": "Alice", "email": "alice@example.com" },
    { "name": "Bob",   "email": "bob@example.com" }
  ]
}
```

### Erro git (path inválido ou hash inexistente)

```json
{
  "error": "fatal: not a git repository (or any of the parent directories): .git"
}
```
HTTP 422.

---

## Critérios de Aceite

- [ ] `GET /commits` sem params retorna até 50 commits por padrão
- [ ] `GET /commits?limit=5` retorna no máximo 5 commits
- [ ] `GET /commits?author=alice` filtra commits pelo nome ou e-mail do autor
- [ ] `GET /commits?search=fix` filtra commits cuja mensagem contém "fix" (case insensitive via git `--grep`)
- [ ] `GET /commits/authors` retorna lista deduplicada por e-mail
- [ ] `GET /commits/:hash` com hash completo ou abreviado retorna o commit
- [ ] `GET /commits/:hash` com hash inexistente retorna 422 com `{"error": "..."}`
- [ ] `repository_id` inválido retorna 404 em todos os endpoints

---

## Testes

### Arquivo: `test/omnigist_web/controllers/api/commit_controller_test.exs`

```elixir
defmodule OmnigistWeb.API.CommitControllerTest do
  use OmnigistWeb.ConnCase

  import Omnigist.RepositoriesFixtures

  # Usa o próprio repo do projeto como fixture git
  @git_path File.cwd!()

  setup do
    {:ok, repo: repository_fixture(%{path: @git_path, name: "omnigist"})}
  end

  describe "GET /api/v1/repositories/:id/commits" do
    test "returns list of commits", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/commits")
      assert %{"data" => commits} = json_response(conn, 200)
      assert is_list(commits)
      assert length(commits) > 0
    end

    test "respects limit param", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/commits?limit=3")
      assert %{"data" => commits} = json_response(conn, 200)
      assert length(commits) <= 3
    end

    test "each commit has required fields", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/commits?limit=1")
      assert %{"data" => [commit]} = json_response(conn, 200)
      assert Map.has_key?(commit, "hash")
      assert Map.has_key?(commit, "short_hash")
      assert Map.has_key?(commit, "message")
      assert Map.has_key?(commit, "author_name")
      assert Map.has_key?(commit, "author_email")
      assert Map.has_key?(commit, "date")
    end

    test "returns 404 for unknown repository_id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/repositories/00000000-0000-0000-0000-000000000000/commits")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/repositories/:id/commits/authors" do
    test "returns unique authors", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/commits/authors")
      assert %{"data" => authors} = json_response(conn, 200)
      assert is_list(authors)
      assert Enum.all?(authors, &(Map.has_key?(&1, "name") and Map.has_key?(&1, "email")))
      emails = Enum.map(authors, & &1["email"])
      assert emails == Enum.uniq(emails)
    end
  end

  describe "GET /api/v1/repositories/:id/commits/:hash" do
    test "returns a single commit by hash", %{conn: conn, repo: repo} do
      # Obtém um hash real via API
      list_conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/commits?limit=1")
      %{"data" => [%{"hash" => hash}]} = json_response(list_conn, 200)

      show_conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/commits/#{hash}")
      assert %{"data" => commit} = json_response(show_conn, 200)
      assert commit["hash"] == hash
    end

    test "returns 422 for unknown hash", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/commits/deadbeefdeadbeef")
      assert %{"error" => _} = json_response(conn, 422)
    end
  end
end
```
