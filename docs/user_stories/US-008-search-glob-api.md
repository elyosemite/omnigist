# US-008 — API de Busca por Glob

## Descrição

**Como** cliente desktop,
**Quero** buscar arquivos em um repositório registrado usando padrões glob,
**Para que** eu possa navegar na estrutura de arquivos do projeto sem clonar ou abrir o repositório localmente.

---

## Contexto Técnico

A busca usa `git ls-files <pattern>` — isso retorna apenas arquivos **rastreados pelo git** (tracked), ignorando arquivos em `.gitignore` e não adicionados. O padrão glob é passado diretamente para o git, que usa sua própria implementação de glob (compatível com `fnmatch`).

---

## Estrutura de Arquivos

```
lib/omnigist_web/controllers/api/
  search_controller.ex
  search_json.ex
```

---

## Rotas

| Método | Caminho | Ação | Descrição |
|--------|---------|------|-----------|
| `GET` | `/api/v1/repositories/:repository_id/search` | `:index` | Busca arquivos por padrão glob |

**Query param:** `pattern` (string, obrigatório) — ex.: `lib/**/*.ex`, `*.md`, `test/**/*_test.exs`

---

## Implementação Esperada

### Router

```elixir
# lib/omnigist_web/router.ex — dentro do resources "/repositories"
resources "/repositories", RepositoryController, except: [:new, :edit] do
  # ...

  get "/search", SearchController, :index
end
```

### Controller

```elixir
# lib/omnigist_web/controllers/api/search_controller.ex
defmodule OmnigistWeb.API.SearchController do
  use OmnigistWeb, :controller

  alias Omnigist.{Repositories, Git}

  action_fallback OmnigistWeb.FallbackController

  def index(conn, %{"repository_id" => repo_id, "pattern" => pattern}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, files} <- Git.search_glob(repo.path, pattern) do
      render(conn, :index, files: files, pattern: pattern)
    end
  end

  def index(conn, %{"repository_id" => _repo_id}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "query param 'pattern' is required"})
  end
end
```

### JSON View

```elixir
# lib/omnigist_web/controllers/api/search_json.ex
defmodule OmnigistWeb.API.SearchJSON do
  def index(%{files: files, pattern: pattern}) do
    %{
      data: %{
        pattern: pattern,
        count: length(files),
        files: files
      }
    }
  end
end
```

---

## Exemplo de Request/Response

### `GET /api/v1/repositories/:id/search?pattern=lib/**/*.ex`

```json
{
  "data": {
    "pattern": "lib/**/*.ex",
    "count": 12,
    "files": [
      "lib/omnigist/accounts.ex",
      "lib/omnigist/accounts/user.ex",
      "lib/omnigist/git.ex",
      "lib/omnigist/git/branch.ex",
      "lib/omnigist/git/commit.ex",
      "lib/omnigist/repositories.ex",
      "lib/omnigist/repositories/repository.ex",
      "lib/omnigist_web/controllers/api/branch_controller.ex",
      "lib/omnigist_web/controllers/api/commit_controller.ex",
      "lib/omnigist_web/controllers/api/repository_controller.ex",
      "lib/omnigist_web/router.ex",
      "lib/omnigist_web.ex"
    ]
  }
}
```

### `GET /api/v1/repositories/:id/search?pattern=*.md`

```json
{
  "data": {
    "pattern": "*.md",
    "count": 2,
    "files": ["README.md", "CLAUDE.md"]
  }
}
```

### `GET /api/v1/repositories/:id/search?pattern=*.xyz` (sem resultados)

```json
{
  "data": {
    "pattern": "*.xyz",
    "count": 0,
    "files": []
  }
}
```
HTTP 200 (lista vazia não é erro).

### `GET /api/v1/repositories/:id/search` (sem pattern)

```json
{ "error": "query param 'pattern' is required" }
```
HTTP 422.

---

## Critérios de Aceite

- [ ] `GET /search?pattern=lib/**/*.ex` retorna apenas arquivos `.ex` dentro de `lib/`
- [ ] `GET /search?pattern=*.md` retorna apenas arquivos Markdown na raiz
- [ ] `GET /search?pattern=test/**/*_test.exs` retorna apenas arquivos de teste
- [ ] Padrão sem resultados retorna `{"data": {"count": 0, "files": []}}` com status 200
- [ ] Requisição sem `pattern` retorna 422 com mensagem clara
- [ ] Arquivos ignorados pelo `.gitignore` **não** aparecem nos resultados
- [ ] Arquivos não rastreados (untracked) **não** aparecem nos resultados
- [ ] O campo `count` sempre corresponde ao `length(files)`
- [ ] `repository_id` inválido retorna 404

---

## Testes

### Arquivo: `test/omnigist_web/controllers/api/search_controller_test.exs`

```elixir
defmodule OmnigistWeb.API.SearchControllerTest do
  use OmnigistWeb.ConnCase

  import Omnigist.RepositoriesFixtures

  # Usa o próprio repo do projeto como fixture — tem arquivos .ex rastreados
  @git_path File.cwd!()

  setup do
    {:ok, repo: repository_fixture(%{path: @git_path, name: "omnigist"})}
  end

  describe "GET /search" do
    test "returns matching files for a valid pattern", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/search?pattern=lib/**/*.ex")
      assert %{"data" => %{"files" => files, "count" => count, "pattern" => pattern}} =
               json_response(conn, 200)

      assert pattern == "lib/**/*.ex"
      assert is_list(files)
      assert count == length(files)
      assert Enum.all?(files, &String.ends_with?(&1, ".ex"))
      assert Enum.all?(files, &String.starts_with?(&1, "lib/"))
    end

    test "returns empty list for pattern with no matches", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/search?pattern=*.xyz_no_match")
      assert %{"data" => %{"files" => [], "count" => 0}} = json_response(conn, 200)
    end

    test "returns 422 when pattern param is missing", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/search")
      assert %{"error" => message} = json_response(conn, 422)
      assert message =~ "pattern"
    end

    test "returns 404 for unknown repository_id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/repositories/00000000-0000-0000-0000-000000000000/search?pattern=*.ex")
      assert json_response(conn, 404)
    end

    test "count matches files length", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/search?pattern=*.exs")
      assert %{"data" => %{"files" => files, "count" => count}} = json_response(conn, 200)
      assert count == length(files)
    end

    test "test files pattern works", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/search?pattern=test/**/*_test.exs")
      assert %{"data" => %{"files" => files}} = json_response(conn, 200)
      assert Enum.all?(files, &String.ends_with?(&1, "_test.exs"))
    end
  end
end
```
