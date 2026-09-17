# 07 - compose-app

API Spring Boot mínima com banco Postgres, usada como exemplo prático da aula
[08 - Docker Compose](../08%20-%20Docker%20Compose.md). O código da aplicação não é o foco: ela existe
para mostrar dois containers conversando entre si.

## Arquivos Docker

| Arquivo | Uso |
| --- | --- |
| `docker-compose.yml` | serviços `app` e `db`, rede, volume e healthchecks |
| `Dockerfile` | imagem da API (mesmo modelo da [aula 04](../04%20-%20Dockerfile.md)) |
| `.env.example` | variáveis usadas pelo Compose; copie para `.env` |
| `.dockerignore` | arquivos fora do contexto de build |
| `deploy/docker-compose.prod.yml` | stack de produção para um servidor com Docker ([aula 09](../09%20-%20Migra%C3%A7%C3%A3o%20para%20Docker%20e%20Kubernetes.md)) |
| `deploy/.env.prod.example` | variáveis do servidor de produção |
| `deploy/k8s/` | os mesmos serviços em Kubernetes ([aula 09](../09%20-%20Migra%C3%A7%C3%A3o%20para%20Docker%20e%20Kubernetes.md)) |
| `deploy/deploy.sh` | deploy no servidor Docker com volta automática ([aula 10](../10%20-%20CI%20e%20CD%20com%20GitHub%20Actions.md)) |
| `.github/workflows/` | CI e CD com GitHub Actions ([aula 10](../10%20-%20CI%20e%20CD%20com%20GitHub%20Actions.md)) |

## Rodando

```bash
docker compose up -d --build --wait
curl -X POST localhost:8080/notes -H 'Content-Type: application/json' -d '{"text": "primeira nota"}'
curl localhost:8080/notes
docker compose down
```

Não é preciso ter Java, Maven nem Postgres instalados na máquina.
