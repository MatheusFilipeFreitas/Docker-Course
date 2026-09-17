# 04 - Dockerfile.dev

🌐 **English** · [Português (Brasil)](../pt-br/04-dockerfile-dev.md)

**Development** environment with hot reload: the code on your machine is mounted inside the container and the
application restarts by itself on every change, with no `docker build`.

This lesson uses Docker Compose with a single service. Compose is covered in depth, with multiple services, in
lesson [06 - Docker Compose](06-docker-compose.md).

**Referenced files**

- [`examples/first-app/Dockerfile.dev`](../../examples/first-app/Dockerfile.dev)
- [`examples/first-app/docker-compose.yml`](../../examples/first-app/docker-compose.yml)
- [`examples/first-app/docker/dev-entrypoint.sh`](../../examples/first-app/docker/dev-entrypoint.sh)

---

## Dockerfile.dev

### Full file

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25

WORKDIR /app

# Dependency layer: only re-downloads when pom.xml changes.
COPY pom.xml /app/
RUN mvn -B dependency:go-offline

# Baseline sources; at runtime they are shadowed by the bind mount from the host.
COPY src /app/src
COPY docker/dev-entrypoint.sh /usr/local/bin/dev-entrypoint.sh
RUN chmod +x /usr/local/bin/dev-entrypoint.sh

# 8080 = app | 35729 = devtools livereload | 5005 = remote debug (JDWP)
EXPOSE 8080 35729 5005

CMD ["/usr/local/bin/dev-entrypoint.sh"]
```

### Explanation

Uses the Maven image as the final image (no multi-stage): in development the JDK and Maven must stay inside the
container to recompile the code

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25
```

