# first-app

🌐 [English](README.md) · **Português (Brasil)**

Aplicação Spring Boot mínima usada como exemplo prático do curso. O código da aplicação não é o foco:
ela existe apenas para ser empacotada e executada com Docker.

Um único endpoint, `GET /hello`, responde com um texto.

## Arquivos Docker

| Arquivo | Uso | Aula |
| --- | --- | --- |
| `Dockerfile` | imagem de produção (multi-stage, usuário sem privilégios) | [03 - Dockerfile](../../docs/pt-br/03-dockerfile.md) |
| `.dockerignore` | arquivos fora do contexto de build | [03 - Dockerfile](../../docs/pt-br/03-dockerfile.md) |
| `Dockerfile.dev` | imagem de desenvolvimento com JDK e Maven | [04 - Dockerfile.dev](../../docs/pt-br/04-dockerfile-dev.md) |
| `docker-compose.yml` | ambiente de dev com hot reload | [04 - Dockerfile.dev](../../docs/pt-br/04-dockerfile-dev.md) |
| `docker/dev-entrypoint.sh` | recompila o código quando um arquivo muda | [04 - Dockerfile.dev](../../docs/pt-br/04-dockerfile-dev.md) |
| `.devcontainer/` | desenvolvimento dentro do container pelo VS Code | [05 - VS Code com Dev Containers](../../docs/pt-br/05-vscode-dev-containers.md) |
| `.vscode/launch.json` | debugger conectado ao container (porta 5005) | [05 - VS Code com Dev Containers](../../docs/pt-br/05-vscode-dev-containers.md) |

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
