# US-005 — API de Remotes (fetch / pull / push)

## Descrição

**Como** cliente desktop,
**Quero** listar remotes e executar operações de sincronização (fetch, pull, push) em um repositório registrado,
**Para que** eu possa manter o repositório sincronizado com o servidor remoto sem usar o terminal.

---

## Contexto Técnico

Operações de rede (`fetch`, `pull`, `push`) podem ser lentas e falhar por razões externas (autenticação, sem conexão, conflitos de push). O servidor retorna 422 com a mensagem do stderr do git em caso de falha. Não há timeout configurado no controller — isso é responsabilidade do cliente.

---

## Estrutura de Arquivos

```
lib/omnigist_web/controllers/api/
  remote_controller.ex
  remote_json.ex
```

---

## Rotas

| Método | Caminho | Ação | Descrição |
|--------|---------|------|-----------|
| `GET` | `/api/v1/repositories/:repository_id/remotes` | `:index` | Lista remotes configurados |
| `POST` | `/api/v1/repositories/:repository_id/remotes/fetch` | `:fetch` | Executa `git fetch` |
| `POST` | `/api/v1/repositories/:repository_id/remotes/pull` | `:pull` | Executa `git pull` |
| `POST` | `/api/v1/repositories/:repository_id/remotes/push` | `:push` | Executa `git push` |

---

## Implementação Esperada

### Router

```elixir
# lib/omnigist_web/router.ex — dentro do resources "/repositories"
resources "/repositories", RepositoryController, except: [:new, :edit] do
  # ...

  get  "/remotes",        RemoteController, :index
  post "/remotes/fetch",  RemoteController, :fetch
  post "/remotes/pull",   RemoteController, :pull
  post "/remotes/push",   RemoteController, :push
end
```

### Controller

```elixir
# lib/omnigist_web/controllers/api/remote_controller.ex
defmodule OmnigistWeb.API.RemoteController do
  use OmnigistWeb, :controller

  alias Omnigist.{Repositories, Git}

  action_fallback OmnigistWeb.FallbackController

  def index(conn, %{"repository_id" => repo_id}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, remotes} <- Git.list_remotes(repo.path) do
      render(conn, :index, remotes: remotes)
    end
  end

  def fetch(conn, %{"repository_id" => repo_id} = params) do
    repo = Repositories.get_repository!(repo_id)
    opts = build_opts(params, [:remote])

    with {:ok, output} <- Git.fetch(repo.path, opts) do
      json(conn, %{data: %{message: output}})
    end
  end

  def pull(conn, %{"repository_id" => repo_id} = params) do
    repo = Repositories.get_repository!(repo_id)
    opts = build_opts(params, [:remote, :branch])

    with {:ok, output} <- Git.pull(repo.path, opts) do
      json(conn, %{data: %{message: output}})
    end
  end

  def push(conn, %{"repository_id" => repo_id} = params) do
    repo = Repositories.get_repository!(repo_id)
    opts = build_opts(params, [:remote, :branch])

    with {:ok, output} <- Git.push(repo.path, opts) do
      json(conn, %{data: %{message: output}})
    end
  end

  # Extrai chaves relevantes dos params e monta keyword list
  defp build_opts(params, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      str_key = Atom.to_string(key)
      case params[str_key] do
        nil   -> acc
        value -> Keyword.put(acc, key, value)
      end
    end)
  end
end
```

### JSON View

```elixir
# lib/omnigist_web/controllers/api/remote_json.ex
defmodule OmnigistWeb.API.RemoteJSON do
  def index(%{remotes: remotes}) do
    %{data: Enum.map(remotes, &data/1)}
  end

  defp data(remote) do
    %{
      name: remote.name,
      fetch_url: remote.fetch_url,
      push_url: remote.push_url
    }
  end
end
```

---

## Exemplo de Request/Response

### `GET /api/v1/repositories/:id/remotes`

