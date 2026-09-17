# 05 - VS Code Dev Containers

🌐 **English** · [Português (Brasil)](../pt-br/05-vscode-dev-containers.md)

Developing **inside the container** with VS Code: the editor runs on macOS, but Java, Maven, the terminal and the
debugger run in the container. Java and Maven do not need to be installed on your machine.

Requires the **Dev Containers** extension (`ms-vscode-remote.remote-containers`) in VS Code.

**Referenced files**

- [`examples/first-app/.devcontainer/devcontainer.json`](../../examples/first-app/.devcontainer/devcontainer.json)
- [`examples/first-app/.devcontainer/docker-compose.extend.yml`](../../examples/first-app/.devcontainer/docker-compose.extend.yml)
- [`examples/first-app/.vscode/launch.json`](../../examples/first-app/.vscode/launch.json)
- reuses `Dockerfile.dev` and `docker-compose.yml` from [lesson 04](04-dockerfile-dev.md)

## How it works

VS Code is split in two: the **UI** stays on macOS and the **VS Code Server** (Java Language Server, terminal,
`mvn`, debugger) runs inside the container.

```
macOS: VS Code window  <-->  container: VS Code Server + JDK 25 + Maven
                  ./  --mounted-->  /app
```

---

## devcontainer.json

### Full file

```json
{
  "name": "first-app (Spring Boot + Maven)",
  "dockerComposeFile": [
    "../docker-compose.yml",
    "docker-compose.extend.yml"
  ],
  "service": "app",
  "workspaceFolder": "/app",
  "shutdownAction": "stopCompose",
  "forwardPorts": [8080, 35729, 5005],
  "portsAttributes": {
    "8080": { "label": "application", "onAutoForward": "notify" },
    "35729": { "label": "devtools livereload" },
    "5005": { "label": "jvm debug" }
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "vscjava.vscode-java-pack",
        "vmware.vscode-boot-dev-pack",
        "ms-azuretools.vscode-docker",
        "redhat.vscode-xml"
      ],
      "settings": {
        "java.configuration.updateBuildConfiguration": "automatic",
        "java.compile.nullAnalysis.mode": "automatic",
        "java.autobuild.enabled": true,
        "java.jdt.ls.java.home": "/opt/java/openjdk",
        "maven.executable.path": "/usr/share/maven/bin/mvn",
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  },
  "postCreateCommand": "mvn -B -q dependency:go-offline",
  "remoteUser": "root"
}
```

### Explanation

Name shown in the bottom-left corner of VS Code when the window is connected to the container

```json
"name": "first-app (Spring Boot + Maven)"
```

Points to the Compose files. The second one is merged on top of the first, so the Dev Container reuses exactly the
same service used by `docker compose up`

```json
"dockerComposeFile": [
  "../docker-compose.yml",
  "docker-compose.extend.yml"
]
```

Tells VS Code which Compose service to open and which folder inside the container is the workspace (the same as the
`./:/app` bind mount)

```json
"service": "app",
"workspaceFolder": "/app"
```

Stops the Compose environment when the VS Code window is closed

```json
"shutdownAction": "stopCompose"
```

Forwards the container ports to your machine and labels each one in the **Ports** tab. Port 8080 shows a
notification when the application starts

```json
"forwardPorts": [8080, 35729, 5005],
"portsAttributes": {
  "8080": { "label": "application", "onAutoForward": "notify" },
  ...
}
```

Extensions installed **inside** the container, not in your local VS Code

```json
"extensions": [
  "vscjava.vscode-java-pack",
  "vmware.vscode-boot-dev-pack",
  "ms-azuretools.vscode-docker",
  "redhat.vscode-xml"
]
```

VS Code settings that only apply inside the container. The paths point to where the
`maven:3.9.16-eclipse-temurin-25` image installs the JDK and Maven

```json
"java.jdt.ls.java.home": "/opt/java/openjdk",
"maven.executable.path": "/usr/share/maven/bin/mvn"
```

Command run only once, right after the container is created

```json
"postCreateCommand": "mvn -B -q dependency:go-offline"
```

User the VS Code Server runs as inside the container. The Maven image only has `root`

```json
"remoteUser": "root"
```

---

## docker-compose.extend.yml

### Full file

```yaml
# Overrides applied only when the project is opened as a VS Code Dev Container.
# VS Code keeps the container alive itself and the Java extension compiles on
# save, so the auto-run entrypoint is replaced by an idle command.
services:
  app:
    command: sleep infinity
```

### Explanation

Replaces the `CMD` from `Dockerfile.dev` with a process that just waits

```yaml
services:
  app:
    command: sleep infinity
```

Without it, the container would run `dev-entrypoint.sh`, and if Maven exited the container would die with it,
closing the VS Code window. With `sleep infinity` the container stays alive and you start the application.

Environment variables, ports and volumes do not need to be repeated here: Compose merges both files, so everything
that is not overridden still comes from `docker-compose.yml`.

---

## launch.json

### Full file

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "Attach to dev container (JDWP 5005)",
      "request": "attach",
      "hostName": "localhost",
      "port": 5005,
      "projectName": "docker"
    }
  ]
}
```

### Explanation

Attaches the VS Code debugger to a JVM that is already running (`attach`) instead of starting a new one. Port 5005
is opened by `-agentlib:jdwp` in `dev-entrypoint.sh` and published in `docker-compose.yml`

```json
"request": "attach",
"hostName": "localhost",
"port": 5005
```

---

## Hot reload in both modes

| | `docker compose up` (lesson 04) | Dev Container |
| --- | --- | --- |
| Detects the change | `dev-entrypoint.sh`, every 2s | Java Language Server, on save |
| Compiles | `mvn compile` | Eclipse JDT incremental compiler |
| Restarts | Spring DevTools | Spring DevTools |
| Time until visible | ~5–15s | ~1–2s |

## Workflow

Open the `examples/first-app` folder in VS Code and run, from the command palette (`Cmd+Shift+P`)

```
Dev Containers: Reopen in Container
```

Once inside the container, start the application from the integrated terminal

```bash
mvn spring-boot:run
```

Saving a `.java` file recompiles and restarts automatically. To debug, press `F5` and choose the
`Attach to dev container (JDWP 5005)` configuration.

After changing `devcontainer.json` or `Dockerfile.dev`, rebuild the container

```
Dev Containers: Rebuild Container
```

To go back to working on macOS

```
Dev Containers: Reopen Folder Locally
```

## Terminal commands

Run them in your Mac terminal, inside the `examples/first-app` folder.

Checks the containers created by the Dev Container (same Compose project)

```bash
docker compose ps
```

Shows the final file resulting from merging both Compose files, with `command: sleep infinity`

```bash
docker compose -f docker-compose.yml -f .devcontainer/docker-compose.extend.yml config
```

Opens a shell in the container from the Mac terminal, without VS Code

```bash
docker compose exec app bash
```

Tears down the environment if the VS Code window was closed without stopping the container

```bash
docker compose down
```
