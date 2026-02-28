# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Initial setup (install deps, create/migrate DB, build assets)
mix setup

# Start server
mix phx.server
iex -S mix phx.server

# Run all tests
mix test

# Run a single test file
mix test test/omnigist/repositories_test.exs

# Run a single test by line number
mix test test/omnigist/repositories_test.exs:42

# Database operations
mix ecto.migrate
mix ecto.reset        # drop + recreate + seed

# Build assets (CSS/JS)
mix assets.build
```

## Purpose

Omnigist is a **Git API backend** consumed by a desktop client. It accelerates the daily developer experience with git — commits, branches, merge, stash, tags, remotes, push/pull/fetch, and smart glob searches. No authentication for now. Repositories are registered in the database (SQLite) and referenced by UUID in API calls.

Built with Phoenix 1.7 (JSON API only, no LiveView for new features), using SQLite as the database (`ecto_sqlite3`). All primary keys use `binary_id` (UUID).

---

## Architecture

### Domain model

- **Repository** — registered git repo on the filesystem (stores name, path, description). No user association.
- **User**, **Gist**, **SavedGist**, **Comment** — legacy domain, kept but not the focus.

### Context layer (`lib/omnigist/`)

| Context | Schema(s) / Role |
|---|---|
| `Omnigist.Repositories` | `Repository` — CRUD of registered repos |
| `Omnigist.Git` | No DB — all git operations via `System.cmd` |
| `Omnigist.Accounts` | `User`, `UserToken` (legacy) |
| `Omnigist.Gists` | `Gist`, `SavedGist` (legacy) |
| `Omnigist.Comments` | `Comment` (legacy) |

### `Omnigist.Repositories`

Standard Ecto context following the same pattern as `Omnigist.Gists`:

```
list_repositories/0
get_repository!/1
create_repository/1
update_repository/2
delete_repository/1
change_repository/2
```

Schema fields: `id` (binary_id), `name`, `path` (unique — absolute filesystem path), `description`, timestamps.

### `Omnigist.Git`

All functions receive `repo_path` (string) as first argument and run `System.cmd("git", [...], cd: repo_path)`.

Return format: `{:ok, result}` | `{:error, reason}`.

**Commits:** `list_commits/2`, `get_commit/2`, `list_authors/1`
**Branches:** `list_branches/1`, `create_branch/2`, `delete_branch/3`, `checkout_branch/2`, `merge_branch/2`
**Remotes:** `list_remotes/1`, `fetch/2`, `pull/2`, `push/2`
**Stash:** `list_stashes/1`, `stash_push/2`, `stash_pop/2`, `stash_drop/2`
**Tags:** `list_tags/1`, `create_tag/3`, `delete_tag/2`
**Search:** `search_glob/2` — runs `git ls-files <pattern>`

Commit parsing uses `--format="%H|%h|%s|%b|%an|%ae|%aI"` split by `|`.

### Pure structs (`lib/omnigist/git/`)

No Ecto, only `defstruct`:

| Module | Fields |
|---|---|
| `Git.Commit` | hash, short_hash, message, body, author_name, author_email, date |
| `Git.Branch` | name, is_current, is_remote, upstream, ahead, behind |
| `Git.Remote` | name, fetch_url, push_url |
| `Git.Tag` | name, hash, message, date, type (`:lightweight` \| `:annotated`) |
| `Git.StashEntry` | index, message, hash |

---

## Web layer (`lib/omnigist_web/`)

### API Routes — `/api/v1/`

All controllers live under `lib/omnigist_web/controllers/api/` and use the alias `OmnigistWeb.API`.

```
resources "/repositories", RepositoryController, except: [:new, :edit]

  GET    /repositories/:id/commits           CommitController :index   # ?limit=&author=&search=
  GET    /repositories/:id/commits/authors   CommitController :authors
  GET    /repositories/:id/commits/:hash     CommitController :show

  GET    /repositories/:id/branches                    BranchController :index
  POST   /repositories/:id/branches                    BranchController :create
  DELETE /repositories/:id/branches/:name              BranchController :delete
  POST   /repositories/:id/branches/:name/checkout     BranchController :checkout
  POST   /repositories/:id/branches/:name/merge        BranchController :merge

  GET    /repositories/:id/remotes           RemoteController :index
  POST   /repositories/:id/remotes/fetch     RemoteController :fetch
  POST   /repositories/:id/remotes/pull      RemoteController :pull
  POST   /repositories/:id/remotes/push      RemoteController :push

  GET    /repositories/:id/stashes           StashController :index
  POST   /repositories/:id/stashes           StashController :create
  POST   /repositories/:id/stashes/:index/pop StashController :pop
  DELETE /repositories/:id/stashes/:index    StashController :drop

  GET    /repositories/:id/tags              TagController :index
  POST   /repositories/:id/tags              TagController :create
  DELETE /repositories/:id/tags/:name        TagController :delete

  GET    /repositories/:id/search            SearchController :index  # ?pattern=src/**/*.ex
```

Git errors return `{"error": "message"}` with status 422.

### Controller pattern

```elixir
defmodule OmnigistWeb.API.CommitController do
  use OmnigistWeb, :controller
  alias Omnigist.{Repositories, Git}

  def index(conn, %{"repository_id" => repo_id} = params) do
    repo = Repositories.get_repository!(repo_id)
    opts = [limit: params["limit"], author: params["author"], grep: params["search"]]
    with {:ok, commits} <- Git.list_commits(repo.path, opts) do
      render(conn, :index, commits: commits)
    end
  end
end
```

### Test support

- `test/support/data_case.ex` — for context/schema tests (wraps each test in a DB transaction)
- `test/support/conn_case.ex` — for controller tests
- `test/support/fixtures/` — factory helpers (`repositories_fixtures.ex` for the new domain)
