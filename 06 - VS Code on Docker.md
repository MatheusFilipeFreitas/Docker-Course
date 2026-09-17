Desenvolvimento dentro do container pelo VS Code: `03 - first-app/.devcontainer/`.

Requer a extensão **Dev Containers** (`ms-vscode-remote.remote-containers`) instalada no VS Code.

## Como funciona

O VS Code se divide em duas partes: a **interface** continua no macOS e o **VS Code Server**
(Language Server do Java, terminal, `mvn`, debugger) roda dentro do container. Não é preciso ter
Java nem Maven instalados na máquina.

```
macOS: janela do VS Code  <-->  container: VS Code Server + JDK 25 + Maven
                    ./  --montado-->  /app
```

## devcontainer.json

Aponta para os arquivos do Compose. O segundo sobrescreve o primeiro, então o Dev Container reaproveita
exatamente o mesmo serviço usado pelo `docker compose up`

```json
"dockerComposeFile": [
  "../docker-compose.yml",
  "docker-compose.extend.yml"
]
```

Indica qual serviço do Compose o VS Code deve abrir, e qual pasta dentro do container é a pasta de trabalho

```json
"service": "app",
"workspaceFolder": "/app"
```

Encaminha as portas do container para a máquina, fazendo o VS Code avisar quando a aplicação sobe

```json
"forwardPorts": [8080, 35729, 5005]
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

Comando executado uma única vez, logo após o container ser criado

```json
"postCreateCommand": "mvn -B -q dependency:go-offline"
```

Encerra o ambiente do Compose ao fechar a janela do VS Code

```json
"shutdownAction": "stopCompose"
```

## docker-compose.extend.yml

Substitui o comando do container por um processo que só espera

```yaml
services:
  app:
    command: sleep infinity
```

Sem isso o container rodaria o `dev-entrypoint.sh`, e se o Maven encerrasse o container morreria junto,
derrubando a janela do VS Code. Com `sleep infinity` o container fica vivo e quem inicia a aplicação é você.

## Hot reload nos dois modos

| | `docker compose up` | Dev Container |
| --- | --- | --- |
| Detecta a mudança | `dev-entrypoint.sh`, a cada 2s | Language Server do Java, ao salvar |
| Compila | `mvn compile` | compilador incremental do Eclipse JDT |
| Reinicia | Spring DevTools | Spring DevTools |
| Tempo até refletir | ~5–15s | ~1–2s |

## Fluxo de uso

Abrir a pasta `03 - first-app` no VS Code e rodar, na paleta de comandos (`Cmd+Shift+P`)

```
Dev Containers: Reopen in Container
```

Já dentro do container, iniciar a aplicação pelo terminal integrado

```bash
mvn spring-boot:run
```

Salvar um `.java` recompila e reinicia sozinho. Para depurar, apertar `F5` e escolher a configuração
`Attach to dev container (JDWP 5005)` definida no `.vscode/launch.json`.

Após alterar o `devcontainer.json` ou o `Dockerfile.dev`, é preciso reconstruir

```
Dev Containers: Rebuild Container
```

Para voltar a trabalhar no macOS

```
Dev Containers: Reopen Folder Locally
```

## Comandos no terminal

Verifica os containers criados pelo Dev Container (mesmo projeto do Compose)

```bash
docker compose ps
```

Entra no container pelo terminal do Mac, sem passar pelo VS Code

```bash
docker compose exec app bash
```

Derruba o ambiente caso a janela do VS Code tenha sido fechada sem parar o container

```bash
docker compose down
```
