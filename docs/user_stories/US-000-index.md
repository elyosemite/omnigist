# User Stories — Omnigist Git API

Índice de todas as User Stories do projeto. Cada arquivo contém: descrição, estrutura de arquivos, código Elixir completo, critérios de aceite e testes.

---

## Tabela de US

| ID | Título | Depende de | Status |
|----|--------|-----------|--------|
| [US-001](./US-001-repository-crud.md) | Registro e Gerenciamento de Repositórios | — | Pendente |
| [US-002](./US-002-git-context.md) | Contexto Git e Structs Puras | — | Pendente |
| [US-003](./US-003-commits-api.md) | API de Commits | US-001, US-002 | Pendente |
| [US-004](./US-004-branches-api.md) | API de Branches | US-001, US-002 | Pendente |
| [US-005](./US-005-remotes-api.md) | API de Remotes (fetch/pull/push) | US-001, US-002 | Pendente |
| [US-006](./US-006-stash-api.md) | API de Stash | US-001, US-002 | Pendente |
| [US-007](./US-007-tags-api.md) | API de Tags | US-001, US-002 | Pendente |
| [US-008](./US-008-search-glob-api.md) | API de Busca por Glob | US-001, US-002 | Pendente |

---

## Ordem de Implementação Sugerida

```
US-001 (Repositories CRUD)
  └── US-002 (Git Context + Structs)
        ├── US-003 (Commits)
        ├── US-004 (Branches)
        ├── US-005 (Remotes)
        ├── US-006 (Stash)
        ├── US-007 (Tags)
        └── US-008 (Search)
```

US-001 e US-002 podem ser implementadas em paralelo pois não dependem uma da outra. As US-003 a US-008 dependem de ambas e podem ser paralelizadas entre si.

---

## Convenções de Código

### Estrutura de pastas dos controllers

```
lib/omnigist_web/controllers/api/
  <resource>_controller.ex    ← lógica HTTP
  <resource>_json.ex          ← serialização JSON
```

### Módulo dos controllers

```elixir
defmodule OmnigistWeb.API.<Resource>Controller do
  use OmnigistWeb, :controller
  alias Omnigist.{Repositories, Git}
  action_fallback OmnigistWeb.FallbackController
  # ...
end
```

### Padrão de retorno do Git context

```elixir
# Sempre {:ok, result} | {:error, reason_string}
with {:ok, data} <- Git.alguma_operacao(repo.path, opts) do
  render(conn, :index, data: data)
end
# O FallbackController trata {:error, reason} → 422 + %{error: reason}
```

### FallbackController (compartilhado)

```
lib/omnigist_web/controllers/fallback_controller.ex
```

Trata: `{:error, string}` → 422, `{:error, :not_found}` → 404, `{:error, %Ecto.Changeset{}}` → 422.

### Fixtures de teste

Repositórios git temporários são criados no `setup` de cada test case:

```elixir
setup do
  tmp_dir = Path.join(System.tmp_dir!(), "test_repo_#{System.unique_integer([:positive])}")
  File.mkdir_p!(tmp_dir)
  System.cmd("git", ["init"], cd: tmp_dir)
  System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)
  System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
  File.write!(Path.join(tmp_dir, "README.md"), "hello")
  System.cmd("git", ["add", "."], cd: tmp_dir)
  System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)
  {:ok, repo: repository_fixture(%{path: tmp_dir}), tmp_dir: tmp_dir}
end
```
