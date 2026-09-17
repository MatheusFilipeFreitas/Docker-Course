# 03 - Dockerfile

🌐 **English** · [Português (Brasil)](../pt-br/03-dockerfile.md)

**Production** image of the example application: it compiles the project and produces a small image containing
only the JRE and the `.jar`.

**Referenced files**

- [`examples/first-app/Dockerfile`](../../examples/first-app/Dockerfile)
- [`examples/first-app/.dockerignore`](../../examples/first-app/.dockerignore)

## Full file

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25 AS build

WORKDIR /app

# Dependency layer: only re-downloads when pom.xml changes.
COPY pom.xml .
RUN mvn -B dependency:go-offline

COPY src ./src
RUN mvn -B package

FROM eclipse-temurin:25-jre-alpine

WORKDIR /app

# Run the application as an unprivileged user instead of root.
RUN addgroup -S app && adduser -S app -G app

COPY --from=build /app/target/*.jar app.jar

USER app

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
```

## Stage 1: build

Sets the base image and names the stage (`build`), so it can be referenced later. The `maven` image ships the full
JDK and Maven, needed to compile

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25 AS build
```

Sets the working directory for the following instructions (like a `cd` that persists). Declared at the top, it
allows relative paths in `COPY` and `RUN`

```dockerfile
WORKDIR /app
```

Copies only `pom.xml` from the build context (your machine) to `/app` and downloads the dependencies

```dockerfile
COPY pom.xml .
RUN mvn -B dependency:go-offline
```

Copies the source code and builds the `.jar` in `/app/target`. `-B` (batch mode) keeps Maven's log clean, without
progress bars

```dockerfile
COPY src ./src
RUN mvn -B package
```

### Layer cache

Each instruction creates a layer, and Docker reuses from cache every layer up to the first one that changed. That
is why order matters: what rarely changes goes first, what often changes goes last.

Editing a `.java` file only invalidates `COPY src` and `mvn package`: the downloaded dependencies stay in the cache.
If `src` were copied before `pom.xml`, any code change would download everything again.

## Stage 2: final image

Starts a **new** image from a base that only has the JRE (no Maven, no JDK). Everything done in the previous stage
is left behind, except what is explicitly copied

```dockerfile
FROM eclipse-temurin:25-jre-alpine

WORKDIR /app
```

Creates a system (`-S`) group and user named `app`. By default the container process runs as `root`: if the
application is compromised, the attacker has full permissions inside the container

```dockerfile
RUN addgroup -S app && adduser -S app -G app
```

Copies the `.jar` from the `build` stage instead of from your machine. The `*.jar` wildcard keeps the build working
when the version in `pom.xml` changes

```dockerfile
COPY --from=build /app/target/*.jar app.jar
```

Switches the user that runs the container process. It comes after `RUN addgroup` because creating users requires
`root`

```dockerfile
USER app
```

Documents which port the process listens on inside the container. It does **not** publish the port: that is done
with `docker run -p`

```dockerfile
EXPOSE 8080
```

Defines the executable that runs when the container starts

```dockerfile
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Why multi-stage

Only the `.jar` crosses over to the final image. Source code, Maven and the dependency repository stay in the
build stage, so the final image is much smaller.

### CMD vs ENTRYPOINT

`ENTRYPOINT` defines the container's fixed executable. `CMD` defines a default command that is **replaced** by any
argument passed to `docker run`

```dockerfile
CMD ["java", "-jar", "app.jar"]
```

```bash
docker run first-app:1.0 sh   # with CMD: runs `sh` instead of the application
```

Used together, `CMD` becomes the default arguments of `ENTRYPOINT`

```dockerfile
ENTRYPOINT ["java", "-jar", "app.jar"]
CMD ["--server.port=8080"]
```

## .dockerignore

Before building, Docker sends the given folder (the `.` in `docker build`) to the daemon: this is the **build
context**. `.dockerignore` removes files from it, using the same syntax as `.gitignore`

```
target/
.git/
.idea/
.vscode/
.devcontainer/
*.iml
HELP.md
README.md
```

This makes the build faster, avoids invalidating the cache because of irrelevant files and prevents local files
(such as an old `target/`) from ending up in the image through a `COPY`.

## Terminal commands

All of them run inside the `examples/first-app` folder.

Builds the image from the Dockerfile in the current directory

```bash
docker build -t first-app:1.0 .
```

Runs the image publishing container port 8080 on port 8080 of your machine. Test it at
<http://localhost:8080/hello>

```bash
docker run --rm -p 8080:8080 first-app:1.0
```

Runs in the background (detached mode), with a container name

```bash
docker run -d --name first-app -p 8080:8080 first-app:1.0
```

Checks which user runs the process (it should print `app`)

```bash
docker run --rm --entrypoint whoami first-app:1.0
```

Shows the image layers and the size of each one

```bash
docker image history first-app:1.0
```

Compares the size of the final image with the build image

```bash
docker images
```

Stops and removes the container, then the image

```bash
docker rm -f first-app
docker rmi first-app:1.0
```
