# compose-app

🌐 [English](README.md) · **Português (Brasil)**

API Spring Boot mínima com banco Postgres, usada como exemplo prático das aulas
[06 - Docker Compose](../../docs/pt-br/06-docker-compose.md),
[07 - Migração para Docker e Kubernetes](../../docs/pt-br/07-migrating-to-docker-and-kubernetes.md) e
[08 - CI e CD com GitHub Actions](../../docs/pt-br/08-ci-cd-github-actions.md). O código da aplicação não é o
foco: ela existe para mostrar dois containers conversando entre si.

## Arquivos Docker

| Arquivo | Uso | Aula |
| --- | --- | --- |
| `docker-compose.yml` | serviços `app` e `db`, rede, volume e healthchecks | 06 |
| `Dockerfile` | imagem da API (mesmo modelo da aula 03) | 03 |
| `.env.example` | variáveis usadas pelo Compose; copie para `.env` | 06 |
| `.dockerignore` | arquivos fora do contexto de build | 03 |
| `deploy/docker-compose.prod.yml` | stack de produção para um servidor com Docker | 07 |
| `deploy/.env.prod.example` | variáveis do servidor de produção | 07 |
| `deploy/k8s/` | os mesmos serviços em Kubernetes | 07 |
| `deploy/deploy.sh` | deploy no servidor Docker com volta automática | 08 |
| `.github/workflows/` | CI e CD com GitHub Actions | 08 |

## Rodando

```bash
docker compose up -d --build --wait
curl -X POST localhost:8080/notes -H 'Content-Type: application/json' -d '{"text": "primeira nota"}'
curl localhost:8080/notes
docker compose down
```

Não é preciso ter Java, Maven nem Postgres instalados na máquina.
