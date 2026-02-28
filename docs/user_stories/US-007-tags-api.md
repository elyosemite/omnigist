# US-007 — API de Tags

## Descrição

**Como** cliente desktop,
**Quero** listar, criar e deletar tags de um repositório registrado,
**Para que** eu possa marcar versões e releases sem usar o terminal.

---

## Contexto Técnico

O git suporta dois tipos de tag: **lightweight** (apenas um ponteiro para um commit) e **annotated** (objeto próprio com mensagem, autor e data). A API distingue os dois via campo `type`. Tags anotadas requerem a flag `-a` e uma mensagem (`-m`). Deletar uma tag só remove localmente — para remover do remote é necessário um `push` separado.

---

## Estrutura de Arquivos

```
lib/omnigist_web/controllers/api/
  tag_controller.ex
  tag_json.ex
```

---

## Rotas

| Método | Caminho | Ação | Descrição |
|--------|---------|------|-----------|
| `GET` | `/api/v1/repositories/:repository_id/tags` | `:index` | Lista todas as tags |
| `POST` | `/api/v1/repositories/:repository_id/tags` | `:create` | Cria tag (lightweight ou annotated) |
| `DELETE` | `/api/v1/repositories/:repository_id/tags/:name` | `:delete` | Remove tag local |

---

## Implementação Esperada

### Router

```elixir
# lib/omnigist_web/router.ex — dentro do resources "/repositories"
resources "/repositories", RepositoryController, except: [:new, :edit] do
  # ...

  get    "/tags",       TagController, :index
  post   "/tags",       TagController, :create
  delete "/tags/:name", TagController, :delete
end
```

### Controller

```elixir
# lib/omnigist_web/controllers/api/tag_controller.ex
defmodule OmnigistWeb.API.TagController do
  use OmnigistWeb, :controller

  alias Omnigist.{Repositories, Git}

  action_fallback OmnigistWeb.FallbackController

  def index(conn, %{"repository_id" => repo_id}) do
    repo = Repositories.get_repository!(repo_id)

    with {:ok, tags} <- Git.list_tags(repo.path) do
      render(conn, :index, tags: tags)
    end
  end

  def create(conn, %{"repository_id" => repo_id, "tag" => tag_params}) do
    repo = Repositories.get_repository!(repo_id)
    name = tag_params["name"]

    opts =
      []
      |> maybe_put(:message, tag_params["message"])
      |> maybe_put(:hash, tag_params["hash"])

    with :ok <- Git.create_tag(repo.path, name, opts) do
      conn
      |> put_status(:created)
      |> json(%{data: %{name: name}})
    end
  end

  def delete(conn, %{"repository_id" => repo_id, "name" => name}) do
    repo = Repositories.get_repository!(repo_id)

    with :ok <- Git.delete_tag(repo.path, name) do
      send_resp(conn, :no_content, "")
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
```

### JSON View

```elixir
# lib/omnigist_web/controllers/api/tag_json.ex
defmodule OmnigistWeb.API.TagJSON do
  def index(%{tags: tags}) do
    %{data: Enum.map(tags, &data/1)}
  end

  defp data(tag) do
    %{
      name: tag.name,
      hash: tag.hash,
      message: tag.message,
      date: tag.date,
      type: tag.type
    }
  end
end
```

---

## Exemplo de Request/Response

### `GET /api/v1/repositories/:id/tags`

```json
{
  "data": [
    {
      "name": "v1.0.0",
      "hash": "a1b2c3d4e5f6...",
      "message": "Release 1.0.0",
      "date": "2024-01-15T10:00:00+00:00",
      "type": "annotated"
    },
    {
      "name": "v0.9.0",
      "hash": "f9e8d7c6b5a4...",
      "message": null,
      "date": "2023-12-01T08:00:00+00:00",
      "type": "lightweight"
    }
  ]
}
```

### `POST /api/v1/repositories/:id/tags` — Tag Anotada

