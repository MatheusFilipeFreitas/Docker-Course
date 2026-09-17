# 08 - Docker Compose

Aplicação com **dois containers** que conversam entre si: uma API Spring Boot e um banco Postgres.
O Docker Compose descreve os dois num único arquivo e sobe tudo com um comando.

**Arquivos referenciados**

- [`07 - compose-app/docker-compose.yml`](07%20-%20compose-app/docker-compose.yml)
- [`07 - compose-app/.env.example`](07%20-%20compose-app/.env.example)
- [`07 - compose-app/Dockerfile`](07%20-%20compose-app/Dockerfile)

## A aplicação

Uma API mínima de notas, salvas no Postgres:

| Método | Rota | Uso |
| --- | --- | --- |
| `GET` | `/notes` | lista as notas |
| `POST` | `/notes` | cria uma nota: `{"text": "..."}` |
| `GET` | `/actuator/health` | informa se a aplicação está saudável (usado pelo healthcheck) |

```
                 máquina                          rede "backend" (interna)
  curl localhost:8080  ──►  app:8080  ──── jdbc:postgresql://db:5432 ────►  db:5432
                          (porta publicada)                         (porta não publicada)
                                                                           │
                                                                    volume db-data
```

---

## Dockerfile

É o mesmo Dockerfile de produção explicado na [aula 04](04%20-%20Dockerfile.md): multi-stage, cache de
dependências e usuário sem privilégios. O Compose só o **usa** para construir a imagem do serviço `app`.

---

## docker-compose.yml

### Arquivo completo

```yaml
name: compose-app

services:
  db:
    image: postgres:18-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-notes}
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-app}
    volumes:
      - db-data:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
    networks:
      - backend

  app:
    build: .
    ports:
      - "${APP_PORT:-8080}:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/${POSTGRES_DB:-notes}
      SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER:-app}
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:-app}
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 3s
      retries: 10
      start_period: 30s
    restart: unless-stopped
    networks:
      - backend

volumes:
  db-data:

networks:
  backend:
```

### Nome do projeto

Prefixo de tudo que o Compose cria: containers (`compose-app-db-1`), rede (`compose-app_backend`) e
volume (`compose-app_db-data`)

```yaml
name: compose-app
```

### services

Cada item dentro de `services` vira um ou mais containers. O **nome do serviço** (`db`, `app`) é também o
nome pelo qual os containers se encontram na rede

```yaml
services:
  db:
    ...
  app:
    ...
```

### Serviço db: imagem pronta

`image` baixa uma imagem pronta do Docker Hub, sem Dockerfile

```yaml
db:
  image: postgres:18-alpine
```

A imagem oficial do Postgres lê estas variáveis na **primeira** inicialização para criar o banco e o
usuário

```yaml
environment:
  POSTGRES_DB: ${POSTGRES_DB:-notes}
  POSTGRES_USER: ${POSTGRES_USER:-app}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-app}
```

`${POSTGRES_DB:-notes}` é **substituição de variável**: o Compose procura `POSTGRES_DB` no terminal ou no
arquivo `.env` da pasta, e usa `notes` se não achar. Assim o projeto sobe sem configuração nenhuma, mas
permite trocar credenciais sem editar o arquivo.

Guarda os dados num **volume nomeado**. Sem ele, os dados vivem na camada do container e somem num
`docker compose down`

```yaml
volumes:
  - db-data:/var/lib/postgresql
```

**Healthcheck**: comando que o Docker roda periodicamente para saber se o serviço está pronto de verdade.
O container estar "rodando" não significa que o Postgres já aceita conexões

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
  interval: 5s
  timeout: 3s
  retries: 10
```

| Campo | Significado |
| --- | --- |
| `test` | comando executado **dentro** do container; saída `0` = saudável |
| `interval` | tempo entre uma verificação e outra |
| `timeout` | tempo máximo de cada verificação |
| `retries` | falhas seguidas até marcar como `unhealthy` |

O `$$` escapa o `$`: o Compose não substitui a variável, e ela é lida pelo shell **dentro** do container.

Conecta o serviço à rede `backend`

```yaml
networks:
  - backend
```

### Serviço app: imagem construída

`build: .` constrói a imagem a partir do `Dockerfile` da pasta atual, em vez de baixar uma pronta

```yaml
app:
  build: .
```

Publica a porta 8080 do container na máquina (`host:container`). Só o `app` publica porta: o `db` fica
acessível apenas pela rede interna

```yaml
ports:
  - "${APP_PORT:-8080}:8080"
```

O Spring Boot converte variáveis de ambiente em propriedades: `SPRING_DATASOURCE_URL` vira
`spring.datasource.url`. Nenhuma credencial fica no código nem na imagem

```yaml
environment:
  SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/${POSTGRES_DB:-notes}
  SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER:-app}
  SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:-app}
```

Repare no host da URL: **`db`**, o nome do serviço. O Compose tem um DNS interno que resolve o nome de cada
serviço para o IP do container. `localhost` não funcionaria: dentro do container `app`, `localhost` é o
próprio container `app`.

**depends_on** define a ordem de inicialização. Com `condition: service_healthy`, o `app` só é criado
depois que o healthcheck do `db` passar

```yaml
depends_on:
  db:
    condition: service_healthy
```

Sem a `condition`, o Compose só espera o container do `db` **iniciar**, e a aplicação poderia tentar
conectar antes de o Postgres estar pronto, falhando na subida.

Healthcheck da própria aplicação, usando o endpoint do Spring Boot Actuator. O `wget` já vem na imagem
Alpine. `start_period` dá um tempo de tolerância para a aplicação subir antes de contar as falhas

```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://localhost:8080/actuator/health"]
  interval: 10s
  timeout: 3s
  retries: 10
  start_period: 30s
