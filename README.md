# Docker Course

🌐 **English** · [Português (Brasil)](README.pt-BR.md)

Notes and hands-on examples to learn Docker: from the first `docker run` to production deploys on Docker
servers and Kubernetes, automated with GitHub Actions.

Every lesson is available in **English** (`docs/en/`) and **Brazilian Portuguese** (`docs/pt-br/`), with the
same file names, and each page links to its translation at the top.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or another compatible runtime, such as OrbStack)
- [VS Code](https://code.visualstudio.com/) with the **Dev Containers** extension, only for lesson 05

Java and Maven do **not** need to be installed: the examples build and run inside containers.

## Repository layout

```
.
├── README.md / README.pt-BR.md
├── docs/
│   ├── en/        lessons in English
│   └── pt-br/     lessons in Brazilian Portuguese (same file names)
└── examples/
    ├── first-app/     single Spring Boot app (lessons 03–05)
    └── compose-app/   Spring Boot API + Postgres (lessons 06–08)
```

Each lesson shows the full file it covers, explains every instruction in order and ends with the terminal
commands to try it out.

## Lessons

| # | Lesson | Português | Topics |
| --- | --- | --- | --- |
| 01 | [Links](docs/en/01-links.md) | [Links](docs/pt-br/01-links.md) | references |
| 02 | [Commands](docs/en/02-commands.md) | [Comandos](docs/pt-br/02-commands.md) | CLI reference: containers, images, registry, volumes, cleanup |
| 03 | [Dockerfile](docs/en/03-dockerfile.md) | [Dockerfile](docs/pt-br/03-dockerfile.md) | production image: multi-stage, layer cache, `USER`, `.dockerignore` |
| 04 | [Dockerfile.dev](docs/en/04-dockerfile-dev.md) | [Dockerfile.dev](docs/pt-br/04-dockerfile-dev.md) | development environment with Compose, bind mount and hot reload |
| 05 | [VS Code Dev Containers](docs/en/05-vscode-dev-containers.md) | [VS Code com Dev Containers](docs/pt-br/05-vscode-dev-containers.md) | the editor working inside the container |
| 06 | [Docker Compose](docs/en/06-docker-compose.md) | [Docker Compose](docs/pt-br/06-docker-compose.md) | multiple services: network, volumes, healthcheck, `depends_on`, `.env` |
| 07 | [Migrating to Docker and Kubernetes](docs/en/07-migrating-to-docker-and-kubernetes.md) | [Migração para Docker e Kubernetes](docs/pt-br/07-migrating-to-docker-and-kubernetes.md) | moving apps from plain servers to Docker or Kubernetes |
| 08 | [CI/CD with GitHub Actions](docs/en/08-ci-cd-github-actions.md) | [CI e CD com GitHub Actions](docs/pt-br/08-ci-cd-github-actions.md) | image per commit on GHCR and automatic deploys |

## Examples

| Example | Used in |
| --- | --- |
| [`examples/first-app`](examples/first-app/) | lessons 03, 04 and 05 |
| [`examples/compose-app`](examples/compose-app/) | lessons 06, 07 and 08 |
