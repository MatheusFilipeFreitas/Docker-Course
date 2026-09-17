# first-app

🌐 **English** · [Português (Brasil)](README.pt-BR.md)

Minimal Spring Boot application used as the hands-on example of the course. The application code is not the
focus: it only exists to be packaged and run with Docker.

A single endpoint, `GET /hello`, returns a text.

## Docker files

| File | Purpose | Lesson |
| --- | --- | --- |
| `Dockerfile` | production image (multi-stage, unprivileged user) | [03 - Dockerfile](../../docs/en/03-dockerfile.md) |
| `.dockerignore` | files left out of the build context | [03 - Dockerfile](../../docs/en/03-dockerfile.md) |
| `Dockerfile.dev` | development image with JDK and Maven | [04 - Dockerfile.dev](../../docs/en/04-dockerfile-dev.md) |
| `docker-compose.yml` | development environment with hot reload | [04 - Dockerfile.dev](../../docs/en/04-dockerfile-dev.md) |
| `docker/dev-entrypoint.sh` | recompiles the code when a file changes | [04 - Dockerfile.dev](../../docs/en/04-dockerfile-dev.md) |
| `.devcontainer/` | developing inside the container with VS Code | [05 - VS Code Dev Containers](../../docs/en/05-vscode-dev-containers.md) |
| `.vscode/launch.json` | debugger attached to the container (port 5005) | [05 - VS Code Dev Containers](../../docs/en/05-vscode-dev-containers.md) |

## Production

```bash
docker build -t first-app:1.0 .
docker run --rm -p 8080:8080 first-app:1.0
```

Open <http://localhost:8080/hello>.

## Development

```bash
docker compose up --build
```

Edit any file under `src/` and the application restarts by itself. To stop:

```bash
docker compose down
```

Java and Maven do not need to be installed on your machine: everything runs inside containers.
