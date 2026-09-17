# 05 - VS Code com Dev Containers

🌐 [English](../en/05-vscode-dev-containers.md) · **Português (Brasil)**

Desenvolvimento **dentro do container** pelo VS Code: o editor roda no macOS, mas o Java, o Maven, o
terminal e o debugger rodam no container. Não é preciso ter Java nem Maven instalados na máquina.

Requer a extensão **Dev Containers** (`ms-vscode-remote.remote-containers`) instalada no VS Code.

**Arquivos referenciados**

- [`examples/first-app/.devcontainer/devcontainer.json`](../../examples/first-app/.devcontainer/devcontainer.json)
- [`examples/first-app/.devcontainer/docker-compose.extend.yml`](../../examples/first-app/.devcontainer/docker-compose.extend.yml)
- [`examples/first-app/.vscode/launch.json`](../../examples/first-app/.vscode/launch.json)
- reaproveita o `Dockerfile.dev` e o `docker-compose.yml` da [aula 04](04-dockerfile-dev.md)

## Como funciona

O VS Code se divide em duas partes: a **interface** continua no macOS e o **VS Code Server**
(Language Server do Java, terminal, `mvn`, debugger) roda dentro do container.

```
macOS: janela do VS Code  <-->  container: VS Code Server + JDK 25 + Maven
                    ./  --montado-->  /app
```

---

## devcontainer.json

### Arquivo completo

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

### Explicação

Nome exibido no canto inferior esquerdo do VS Code quando a janela está conectada ao container

```json
"name": "first-app (Spring Boot + Maven)"
```

Aponta para os arquivos do Compose. O segundo é mesclado por cima do primeiro, então o Dev Container
reaproveita exatamente o mesmo serviço usado pelo `docker compose up`

```json
"dockerComposeFile": [
  "../docker-compose.yml",
  "docker-compose.extend.yml"
]
```

Indica qual serviço do Compose o VS Code deve abrir, e qual pasta dentro do container é a pasta de trabalho
(a mesma do bind mount `./:/app`)

```json
"service": "app",
"workspaceFolder": "/app"
```

Encerra o ambiente do Compose ao fechar a janela do VS Code

```json
"shutdownAction": "stopCompose"
```

Encaminha as portas do container para a máquina e dá um nome a cada uma na aba **Ports**. A 8080 avisa
com uma notificação quando a aplicação sobe

```json
"forwardPorts": [8080, 35729, 5005],
"portsAttributes": {
  "8080": { "label": "application", "onAutoForward": "notify" },
  ...
}
```

Extensões instaladas **dentro** do container, não no VS Code local

```json
"extensions": [
  "vscjava.vscode-java-pack",
  "vmware.vscode-boot-dev-pack",
  "ms-azuretools.vscode-docker",
  "redhat.vscode-xml"
]
```

Configurações do VS Code válidas só dentro do container. Os caminhos apontam para onde a imagem
`maven:3.9.16-eclipse-temurin-25` instala o JDK e o Maven

```json
"java.jdt.ls.java.home": "/opt/java/openjdk",
"maven.executable.path": "/usr/share/maven/bin/mvn"
```

Comando executado uma única vez, logo após o container ser criado

```json
"postCreateCommand": "mvn -B -q dependency:go-offline"
```

Usuário com que o VS Code Server roda dentro do container. A imagem do Maven só tem o `root`

```json
"remoteUser": "root"
```

---

## docker-compose.extend.yml

### Arquivo completo

```yaml
# Overrides applied only when the project is opened as a VS Code Dev Container.
# VS Code keeps the container alive itself and the Java extension compiles on
# save, so the auto-run entrypoint is replaced by an idle command.
services:
  app:
    command: sleep infinity
```

### Explicação

Substitui o `CMD` do `Dockerfile.dev` por um processo que só espera

```yaml
services:
  app:
    command: sleep infinity
```

Sem isso o container rodaria o `dev-entrypoint.sh`, e se o Maven encerrasse o container morreria junto,
derrubando a janela do VS Code. Com `sleep infinity` o container fica vivo e quem inicia a aplicação é você.

As variáveis de ambiente, portas e volumes não precisam ser repetidos aqui: o Compose mescla os dois
arquivos, então tudo que não é sobrescrito continua valendo do `docker-compose.yml`.

---

## launch.json

### Arquivo completo

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

### Explicação

Conecta o debugger do VS Code a uma JVM que já está rodando (`attach`), em vez de iniciar uma nova.
A porta 5005 é a aberta pelo `-agentlib:jdwp` no `dev-entrypoint.sh` e publicada no `docker-compose.yml`

```json
"request": "attach",
"hostName": "localhost",
"port": 5005
```

---

## Hot reload nos dois modos

| | `docker compose up` (aula 04) | Dev Container |
| --- | --- | --- |
| Detecta a mudança | `dev-entrypoint.sh`, a cada 2s | Language Server do Java, ao salvar |
| Compila | `mvn compile` | compilador incremental do Eclipse JDT |
| Reinicia | Spring DevTools | Spring DevTools |
| Tempo até refletir | ~5–15s | ~1–2s |

## Fluxo de uso

Abrir a pasta `examples/first-app` no VS Code e rodar, na paleta de comandos (`Cmd+Shift+P`)

```
Dev Containers: Reopen in Container
```

Já dentro do container, iniciar a aplicação pelo terminal integrado

```bash
mvn spring-boot:run
```

Salvar um `.java` recompila e reinicia sozinho. Para depurar, apertar `F5` e escolher a configuração
`Attach to dev container (JDWP 5005)`.

Após alterar o `devcontainer.json` ou o `Dockerfile.dev`, é preciso reconstruir

```
Dev Containers: Rebuild Container
```

Para voltar a trabalhar no macOS

```
Dev Containers: Reopen Folder Locally
```

## Comandos no terminal

Rodam no terminal do Mac, dentro da pasta `examples/first-app`.

Verifica os containers criados pelo Dev Container (mesmo projeto do Compose)

```bash
docker compose ps
```

Mostra o arquivo final resultante da mescla dos dois arquivos do Compose, com o `command: sleep infinity`

```bash
docker compose -f docker-compose.yml -f .devcontainer/docker-compose.extend.yml config
```

Entra no container pelo terminal do Mac, sem passar pelo VS Code

```bash
docker compose exec app bash
```

Derruba o ambiente caso a janela do VS Code tenha sido fechada sem parar o container

```bash
docker compose down
```
