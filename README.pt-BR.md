# Curso de Docker

🌐 [English](README.md) · **Português (Brasil)**

Anotações e exemplos práticos para aprender Docker: do primeiro `docker run` até deploys em produção em
servidores com Docker e Kubernetes, automatizados com GitHub Actions.

Todas as aulas existem em **inglês** (`docs/en/`) e **português** (`docs/pt-br/`), com os mesmos nomes de
arquivo, e cada página tem no topo um link para a tradução.

## Pré-requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (ou outro runtime compatível, como OrbStack)
- [VS Code](https://code.visualstudio.com/) com a extensão **Dev Containers**, apenas para a aula 05

Java e Maven **não** precisam estar instalados: os exemplos compilam e rodam dentro dos containers.

## Organização do repositório

```
.
├── README.md / README.pt-BR.md
├── docs/
│   ├── en/        aulas em inglês
│   └── pt-br/     aulas em português (mesmos nomes de arquivo)
└── examples/
    ├── first-app/     aplicação Spring Boot simples (aulas 03–05)
    └── compose-app/   API Spring Boot + Postgres (aulas 06–08)
```

Cada aula mostra o arquivo completo, explica cada instrução na ordem em que aparece e termina com os comandos
para testar no terminal.

## Aulas

| # | Aula | English | Conteúdo |
| --- | --- | --- | --- |
| 01 | [Links](docs/pt-br/01-links.md) | [Links](docs/en/01-links.md) | referências |
| 02 | [Comandos](docs/pt-br/02-commands.md) | [Commands](docs/en/02-commands.md) | referência da CLI: containers, imagens, registry, volumes e limpeza |
| 03 | [Dockerfile](docs/pt-br/03-dockerfile.md) | [Dockerfile](docs/en/03-dockerfile.md) | imagem de produção: multi-stage, cache de camadas, `USER`, `.dockerignore` |
| 04 | [Dockerfile.dev](docs/pt-br/04-dockerfile-dev.md) | [Dockerfile.dev](docs/en/04-dockerfile-dev.md) | ambiente de desenvolvimento com Compose, bind mount e hot reload |
| 05 | [VS Code com Dev Containers](docs/pt-br/05-vscode-dev-containers.md) | [VS Code Dev Containers](docs/en/05-vscode-dev-containers.md) | o editor trabalhando dentro do container |
| 06 | [Docker Compose](docs/pt-br/06-docker-compose.md) | [Docker Compose](docs/en/06-docker-compose.md) | vários serviços: rede, volumes, healthcheck, `depends_on`, `.env` |
| 07 | [Migração para Docker e Kubernetes](docs/pt-br/07-migrating-to-docker-and-kubernetes.md) | [Migrating to Docker and Kubernetes](docs/en/07-migrating-to-docker-and-kubernetes.md) | levar apps de servidores sem Docker para Docker ou Kubernetes |
| 08 | [CI e CD com GitHub Actions](docs/pt-br/08-ci-cd-github-actions.md) | [CI/CD with GitHub Actions](docs/en/08-ci-cd-github-actions.md) | imagem por commit no GHCR e deploy automático |

## Exemplos

| Exemplo | Usado nas aulas |
| --- | --- |
| [`examples/first-app`](examples/first-app/) | 03, 04 e 05 |
| [`examples/compose-app`](examples/compose-app/) | 06, 07 e 08 |