Request body:
```json
{
  "tag": {
    "name": "v1.1.0",
    "message": "Release 1.1.0 — add payments"
  }
}
```

Response 201:
```json
{ "data": { "name": "v1.1.0" } }
```

### `POST /api/v1/repositories/:id/tags` — Tag Lightweight

Request body:
```json
{ "tag": { "name": "build-20240115" } }
```

### `POST /api/v1/repositories/:id/tags` — Tag em commit específico

Request body:
```json
{
  "tag": {
    "name": "v1.0.0-hotfix",
    "hash": "a1b2c3d"
  }
}
```

### `DELETE /api/v1/repositories/:id/tags/v0.9.0`

Response 204 (sem body).

### Tag já existente

```json
{ "error": "fatal: tag 'v1.0.0' already exists" }
```
HTTP 422.

---

## Critérios de Aceite

- [ ] `GET /tags` retorna lista vazia `[]` quando não há tags (não 422)
- [ ] `GET /tags` diferencia `type: "annotated"` de `type: "lightweight"` corretamente
- [ ] `POST /tags` com apenas `name` cria tag lightweight e retorna 201
- [ ] `POST /tags` com `name` e `message` cria tag annotated e retorna 201
- [ ] `POST /tags` com `name` e `hash` cria tag apontando para o hash especificado
- [ ] `POST /tags` com nome já existente retorna 422
- [ ] `POST /tags` sem `name` retorna 422
- [ ] `DELETE /tags/:name` remove tag local e retorna 204
- [ ] `DELETE /tags/:name` para tag inexistente retorna 422
- [ ] `repository_id` inválido retorna 404

---

## Testes

### Arquivo: `test/omnigist_web/controllers/api/tag_controller_test.exs`

```elixir
defmodule OmnigistWeb.API.TagControllerTest do
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

  describe "GET /tags" do
    test "returns empty list when no tags", %{conn: conn, repo: repo} do
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/tags")
      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns tags with correct fields", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      System.cmd("git", ["tag", "v1.0.0"], cd: tmp_dir)
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/tags")
      assert %{"data" => [tag]} = json_response(conn, 200)
      assert tag["name"] == "v1.0.0"
      assert tag["type"] == "lightweight"
    end

    test "identifies annotated tags correctly", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      System.cmd("git", ["tag", "-a", "v2.0.0", "-m", "Release 2.0"], cd: tmp_dir)
      conn = get(conn, ~p"/api/v1/repositories/#{repo.id}/tags")
      assert %{"data" => [tag]} = json_response(conn, 200)
      assert tag["name"] == "v2.0.0"
      assert tag["type"] == "annotated"
    end
  end

  describe "POST /tags" do
    test "creates a lightweight tag and returns 201", %{conn: conn, repo: repo} do
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/tags", tag: %{name: "v1.0.0"})
      assert %{"data" => %{"name" => "v1.0.0"}} = json_response(conn, 201)
    end

    test "creates an annotated tag with message", %{conn: conn, repo: repo} do
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/tags",
        tag: %{name: "v1.0.0", message: "Release 1.0"})
      assert json_response(conn, 201)
    end

    test "returns 422 for duplicate tag name", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      System.cmd("git", ["tag", "v1.0.0"], cd: tmp_dir)
      conn = post(conn, ~p"/api/v1/repositories/#{repo.id}/tags", tag: %{name: "v1.0.0"})
      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "DELETE /tags/:name" do
    test "deletes tag and returns 204", %{conn: conn, repo: repo, tmp_dir: tmp_dir} do
      System.cmd("git", ["tag", "to-delete"], cd: tmp_dir)
      conn = delete(conn, ~p"/api/v1/repositories/#{repo.id}/tags/to-delete")
      assert response(conn, 204)
    end

    test "returns 422 for nonexistent tag", %{conn: conn, repo: repo} do
      conn = delete(conn, ~p"/api/v1/repositories/#{repo.id}/tags/ghost")
      assert %{"error" => _} = json_response(conn, 422)
    end
  end
end
```
