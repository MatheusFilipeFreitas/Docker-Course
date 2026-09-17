# 06 - Docker Compose

🌐 **English** · [Português (Brasil)](../pt-br/06-docker-compose.md)

An application with **two containers** talking to each other: a Spring Boot API and a Postgres database. Docker
Compose describes both in a single file and starts everything with one command.

**Referenced files**

- [`examples/compose-app/docker-compose.yml`](../../examples/compose-app/docker-compose.yml)
- [`examples/compose-app/.env.example`](../../examples/compose-app/.env.example)
- [`examples/compose-app/Dockerfile`](../../examples/compose-app/Dockerfile)

## The application

A minimal notes API, stored in Postgres:

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/notes` | lists the notes |
| `POST` | `/notes` | creates a note: `{"text": "..."}` |
| `GET` | `/actuator/health` | tells whether the application is healthy (used by the healthcheck) |

```
               your machine                     "backend" network (internal)
  curl localhost:8080  ──►  app:8080  ──── jdbc:postgresql://db:5432 ────►  db:5432
                          (published port)                          (port not published)
                                                                           │
                                                                    db-data volume
```

---

## Dockerfile

It is the same production Dockerfile explained in [lesson 03](03-dockerfile.md): multi-stage, dependency cache and
unprivileged user. Compose only **uses** it to build the image of the `app` service.

---

## docker-compose.yml

### Full file

```yaml
name: compose-app

services:
  db:
    image: postgres:18-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-notes}
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-app}
    volumes:
      - db-data:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
    networks:
      - backend

  app:
    build: .
    ports:
      - "${APP_PORT:-8080}:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/${POSTGRES_DB:-notes}
      SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER:-app}
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:-app}
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 3s
      retries: 10
      start_period: 30s
    restart: unless-stopped
    networks:
      - backend

volumes:
  db-data:

networks:
  backend:
```

### Project name

Prefix for everything Compose creates: containers (`compose-app-db-1`), network (`compose-app_backend`) and volume
(`compose-app_db-data`)

```yaml
name: compose-app
```

### services

Each item under `services` becomes one or more containers. The **service name** (`db`, `app`) is also the name the
containers use to find each other on the network

```yaml
services:
  db:
    ...
  app:
    ...
```

### db service: ready-made image

`image` pulls a ready-made image from Docker Hub, with no Dockerfile

```yaml
db:
  image: postgres:18-alpine
```

The official Postgres image reads these variables on its **first** start to create the database and the user

```yaml
environment:
  POSTGRES_DB: ${POSTGRES_DB:-notes}
  POSTGRES_USER: ${POSTGRES_USER:-app}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-app}
```

`${POSTGRES_DB:-notes}` is **variable substitution**: Compose looks for `POSTGRES_DB` in your shell or in the `.env`
file of the folder, and uses `notes` if it is not found. The project starts with no configuration at all, yet
credentials can change without editing the file.

Stores the data in a **named volume**. Without it, data lives in the container layer and is lost on
`docker compose down`

```yaml
volumes:
  - db-data:/var/lib/postgresql
```

**Healthcheck**: a command Docker runs periodically to know whether the service is really ready. A "running"
container does not mean Postgres already accepts connections

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
  interval: 5s
  timeout: 3s
  retries: 10
```

| Field | Meaning |
| --- | --- |
| `test` | command run **inside** the container; exit code `0` = healthy |
| `interval` | time between checks |
| `timeout` | maximum time for each check |
| `retries` | consecutive failures before marking it `unhealthy` |

`$$` escapes `$`: Compose does not substitute the variable, and it is read by the shell **inside** the container.

Connects the service to the `backend` network

```yaml
networks:
  - backend
```

### app service: built image

`build: .` builds the image from the `Dockerfile` in the current folder instead of pulling a ready-made one

```yaml
app:
  build: .
```

Publishes container port 8080 on your machine (`host:container`). Only `app` publishes a port: `db` is reachable
only through the internal network

```yaml
ports:
  - "${APP_PORT:-8080}:8080"
```

Spring Boot turns environment variables into properties: `SPRING_DATASOURCE_URL` becomes `spring.datasource.url`.
No credentials live in the code or in the image

```yaml
environment:
  SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/${POSTGRES_DB:-notes}
  SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER:-app}
  SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:-app}
```

Look at the URL host: **`db`**, the service name. Compose has an internal DNS that resolves each service name to
the container IP. `localhost` would not work: inside the `app` container, `localhost` is the `app` container itself.

**depends_on** defines the startup order. With `condition: service_healthy`, `app` is only created after the `db`
healthcheck passes

```yaml
depends_on:
  db:
    condition: service_healthy
```

Without the `condition`, Compose only waits for the `db` container to **start**, and the application could try to
connect before Postgres is ready, failing on startup.

Healthcheck of the application itself, using the Spring Boot Actuator endpoint. `wget` already ships with the
Alpine image. `start_period` gives the application time to start before failures are counted