```

**Restart policy**: se o processo da aplicação morrer, o Docker reinicia o container. Só não reinicia se
ele tiver sido parado manualmente

```yaml
restart: unless-stopped
```

| Valor | Comportamento |
| --- | --- |
| `no` | nunca reinicia (padrão) |
| `on-failure` | reinicia só se sair com erro |
| `always` | sempre reinicia, inclusive ao reabrir o Docker |
| `unless-stopped` | como `always`, exceto se foi parado manualmente (`stop` ou `kill`) |

### volumes

Declara os volumes nomeados usados pelos serviços. O Docker decide onde guardar os dados, e eles
sobrevivem ao `docker compose down`

```yaml
volumes:
  db-data:
```

### networks

Declara a rede usada pelos serviços. Sem este bloco, o Compose criaria uma rede `default` e colocaria todos
os serviços nela, com o mesmo efeito. Declarar deixa explícito quem fala com quem, e permite, por exemplo,
isolar um serviço numa rede separada

```yaml
networks:
  backend:
```

---

## .env.example

### Arquivo completo

```bash
# Copy to .env and adjust: cp .env.example .env
# docker compose reads .env automatically from this folder.
POSTGRES_DB=notes
POSTGRES_USER=app
POSTGRES_PASSWORD=change-me
APP_PORT=8080
```

### Explicação

O Compose lê automaticamente um arquivo chamado `.env` na mesma pasta do `docker-compose.yml` e usa os
valores nas substituições `${...}`.

O `.env` guarda senhas, então fica no `.gitignore` e no `.dockerignore`. O que vai para o git é o
`.env.example`, que só documenta quais variáveis existem. Para usar

```bash
cp .env.example .env
```

A ordem de prioridade é: variável exportada no terminal → `.env` → valor padrão depois do `:-`.

---

## Comandos no terminal

Todos rodam dentro da pasta `07 - compose-app`.

### Subindo o ambiente

Constrói a imagem do `app` e sobe os dois serviços, com os logs na tela

```bash
docker compose up --build
```

Sobe em background e só devolve o terminal quando os healthchecks passarem

```bash
docker compose up -d --build --wait
```

Lista os serviços e o status de cada um. A coluna `STATUS` mostra `(healthy)`

```bash
docker compose ps
```

### Testando a aplicação

Cria uma nota

```bash
curl -X POST localhost:8080/notes -H 'Content-Type: application/json' -d '{"text": "primeira nota"}'
```

Lista as notas

```bash
curl localhost:8080/notes
```

Consulta o banco direto, rodando o `psql` dentro do container `db`

```bash
docker compose exec db psql -U app -d notes -c 'select * from note'
```

### Rede e DNS interno

Confere que o nome `db` resolve dentro do container `app`

```bash
docker compose exec app nslookup db
```

Mostra a rede criada e quais containers estão conectados a ela

```bash
docker network inspect compose-app_backend
```

### Persistência com volumes

Remove os containers e a rede, mas **mantém** o volume. Ao subir de novo, as notas continuam lá

```bash
docker compose down
docker compose up -d --wait
curl localhost:8080/notes
```

Remove também o volume. Ao subir de novo, o banco começa vazio

```bash
docker compose down -v
```

Lista o volume criado pelo projeto

```bash
docker volume ls --filter name=compose-app
```

### Healthcheck e restart

Mostra o histórico dos healthchecks do `db`

```bash
docker inspect --format '{{json .State.Health}}' compose-app-db-1
```

Encerra o processo da aplicação por dentro, simulando uma queda. O `restart: unless-stopped` sobe o
container de novo e o contador de reinícios aumenta

```bash
docker compose exec app kill 1
docker inspect --format '{{.RestartCount}}' compose-app-app-1
```

Já o `docker compose stop` (ou `kill`) conta como parada manual: o container **não** é reiniciado.

### Referência geral do docker compose

Sobe todos os serviços definidos no `docker-compose.yml`, com os logs na tela

```bash
docker compose up
```

Sobe os serviços em background (modo detached)

```bash
docker compose up -d
```

Reconstrói as imagens antes de subir (usar após alterar um Dockerfile)

```bash
docker compose up --build
```

Sobe apenas um serviço (e os serviços de que ele depende)

```bash
docker compose up -d <service-name>
```

Apenas constrói as imagens, sem subir os serviços

```bash
docker compose build
```

Constrói ignorando o cache das camadas

```bash
docker compose build --no-cache
```

Baixa as imagens mais recentes dos serviços que usam `image`

```bash
docker compose pull
```

Lista os serviços do projeto e seus status

```bash
docker compose ps
```

Mostra os logs de todos os serviços

```bash
docker compose logs
```

Acompanha os logs de um serviço específico em tempo real

```bash
docker compose logs -f <service-name>
```

Executa um comando dentro de um serviço que já está rodando

```bash
docker compose exec <service-name> sh
```

Roda um comando pontual num container novo, removido ao terminar

```bash
docker compose run --rm <service-name> <command>
```

Para os serviços sem remover os containers

```bash
docker compose stop
```

Inicia novamente os serviços parados

```bash
docker compose start
```

Reinicia um serviço

```bash
docker compose restart <service-name>
```

Para e remove containers e rede do projeto (mantém os volumes)

```bash
docker compose down
```

Para e remove também os volumes nomeados

```bash
docker compose down -v
```

Usa um arquivo de compose com outro nome ou caminho

```bash
docker compose -f <file-name>.yml up
```

Mescla dois arquivos de compose, o segundo sobrescrevendo o primeiro

```bash
docker compose -f docker-compose.yml -f <override-file>.yml up
```

Mostra o arquivo final já com as variáveis resolvidas (útil para conferir erros e o `.env`)

```bash
docker compose config
```
