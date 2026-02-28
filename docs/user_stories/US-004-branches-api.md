# US-004 — API de Branches

## Descrição

**Como** cliente desktop,
**Quero** listar, criar, deletar, fazer checkout e merge de branches de um repositório registrado,
**Para que** eu possa gerenciar o fluxo de branches sem sair da ferramenta desktop.

---

## Contexto Técnico

Operações de branch modificam estado no repositório local. `checkout` e `merge` têm potencial de conflito — em caso de falha o git retorna exit code != 0 e o controller responde com 422 + mensagem do stderr. Não há rollback automático.

---

## Estrutura de Arquivos

```
lib/omnigist_web/controllers/api/
  branch_controller.ex
  branch_json.ex
```

---

## Rotas

| Método | Caminho | Ação | Descrição |
|--------|---------|------|-----------|
| `GET` | `/api/v1/repositories/:repository_id/branches` | `:index` | Lista branches (local + remote) |
| `POST` | `/api/v1/repositories/:repository_id/branches` | `:create` | Cria nova branch |
| `DELETE` | `/api/v1/repositories/:repository_id/branches/:name` | `:delete` | Deleta branch local |
| `POST` | `/api/v1/repositories/:repository_id/branches/:name/checkout` | `:checkout` | Faz checkout da branch |
| `POST` | `/api/v1/repositories/:repository_id/branches/:name/merge` | `:merge` | Merge da branch na atual |

---

## Implementação Esperada

### Router

```elixir
# lib/omnigist_web/router.ex — dentro do resources "/repositories"
resources "/repositories", RepositoryController, except: [:new, :edit] do
  # ...outros recursos...

  get    "/branches",                    BranchController, :index
  post   "/branches",                    BranchController, :create
  delete "/branches/:name",              BranchController, :delete
  post   "/branches/:name/checkout",     BranchController, :checkout
  post   "/branches/:name/merge",        BranchController, :merge
end
```

### Controller

```elixir
# lib/omnigist_web/controllers/api/branch_controller.ex
defmodule OmnigistWeb.API.BranchController do
  use OmnigistWeb, :controller

  alias Omnigist.{Repositories, Git}

  action_fallback OmnigistWeb.FallbackController

  def index(conn, %{"repository_id" => repo_id}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, branches} <- Git.list_branches(repo.path) do
      render(conn, :index, branches: branches)
    end
  end

  def create(conn, %{"repository_id" => repo_id, "branch" => %{"name" => name}}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, branch} <- Git.create_branch(repo.path, name) do
      conn
      |> put_status(:created)
      |> render(:show, branch: branch)
    end
  end

  def delete(conn, %{"repository_id" => repo_id, "name" => name} = params) do
    repo = Repositories.get_repository!(repo_id)
    force = params["force"] == "true"

    with :ok <- Git.delete_branch(repo.path, name, force: force) do
      send_resp(conn, :no_content, "")
    end
  end

  def checkout(conn, %{"repository_id" => repo_id, "name" => name}) do
    repo = Repositories.get_repository!(repo_id)

    with :ok <- Git.checkout_branch(repo.path, name) do
      send_resp(conn, :no_content, "")
    end
  end

  def merge(conn, %{"repository_id" => repo_id, "name" => name}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, output} <- Git.merge_branch(repo.path, name) do
      json(conn, %{data: %{message: output}})
    end
  end
end
```

### JSON View

```elixir
# lib/omnigist_web/controllers/api/branch_json.ex
defmodule OmnigistWeb.API.BranchJSON do
  def index(%{branches: branches}) do
    %{data: Enum.map(branches, &data/1)}
  end

  def show(%{branch: branch}) do
    %{data: data(branch)}
  end

  defp data(branch) do
    %{
      name: branch.name,
      is_current: branch.is_current,
      is_remote: branch.is_remote,
      upstream: branch.upstream,
      ahead: branch.ahead,
      behind: branch.behind
    }
  end
end
```

---

## Exemplo de Request/Response

### `GET /api/v1/repositories/:id/branches`

```json
{
  "data": [
    {
      "name": "main",
      "is_current": true,
      "is_remote": false,
      "upstream": "origin/main",
      "ahead": 2,
      "behind": 0
    },
    {
      "name": "feature/login",
      "is_current": false,
      "is_remote": false,
      "upstream": null,
      "ahead": 0,
      "behind": 0
    },
    {
      "name": "remotes/origin/main",
      "is_current": false,
      "is_remote": true,
      "upstream": null,
      "ahead": 0,
      "behind": 0
    }
  ]
}
```

