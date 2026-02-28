# US-006 — API de Stash

## Descrição

**Como** cliente desktop,
**Quero** listar, criar, aplicar e remover entradas do stash de um repositório registrado,
**Para que** eu possa guardar e recuperar mudanças em progresso sem fazer commits.

---

## Contexto Técnico

O stash do git é identificado por índice numérico (`stash@{0}`, `stash@{1}`, ...). O índice 0 é sempre o mais recente. Após `pop` ou `drop`, os índices das entradas restantes se reorganizam. O controller usa o índice como parâmetro de rota (`:index`).

---

## Estrutura de Arquivos

```
lib/omnigist_web/controllers/api/
  stash_controller.ex
  stash_json.ex
```

---

## Rotas

| Método | Caminho | Ação | Descrição |
|--------|---------|------|-----------|
| `GET` | `/api/v1/repositories/:repository_id/stashes` | `:index` | Lista todas as entradas do stash |
| `POST` | `/api/v1/repositories/:repository_id/stashes` | `:create` | Cria nova entrada (stash push) |
| `POST` | `/api/v1/repositories/:repository_id/stashes/:index/pop` | `:pop` | Aplica e remove a entrada (stash pop) |
| `DELETE` | `/api/v1/repositories/:repository_id/stashes/:index` | `:drop` | Remove a entrada sem aplicar (stash drop) |

---

## Implementação Esperada

### Router

```elixir
# lib/omnigist_web/router.ex — dentro do resources "/repositories"
resources "/repositories", RepositoryController, except: [:new, :edit] do
  # ...

  get    "/stashes",             StashController, :index
  post   "/stashes",             StashController, :create
  post   "/stashes/:index/pop",  StashController, :pop
  delete "/stashes/:index",      StashController, :drop
end
```

### Controller

```elixir
# lib/omnigist_web/controllers/api/stash_controller.ex
defmodule OmnigistWeb.API.StashController do
  use OmnigistWeb, :controller

  alias Omnigist.{Repositories, Git}

  action_fallback OmnigistWeb.FallbackController

  def index(conn, %{"repository_id" => repo_id}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, stashes} <- Git.list_stashes(repo.path) do
      render(conn, :index, stashes: stashes)
    end
  end

  def create(conn, %{"repository_id" => repo_id} = params) do
    repo = Repositories.get_repository!(repo_id)
    message = get_in(params, ["stash", "message"])
    opts = if message, do: [message: message], else: []

    with :ok <- Git.stash_push(repo.path, opts) do
      send_resp(conn, :created, "")
    end
  end

  def pop(conn, %{"repository_id" => repo_id, "index" => index}) do
    repo = Repositories.get_repository!(repo_id)

    with :ok <- Git.stash_pop(repo.path, index) do
      send_resp(conn, :no_content, "")
    end
  end

  def drop(conn, %{"repository_id" => repo_id, "index" => index}) do
    repo = Repositories.get_repository!(repo_id)

    with :ok <- Git.stash_drop(repo.path, index) do
      send_resp(conn, :no_content, "")
    end
  end
end
```

### JSON View

```elixir
# lib/omnigist_web/controllers/api/stash_json.ex
defmodule OmnigistWeb.API.StashJSON do
  def index(%{stashes: stashes}) do
    %{data: Enum.map(stashes, &data/1)}
  end

  defp data(stash) do
    %{
      index: stash.index,
      message: stash.message,
      hash: stash.hash
    }
  end
end
```

---

## Exemplo de Request/Response

### `GET /api/v1/repositories/:id/stashes`

```json
{
  "data": [
    {
      "index": 0,
      "message": "WIP on main: a1b2c3d Add login",
      "hash": "f9e8d7c6b5a4..."
    },
    {
      "index": 1,
      "message": "On feature/x: work in progress",
      "hash": "1a2b3c4d5e6f..."
    }
  ]
}
```

### `POST /api/v1/repositories/:id/stashes`

Request body (opcional):
```json
{ "stash": { "message": "WIP: payments refactor" } }
```

Response 201 (sem body).

### `POST /api/v1/repositories/:id/stashes/0/pop`

Response 204 (sem body).

### `DELETE /api/v1/repositories/:id/stashes/1`

Response 204 (sem body).

### Stash pop com conflito

```json
{
  "error": "CONFLICT (content): Merge conflict in lib/app.ex\nThe stash entry is kept in case you need it again."
}
```
HTTP 422.

### Stash vazio

`GET /api/v1/repositories/:id/stashes` quando não há nada no stash:
```json
{ "data": [] }
```
HTTP 200 (não é erro).

---

## Critérios de Aceite

- [ ] `GET /stashes` retorna lista vazia `[]` quando o stash está vazio (não 422)
- [ ] `GET /stashes` retorna entradas com `index` começando em 0 (mais recente)
- [ ] `POST /stashes` sem body executa `git stash push` e retorna 201
- [ ] `POST /stashes` com `{"stash": {"message": "..."}}` executa `git stash push -m <msg>` e retorna 201
- [ ] `POST /stashes` quando não há mudanças para guardar retorna 422 com mensagem do git
- [ ] `POST /stashes/0/pop` aplica o stash mais recente e retorna 204
- [ ] `POST /stashes/0/pop` com conflito retorna 422 com a mensagem de conflito
- [ ] `DELETE /stashes/0` remove a entrada sem aplicar e retorna 204
- [ ] `DELETE /stashes/99` (índice inexistente) retorna 422
- [ ] `repository_id` inválido retorna 404

---

## Testes

### Arquivo: `test/omnigist_web/controllers/api/stash_controller_test.exs`

```elixir
defmodule OmnigistWeb.API.StashControllerTest do
  use OmnigistWeb.ConnCase

  import Omnigist.RepositoriesFixtures

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "test_repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)

    # Commit inicial
    File.write!(Path.join(tmp_dir, "README.md"), "hello")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    {:ok, repo: repository_fixture(%{path: tmp_dir, name: "test-repo"}), tmp_dir: tmp_dir}
  end

  describe "GET /stashes" do
    test "returns empty list when stash is clean", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/stashes")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns stash entries", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "README.md"), "modified")
      System.cmd("git", ["stash", "push", "-m", "my stash"], cd: tmp_dir)

      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/stashes")
      assert %{"data" => [stash]} = json_response(conn, 200)
      assert stash["index"] == 0
      assert is_binary(stash["message"])
      assert is_binary(stash["hash"])
    end
  end

  describe "POST /stashes" do
    test "creates a stash entry and returns 201", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "README.md"), "dirty")

      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/stashes",
        stash: %{message: "my wip"})
      assert response(conn, 201)
    end

    test "returns 422 when working tree is clean", %{conn: conn, repo: repo} do
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/stashes")
      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "POST /stashes/:index/pop" do
    test "pops the stash and returns 204", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "README.md"), "dirty")
      System.cmd("git", ["stash"], cd: tmp_dir)

      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/stashes/0/pop")
      assert response(conn, 204)
    end

    test "returns 422 for nonexistent stash index", %{conn: conn, repo: repo} do
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/stashes/99/pop")
      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "DELETE /stashes/:index" do
    test "drops the stash entry and returns 204", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "README.md"), "dirty")
      System.cmd("git", ["stash"], cd: tmp_dir)

      conn = delete(conn, ~p"/api/v1/repositories/#{repo.id}/stashes/0")
      assert response(conn, 204)
    end

    test "returns 422 for nonexistent index", %{conn: conn, repo: repo} do
      conn = delete(conn, ~p"/api/v1/repositories/#{repo.id}/stashes/99")
      assert %{"error" => _} = json_response(conn, 422)
    end
  end
end
```