```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://localhost:8080/actuator/health"]
  interval: 10s
  timeout: 3s
  retries: 10
  start_period: 30s
```

**Restart policy**: if the application process dies, Docker restarts the container. It is not restarted if it was
stopped manually

```yaml
restart: unless-stopped
```

| Value | Behavior |
| --- | --- |
| `no` | never restarts (default) |
| `on-failure` | restarts only if it exits with an error |
| `always` | always restarts, including when Docker starts again |
| `unless-stopped` | like `always`, except when stopped manually (`stop` or `kill`) |

### volumes

Declares the named volumes used by the services. Docker decides where the data is stored, and it survives
`docker compose down`

```yaml
volumes:
  db-data:
```

### networks

Declares the network used by the services. Without this block, Compose would create a `default` network with all
services in it, with the same effect. Declaring it makes explicit who talks to whom and allows, for example,
isolating a service in a separate network

```yaml
networks:
  backend:
```

---

## .env.example

### Full file

```bash
# Copy to .env and adjust: cp .env.example .env
# docker compose reads .env automatically from this folder.
POSTGRES_DB=notes
POSTGRES_USER=app
POSTGRES_PASSWORD=change-me
APP_PORT=8080
```

### Explanation

Compose automatically reads a file named `.env` in the same folder as `docker-compose.yml` and uses its values in
the `${...}` substitutions.

`.env` holds passwords, so it is listed in `.gitignore` and `.dockerignore`. What goes to Git is `.env.example`,
which only documents which variables exist. To use it

```bash
cp .env.example .env
```

The precedence order is: variable exported in the shell → `.env` → default value after `:-`.

---

## Terminal commands

All of them run inside the `examples/compose-app` folder.

### Starting the environment

Builds the `app` image and starts both services, with logs on screen

```bash
docker compose up --build
```

Starts in the background and only returns once the healthchecks pass

```bash
docker compose up -d --build --wait
```

Lists the services and the status of each one. The `STATUS` column shows `(healthy)`

```bash
docker compose ps
```

### Testing the application

Creates a note

```bash
curl -X POST localhost:8080/notes -H 'Content-Type: application/json' -d '{"text": "first note"}'
```

Lists the notes

```bash
curl localhost:8080/notes
```

Queries the database directly, running `psql` inside the `db` container

```bash
docker compose exec db psql -U app -d notes -c 'select * from note'
```

### Network and internal DNS

Checks that the name `db` resolves inside the `app` container

```bash
docker compose exec app nslookup db
```

Shows the created network and which containers are connected to it

```bash
docker network inspect compose-app_backend
```

### Persistence with volumes

Removes the containers and the network but **keeps** the volume. After starting again, the notes are still there

```bash
docker compose down
docker compose up -d --wait
curl localhost:8080/notes
```

Also removes the volume. After starting again, the database is empty

```bash
docker compose down -v
```

Lists the volume created by the project

```bash
docker volume ls --filter name=compose-app
```

### Healthcheck and restart

Shows the `db` healthcheck history

```bash
docker inspect --format '{{json .State.Health}}' compose-app-db-1
```

Kills the application process from the inside, simulating a crash. `restart: unless-stopped` starts the container
again and the restart counter increases

```bash
docker compose exec app kill 1
docker inspect --format '{{.RestartCount}}' compose-app-app-1
```

`docker compose stop` (or `kill`), on the other hand, counts as a manual stop: the container is **not** restarted.

### General docker compose reference

Starts every service defined in `docker-compose.yml`, with logs on screen

```bash
docker compose up
```

Starts the services in the background (detached mode)

```bash
docker compose up -d
```

Rebuilds the images before starting (use it after changing a Dockerfile)

```bash
docker compose up --build
```

Starts a single service (and the services it depends on)

```bash
docker compose up -d <service-name>
```

Only builds the images, without starting the services

```bash
docker compose build
```

Builds ignoring the layer cache

```bash
docker compose build --no-cache
```

Pulls the latest images of the services that use `image`

```bash
docker compose pull
```

Lists the project services and their status

```bash
docker compose ps
```

Shows the logs of every service

```bash
docker compose logs
```

Follows the logs of a specific service in real time

```bash
docker compose logs -f <service-name>
```

Runs a command inside a service that is already running

```bash
docker compose exec <service-name> sh
```

Runs a one-off command in a new container, removed when it finishes

```bash
docker compose run --rm <service-name> <command>
```

Stops the services without removing the containers

```bash
docker compose stop
```

Starts the stopped services again

```bash
docker compose start
```

Restarts a service

```bash
docker compose restart <service-name>
```

Stops and removes the project containers and network (keeps the volumes)

```bash
docker compose down
```

Stops and also removes the named volumes

```bash
docker compose down -v
```

Uses a compose file with another name or path

```bash
docker compose -f <file-name>.yml up
```

Merges two compose files, the second overriding the first

```bash
docker compose -f docker-compose.yml -f <override-file>.yml up
```

Shows the final file with the variables resolved (useful to check errors and the `.env`)

```bash
docker compose config
```
