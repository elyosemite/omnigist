# US-002 — Contexto Git e Structs Puras

## Descrição

**Como** desenvolvedor backend,
**Quero** um contexto `Omnigist.Git` centralizado com structs tipadas para cada entidade git,
**Para que** todos os controllers de git tenham uma interface uniforme e tipada para executar operações git via `System.cmd`.

---

## Contexto Técnico

Não há banco de dados envolvido nesta US. O contexto `Omnigist.Git` é uma camada de abstração sobre o CLI do git. Toda operação recebe `repo_path` como primeiro argumento e delega para `System.cmd("git", args, cd: repo_path)`. As structs puras (`defstruct`) representam as entidades git sem Ecto.

---

## Estrutura de Arquivos

```
lib/omnigist/
  git/
    commit.ex         ← defstruct pura
    branch.ex         ← defstruct pura
    remote.ex         ← defstruct pura
    tag.ex            ← defstruct pura
    stash_entry.ex    ← defstruct pura
  git.ex              ← Context principal
```

---

## Implementação Esperada

### 1. Structs Puras

```elixir
# lib/omnigist/git/commit.ex
defmodule Omnigist.Git.Commit do
  @enforce_keys [:hash, :short_hash, :message, :author_name, :author_email, :date]
  defstruct [:hash, :short_hash, :message, :body, :author_name, :author_email, :date]
end
```

```elixir
# lib/omnigist/git/branch.ex
defmodule Omnigist.Git.Branch do
  @enforce_keys [:name]
  defstruct [:name, is_current: false, is_remote: false, upstream: nil, ahead: 0, behind: 0]
end
```

```elixir
# lib/omnigist/git/remote.ex
defmodule Omnigist.Git.Remote do
  @enforce_keys [:name]
  defstruct [:name, :fetch_url, :push_url]
end
```

```elixir
# lib/omnigist/git/tag.ex
defmodule Omnigist.Git.Tag do
  @enforce_keys [:name]
  defstruct [:name, :hash, :message, :date, type: :lightweight]
end
```

```elixir
# lib/omnigist/git/stash_entry.ex
defmodule Omnigist.Git.StashEntry do
  @enforce_keys [:index, :message, :hash]
  defstruct [:index, :message, :hash]
end
```

### 2. Context Git — esqueleto e helpers internos