### `POST /api/v1/repositories/:id/branches`

Request body:
```json
{ "branch": { "name": "feature/payments" } }
```

Response 201:
```json
{ "data": { "name": "feature/payments", "is_current": false, "is_remote": false, "upstream": null, "ahead": 0, "behind": 0 } }
```

### Erro de merge com conflito

```json
{ "error": "CONFLICT (content): Merge conflict in lib/app.ex\nAutomatic merge failed; fix conflicts and then commit the result." }
```
HTTP 422.

---

## Critérios de Aceite

- [ ] `GET /branches` retorna branches locais e remotas com `is_remote` correto
- [ ] `GET /branches` indica a branch atual via `is_current: true` em exatamente uma entrada
- [ ] `GET /branches` retorna `ahead` e `behind` quando há upstream configurado
- [ ] `POST /branches` com `name` válido cria a branch e retorna 201
- [ ] `POST /branches` com nome já existente retorna 422
- [ ] `DELETE /branches/:name` remove a branch local e retorna 204
- [ ] `DELETE /branches/:name?force=true` usa `-D` em vez de `-d` (permite deletar branch não mergeada)
- [ ] `DELETE /branches/:name` na branch atual retorna 422 com mensagem do git
- [ ] `POST /branches/:name/checkout` faz checkout e retorna 204
- [ ] `POST /branches/:name/checkout` para branch inexistente retorna 422
- [ ] `POST /branches/:name/merge` retorna 200 com output do git em caso de sucesso
- [ ] `POST /branches/:name/merge` com conflito retorna 422 com a mensagem de conflito
- [ ] `repository_id` inválido retorna 404 em todos os endpoints

---

## Testes

### Arquivo: `test/omnigist_web/controllers/api/branch_controller_test.exs`

```elixir
defmodule OmnigistWeb.API.BranchControllerTest do
  use OmnigistWeb.ConnCase

  import Omnigist.RepositoriesFixtures

  setup do
    # Cria um repo git temporário isolado para testes destrutivos
    tmp_dir = Path.join(System.tmp_dir!(), "test_repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)

    # Commit inicial necessário para criar branches
    File.write!(Path.join(tmp_dir, "README.md"), "hello")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    {:ok, repo: repository_fixture(%{path: tmp_dir, name: "test-repo"}), tmp_dir: tmp_dir}
  end

  describe "GET /branches" do
    test "returns branches", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/branches")
      assert %{"data" => branches} = json_response(conn, 200)
      assert is_list(branches)
      assert Enum.count(branches, & &1["is_current"]) == 1
    end
  end

  describe "POST /branches" do
    test "creates a branch and returns 201", %{conn: conn, repo: repo} do
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/branches",
        branch: %{name: "feature/new-thing"})
      assert %{"data" => %{"name" => "feature/new-thing"}} = json_response(conn, 201)
    end

    test "returns 422 for duplicate branch name", %{conn: conn, repo: repo} do
      post(conn, ~p"/api/v1/repositories/#{repo.id}/branches", branch: %{name: "dup"})
      conn2 = post(conn, ~p"/api/v1/repositories/#{repo.id}/branches", branch: %{name: "dup"})
      assert %{"error" => _} = json_response(conn2, 422)
    end
  end

  describe "DELETE /branches/:name" do
    test "deletes a branch and returns 204", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      System.cmd("git", ["branch", "to-delete"], cd: tmp_dir)
      conn = delete(conn, ~p"/api/v1/repositories/#{repo.id}/branches/to-delete")
      assert response(conn, 204)
    end

    test "returns 422 when deleting current branch", %{conn: conn, repo: repo} do
      conn = delete(conn, ~p"/api/v1/repositories/#{repo.id}/branches/main")
      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "POST /branches/:name/checkout" do
    test "checks out a branch and returns 204", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      System.cmd("git", ["branch", "other"], cd: tmp_dir)
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/branches/other/checkout")
      assert response(conn, 204)
    end

    test "returns 422 for non-existent branch", %{conn: conn, repo: repo} do
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/branches/ghost/checkout")
      assert %{"error" => _} = json_response(conn, 422)
    end
  end
end
```
