# 05 - Dockerfile.dev

Ambiente de **desenvolvimento** com hot reload: o código da máquina é montado dentro do container e a
aplicação reinicia sozinha a cada alteração, sem `docker build`.

Esta aula usa o Docker Compose com um único serviço. O Compose é aprofundado, com mais de um serviço,
na aula [08 - Docker Compose](08%20-%20Docker%20Compose.md).

**Arquivos referenciados**

- [`03 - first-app/Dockerfile.dev`](03%20-%20first-app/Dockerfile.dev)
- [`03 - first-app/docker-compose.yml`](03%20-%20first-app/docker-compose.yml)
- [`03 - first-app/docker/dev-entrypoint.sh`](03%20-%20first-app/docker/dev-entrypoint.sh)

---

## Dockerfile.dev

### Arquivo completo

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25

WORKDIR /app

# Dependency layer: only re-downloads when pom.xml changes.
COPY pom.xml /app/
RUN mvn -B dependency:go-offline

# Baseline sources; at runtime they are shadowed by the bind mount from the host.
COPY src /app/src
COPY docker/dev-entrypoint.sh /usr/local/bin/dev-entrypoint.sh
RUN chmod +x /usr/local/bin/dev-entrypoint.sh

# 8080 = app | 35729 = devtools livereload | 5005 = remote debug (JDWP)
EXPOSE 8080 35729 5005

CMD ["/usr/local/bin/dev-entrypoint.sh"]
```

### Explicação

Usa a imagem do Maven como imagem final (sem multi-stage): em desenvolvimento o JDK e o Maven precisam
continuar dentro do container para recompilar o código

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25
```

