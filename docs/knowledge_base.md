# Base de Conhecimento - Elixir e Phoenix

Este arquivo registra conceitos, dúvidas e padrões descobertos durante o desenvolvimento do projeto Omnigist.

## Sumário
*   [Elixir: Sigils e Charlists (~c)](#elixir-sigils-e-charlists-c)
*   [Erlang: Módulo :httpc](#erlang-módulo-httpc)
*   [Workflow: Integração de Novos Sistemas Cloud](#workflow-integração-de-novos-sistemas-cloud)

---

## Elixir: Sigils e Charlists (~c)

### Contexto
Uso de `~c"..."` em cabeçalhos (headers) e URLs ao utilizar o módulo `:httpc` do Erlang.

### O que são Sigils (~)
Sigils são atalhos sintáticos em Elixir iniciados pelo caractere til (`~`). Eles permitem trabalhar com representações textuais de forma flexível. Exemplos comuns incluem `~r` para expressões regulares e `~w` para listas de palavras.

### Charlists vs Strings
1.  **Strings ("exemplo")**: São binários codificados em UTF-8. É o padrão nativo do Elixir para quase todas as operações de texto.
2.  **Charlists (~c"exemplo" ou 'exemplo')**: São listas de inteiros onde cada número representa um caractere (Unicode code point). É o formato legado utilizado pela linguagem Erlang.

### Por que usar ~c no Azure Client?
O módulo `:httpc` faz parte da biblioteca padrão do Erlang (OTP). Como o Erlang foi criado antes das strings binárias do Elixir, suas funções de rede exigem Charlists para URLs e cabeçalhos.
*   O sigilo `~c` é a forma moderna (Elixir 1.15+) de declarar Charlists de forma legível.

### Estruturas de Dados: Lista de Tuplas vs Maps
No trecho de código dos headers, a estrutura utilizada não é um Map (`%{}`), mas sim uma **Lista de Tuplas**:
```elixir
headers = [
  { ~c"Authorization", ~c"Basic #{credentials}" },
  { ~c"Accept", ~c"application/json" }
]
```
*   **Lista de Tuplas**: Uma lista `[]` contendo elementos do tipo `{key, value}`. Comum em protocolos de rede e bibliotecas Erlang por permitir chaves duplicadas e manter a ordem.
*   **Maps**: Estrutura `%{key => value}` otimizada para busca rápida por chave única, mas sem garantia de ordem.

---

## Erlang: Módulo :httpc

O módulo `:httpc` é o cliente HTTP padrão da biblioteca `inets` do Erlang. Ele é útil para realizar requisições sem a necessidade de dependências externas.

### Assinatura da Função
A função principal é `:httpc.request/4`:
```elixir
:httpc.request(method, request, http_options, options)
```

### Requisição GET
Para requisições sem corpo (GET, DELETE), o parâmetro `request` é a tupla `{url, headers}`.
*   **URL**: Deve ser uma Charlist.
*   **Headers**: Lista de tuplas `{charlist, charlist}`.

Exemplo:
```elixir
url = ~c"https://api.example.com/data"
headers = [{~c"Accept", ~c"application/json"}]

{:ok, {{_ver, 200, _msg}, _headers, body}} = :httpc.request(:get, {url, headers}, [], [])
```

### Requisição POST com JSON
Para requisições com corpo (POST, PUT, PATCH), o parâmetro `request` é a tupla `{url, headers, content_type, body}`.
*   **Content-Type**: Charlist (ex: `~c"application/json"`).
*   **Body**: O conteúdo da requisição. Embora o Erlang prefira Charlists, o `:httpc` moderno aceita strings binárias do Elixir.

Exemplo:
```elixir
url = ~c"https://api.example.com/create"
headers = []
content_type = ~c"application/json"
body = Jason.encode!(%{nome: "Item Teste", valor: 100})

{:ok, {{_ver, 201, _msg}, _headers, response_body}} = 
  :httpc.request(:post, {url, headers, content_type, body}, [], [])
```

### Observações Importantes
1.  **Imutabilidade dos Headers**: Os nomes e valores dos headers devem ser obrigatoriamente Charlists.
2.  **Tratamento de Resposta**: O corpo da resposta (`body`) geralmente retorna como uma Charlist. Para converter de volta para uma string Elixir, use `List.to_string(body)`.
3.  **JSON**: Sempre use uma biblioteca como `Jason` para codificar e decodificar o corpo antes de enviar/receber via `:httpc`.

---

## Workflow: Integração de Novos Sistemas Cloud

Ao integrar um novo sistema (ex: GitLab, Bitbucket), siga este padrão arquitetural estabelecido no projeto Omnigist.

### Passo 1: Camada de Domínio (`lib/omnigist/[sistema]/`)
Esta camada lida com a lógica pura do sistema externo.

1.  **Criar o Diretório**: `lib/omnigist/gitlab/`.
2.  **Definir Structs (Schemas)**: Crie arquivos para representar as entidades (ex: `gitlab_repository.ex`).
    ```elixir
    defmodule Omnigist.GitLab.Repository do
      defstruct [:id, :name, :description, :web_url]
    end
    ```
3.  **Implementar o Client (`client.ex`)**: Centralize as chamadas HTTP usando `:httpc`.
    *   Utilize Charlists para headers e URLs.
    *   Retorne tuplas padronizadas como `{:ok, data}` ou `{:error, reason}`.

### Passo 2: Camada Web - API Controller (`lib/omnigist_web/controllers/api/`)
Esta camada expõe as funcionalidades do domínio para o mundo externo.

1.  **Criar o Controller**: `gitlab_controller.ex`.
    *   Chame as funções do seu `Client`.
    *   Use o `FallbackController` para lidar com erros de forma padronizada.
2.  **Criar o JSON View**: `gitlab_json.ex`.
    *   Utilize o padrão Phoenix 1.7+ de módulos JSON (sem arquivos `.json.heex`).
    *   Defina as funções `index/1`, `show/1` ou `data/1` para formatar o mapa de resposta.

### Passo 3: Rotas (`lib/omnigist_web/router.ex`)
Registre os endpoints no escopo de API.

1.  Localize o escopo `scope "/api/v1"`.
2.  Adicione as rotas seguindo o padrão REST:
    ```elixir
    get "/gitlab/projects", GitLabController, :index
    ```

### Resumo do Fluxo de Dados
1.  **Request**: Chega no `router.ex`.
2.  **Dispatch**: Encaminha para o `GitLabController`.
3.  **Action**: O controller chama o `GitLab.Client`.
4.  **External**: O `Client` faz a requisição via `:httpc`.
5.  **Response**: O `Client` decodifica o JSON e retorna structs/mapas.
6.  **Render**: O controller chama o `GitLabJSON` para formatar a resposta final.

---
