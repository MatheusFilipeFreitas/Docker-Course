# 07 - Migrating to Docker and Kubernetes

🌐 **English** · [Português (Brasil)](../pt-br/07-migrating-to-docker-and-kubernetes.md)

A step-by-step guide to move an application from a **traditional server** (no Docker: Java, Node or nginx installed
directly on the system) to a **server with Docker** or to a **Kubernetes cluster**.

The core idea: the `Dockerfile` and `docker-compose.yml` become the **executable documentation** of how the
application runs. Once a project has these files, changing servers means copying two files and running one command,
and the same guide works for every project.

The example used from start to finish is the API from [lesson 06](06-docker-compose.md), but each phase also brings
templates for other stacks.

**Referenced files**

- [`examples/compose-app/Dockerfile`](../../examples/compose-app/Dockerfile)
- [`examples/compose-app/docker-compose.yml`](../../examples/compose-app/docker-compose.yml) (local environment)
- [`examples/compose-app/deploy/docker-compose.prod.yml`](../../examples/compose-app/deploy/docker-compose.prod.yml)
- [`examples/compose-app/deploy/.env.prod.example`](../../examples/compose-app/deploy/.env.prod.example)
- [`examples/compose-app/deploy/k8s/`](../../examples/compose-app/deploy/k8s/) (Kubernetes manifests)

## Overview

```
 old server                              your machine                         target
┌──────────────────┐   1. inventory    ┌──────────────────────┐  6. push   ┌────────────────────────┐
│ java -jar app.jar│ ────────────────► │ Dockerfile           │ ─────────► │ registry (Docker Hub,  │
│ local postgres   │   2. mapping      │ docker-compose.yml   │            │ GHCR, ECR...)          │
│ nginx            │   3. adjustments  │ 4-5. build and test  │            └───────────┬────────────┘
│ systemd, cron    │                   └──────────────────────┘                        │ pull
└────────┬─────────┘                                                     ┌─────────────┴────────────┐
         │ 8. data (pg_dump, rsync)                                      │ 7A. server with Docker   │
         └──────────────────────────────────────────────────────────────►│ 7B. Kubernetes cluster   │
                                                                         └─────────────┬────────────┘
                                                                         9. DNS cutover and rollback
```

| Phase | Result |
| --- | --- |
| 1. Inventory | list of everything the application uses on the current server |
| 2. Mapping | each inventory item matched to a Docker instruction |
| 3. Prepare the application | configuration through environment variables, logs to the terminal |
| 4. Dockerfile | image that runs the application with nothing installed on the host |
| 5. Local docker-compose | the whole server reproduced on your machine |
| 6. Registry | versioned image available to any server |
| 7A. Server with Docker | deploy with `docker compose` |
| 7B. Kubernetes | deploy with manifests |
| 8. Data | database and files copied to the new environment |
| 9. Cutover | traffic pointed to the new environment, with a rollback plan |

---

## Phase 1 — Inventory of the current server

Before writing any Dockerfile, find out **everything** the application uses. Whatever is left out of the inventory
is exactly what will break after the migration.

### How the application starts

On most Linux servers the application is a `systemd` service. The service file alone answers half of the
inventory: user, folder, variables, command and restart policy

```bash
systemctl list-units --type=service --state=running
systemctl cat notes.service
```

A typical example:

```ini
[Service]
User=notes
WorkingDirectory=/opt/notes
EnvironmentFile=/etc/notes/notes.env
ExecStart=/usr/bin/java -Xmx512m -jar /opt/notes/notes.jar --spring.config.additional-location=/etc/notes/
Restart=always
```

Without `systemd`, find the process and its full command line

```bash
ps aux | grep -E "java|node|python"
cat /proc/<pid>/cmdline | tr '\0' ' '
```

### Runtime versions

The Dockerfile base image must use the **same version** running today

```bash
java -version
node --version
nginx -v
psql --version
```

### Environment variables and configuration files

Variables of the running process (including the ones from `EnvironmentFile`)

```bash
sudo cat /proc/<pid>/environ | tr '\0' '\n'
```

Configuration files the process has open, and where they live

```bash
sudo ls -l /proc/<pid>/cwd
sudo lsof -p <pid> | grep -E "\.(properties|yml|yaml|json|conf|env)$"
```

