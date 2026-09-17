# Curso de Docker

Anotações e exemplos práticos de Docker, do primeiro `docker run` até um ambiente de desenvolvimento
completo dentro de containers.

## Pré-requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (ou outro runtime compatível, como OrbStack)
- [VS Code](https://code.visualstudio.com/) com a extensão **Dev Containers**, apenas para a aula 06

Java e Maven **não** precisam estar instalados: o exemplo compila e roda dentro dos containers.

## Aulas

Os projetos (`03`, `07`) contêm os arquivos Docker. Cada aula mostra o arquivo completo, explica cada
instrução na ordem em que aparece e termina com os comandos para testar no terminal.

| # | Aula | Conteúdo |
| --- | --- | --- |
| 01 | [Links](01%20-%20Links.md) | referências |
| 02 | [Commands](02%20-%20Commands.md) | referência da CLI: containers, imagens, registry, volumes e limpeza |
| 03 | [first-app](03%20-%20first-app/) | aplicação de exemplo usada nas aulas seguintes |
| 04 | [Dockerfile](04%20-%20Dockerfile.md) | imagem de produção: multi-stage, cache de camadas, `USER`, `.dockerignore` |
| 05 | [Dockerfile.dev](05%20-%20Dockerfile.dev.md) | ambiente de desenvolvimento com Compose, bind mount e hot reload |
| 06 | [VS Code on Docker](06%20-%20VS%20Code%20on%20Docker.md) | Dev Containers: o editor trabalhando dentro do container |
| 07 | [compose-app](07%20-%20compose-app/) | aplicação de exemplo com API + Postgres, usada na aula 08 |
| 08 | [Docker Compose](08%20-%20Docker%20Compose.md) | vários serviços: rede interna, volumes, healthcheck, `depends_on`, `.env` e referência de comandos |
| 09 | [Migração para Docker e Kubernetes](09%20-%20Migra%C3%A7%C3%A3o%20para%20Docker%20e%20Kubernetes.md) | roteiro para levar apps de um servidor sem Docker para Docker ou Kubernetes |
| 10 | [CI e CD com GitHub Actions](10%20-%20CI%20e%20CD%20com%20GitHub%20Actions.md) | build a cada commit, imagem no GHCR com o hash do commit e deploy automático |