Copia apenas o `pom.xml` e baixa as dependências. Essa camada só é refeita quando o `pom.xml` muda
(mesma técnica de cache da [aula 04](04%20-%20Dockerfile.md#cache-de-camadas))

```dockerfile
COPY pom.xml /app/
RUN mvn -B dependency:go-offline
```

Copia o código e o script de inicialização, e dá permissão de execução ao script. O `src` copiado aqui
só é usado se o container rodar sem o bind mount: com o Compose, ele é coberto pela pasta local

```dockerfile
COPY src /app/src
COPY docker/dev-entrypoint.sh /usr/local/bin/dev-entrypoint.sh
RUN chmod +x /usr/local/bin/dev-entrypoint.sh
```

Documenta as três portas do ambiente de dev

```dockerfile
EXPOSE 8080 35729 5005
```

| Porta | Uso |
| --- | --- |
| 8080 | aplicação |
| 35729 | LiveReload do Spring DevTools |
| 5005 | debugger remoto (JDWP) |

Em vez de `java -jar`, o container roda o script que vigia o código e recompila. Usa `CMD` (e não
`ENTRYPOINT`) para que a [aula 06](06%20-%20VS%20Code%20on%20Docker.md) possa trocar o comando por
`sleep infinity`

```dockerfile
CMD ["/usr/local/bin/dev-entrypoint.sh"]
```

---

## docker-compose.yml

### Arquivo completo

```yaml
name: first-app

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "${APP_PORT:-8080}:8080"   # application (override: APP_PORT=8081 docker compose up)
      - "35729:35729" # devtools livereload
      - "5005:5005"   # remote debugger (JDWP)
    volumes:
      # Local code is mounted live: edits on the host trigger a recompile + restart.
      - ./:/app
      # Named volumes shadow the host folders so container builds and the local
      # Maven repository survive restarts without polluting the project dir.
      - app-target:/app/target
      - maven-repo:/root/.m2
    environment:
      SPRING_PROFILES_ACTIVE: dev
      # macOS/Windows bind mounts do not always emit inotify events; polling is reliable.
      SPRING_DEVTOOLS_RESTART_POLL_INTERVAL: 2s
      SPRING_DEVTOOLS_RESTART_QUIET_PERIOD: 1s
    stdin_open: true
    tty: true

volumes:
  app-target:
  maven-repo:
```

### Explicação

Define o nome do projeto, usado como prefixo dos containers, redes e volumes

```yaml
name: first-app
```

Manda o Compose construir a imagem a partir do `Dockerfile.dev` em vez do `Dockerfile` padrão

```yaml
build:
  context: .
  dockerfile: Dockerfile.dev
```

Publica as portas na máquina (`host:container`). `${APP_PORT:-8080}` lê a variável `APP_PORT` e usa
`8080` se ela não existir, permitindo trocar a porta do host sem editar o arquivo

```yaml
ports:
  - "${APP_PORT:-8080}:8080"
  - "35729:35729"
  - "5005:5005"
```

**Bind mount**: monta a pasta do projeto dentro do container. É isto que faz o hot reload funcionar: não
há cópia, o `/app` do container **é** a pasta local

```yaml
volumes:
  - ./:/app
```

**Volumes nomeados** montados por cima do bind mount. O `target/` do container fica separado do `target/`
da máquina (evitando conflito entre o que a IDE compila e o que o container compila) e o repositório do
Maven sobrevive entre um `down` e um `up`

```yaml
  - app-target:/app/target
  - maven-repo:/root/.m2
```

Variáveis de ambiente lidas pelo Spring Boot. O polling é necessário porque bind mounts no macOS e no
Windows nem sempre emitem eventos de alteração de arquivo. Este é o único lugar onde o perfil e o polling
são configurados: o processo iniciado pelo `dev-entrypoint.sh` herda essas variáveis

```yaml
environment:
  SPRING_PROFILES_ACTIVE: dev
  SPRING_DEVTOOLS_RESTART_POLL_INTERVAL: 2s
  SPRING_DEVTOOLS_RESTART_QUIET_PERIOD: 1s
```

Equivalem ao `-it` do `docker run`: mantêm a entrada aberta e um terminal alocado, deixando os logs
coloridos e o `Ctrl+C` funcionando

```yaml
stdin_open: true
tty: true
```

Declara os volumes nomeados. O Docker cria e gerencia onde eles ficam guardados

```yaml
volumes:
  app-target:
  maven-repo:
```

---

## dev-entrypoint.sh

O `spring-boot-devtools` (declarado no `pom.xml`) vigia o `target/classes` e reinicia o contexto do
Spring quando um `.class` muda. Ele **não** compila `.java` — quem faz isso é este script.

Compila uma vez e marca o horário da compilação num arquivo de referência

```bash
mvn -q compile
touch "$STAMP"
```

Sobe a aplicação em background (`&`), abrindo a porta 5005 para o debugger remoto

```bash
mvn spring-boot:run \
  -Dspring-boot.run.jvmArguments="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005" &
APP_PID=$!
```

Repassa o sinal de parada para a aplicação. O `docker compose down` e o `Ctrl+C` enviam `SIGTERM` e
`SIGINT` ao processo principal do container (este script), que precisa encerrar a aplicação

```bash
trap 'kill -TERM "$APP_PID" 2>/dev/null || true; exit 0' INT TERM
```

A cada 2 segundos procura algum arquivo mais novo que a última compilação. Achando, roda `mvn compile`,
o `target/classes` muda e o DevTools reinicia a aplicação

```bash
find src pom.xml -newer "$STAMP" -type f ... -print -quit
```

O fluxo completo: editar um arquivo no Mac → o arquivo muda dentro do container (bind mount) →
`mvn compile` → DevTools reinicia. Sem `docker build`, sem `docker restart`.

---

## Comandos no terminal

Todos rodam dentro da pasta `03 - first-app`.

Constrói a imagem e sobe o ambiente, deixando os logs na tela. Teste em <http://localhost:8080/hello>,
altere o texto no `HelloController.java` e recarregue a página

```bash
docker compose up --build
```

Sobe em background e com outra porta no host, caso a 8080 esteja ocupada

```bash
APP_PORT=8081 docker compose up -d --build
```

Acompanha os logs do serviço `app` (procure por `[dev] change detected`)

```bash
docker compose logs -f app
```

Abre um shell dentro do container e confere que o `/app` é a pasta local

```bash
docker compose exec app bash
ls /app
```

Lista os volumes criados para o projeto

```bash
docker volume ls --filter name=first-app
```

Reconstrói a imagem sem usar cache (útil após mexer no `Dockerfile.dev`)

```bash
docker compose build --no-cache
```

Derruba o ambiente, mantendo os volumes de cache

```bash
docker compose down
```

Derruba o ambiente removendo também os volumes (`target/` e `~/.m2`)

```bash
docker compose down -v
```