Copies only `pom.xml` and downloads the dependencies. This layer is only rebuilt when `pom.xml` changes (same cache
technique as [lesson 03](03-dockerfile.md#layer-cache))

```dockerfile
COPY pom.xml /app/
RUN mvn -B dependency:go-offline
```

Copies the code and the startup script, and makes the script executable. The `src` copied here is only used if the
container runs without the bind mount: with Compose, it is covered by the local folder

```dockerfile
COPY src /app/src
COPY docker/dev-entrypoint.sh /usr/local/bin/dev-entrypoint.sh
RUN chmod +x /usr/local/bin/dev-entrypoint.sh
```

Documents the three ports of the development environment

```dockerfile
EXPOSE 8080 35729 5005
```

| Port | Purpose |
| --- | --- |
| 8080 | application |
| 35729 | Spring DevTools LiveReload |
| 5005 | remote debugger (JDWP) |

Instead of `java -jar`, the container runs the script that watches the code and recompiles. It uses `CMD` (not
`ENTRYPOINT`) so that [lesson 05](05-vscode-dev-containers.md) can replace the command with `sleep infinity`

```dockerfile
CMD ["/usr/local/bin/dev-entrypoint.sh"]
```

---

## docker-compose.yml

### Full file

```yaml
name: first-app

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "${APP_PORT:-8080}:8080"   # application (override: APP_PORT=8081 docker compose up)
      - "35729:35729" # devtools livereload
      - "5005:5005"   # remote debugger (JDWP)
    volumes:
      # Local code is mounted live: edits on the host trigger a recompile + restart.
      - ./:/app
      # Named volumes shadow the host folders so container builds and the local
      # Maven repository survive restarts without polluting the project dir.
      - app-target:/app/target
      - maven-repo:/root/.m2
    environment:
      SPRING_PROFILES_ACTIVE: dev
      # macOS/Windows bind mounts do not always emit inotify events; polling is reliable.
      SPRING_DEVTOOLS_RESTART_POLL_INTERVAL: 2s
      SPRING_DEVTOOLS_RESTART_QUIET_PERIOD: 1s
    stdin_open: true
    tty: true

volumes:
  app-target:
  maven-repo:
```

### Explanation

Sets the project name, used as a prefix for containers, networks and volumes

```yaml
name: first-app
```

Tells Compose to build the image from `Dockerfile.dev` instead of the default `Dockerfile`

```yaml
build:
  context: .
  dockerfile: Dockerfile.dev
```

Publishes the ports on your machine (`host:container`). `${APP_PORT:-8080}` reads the `APP_PORT` variable and uses
`8080` if it is not set, so the host port can change without editing the file

```yaml
ports:
  - "${APP_PORT:-8080}:8080"
  - "35729:35729"
  - "5005:5005"
```

**Bind mount**: mounts the project folder inside the container. This is what makes hot reload work: nothing is
copied, the container's `/app` **is** the local folder

```yaml
volumes:
  - ./:/app
```

**Named volumes** mounted on top of the bind mount. The container's `target/` is kept apart from your machine's
`target/` (avoiding conflicts between what the IDE compiles and what the container compiles), and the Maven
repository survives a `down` and `up`

```yaml
  - app-target:/app/target
  - maven-repo:/root/.m2
```

Environment variables read by Spring Boot. Polling is needed because bind mounts on macOS and Windows do not always
emit file change events. This is the only place where the profile and polling are configured: the process started
by `dev-entrypoint.sh` inherits these variables

```yaml
environment:
  SPRING_PROFILES_ACTIVE: dev
  SPRING_DEVTOOLS_RESTART_POLL_INTERVAL: 2s
  SPRING_DEVTOOLS_RESTART_QUIET_PERIOD: 1s
```

Equivalent to `-it` in `docker run`: keeps input open and allocates a terminal, so logs are colored and `Ctrl+C`
works

```yaml
stdin_open: true
tty: true
```

Declares the named volumes. Docker creates them and manages where they are stored

```yaml
volumes:
  app-target:
  maven-repo:
```

---

## dev-entrypoint.sh

`spring-boot-devtools` (declared in `pom.xml`) watches `target/classes` and restarts the Spring context when a
`.class` file changes. It does **not** compile `.java` files — this script does.

Compiles once and records the compilation time in a reference file

```bash
mvn -q compile
touch "$STAMP"
```

Starts the application in the background (`&`), opening port 5005 for the remote debugger

```bash
mvn spring-boot:run \
  -Dspring-boot.run.jvmArguments="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005" &
APP_PID=$!
```

Forwards the stop signal to the application. `docker compose down` and `Ctrl+C` send `SIGTERM` and `SIGINT` to the
container's main process (this script), which must stop the application

```bash
trap 'kill -TERM "$APP_PID" 2>/dev/null || true; exit 0' INT TERM
```

Every 2 seconds, looks for a file newer than the last compilation. When one is found, it runs `mvn compile`,
`target/classes` changes and DevTools restarts the application

```bash
find src pom.xml -newer "$STAMP" -type f ... -print -quit
```

The full flow: edit a file on your Mac → the file changes inside the container (bind mount) → `mvn compile` →
DevTools restarts. No `docker build`, no `docker restart`.

---

## Terminal commands

All of them run inside the `examples/first-app` folder.

Builds the image and starts the environment, keeping the logs on screen. Test it at <http://localhost:8080/hello>,
change the text in `HelloController.java` and reload the page

```bash
docker compose up --build
```

Starts in the background with another host port, in case 8080 is busy

```bash
APP_PORT=8081 docker compose up -d --build
```

Follows the logs of the `app` service (look for `[dev] change detected`)

```bash
docker compose logs -f app
```

Opens a shell inside the container and checks that `/app` is the local folder

```bash
docker compose exec app bash
ls /app
```

Lists the volumes created for the project

```bash
docker volume ls --filter name=first-app
```

Rebuilds the image without cache (useful after changing `Dockerfile.dev`)

```bash
docker compose build --no-cache
```

Tears down the environment, keeping the cache volumes

```bash
docker compose down
```

Tears down the environment and also removes the volumes (`target/` and `~/.m2`)

```bash
docker compose down -v
```
