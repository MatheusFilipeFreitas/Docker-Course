# 03 - first-app

Aplicação Spring Boot mínima usada como exemplo prático do curso. O código da aplicação não é o foco:
ela existe apenas para ser empacotada e executada com Docker.

Um único endpoint, `GET /hello`, responde com um texto.

## Arquivos Docker

| Arquivo | Uso | Aula |
| --- | --- | --- |
| `Dockerfile` | imagem de produção (multi-stage, usuário sem privilégios) | [04 - Dockerfile](../04%20-%20Dockerfile.md) |
| `.dockerignore` | arquivos fora do contexto de build | [04 - Dockerfile](../04%20-%20Dockerfile.md) |
| `Dockerfile.dev` | imagem de desenvolvimento com JDK e Maven | [05 - Dockerfile.dev](../05%20-%20Dockerfile.dev.md) |
| `docker-compose.yml` | ambiente de dev com hot reload | [05 - Dockerfile.dev](../05%20-%20Dockerfile.dev.md) |
| `docker/dev-entrypoint.sh` | recompila o código quando um arquivo muda | [05 - Dockerfile.dev](../05%20-%20Dockerfile.dev.md) |
| `.devcontainer/` | desenvolvimento dentro do container pelo VS Code | [06 - VS Code on Docker](../06%20-%20VS%20Code%20on%20Docker.md) |
| `.vscode/launch.json` | debugger conectado ao container (porta 5005) | [06 - VS Code on Docker](../06%20-%20VS%20Code%20on%20Docker.md) |

## Produção

```bash
docker build -t first-app:1.0 .
docker run --rm -p 8080:8080 first-app:1.0
```

Acesse <http://localhost:8080/hello>.

## Desenvolvimento

```bash
docker compose up --build
```

Edite qualquer arquivo em `src/` e a aplicação reinicia sozinha. Para encerrar:

```bash
docker compose down
```

Não é preciso ter Java nem Maven instalados na máquina: tudo roda dentro dos containers.