```json
{
  "data": [
    {
      "name": "origin",
      "fetch_url": "git@github.com:user/repo.git",
      "push_url": "git@github.com:user/repo.git"
    },
    {
      "name": "upstream",
      "fetch_url": "https://github.com/original/repo.git",
      "push_url": "https://github.com/original/repo.git"
    }
  ]
}
```

### `POST /api/v1/repositories/:id/remotes/fetch`

Request body (opcional):
```json
{ "remote": "origin" }
```

Response 200:
```json
{
  "data": {
    "message": "From github.com:user/repo\n   a1b2c3d..e4f5g6h  main -> origin/main"
  }
}
```

### `POST /api/v1/repositories/:id/remotes/pull`

Request body:
```json
{ "remote": "origin", "branch": "main" }
```

### `POST /api/v1/repositories/:id/remotes/push`

Request body:
```json
{ "remote": "origin", "branch": "feature/payments" }
```

### Erro de autenticação

```json
{ "error": "git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository." }
```
HTTP 422.

---

## Critérios de Aceite

- [ ] `GET /remotes` retorna todos os remotes com `fetch_url` e `push_url` distintos quando configurados
- [ ] `GET /remotes` retorna lista vazia `[]` para repo sem remotes (não 422)
- [ ] `POST /remotes/fetch` sem body faz fetch de todos os remotes (`--all`)
- [ ] `POST /remotes/fetch` com `{"remote": "origin"}` faz fetch apenas do remote especificado
- [ ] `POST /remotes/pull` sem body usa `origin` como remote padrão
- [ ] `POST /remotes/pull` com `remote` e `branch` executa `git pull <remote> <branch>`
- [ ] `POST /remotes/push` sem body usa `origin` como remote padrão
- [ ] Falha de autenticação (exit code != 0) retorna 422 com mensagem do git
- [ ] `repository_id` inválido retorna 404

---

## Testes

### Arquivo: `test/omnigist_web/controllers/api/remote_controller_test.exs`

```elixir
defmodule OmnigistWeb.API.RemoteControllerTest do
  use OmnigistWeb.ConnCase

  import Omnigist.RepositoriesFixtures

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "test_repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)

    {:ok, repo: repository_fixture(%{path: tmp_dir, name: "test-repo"}), tmp_dir: tmp_dir}
  end

  describe "GET /remotes" do
    test "returns empty list when no remotes configured", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/remotes")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns remotes when configured", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      System.cmd("git", ["remote", "add", "origin", "https://github.com/user/repo.git"], cd: tmp_dir)
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/remotes")
      assert %{"data" => [remote]} = json_response(conn, 200)
      assert remote["name"] == "origin"
      assert remote["fetch_url"] == "https://github.com/user/repo.git"
    end

    test "returns 404 for unknown repository_id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/repositories/00000000-0000-0000-0000-000000000000/remotes")
      assert json_response(conn, 404)
    end
  end

  describe "POST /remotes/fetch" do
    test "returns 422 when remote does not exist", %{conn: conn, repo: repo} do
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/remotes/fetch",
        %{remote: "nonexistent"})
      assert %{"error" => _} = json_response(conn, 422)
    end

    # Teste de fetch real requer acesso a rede — marcar como @tag :integration
    @tag :integration
    test "fetches from remote successfully", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      # Setup: clonar um repo local como remote
      origin_dir = Path.join(System.tmp_dir!(), "origin_#{System.unique_integer([:positive])}")
      File.mkdir_p!(origin_dir)
      System.cmd("git", ["init", "--bare"], cd: origin_dir)
      System.cmd("git", ["remote", "add", "origin", origin_dir], cd: tmp_dir)

      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/remotes/fetch")
      assert %{"data" => %{"message" => _}} = json_response(conn, 200)
    end
  end
end
```

> **Nota:** Testes de `push` e `pull` que requerem comunicação real com um remote devem ser marcados com `@tag :integration` e excluídos da suite default com `mix test --exclude integration`.