### Ports and network dependencies

Ports the application listens on

```bash
sudo ss -tlnp
```

Outbound connections: database, cache, queues, external APIs. Each destination becomes a Compose service or an
environment variable

```bash
sudo ss -tnp | grep <pid>
```

### Files on disk

Folders the application **writes** to: uploads, generated reports, logs. Everything written that must survive
becomes a volume

```bash
sudo lsof -p <pid> | grep -v -E "\.jar|\.so|/proc|/dev"
du -sh /opt/notes/* /var/lib/notes 2>/dev/null
```

### Scheduled tasks, proxy and certificates

```bash
crontab -l -u notes
ls /etc/cron.d/
ls /etc/nginx/sites-enabled/ && cat /etc/nginx/sites-enabled/*
ls /etc/letsencrypt/live/ 2>/dev/null
```

### Inventory sheet

Fill in a table like this one for each project:

| Item | Current server (example) |
| --- | --- |
| Runtime | Java 25 |
| Artifact | `/opt/notes/notes.jar` (source code in Git: yes/no) |
| Command | `java -Xmx512m -jar notes.jar` |
| User | `notes` |
| Port | 8080, behind nginx on 443 |
| Configuration | `/etc/notes/notes.env`, `application.properties` |
| Secrets | database password inside `notes.env` |
| Database | local Postgres 18, `notes` database |
| Written files | `/var/lib/notes/uploads` |
| Logs | `/var/log/notes/app.log` |
| Scheduled tasks | `cron`: daily cleanup at 3 AM |
| Automatic restart | `Restart=always` |
| Domain and TLS | `notes.example.com`, Let's Encrypt |

---

## Phase 2 — Map the server to Docker and Kubernetes

Each inventory line has a proper place in the new environment:

| On the current server | In the Dockerfile | In docker-compose | In Kubernetes |
| --- | --- | --- | --- |
| Installed runtime (`java`, `node`) | `FROM` | — | — |
| Build (`mvn package`, `npm run build`) | build stage (multi-stage) | `build:` (local only) | — |
| `ExecStart=` | `ENTRYPOINT` / `CMD` | `command:` | `command:` / `args:` |
| `User=` | `USER` | `user:` | `securityContext` |
| `WorkingDirectory=` | `WORKDIR` | `working_dir:` | `workingDir:` |
| Application port | `EXPOSE` | `ports:` | `Service` + `Ingress` |
| `EnvironmentFile=` / variables | — (never in the image) | `environment:` + `.env` | `ConfigMap` |
| Passwords | — (never in the image) | `.env` outside Git | `Secret` |
| Configuration file | `COPY` (if identical in every environment) | file volume | mounted `ConfigMap` |
| Data / uploads folder | — | named volume | `PersistentVolumeClaim` |
| Logs in files | — | logs to stdout + `logging:` | logs to stdout |
| `Restart=always` | — | `restart: unless-stopped` | `Deployment` default |
| Local Postgres | — | `db` service | `StatefulSet` or managed database |
| Startup order | — | `depends_on` + `healthcheck` | `initContainers` + probes |
| Health monitoring | `HEALTHCHECK` | `healthcheck:` | `readiness`/`liveness` probes |
| `-Xmx512m` and memory limit | — | `deploy.resources.limits` | `resources.limits` |
| `cron` | — | host cron or dedicated service | `CronJob` |
| nginx + certificate | — | proxy service (nginx, Caddy, Traefik) | `Ingress` + cert-manager |

---

## Phase 3 — Prepare the application

An application in a container must follow three rules. Almost every migration problem comes from one of them.

### Configuration through environment variables

The **same image** runs in every environment; only the variables change. Look in the code and configuration for
hard-coded addresses, paths and passwords

```bash
grep -rn -E "localhost|127\.0\.0\.1|/opt/|/var/|password" src/main/resources/
```

In Spring Boot no code change is needed: any property can be overridden by an environment variable, replacing `.`
with `_` and using uppercase

| Property | Environment variable |
| --- | --- |
| `spring.datasource.url` | `SPRING_DATASOURCE_URL` |
| `server.port` | `SERVER_PORT` |
| `app.upload.dir` | `APP_UPLOAD_DIR` |

In Node, read `process.env.DATABASE_URL` instead of fixed values.

