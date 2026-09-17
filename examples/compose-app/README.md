# compose-app

🌐 **English** · [Português (Brasil)](README.pt-BR.md)

Minimal Spring Boot API with a Postgres database, used as the hands-on example of lessons
[06 - Docker Compose](../../docs/en/06-docker-compose.md),
[07 - Migrating to Docker and Kubernetes](../../docs/en/07-migrating-to-docker-and-kubernetes.md) and
[08 - CI/CD with GitHub Actions](../../docs/en/08-ci-cd-github-actions.md). The application code is not the
focus: it exists to show two containers talking to each other.

## Docker files

| File | Purpose | Lesson |
| --- | --- | --- |
| `docker-compose.yml` | `app` and `db` services, network, volume and healthchecks | 06 |
| `Dockerfile` | API image (same model as lesson 03) | 03 |
| `.env.example` | variables used by Compose; copy it to `.env` | 06 |
| `.dockerignore` | files left out of the build context | 03 |
| `deploy/docker-compose.prod.yml` | production stack for a server with Docker | 07 |
| `deploy/.env.prod.example` | production server variables | 07 |
| `deploy/k8s/` | the same services on Kubernetes | 07 |
| `deploy/deploy.sh` | deploy to the Docker server with automatic rollback | 08 |
| `.github/workflows/` | CI and CD with GitHub Actions | 08 |

## Running

```bash
docker compose up -d --build --wait
curl -X POST localhost:8080/notes -H 'Content-Type: application/json' -d '{"text": "first note"}'
curl localhost:8080/notes
docker compose down
```

Java, Maven and Postgres do not need to be installed on your machine.