```elixir
# lib/omnigist/git.ex
defmodule Omnigist.Git do
  @moduledoc """
  Contexto para operações git via System.cmd.
  Todas as funções recebem `repo_path` como primeiro argumento.
  Retornam {:ok, resultado} | {:error, motivo}.
  """

  alias Omnigist.Git.{Commit, Branch, Remote, Tag, StashEntry}

  # Formato de log que permite parsing determinístico por campo
  @log_format "%H|%h|%s|%b|%an|%ae|%aI"
  # Separador de commits para não conflitar com newlines no body
  @commit_separator "---COMMIT---"

  # ---------------------------------------------------------------------------
  # Commits
  # ---------------------------------------------------------------------------

  def list_commits(repo_path, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    author = Keyword.get(opts, :author)
    grep = Keyword.get(opts, :grep)

    args =
      ["log", "--format=#{@commit_separator}#{@log_format}"]
      |> maybe_add_limit(limit)
      |> maybe_add_author(author)
      |> maybe_add_grep(grep)

    case run_git(repo_path, args) do
      {:ok, output} -> {:ok, parse_commits(output)}
      error -> error
    end
  end

  def get_commit(repo_path, hash) do
    args = ["show", "--format=#{@log_format}", "--no-patch", hash]

    case run_git(repo_path, args) do
      {:ok, output} ->
        case parse_commit_line(output) do
          {:ok, commit} -> {:ok, commit}
          :error -> {:error, "commit not found: #{hash}"}
        end
      error -> error
    end
  end

  def list_authors(repo_path) do
    case run_git(repo_path, ["log", "--format=%an|%ae", "--no-merges"]) do
      {:ok, output} ->
        authors =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            [name, email] = String.split(line, "|", parts: 2)
            %{name: name, email: email}
          end)
          |> Enum.uniq_by(& &1.email)

        {:ok, authors}

      error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Branches
  # ---------------------------------------------------------------------------

  def list_branches(repo_path) do
    case run_git(repo_path, ["branch", "--all", "--format=%(refname:short)|%(HEAD)|%(upstream:short)|%(upstream:track,nobracket)"]) do
      {:ok, output} ->
        branches =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_branch_line/1)

        {:ok, branches}

      error -> error
    end
  end

  def create_branch(repo_path, name) do
    case run_git(repo_path, ["branch", name]) do
      {:ok, _} -> {:ok, %Branch{name: name}}
      error -> error
    end
  end

  def delete_branch(repo_path, name, opts \\ []) do
    flag = if Keyword.get(opts, :force, false), do: "-D", else: "-d"

    case run_git(repo_path, ["branch", flag, name]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def checkout_branch(repo_path, name) do
    case run_git(repo_path, ["checkout", name]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def merge_branch(repo_path, name) do
    case run_git(repo_path, ["merge", name]) do
      {:ok, output} -> {:ok, output}
      error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Remotes
  # ---------------------------------------------------------------------------

  def list_remotes(repo_path) do
    case run_git(repo_path, ["remote", "-v"]) do
      {:ok, output} -> {:ok, parse_remotes(output)}
      error -> error
    end
  end

  def fetch(repo_path, opts \\ []) do
    remote = Keyword.get(opts, :remote, "--all")
    args = if remote == "--all", do: ["fetch", "--all"], else: ["fetch", remote]

    case run_git(repo_path, args) do
      {:ok, output} -> {:ok, output}
      error -> error
    end
  end

  def pull(repo_path, opts \\ []) do
    remote = Keyword.get(opts, :remote, "origin")
    branch = Keyword.get(opts, :branch)
    args = if branch, do: ["pull", remote, branch], else: ["pull", remote]

    case run_git(repo_path, args) do
      {:ok, output} -> {:ok, output}
      error -> error
    end
  end

  def push(repo_path, opts \\ []) do
    remote = Keyword.get(opts, :remote, "origin")
    branch = Keyword.get(opts, :branch)
    args = if branch, do: ["push", remote, branch], else: ["push", remote]

    case run_git(repo_path, args) do
      {:ok, output} -> {:ok, output}
      error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Stash
  # ---------------------------------------------------------------------------

  def list_stashes(repo_path) do
    case run_git(repo_path, ["stash", "list", "--format=%gd|%gs|%H"]) do
      {:ok, output} ->
        stashes =
          output
          |> String.split("\n", trim: true)
          |> Enum.with_index()
          |> Enum.map(fn {line, idx} ->
            [_ref, message, hash] = String.split(line, "|", parts: 3)
            %StashEntry{index: idx, message: message, hash: hash}
          end)

        {:ok, stashes}

      error -> error
    end
  end

  def stash_push(repo_path, opts \\ []) do
    message = Keyword.get(opts, :message)
    args = if message, do: ["stash", "push", "-m", message], else: ["stash", "push"]

    case run_git(repo_path, args) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def stash_pop(repo_path, index) do
    case run_git(repo_path, ["stash", "pop", "stash@{#{index}}"]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def stash_drop(repo_path, index) do
    case run_git(repo_path, ["stash", "drop", "stash@{#{index}}"]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Tags
  # ---------------------------------------------------------------------------

  def list_tags(repo_path) do
    case run_git(repo_path, ["tag", "--list", "--format=%(refname:short)|%(objecttype)|%(*objectname)|%(subject)|%(creatordate:iso-strict)"]) do
      {:ok, output} ->
        tags =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_tag_line/1)

        {:ok, tags}

      error -> error
    end
  end

  def create_tag(repo_path, name, opts \\ []) do
    message = Keyword.get(opts, :message)
    hash = Keyword.get(opts, :hash)

    args =
      cond do
        message -> ["tag", "-a", name, "-m", message] ++ List.wrap(hash)
        hash    -> ["tag", name, hash]
        true    -> ["tag", name]
      end

    case run_git(repo_path, args) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def delete_tag(repo_path, name) do
    case run_git(repo_path, ["tag", "-d", name]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Glob Search
  # ---------------------------------------------------------------------------

  def search_glob(repo_path, pattern) do
    case run_git(repo_path, ["ls-files", pattern]) do
      {:ok, output} ->
        files = String.split(output, "\n", trim: true)
        {:ok, files}

      error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers privados
  # ---------------------------------------------------------------------------

  defp run_git(repo_path, args) do
    case System.cmd("git", args, cd: repo_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp maybe_add_limit(args, nil), do: args
  defp maybe_add_limit(args, limit), do: args ++ ["-n", to_string(limit)]

  defp maybe_add_author(args, nil), do: args
  defp maybe_add_author(args, author), do: args ++ ["--author", author]

  defp maybe_add_grep(args, nil), do: args
  defp maybe_add_grep(args, grep), do: args ++ ["--grep", grep]

  defp parse_commits(output) do
    output
    |> String.split(@commit_separator, trim: true)
    |> Enum.map(&parse_commit_line/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, commit} -> commit end)
  end

  defp parse_commit_line(line) do
    case String.split(String.trim(line), "|", parts: 7) do
      [hash, short_hash, message, body, author_name, author_email, date] ->
        {:ok,
         %Commit{
           hash: hash,
           short_hash: short_hash,
           message: message,
           body: body,
           author_name: author_name,
           author_email: author_email,
           date: date
         }}

      _ -> :error
    end
  end

  defp parse_branch_line(line) do
    case String.split(line, "|", parts: 4) do
      [name, head, upstream, track] ->
        {ahead, behind} = parse_track(track)

        %Branch{
          name: name,
          is_current: head == "*",
          is_remote: String.starts_with?(name, "remotes/"),
          upstream: if(upstream == "", do: nil, else: upstream),
          ahead: ahead,
          behind: behind
        }

      _ ->
        %Branch{name: line}
    end
  end

  defp parse_track(track) do
    ahead = Regex.run(~r/ahead (\d+)/, track) |> extract_int()
    behind = Regex.run(~r/behind (\d+)/, track) |> extract_int()
    {ahead, behind}
  end

  defp extract_int(nil), do: 0
  defp extract_int([_, n]), do: String.to_integer(n)

  defp parse_remotes(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^(\S+)\s+(\S+)\s+\((fetch|push)\)$/, line) do
        [_, name, url, type] ->
          remote = Map.get(acc, name, %Remote{name: name})

          remote =
            case type do
              "fetch" -> %{remote | fetch_url: url}
              "push"  -> %{remote | push_url: url}
            end

          Map.put(acc, name, remote)

        _ -> acc
      end
    end)
    |> Map.values()
  end

  defp parse_tag_line(line) do
    case String.split(line, "|", parts: 5) do
      [name, "tag", _hash, message, date] ->
        %Tag{name: name, message: message, date: date, type: :annotated}

      [name, _, hash, _, date] ->
        %Tag{name: name, hash: hash, date: date, type: :lightweight}

      _ ->
        %Tag{name: line}
    end
  end
end
```