### Logs to the terminal (stdout)

Docker and Kubernetes collect what the process writes to **stdout**. Logs written to a file inside the container
disappear when the container is recreated. Remove settings such as `logging.file.name` and file appenders.

### No local state

Containers are disposable: anything written outside a volume is lost on the next deploy. Files uploaded by users go
to a volume (or, better, to object storage such as S3). On Kubernetes, with more than one replica, each pod has its
own disk, so in-memory sessions and uploads on local disk do not work.

### Graceful shutdown and health endpoint

Docker sends `SIGTERM` to stop the container. The application must be the main process (exec form of `ENTRYPOINT`,
with brackets) to receive the signal. In Spring Boot, also enable graceful shutdown and expose the health check

```properties
server.shutdown=graceful
management.endpoints.web.exposure.include=health
```

---

## Phase 4 — Write the Dockerfile

### With source code (the ideal case)

The Dockerfile compiles the project, and the server needs no Maven, JDK or Node. This is the model from
[lesson 03](03-dockerfile.md), used in `examples/compose-app/Dockerfile`:

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
RUN mvn -B package

FROM eclipse-temurin:25-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /app/target/*.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Without source code (only the server's `.jar`)

Old projects sometimes only exist as the artifact on the server. They can still be migrated ("lift and shift"):
copy the `.jar` to your machine and package only its execution. Use the **same Java version** found in the inventory

```bash
scp user@old-server:/opt/notes/notes.jar .
```

```dockerfile
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY notes.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Templates for other stacks

Starting points: adjust the versions to the ones found in the inventory.

**Node.js (API)**

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

For Next.js, enable `output: "standalone"` in `next.config.js` and copy `.next/standalone`, `.next/static` and
`public` to the final image, running `node server.js`.

**Angular (static frontend served by nginx)**

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/<project-name>/browser /usr/share/nginx/html
EXPOSE 80
```

Minimal `nginx.conf`, sending Angular routes to `index.html`:

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**Quarkus**: generated projects already ship ready-made Dockerfiles in `src/main/docker/` (JVM and native). Start
from them.

### JVM memory

On the old server, `-Xmx512m` fixed the heap. In a container, prefer setting the **container limit** and letting
the JVM size the heap proportionally

```yaml
JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=75
```

### .dockerignore

Keeps `target/`, `node_modules/`, `.git/` and especially `.env` out of the image (see
[lesson 03](03-dockerfile.md#dockerignore))

```
target/
node_modules/
dist/
.git/
.env
```

### Testing the image alone

```bash
docker build -t notes:test .
docker run --rm -p 8080:8080 -e SPRING_DATASOURCE_URL=... notes:test
```

---

## Phase 5 — Reproduce the server with docker-compose

Before touching any server, recreate the whole environment on your machine: application, database and the other
dependencies from the inventory. If it works here, it works on the target.

This is the `docker-compose.yml` explained in [lesson 06](06-docker-compose.md):

```bash
cd examples/compose-app
docker compose up -d --build --wait
curl localhost:8080/notes
```

Use the **same major version** of the database as the old server (`postgres:18-alpine` for Postgres 18). A dump from
a newer version does not always restore on an older one.

This is also the moment to test the data restore (see [Phase 8](#phase-8--migrate-the-data)) with a copy of the
production database.

---

## Phase 6 — Version and publish the image

The target server compiles nothing: it **pulls** the image from a registry. The commands below are the manual
process; [lesson 08](08-ci-cd-github-actions.md) does the same through GitHub Actions, publishing to the GitHub
Container Registry.

Logs in to the registry (Docker Hub; for GitHub use `docker login ghcr.io`)

```bash
docker login
```

Builds the image with the registry name and a **version**. Never deploy `latest`: you cannot tell what is running
or go back to the previous version

```bash
docker build -t docker.io/<user>/compose-app:1.0.0 .
```

A common alternative is using the commit hash as the version

```bash
docker build -t docker.io/<user>/compose-app:$(git rev-parse --short HEAD) .
```

If the server has a different architecture from your machine (Apple Silicon Mac → AMD64 server), build for both

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t docker.io/<user>/compose-app:1.0.0 --push .
```

Pushes to the registry

```bash
docker push docker.io/<user>/compose-app:1.0.0
```

---

## Phase 7A — Deploy to a server with Docker

The production compose file differs from the local one: it has no `build`, mounts no source code and is stricter
about passwords, memory and logs.

### docker-compose.prod.yml

#### Full file

```yaml
# Production stack for a server that only has Docker installed.
# No build and no source code on the server: the app image comes from a registry.
name: compose-app

services:
  db:
    image: postgres:18-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-notes}
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
    volumes:
      - db-data:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: 10m
        max-file: "3"

  app:
    image: ${APP_IMAGE:?set APP_IMAGE in .env}:${APP_VERSION:?set APP_VERSION in .env}
    ports:
      # Only reachable from the server itself: the reverse proxy (nginx, Caddy, Traefik) publishes it.
      - "127.0.0.1:${APP_PORT:-8080}:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/${POSTGRES_DB:-notes}
      SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER:-app}
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD}
      JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=75
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
    deploy:
      resources:
        limits:
          memory: 512m
    logging:
      driver: json-file
      options:
        max-size: 10m
        max-file: "3"

volumes:
  db-data:
```

#### What changes compared to the local compose file

There is no `build`: the image comes from the registry, with name and version set in `.env`. `:?` makes Compose
**stop with an error** if the variable is missing, instead of starting with a wrong value

```yaml
image: ${APP_IMAGE:?set APP_IMAGE in .env}:${APP_VERSION:?set APP_VERSION in .env}
```

The database password has no default value: it is mandatory

```yaml
POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
```

The port is only published on `127.0.0.1`: nobody reaches the application directly from the internet, only the
reverse proxy installed on the server (which handles HTTPS)

```yaml
ports:
  - "127.0.0.1:${APP_PORT:-8080}:8080"
```

Container memory limit, replacing the old server's `-Xmx`. `MaxRAMPercentage` makes the JVM use 75% of that limit as
heap

```yaml
JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=75
...
deploy:
  resources:
    limits:
      memory: 512m
```

Log rotation. Without it, the container log file grows until the server disk is full

```yaml
logging:
  driver: json-file
  options:
    max-size: 10m
    max-file: "3"
```

`db` also gets `restart: unless-stopped`, so it comes back by itself if the server reboots.

### .env.prod.example

#### Full file

```bash
# Copy to the server as .env, next to docker-compose.yml: cp .env.prod.example .env
APP_IMAGE=ghcr.io/your-user/compose-app
# Commit hash of the running image. Updated by deploy.sh on every deploy.
APP_VERSION=replace-with-a-commit-hash
APP_PORT=8080
POSTGRES_DB=notes
POSTGRES_USER=app
POSTGRES_PASSWORD=change-me
```

### Preparing the server

Installs Docker (Ubuntu/Debian) and lets the user run Docker without `sudo`

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

Creates the project folder and sends **only** the compose file and the `.env` example. No source code goes to the
server

```bash
ssh user@new-server "mkdir -p ~/apps/compose-app"
scp deploy/docker-compose.prod.yml user@new-server:~/apps/compose-app/docker-compose.yml
scp deploy/.env.prod.example user@new-server:~/apps/compose-app/.env
```

On the server, edit `.env` with the version and real passwords, and protect the file

```bash
cd ~/apps/compose-app
nano .env
chmod 600 .env
```

### Starting and updating

Checks that every variable was resolved

```bash
docker compose config
```

Pulls the images and starts everything

```bash
docker compose pull
docker compose up -d --wait
docker compose ps
```

New version: change `APP_VERSION` in `.env` and run it again. Only the `app` container is recreated.
[Lesson 08](08-ci-cd-github-actions.md) automates this on every commit with `deploy.sh`

```bash
docker compose pull app
docker compose up -d --wait app
```

Going back to the previous version is the same command, with the old `APP_VERSION`.

### Reverse proxy

The old server's nginx can be reused: just point `proxy_pass` to the port published on `127.0.0.1`

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

With several projects on the same server, give each one a different `APP_PORT` (8080, 8081, ...) and a `server`
block per domain.

---

## Phase 7B — Deploy to Kubernetes

Kubernetes does not read `docker-compose.yml`, but every compose block has a direct equivalent. The image published
in Phase 6 is **the same**.

| docker-compose | Kubernetes | File |
| --- | --- | --- |
| `name:` (project) | `Namespace` | `namespace.yaml` |
| `environment:` without passwords | `ConfigMap` | `configmap.yaml` |
| `.env` with passwords | `Secret` (created outside Git) | `secret.example.yaml` |
| `db` service + volume | `StatefulSet` + `volumeClaimTemplates` + `Service` | `postgres.yaml` |
| `app` service | `Deployment` | `app.yaml` |
| service name on the network (`db`, `app`) | `Service` | `postgres.yaml`, `app.yaml` |
| `depends_on` + `condition` | `initContainers` | `app.yaml` |
| `healthcheck` | `readinessProbe`, `livenessProbe`, `startupProbe` | `app.yaml` |
| `deploy.resources.limits` | `resources` | `app.yaml` |
| `ports:` + reverse proxy | `Ingress` | `ingress.yaml` |
| `restart:` | automatic | — |
| `docker compose up` | `kubectl apply -k` | `kustomization.yaml` |

> The [Kompose](https://kompose.io) tool (`kompose convert -f docker-compose.yml`) generates manifests from a compose
> file. It is a good draft, but review the result: it does not create proper probes, `initContainers` or `Secret`.

### kustomization.yaml

#### Full file

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: compose-app

resources:
  - namespace.yaml
  - configmap.yaml
  - postgres.yaml
  - app.yaml
  - ingress.yaml

images:
  - name: compose-app
    newName: ghcr.io/your-user/compose-app
    newTag: 1.0.0
```

#### Explanation

Lists the files applied together and puts all of them in the `compose-app` namespace. With it, `kubectl apply -k`
works like `docker compose up`

```yaml
namespace: compose-app
resources:
  - namespace.yaml
  ...
```

Replaces the image name in every manifest. To release a new version, only `newTag` changes

```yaml
images:
  - name: compose-app
    newName: ghcr.io/your-user/compose-app
    newTag: 1.0.0
```

`secret.example.yaml` is **not** in the list on purpose: this way a `kubectl apply -k` (by hand or by the pipeline in
[lesson 08](08-ci-cd-github-actions.md)) never overwrites the cluster's real password.

### namespace.yaml

#### Full file

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: compose-app
```

#### Explanation

Groups the project resources, like the compose `name:`. Several projects share the same cluster, each in its own
namespace.

### secret.example.yaml

#### Full file

```yaml
# Example only, not part of kustomization.yaml: the CD pipeline must never overwrite the real secret.
# Create it once per cluster with `kubectl create secret` (or a secret manager such as
# Sealed Secrets, External Secrets or Vault). For a local test: kubectl apply -f secret.example.yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: compose-app
type: Opaque
stringData:
  POSTGRES_USER: app
  POSTGRES_PASSWORD: change-me
```

#### Explanation

Equivalent to the passwords in `.env`. `stringData` accepts plain text values; Kubernetes stores them as base64,
which is **not** encryption. The file is only an example for local tests. In production, create the secret once from
the terminal

```bash
kubectl -n compose-app create secret generic db-credentials \
  --from-literal=POSTGRES_USER=app \
  --from-literal=POSTGRES_PASSWORD='strong-password'
```

### configmap.yaml

#### Full file

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  POSTGRES_DB: notes
  SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/notes
  JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=75
```

#### Explanation

Equivalent to the `environment:` variables that are not secrets. The URL still uses `db` as host: on Kubernetes the
`Service` name is resolved by the cluster DNS, just like the service name in Compose.

### postgres.yaml

#### Full file

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db
spec:
  clusterIP: None
  selector:
    app: db
  ports:
    - port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
        - name: postgres
          image: postgres:18-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef:
                  name: app-config
                  key: POSTGRES_DB
          envFrom:
            - secretRef:
                name: db-credentials
          readinessProbe:
            exec:
              command: ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
            periodSeconds: 5
          volumeMounts:
            - name: db-data
              mountPath: /var/lib/postgresql
  volumeClaimTemplates:
    - metadata:
        name: db-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

#### Explanation

`Service` without an IP (`clusterIP: None`, called *headless*). Creates the name `db` on the cluster network,
pointing to the database pod

```yaml
kind: Service
metadata:
  name: db
spec:
  clusterIP: None
```

`StatefulSet` instead of `Deployment`: guarantees a fixed pod name (`db-0`) and the same disk even if the pod is
recreated

```yaml
kind: StatefulSet
```

Variables come from the `ConfigMap` (`POSTGRES_DB`) and from the `Secret` (every key of `db-credentials`, with
`envFrom`)

```yaml
env:
  - name: POSTGRES_DB
    valueFrom:
      configMapKeyRef: ...
envFrom:
  - secretRef:
      name: db-credentials
```

Equivalent to the compose `healthcheck`: the pod only receives connections once `pg_isready` passes

```yaml
readinessProbe:
  exec:
    command: ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
```

Equivalent to the `db-data` named volume: asks the cluster for a 1 GiB disk (`PersistentVolumeClaim`)

```yaml
volumeClaimTemplates:
  - metadata:
      name: db-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

> In production, consider a managed database (RDS, Cloud SQL, Azure Database). Then `postgres.yaml` goes away and only
> the `SPRING_DATASOURCE_URL` in the `ConfigMap` changes.

### app.yaml

#### Full file

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      initContainers:
        # Kubernetes has no depends_on: wait for the database before starting the app.
        - name: wait-for-db
          image: postgres:18-alpine
          command: ["sh", "-c", "until pg_isready -h db -p 5432; do echo waiting for db; sleep 2; done"]
      containers:
        - name: app
          image: compose-app
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: app-config
          env:
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: POSTGRES_USER
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: POSTGRES_PASSWORD
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            periodSeconds: 10
          startupProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            periodSeconds: 5
            failureThreshold: 30
---
apiVersion: v1
kind: Service
metadata:
  name: app
spec:
  selector:
    app: app
  ports:
    - port: 80
      targetPort: 8080
```

#### Explanation

`Deployment` with two replicas: Kubernetes keeps two pods running and replaces one at a time during updates, with no
downtime

```yaml
kind: Deployment
spec:
  replicas: 2
```

Replaces `depends_on`: the `initContainer` runs **before** the application and only finishes once the database
answers

```yaml
initContainers:
  - name: wait-for-db
    image: postgres:18-alpine
    command: ["sh", "-c", "until pg_isready -h db -p 5432; do echo waiting for db; sleep 2; done"]
```

The `compose-app` name is replaced by `images:` in `kustomization.yaml`

```yaml
image: compose-app
```

Loads every variable from the `ConfigMap` and maps the `Secret` keys to the names Spring Boot expects

```yaml
envFrom:
  - configMapRef:
      name: app-config
env:
  - name: SPRING_DATASOURCE_USERNAME
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: POSTGRES_USER
```

`requests` is what the pod reserves on the node; `limits` is the ceiling, like `deploy.resources.limits` in compose

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    memory: 512Mi
```

The compose `healthcheck` becomes three probes. Spring Boot Actuator detects it is running on Kubernetes and creates
the `/liveness` and `/readiness` endpoints by itself

| Probe | Question | On failure |
| --- | --- | --- |
| `startupProbe` | has the application finished starting? | waits (up to 30 × 5s) before running the others |
| `readinessProbe` | can it receive traffic now? | removes the pod from the `Service`, without restarting |
| `livenessProbe` | is the process stuck? | restarts the container |

Liveness does **not** check the database: if the database goes down, restarting the application solves nothing.

The `Service` gives the pods the name `app` and spreads requests across the replicas

```yaml
kind: Service
metadata:
  name: app
spec:
  ports:
    - port: 80
      targetPort: 8080
```

### ingress.yaml

#### Full file

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
spec:
  rules:
    - host: notes.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app
                port:
                  number: 80
```

#### Explanation

Replaces the server's nginx: receives the domain requests and forwards them to the `app` `Service`. It requires an
Ingress Controller in the cluster (ingress-nginx, Traefik). HTTPS is usually added with
[cert-manager](https://cert-manager.io).

### Deploy commands

Shows the final result, with namespace and image already replaced, without applying anything

```bash
kubectl kustomize deploy/k8s
```

Creates the namespace and the secret (first time only). For a local test, the example file is enough

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/secret.example.yaml
```

Applies all manifests

```bash
kubectl apply -k deploy/k8s
```

Follows the rollout

```bash
kubectl -n compose-app rollout status statefulset/db
kubectl -n compose-app rollout status deployment/app
kubectl -n compose-app get pods,svc,ingress,pvc
```

Application logs (from all replicas)

```bash
kubectl -n compose-app logs -f deployment/app
```

Tests without Ingress, forwarding the `Service` port to your machine

```bash
kubectl -n compose-app port-forward svc/app 8080:80
curl localhost:8080/notes
```

New version: change `newTag` in `kustomization.yaml` and apply. Kubernetes replaces the pods one by one.
[Lesson 08](08-ci-cd-github-actions.md) automates this on every commit

```bash
kubectl apply -k deploy/k8s
kubectl -n compose-app rollout status deployment/app
```

Goes back to the previous version

```bash
kubectl -n compose-app rollout undo deployment/app
```

---

## Phase 8 — Migrate the data

### Database

On the **old server**, create the dump. `--no-owner` avoids errors if the database user has another name on the
target, and `--clean --if-exists` lets you repeat the restore

```bash
pg_dump -U app -d notes --no-owner --clean --if-exists > notes.sql
```

Copy the dump to your machine or to the new server

```bash
scp user@old-server:~/notes.sql .
```

**Docker target**: start only the database, restore, then start the application. `-T` disables the interactive
terminal so the file can be redirected with `<`

```bash
docker compose up -d --wait db
docker compose exec -T db psql -U app -d notes < notes.sql
docker compose up -d --wait
```

After restoring, create a new record to check. If you get `duplicate key value violates unique constraint`, the
**sequence** is behind the data (common when data was inserted by hand or came from another database, such as
MySQL). Move the sequence past the highest id

```bash
docker compose exec db psql -U app -d notes -c "select setval('note_seq', (select max(id) from note))"
```

**Kubernetes target**: same process, running `psql` inside the `db-0` pod

```bash
kubectl -n compose-app exec -i db-0 -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < notes.sql
```

### Files (uploads)

For a **bind mount** on the Docker server, copy straight to the host folder

```bash
rsync -avz user@old-server:/var/lib/notes/uploads/ ~/apps/compose-app/uploads/
```

For a **named volume**, copy through a temporary container that mounts the volume

```bash
docker run --rm -v compose-app_uploads:/data -v "$PWD/uploads":/source alpine cp -a /source/. /data/
```

On **Kubernetes**, copy into the pod that mounts the volume

```bash
kubectl -n compose-app cp ./uploads <pod-name>:/app/uploads
```

---

## Phase 9 — Cutover and rollback plan

1. **Days before**: lower the DNS record TTL (for example, to 300 seconds) so the change propagates quickly.
2. **Rehearsal**: with the new environment up and a copy of the data, test the application through the IP or a
   temporary domain.
3. **Maintenance window**: stop the application on the old server (`sudo systemctl stop notes`) so no new data
   comes in.
4. **Final sync**: create a new dump and restore it on the target (Phase 8). Run the files `rsync` again.
5. **DNS switch**: point the domain to the new server (or to the cluster Ingress).
6. **Verification**: run the smoke tests, watch the logs and metrics.
7. **Rollback plan**: if something fails, point the DNS back and run `sudo systemctl start notes` on the old server.
   **Do not shut down** the old server for a few days.

Smoke tests after the cutover

```bash
curl -fsS https://notes.example.com/actuator/health
curl -fsS https://notes.example.com/notes
```

---

## Checklist per project

Copy it for every project being migrated:

```markdown
### <project name>

- [ ] Inventory filled in (runtime, command, ports, variables, secrets, database, files, cron, domain)
- [ ] Configuration read from environment variables; no hard-coded address or password
- [ ] Logs to stdout
- [ ] Health endpoint exposed
- [ ] Multi-stage Dockerfile, runtime version matching the inventory, unprivileged USER
- [ ] .dockerignore (including .env)
- [ ] Local docker-compose.yml starts the full environment
- [ ] Data restore tested locally
- [ ] Image published to the registry with a version (not latest)
- [ ] Docker target: docker-compose.prod.yml + .env on the server, reverse proxy configured
- [ ] Kubernetes target: manifests applied, Secret created outside Git, probes working
- [ ] CI/CD pipeline configured (lesson 08)
- [ ] Database backup configured in the new environment
- [ ] Cutover done, smoke tests passing
- [ ] Old server shut down after the safety period
```
