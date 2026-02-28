# Dependências do Omnigist — Guia Detalhado

Este documento explica cada dependência declarada no `mix.exs`, para que serve,
quais são suas principais funções e como elas se usam na prática com exemplos de código.

---

## Sumário

1. [pbkdf2_elixir](#1-pbkdf2_elixir)
2. [phoenix](#2-phoenix)
3. [phoenix_ecto](#3-phoenix_ecto)
4. [ecto_sql](#4-ecto_sql)
5. [ecto_sqlite3](#5-ecto_sqlite3)
6. [phoenix_html](#6-phoenix_html)
7. [phoenix_live_reload](#7-phoenix_live_reload)
8. [phoenix_live_view](#8-phoenix_live_view)
9. [floki](#9-floki)
10. [phoenix_live_dashboard](#10-phoenix_live_dashboard)
11. [esbuild](#11-esbuild)
12. [tailwind](#12-tailwind)
13. [heroicons](#13-heroicons)
14. [swoosh](#14-swoosh)
15. [finch](#15-finch)
16. [telemetry_metrics](#16-telemetry_metrics)
17. [telemetry_poller](#17-telemetry_poller)
18. [gettext](#18-gettext)
19. [jason](#19-jason)
20. [dns_cluster](#20-dns_cluster)
21. [bandit](#21-bandit)

---

## 1. `pbkdf2_elixir`

**O que é:** Implementação do algoritmo PBKDF2 para hashing de senhas.

**Por que existe:** Senhas nunca devem ser salvas em texto puro no banco de dados.
Se o banco vazar, o atacante não consegue descobrir as senhas originais — ele só
vê hashes. PBKDF2 é deliberadamente lento para dificultar ataques de força bruta.

**Onde é usado no Omnigist:** Pelo sistema gerado pelo `phx.gen.auth` para
registrar e autenticar usuários.

```elixir
# Gera um hash seguro da senha
hash = Pbkdf2.hash_pwd_salt("minha_senha_123")
#=> "$pbkdf2-sha512$160000$randomsalt$longhashstring..."

# Verifica se uma senha bate com o hash salvo no banco
Pbkdf2.verify_pass("minha_senha_123", hash)
#=> true

Pbkdf2.verify_pass("senha_errada", hash)
#=> false

# Importante: mesmo chamando hash_pwd_salt com a mesma senha,
# o resultado é sempre diferente por causa do salt aleatório
Pbkdf2.hash_pwd_salt("mesma_senha") == Pbkdf2.hash_pwd_salt("mesma_senha")
#=> false — sempre gera um hash diferente
```

**Conceito importante — o que é "salt":**
Salt é um valor aleatório concatenado à senha antes de fazer o hash.
Ele garante que dois usuários com a mesma senha tenham hashes diferentes no banco,
e que ataques de rainbow table (tabelas pré-computadas de hashes) não funcionem.

---

## 2. `phoenix`

**O que é:** O framework web principal. É o esqueleto de toda a aplicação.

**Por que existe:** Fornece toda a infraestrutura para receber requisições HTTP,
roteá-las para o controller correto, processar e devolver uma resposta.

**Principais componentes:**

### Router — define as rotas da aplicação

```elixir
# lib/omnigist_web/router.ex
defmodule OmnigistWeb.Router do
  use OmnigistWeb, :router

  # Pipeline define plugs aplicados em sequência às requisições
  pipeline :api do
    plug :accepts, ["json"]
  end

  # Scope agrupa rotas sob um prefixo de URL e um módulo
  scope "/api/v1", OmnigistWeb.API, as: :api do
    pipe_through :api

    get "/github/repos/:owner/:repo", GitHubController, :show
    # GET /api/v1/github/repos/elixir-lang/elixir
    # → chama GitHubController.show(conn, %{"owner" => "elixir-lang", "repo" => "elixir"})
  end
end
```

### Plug — middleware que transforma a conexão

```elixir
# Um plug é qualquer módulo ou função que recebe conn e retorna conn
# Exemplo de plug de autenticação simples
defmodule MinhaApp.RequireAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> _token] -> conn          # deixa passar
      _ ->
        conn
        |> send_resp(401, "unauthorized")
        |> halt()                             # interrompe a pipeline
    end
  end
end
```

### Controller — recebe a requisição e monta a resposta

```elixir
defmodule OmnigistWeb.API.ExemploController do
  use OmnigistWeb, :controller

  # conn = estrutura que representa a requisição+resposta HTTP
  # params = parâmetros da URL e do body já decodificados
  def show(conn, %{"id" => id}) do
    # render/3 — delega a formatação para o JSON view
    render(conn, :show, item: %{id: id, nome: "Exemplo"})

    # json/2 — retorna JSON diretamente sem view
    # json(conn, %{id: id})

    # send_resp/3 — resposta manual com status e body
    # send_resp(conn, 200, "ok")

    # put_status/2 — define o status HTTP
    # conn |> put_status(201) |> json(%{created: true})
  end
end
```

---

## 3. `phoenix_ecto`

**O que é:** Camada de integração entre Phoenix e Ecto.

**Por que existe:** Sem ele, os changesets do Ecto não se conversam com os
formulários e controllers do Phoenix. Ele também adiciona o
`Ecto.DevLogger` que imprime as queries SQL no console em desenvolvimento.

**Principal uso — traduzir erros de changeset para o controller:**

```elixir
# O FallbackController usa phoenix_ecto para extrair mensagens de erro
defmodule OmnigistWeb.FallbackController do
  use OmnigistWeb, :controller

  # Quando um changeset inválido chega como erro:
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    # traverse_errors/2 vem do phoenix_ecto — formata os erros
    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
    # resposta: {"errors": {"name": ["can't be blank"]}}
  end
end
```

---

## 4. `ecto_sql`

**O que é:** O ORM (Object-Relational Mapper) do Elixir. Gerencia toda
a interação com bancos de dados relacionais.

**Por que existe:** Sem ele, você teria que escrever SQL puro e mapear
os resultados manualmente. O Ecto fornece schemas, changesets, queries
composáveis e migrations.

**Principais funções:**

### Schema — mapeia uma tabela para um módulo Elixir

```elixir
defmodule Omnigist.Repositories.Repository do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "repositories" do
    field :name, :string      # coluna name VARCHAR no banco
    field :path, :string      # coluna path VARCHAR no banco
    field :description, :string
    timestamps(type: :utc_datetime)  # inserted_at e updated_at automáticos
  end

  # Changeset — valida e filtra os dados antes de ir pro banco
  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:name, :path, :description])
    # cast/3: aceita apenas os campos listados dos attrs recebidos
    |> validate_required([:name, :path])
    # validate_required/2: garante que name e path não são nulos/vazios
    |> unique_constraint(:path)
    # unique_constraint/2: valida unicidade (precisa de index no banco)
  end
end
```

### Repo — executa operações no banco

```elixir
alias Omnigist.Repo
alias Omnigist.Repositories.Repository

# INSERT
{:ok, repo} = Repo.insert(%Repository{name: "meu-repo", path: "/home/user/proj"})

# SELECT todos
repos = Repo.all(Repository)
#=> [%Repository{id: "uuid-1", name: "meu-repo", ...}]

# SELECT por id — levanta exceção se não encontrar
repo = Repo.get!(Repository, "uuid-1")

# SELECT por id — retorna nil se não encontrar
repo = Repo.get(Repository, "uuid-inexistente")
#=> nil

# UPDATE
{:ok, atualizado} = Repo.update(Repository.changeset(repo, %{description: "novo"}))

# DELETE
{:ok, _} = Repo.delete(repo)
```

### Query — consultas composáveis

```elixir
import Ecto.Query

# Busca repositories onde name contém "elixir"
query =
  from r in Repository,
    where: like(r.name, "%elixir%"),
    order_by: [desc: r.inserted_at],
    limit: 10,
    select: r

repos = Repo.all(query)

# Composição — adiciona condições gradualmente
base = from r in Repository, order_by: r.name

filtrada =
  if termo do
    from r in base, where: like(r.name, ^"%#{termo}%")
    # ^ (pin operator) — injeta valor Elixir na query de forma segura (evita SQL injection)
  else
    base
  end

Repo.all(filtrada)
```

### Migration — versionamento do esquema do banco

```elixir
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
    # Garante no banco que dois repos não podem ter o mesmo path
  end
end
```

```bash
mix ecto.migrate       # aplica migrations pendentes
mix ecto.rollback      # desfaz a última migration
mix ecto.reset         # apaga tudo e recria do zero
```

---

## 5. `ecto_sqlite3`

**O que é:** Driver que conecta o Ecto ao banco de dados SQLite.

**Por que existe:** O Ecto é agnóstico de banco — ele não sabe falar diretamente
com SQLite, PostgreSQL ou MySQL. Cada banco precisa de seu próprio adapter.
Este é o adapter para SQLite.

**Onde é configurado:**

```elixir
# config/dev.exs
config :omnigist, Omnigist.Repo,
  adapter: Ecto.Adapters.SQLite3,   # ← vem do ecto_sqlite3
  database: "omnigist_dev.db"       # arquivo no filesystem local
```

**Diferença prática do SQLite vs PostgreSQL:**
SQLite é um arquivo local — não precisa de servidor rodando. Ideal para
desenvolvimento e projetos menores. O `ecto_sqlite3` abstrai isso e
você usa o mesmo código Ecto independente do banco.

---

## 6. `phoenix_html`

**O que é:** Helpers para geração segura de HTML dentro do Phoenix.

**Por que existe:** Quando você coloca dados do usuário dentro de HTML,
existe risco de XSS (Cross-Site Scripting) — o usuário injeta JavaScript
malicioso que executa no browser de outras pessoas. O `phoenix_html`
escapa automaticamente qualquer valor interpolado nos templates.

```elixir
# Em um template HEEx (.html.heex):

# Seguro — escapa automaticamente < > " ' &
<p>{@nome_do_usuario}</p>
# Se nome = "<script>alert('xss')</script>"
# Renderiza: <p>&lt;script&gt;alert('xss')&lt;/script&gt;</p>
# O browser mostra texto, não executa o script

# raw/1 — quando você QUER renderizar HTML sem escape (use com cuidado)
# Só use se o conteúdo vier de fonte confiável (não do usuário)
{Phoenix.HTML.raw("<strong>negrito</strong>")}
```

---

## 7. `phoenix_live_reload`

**O que é:** Recarregamento automático do browser durante desenvolvimento.

**Por que existe:** Sem ele, você precisaria apertar F5 no browser a cada
mudança de código. Com ele, o browser detecta mudanças e recarrega
automaticamente — ou, no caso de CSS, injeta o novo estilo sem nem
recarregar a página.

**Importante:** Só ativo em ambiente de desenvolvimento (`only: :dev`).
Em produção não existe. Não há código seu que precise interagir com ele
diretamente — ele funciona sozinho.

```elixir
# mix.exs — note o "only: :dev"
{:phoenix_live_reload, "~> 1.2", only: :dev}

# config/dev.exs — o que ele observa
config :omnigist, OmnigistWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|gif|svg)$",
      ~r"lib/omnigist_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]
```

---

## 8. `phoenix_live_view`

**O que é:** Biblioteca para criar interfaces web reativas e interativas
usando apenas Elixir — sem escrever JavaScript.

**Por que existe:** Normalmente interfaces reativas (que atualizam sem
recarregar a página) precisam de um framework JavaScript como React ou Vue.
O LiveView usa WebSockets para manter uma conexão entre o browser e o servidor
— quando o estado muda no servidor, apenas o diff do HTML é enviado ao browser.

**Como funciona:**

```elixir
defmodule OmnigistWeb.ContadorLive do
  use OmnigistWeb, :live_view

  # mount/3 — executado quando o usuário acessa a página
  # inicializa o estado (socket.assigns)
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :contador, 0)}
    # assign/3 — armazena valor no estado do LiveView
    # disponível no template como @contador
  end

  # render/1 — define o HTML da página
  # re-executado automaticamente quando assigns mudam
  def render(assigns) do
    ~H"""
    <div>
      <p>Contador: {@contador}</p>
      <button phx-click="incrementar">+1</button>
      <button phx-click="decrementar">-1</button>
    </div>
    """
    # phx-click="incrementar" — quando clicado, envia evento
    # "incrementar" para o servidor via WebSocket
  end

  # handle_event/3 — trata eventos vindos do browser
  def handle_event("incrementar", _params, socket) do
    {:noreply, update(socket, :contador, &(&1 + 1))}
    # update/3 — atualiza um assign aplicando uma função
    # &(&1 + 1) = fn atual -> atual + 1 end
  end

  def handle_event("decrementar", _params, socket) do
    {:noreply, update(socket, :contador, &(&1 - 1))}
  end
end
```

**No Omnigist:** Todas as telas de autenticação (login, registro, reset de senha,
confirmação de e-mail, settings) são LiveViews.

---

## 9. `floki`

**O que é:** Parser e buscador de HTML — usado exclusivamente em testes.

**Por que existe:** Em testes de controller e LiveView, o Phoenix retorna
HTML como string. O Floki permite buscar elementos nesse HTML usando seletores
CSS, para verificar se o conteúdo esperado está presente.

```elixir
# Só disponível em: only: :test
html = """
<html>
  <body>
    <h1 class="titulo">Bem-vindo</h1>
    <ul>
      <li>Item 1</li>
      <li>Item 2</li>
    </ul>
  </body>
</html>
"""

# find/2 — busca elementos por seletor CSS
Floki.find(html, "h1")
#=> [{"h1", [{"class", "titulo"}], ["Bem-vindo"]}]

Floki.find(html, "li")
#=> [{"li", [], ["Item 1"]}, {"li", [], ["Item 2"]}]

# text/1 — extrai o texto dos elementos encontrados
html |> Floki.find("h1") |> Floki.text()
#=> "Bem-vindo"

# Uso típico em teste de controller:
test "mostra o título correto", %{conn: conn} do
  conn = get(conn, "/")
  assert html_response(conn, 200) =~ "Bem-vindo"
  # ou com floki para ser mais preciso:
  {:ok, doc} = Floki.parse_document(html_response(conn, 200))
  assert Floki.find(doc, "h1") |> Floki.text() == "Bem-vindo"
end
```

---

## 10. `phoenix_live_dashboard`

**O que é:** Painel de monitoramento em tempo real acessível em `/dev/dashboard`.

**Por que existe:** Permite inspecionar o que está acontecendo dentro da
aplicação Elixir sem ferramentas externas — processos, memória, queries,
WebSockets ativos, logs, etc.

**Disponível em:** `http://localhost:4000/dev/dashboard`

**O que você vê lá:**
- Processos Erlang ativos (cada requisição, cada LiveView é um processo)
- Uso de memória e CPU da VM Erlang
- Métricas de HTTP (tempo de resposta, status codes)
- Queries SQL executadas e quanto tempo levaram
- Conexões WebSocket ativas (LiveViews abertas)

Não precisa de nenhum código seu para funcionar — o router já configura:

```elixir
# lib/omnigist_web/router.ex
if Application.compile_env(:omnigist, :dev_routes) do
  import Phoenix.LiveDashboard.Router

  scope "/dev" do
    pipe_through :browser
    live_dashboard "/dashboard", metrics: OmnigistWeb.Telemetry
  end
end
```

---

## 11. `esbuild`

**O que é:** Bundler e minificador de JavaScript extremamente rápido.

**Por que existe:** Browsers não entendem módulos JavaScript do Node.js diretamente.
O esbuild pega todos os arquivos `.js` do projeto, resolve as dependências
(`import`/`require`) e gera um único arquivo otimizado para o browser.

```bash
# Compila os assets uma vez
mix assets.build

# Em desenvolvimento — recompila automaticamente quando arquivos mudam
mix phx.server   # já inclui o watcher do esbuild
```

```elixir
# config/config.exs — configuração do esbuild
config :esbuild,
  version: "0.17.11",
  omnigist: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets),
    # js/app.js   → ponto de entrada
    # --bundle    → junta tudo em um arquivo
    # --outdir    → onde salva o resultado
    cd: Path.expand("../assets", __DIR__)
  ]
```

---

## 12. `tailwind`

**O que é:** Compilador do framework CSS Tailwind.

**Por que existe:** O Tailwind escaneia seus templates e gera um arquivo CSS
contendo **apenas** as classes que você realmente usou. Sem isso, o CSS final
teria centenas de kilobytes de classes que nunca são usadas.

```bash
mix assets.build   # compila o CSS
```

**Como funciona na prática:**

```html
<!-- Você escreve no template: -->
<button class="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600">
  Clique aqui
</button>

<!-- O Tailwind detecta essas classes e gera somente elas no CSS final.
     Classes que você não usou (bg-red-500, text-xl, etc.) não aparecem. -->
```

---

## 13. `heroicons`

**O que é:** Biblioteca de ícones SVG criada pelo time do Tailwind CSS.

**Por que existe:** Fornece mais de 290 ícones prontos para uso nos templates.

**Diferença importante dos outros pacotes:**

```elixir
# mix.exs
{:heroicons,
  github: "tailwindlabs/heroicons",
  app: false,       # ← NÃO é um pacote Elixir compilado
  compile: false,   # ← NÃO gera módulo, NÃO tem funções
  depth: 1}
# São apenas arquivos SVG copiados para o projeto durante o build
```

**Como usar nos templates:**

```html
<!-- Phoenix gera componentes a partir dos SVGs -->
<.icon name="hero-home" />
<.icon name="hero-user-circle" class="w-6 h-6 text-gray-500" />
<.icon name="hero-magnifying-glass-solid" />
```

---

## 14. `swoosh`

**O que é:** Biblioteca para envio de e-mails.

**Por que existe:** O Omnigist precisa enviar e-mails transacionais:
confirmação de cadastro, reset de senha, confirmação de e-mail novo.

```elixir
# lib/omnigist/accounts/user_notifier.ex
defmodule Omnigist.Accounts.UserNotifier do
  import Swoosh.Email

  def deliver_confirmation_instructions(user, url) do
    email =
      new()
      |> to({user.email, user.email})
      |> from({"Omnigist", "noreply@omnigist.com"})
      |> subject("Confirme seu e-mail")
      |> text_body("""
      Olá #{user.email},

      Clique no link para confirmar sua conta:
      #{url}
      """)

    Omnigist.Mailer.deliver(email)
    # Em dev: não envia de verdade — aparece em localhost:4000/dev/mailbox
    # Em prod: usa o adapter configurado (SendGrid, Mailgun, SMTP, etc.)
  end
end
```

**Em desenvolvimento:** Os e-mails não são enviados de verdade.
Você os vê em `http://localhost:4000/dev/mailbox`.

---

## 15. `finch`

**O que é:** Cliente HTTP de alta performance com connection pooling.

**Por que existe:** O Swoosh precisa de um cliente HTTP para enviar e-mails
via APIs externas (SendGrid, Mailgun, etc.). O Finch gerencia um pool de
conexões HTTP reutilizáveis — em vez de abrir uma conexão nova a cada
requisição, reutiliza conexões já estabelecidas.

```elixir
# lib/omnigist/application.ex — Finch é iniciado como processo supervisor
children = [
  {Finch, name: Omnigist.Finch}
  # nome registrado para ser referenciado pelo Swoosh
]

# Uso direto (além do Swoosh, você pode usar para qualquer HTTP):
request = Finch.build(:get, "https://api.github.com/users/elixir-lang")
{:ok, response} = Finch.request(request, Omnigist.Finch)
response.status   #=> 200
response.body     #=> "{\"login\":\"elixir-lang\",...}"
```

**Diferença do `:httpc` do Erlang:**
`:httpc` é mais simples mas não tem connection pooling.
`Finch` é recomendado para produção por ser mais eficiente com múltiplas
requisições concorrentes.

---

## 16. `telemetry_metrics`

**O que é:** Sistema de definição e agregação de métricas da aplicação.

**Por que existe:** Permite medir o que está acontecendo: quantas requisições
por segundo, tempo médio de resposta, quantas queries lentas, etc.

```elixir
# lib/omnigist_web/telemetry.ex
defmodule OmnigistWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def metrics do
    [
      # Tempo de cada requisição HTTP
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),

      # Tempo de cada query no banco
      summary("omnigist.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Tempo total das queries Ecto"
      ),

      # Contagem de requisições por rota
      counter("phoenix.router_dispatch.stop.duration",
        tags: [:route]
      )
    ]
  end
end
```

---

## 17. `telemetry_poller`

**O que é:** Complemento do `telemetry_metrics` — coleta métricas da VM
Erlang periodicamente (não por evento, mas por tempo).

**Por que existe:** Algumas métricas não são baseadas em eventos (uma
requisição aconteceu), mas em estado contínuo (quanta memória está sendo
usada agora?). O `telemetry_poller` dispara medições em intervalos regulares.

```elixir
# lib/omnigist_web/telemetry.ex
def init(_arg) do
  children = [
    {:telemetry_poller,
     measurements: [
       # A cada 10 segundos, mede memória e processos da VM Erlang
       {Telemetry.Metrics.BEAM, :dispatch_stats, []}
     ],
     period: :timer.seconds(10)}
  ]

  Supervisor.init(children, strategy: :one_for_one)
end
```

---

## 18. `gettext`

**O que é:** Sistema de internacionalização (i18n) — permite traduzir
a aplicação para múltiplos idiomas.

**Por que existe:** Centraliza todos os textos da interface em arquivos
de tradução. Para adicionar suporte a um novo idioma, basta criar um
arquivo de tradução — sem mudar código.

```elixir
# Em qualquer módulo que tenha "use Gettext, backend: OmnigistWeb.Gettext":

# Tradução simples
gettext("Welcome")
#=> "Bem-vindo" (se locale pt_BR) ou "Welcome" (fallback en)

# Tradução com variável interpolada
gettext("Hello, %{name}!", name: "Alice")
#=> "Olá, Alice!"

# Plural — singular vs plural
ngettext("1 repository found", "%{count} repositories found", count)
#=> "1 repositório encontrado" ou "5 repositórios encontrados"
```

**Arquivo de tradução** (`priv/gettext/pt_BR/LC_MESSAGES/default.po`):
```
msgid "Welcome"
msgstr "Bem-vindo"

msgid "Hello, %{name}!"
msgstr "Olá, %{name}!"
```

---

## 19. `jason`

**O que é:** Biblioteca para serializar (Elixir → JSON) e desserializar
(JSON → Elixir) dados no formato JSON.

**Por que existe:** É o padrão de comunicação da API do Omnigist.
Todo response dos controllers JSON passa pelo Jason.

```elixir
# Encode — Elixir para JSON
Jason.encode!(%{name: "Alice", age: 30})
#=> "{\"name\":\"Alice\",\"age\":30}"

Jason.encode!([1, 2, 3])
#=> "[1,2,3]"

# Decode — JSON para Elixir
Jason.decode!("{\"name\":\"Alice\",\"age\":30}")
#=> %{"name" => "Alice", "age" => 30}
# Note: chaves viram strings, não átomos

# Versões com ! levantam exceção em erro
# Versões sem ! retornam {:ok, result} | {:error, reason}
Jason.encode(%{ok: true})   #=> {:ok, "{\"ok\":true}"}
Jason.decode("json inválido") #=> {:error, %Jason.DecodeError{}}

# Tornar uma struct serializável pelo Jason:
defmodule MeuStruct do
  @derive Jason.Encoder   # ← instrui o Jason a saber serializar esta struct
  defstruct [:id, :nome]
end

Jason.encode!(%MeuStruct{id: 1, nome: "teste"})
#=> "{\"id\":1,\"nome\":\"teste\"}"
```

---

## 20. `dns_cluster`

**O que é:** Permite que múltiplas instâncias da aplicação se descubram
e formem um cluster Erlang usando DNS.

**Por que existe:** Elixir/Erlang suportam sistemas distribuídos nativamente —
múltiplos servidores podem rodar a mesma aplicação e se comunicar diretamente.
O `dns_cluster` automatiza a descoberta dos nós via registros DNS.

**Em desenvolvimento:** Não tem efeito prático — você tem um único servidor.

```elixir
# lib/omnigist/application.ex
children = [
  {DNSCluster, query: Application.get_env(:omnigist, :dns_cluster_query) || :ignore}
  # :ignore = desativado (padrão em dev)
  # "omnigist.internal" = busca nós via DNS em produção
]
```

**Quando importa:** Em produção com múltiplas instâncias (ex: 3 servidores
no Fly.io). Os nós se encontram e podem compartilhar estado do LiveView,
filas de trabalho, etc.

---

## 21. `bandit`

**O que é:** Servidor web HTTP/1.1 e HTTP/2 puro Elixir.

**Por que existe:** É o processo que fica escutando na porta 4000 e
recebe as conexões TCP dos browsers e clientes HTTP. Sem ele, a aplicação
Phoenix não seria acessível via rede.

**Alternativa ao Cowboy:** O Phoenix historicamente usava o Cowboy (servidor
escrito em Erlang). O Bandit é a alternativa moderna escrita em Elixir puro,
com melhor suporte a HTTP/2 e WebSockets.

```elixir
# config/config.exs — Phoenix usa o Bandit automaticamente
config :omnigist, OmnigistWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter   # ← define o Bandit como servidor

# lib/omnigist_web/endpoint.ex — o Endpoint conecta tudo
defmodule OmnigistWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :omnigist
  # O Bandit escuta a porta configurada e passa as requisições
  # para o Endpoint, que passa para o Router, que passa para o Controller
end
```

**Fluxo completo de uma requisição:**

```
Browser
  └─► Bandit (porta 4000) — aceita conexão TCP
        └─► OmnigistWeb.Endpoint — aplica plugs globais (sessão, etc.)
              └─► OmnigistWeb.Router — encontra a rota
                    └─► Pipeline (:api) — aplica plugs da pipeline
                          └─► GitHubController.show/2 — executa a lógica
                                └─► GitHubJSON.show/1 — serializa resposta
                                      └─► Jason.encode! — gera JSON
                                            └─► Bandit — envia resposta HTTP
```

---

## Resumo Visual

```
┌─────────────────────────────────────────────────────┐
│                    INFRAESTRUTURA                    │
│  bandit (servidor HTTP)  │  dns_cluster (cluster)   │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│                  FRAMEWORK WEB                       │
│  phoenix │ phoenix_html │ phoenix_live_view           │
│  phoenix_live_reload (dev) │ phoenix_live_dashboard   │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│                  BANCO DE DADOS                      │
│  ecto_sql │ ecto_sqlite3 │ phoenix_ecto              │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│              COMUNICAÇÃO EXTERNA                     │
│  swoosh (email) │ finch (HTTP client)                │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│                   SEGURANÇA                          │
│  pbkdf2_elixir (hash de senhas)                      │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│                    ASSETS                            │
│  esbuild (JS) │ tailwind (CSS) │ heroicons (ícones)  │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│                  UTILITÁRIOS                         │
│  jason (JSON) │ gettext (i18n) │ floki (HTML/testes) │
│  telemetry_metrics │ telemetry_poller                │
└─────────────────────────────────────────────────────┘
```
