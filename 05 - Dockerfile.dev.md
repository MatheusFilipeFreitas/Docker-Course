Ambiente de desenvolvimento com hot reload: `03 - first-app/Dockerfile.dev`,
`docker-compose.yml` e `docker/dev-entrypoint.sh`.

## Dockerfile.dev

Usa a imagem do Maven como imagem final (sem multi-stage): em desenvolvimento o JDK e o Maven
precisam continuar dentro do container para recompilar o código

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25
```

Copia apenas o `pom.xml` primeiro e baixa as dependências. Como o Docker guarda cada instrução em
cache, essa camada só é refeita quando o `pom.xml` muda — editar um `.java` não redownloada nada

```dockerfile
COPY pom.xml /app/
RUN mvn -B dependency:go-offline
```

Copia o código e o script de inicialização, e dá permissão de execução ao script

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

Em vez de `java -jar`, o container roda o script que vigia o código e recompila

```dockerfile
CMD ["/usr/local/bin/dev-entrypoint.sh"]
```

## docker-compose.yml

Define o nome do projeto, usado como prefixo dos containers, redes e volumes

```yaml
name: first-app
```

Manda o Compose construir a imagem a partir do `Dockerfile.dev` em vez de baixar uma pronta

```yaml
build:
  context: .
  dockerfile: Dockerfile.dev
```

Publica as portas na máquina. `APP_PORT` permite trocar a porta do host sem editar o arquivo

```yaml
ports:
  - "${APP_PORT:-8080}:8080"
  - "35729:35729"
  - "5005:5005"
```

Monta a pasta do projeto dentro do container. É isto que faz o hot reload funcionar: não há cópia,
o `/app` do container **é** a pasta local

```yaml
volumes:
  - ./:/app
```

Volumes nomeados montados por cima do bind mount. O `target/` do container fica separado do `target/`
da máquina (evitando conflito entre o que o IntelliJ compila e o que o container compila) e o
repositório do Maven sobrevive entre um `down` e um `up`

```yaml
  - app-target:/app/target
  - maven-repo:/root/.m2
```

Variáveis de ambiente lidas pelo Spring Boot. O polling é necessário porque bind mounts no
macOS e no Windows nem sempre emitem eventos de alteração de arquivo

```yaml
environment:
  SPRING_PROFILES_ACTIVE: dev
  SPRING_DEVTOOLS_RESTART_POLL_INTERVAL: 2s
  SPRING_DEVTOOLS_RESTART_QUIET_PERIOD: 1s
```

## Como o hot reload acontece

O `spring-boot-devtools` (declarado no `pom.xml`) vigia o `target/classes` e reinicia o contexto do
Spring quando um `.class` muda. Ele **não** compila `.java` — quem faz isso é o `dev-entrypoint.sh`:

```bash
find src pom.xml -newer /tmp/.last-compile -type f ... -print -quit
```

A cada 2 segundos o script procura algum arquivo mais novo que a última compilação. Achando, roda
`mvn compile`, o `target/classes` muda e o DevTools reinicia a aplicação em cerca de 0,1s.

Editar um arquivo no Mac → o arquivo muda dentro do container (bind mount) → `mvn compile` →
DevTools reinicia. Sem `docker build`, sem `docker restart`.

## Comandos no terminal

Constrói a imagem e sobe o ambiente, deixando os logs na tela

```bash
docker compose up --build
```

Sobe em background e com outra porta no host, caso a 8080 esteja ocupada

```bash
APP_PORT=8081 docker compose up -d --build
```

Acompanha os logs do serviço `app`

```bash
docker compose logs -f app
```

Abre um shell dentro do container em execução

```bash
docker compose exec app bash
```

Lista os serviços do projeto e seus status

```bash
docker compose ps
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