---

## Critérios de Aceite

- [ ] Todos os módulos de struct compilam sem erros
- [ ] `Omnigist.Git.list_commits/2` retorna `{:ok, [%Commit{}, ...]}` para um repo válido
- [ ] `Omnigist.Git.list_commits/2` retorna `{:error, mensagem}` para um path inválido
- [ ] `opts` de `list_commits` — `limit`, `author`, `grep` — filtram corretamente via flags do git
- [ ] `Omnigist.Git.list_branches/1` distingue branches locais de remotas via `is_remote`
- [ ] `Omnigist.Git.list_remotes/1` agrupa fetch_url e push_url pelo mesmo nome de remote
- [ ] `Omnigist.Git.search_glob/2` retorna lista de paths relativos ao repo
- [ ] Qualquer operação git com exit code != 0 retorna `{:error, stderr_output}`
- [ ] Nenhuma função neste módulo acessa o banco de dados

---

## Testes

### Arquivo: `test/omnigist/git_test.exs`

```elixir
defmodule Omnigist.GitTest do
  use ExUnit.Case, async: true

  alias Omnigist.Git
  alias Omnigist.Git.{Commit, Branch, Tag, StashEntry, Remote}

  # Usa o próprio repositório do projeto como fixture de teste
  @repo_path File.cwd!()

  describe "list_commits/2" do
    test "returns a list of commits" do
      assert {:ok, commits} = Git.list_commits(@repo_path)
      assert is_list(commits)
      assert length(commits) > 0
      assert %Commit{} = hd(commits)
    end

    test "respects limit option" do
      assert {:ok, commits} = Git.list_commits(@repo_path, limit: 3)
      assert length(commits) <= 3
    end

    test "returns error for invalid path" do
      assert {:error, _reason} = Git.list_commits("/tmp/definitely_not_a_git_repo_xyz")
    end
  end

  describe "get_commit/2" do
    test "returns a commit by hash" do
      {:ok, [first | _]} = Git.list_commits(@repo_path, limit: 1)
      assert {:ok, %Commit{hash: hash}} = Git.get_commit(@repo_path, first.hash)
      assert hash == first.hash
    end

    test "returns error for unknown hash" do
      assert {:error, _} = Git.get_commit(@repo_path, "deadbeefdeadbeef")
    end
  end

  describe "list_branches/1" do
    test "returns branches with correct struct fields" do
      assert {:ok, branches} = Git.list_branches(@repo_path)
      assert is_list(branches)
      assert Enum.any?(branches, & &1.is_current)
    end
  end

  describe "list_authors/1" do
    test "returns unique authors" do
      assert {:ok, authors} = Git.list_authors(@repo_path)
      assert is_list(authors)
      assert Enum.all?(authors, &(Map.has_key?(&1, :name) and Map.has_key?(&1, :email)))
      emails = Enum.map(authors, & &1.email)
      assert emails == Enum.uniq(emails)
    end
  end

  describe "search_glob/2" do
    test "returns matching files" do
      assert {:ok, files} = Git.search_glob(@repo_path, "lib/**/*.ex")
      assert is_list(files)
      assert Enum.all?(files, &String.ends_with?(&1, ".ex"))
    end

    test "returns empty list for pattern with no matches" do
      assert {:ok, []} = Git.search_glob(@repo_path, "*.xyz_no_match")
    end
  end
end
```

> **Nota:** Os testes de operações com side effects (create_branch, push, pull, stash) devem ser feitos com um repositório git temporário criado no setup do teste, usando `System.cmd("git", ["init", tmp_dir])`.
