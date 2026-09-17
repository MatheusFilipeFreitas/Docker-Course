# 07 - Migração para Docker e Kubernetes

🌐 [English](../en/07-migrating-to-docker-and-kubernetes.md) · **Português (Brasil)**

Roteiro para tirar uma aplicação de um **servidor tradicional** (sem Docker: Java, Node ou nginx instalados
direto no sistema) e levá-la para um **servidor com Docker** ou para um **cluster Kubernetes**.

A ideia central: o `Dockerfile` e o `docker-compose.yml` viram a **documentação executável** de como a
aplicação roda. Depois que um projeto tem esses arquivos, trocar de servidor é copiar dois arquivos e rodar
um comando, e o mesmo roteiro serve para todos os projetos.

O exemplo usado do começo ao fim é a API da [aula 06](06-docker-compose.md), mas cada fase traz
modelos para outras stacks.

**Arquivos referenciados**

- [`examples/compose-app/Dockerfile`](../../examples/compose-app/Dockerfile)
- [`examples/compose-app/docker-compose.yml`](../../examples/compose-app/docker-compose.yml) (ambiente local)
- [`examples/compose-app/deploy/docker-compose.prod.yml`](../../examples/compose-app/deploy/docker-compose.prod.yml)
- [`examples/compose-app/deploy/.env.prod.example`](../../examples/compose-app/deploy/.env.prod.example)
- [`examples/compose-app/deploy/k8s/`](../../examples/compose-app/deploy/k8s/) (manifests do Kubernetes)

## Visão geral

```
 servidor antigo                         sua máquina                          destino
┌──────────────────┐   1. inventário   ┌──────────────────────┐  6. push   ┌────────────────────────┐
│ java -jar app.jar│ ────────────────► │ Dockerfile           │ ─────────► │ registry (Docker Hub,  │
│ postgres local   │   2. mapeamento   │ docker-compose.yml   │            │ GHCR, ECR...)          │
│ nginx            │   3. ajustes      │ 4-5. build e teste   │            └───────────┬────────────┘
│ systemd, cron    │                   └──────────────────────┘                        │ pull
└────────┬─────────┘                                                     ┌─────────────┴────────────┐
         │ 8. dados (pg_dump, rsync)                                     │ 7A. servidor com Docker  │
         └──────────────────────────────────────────────────────────────►│ 7B. cluster Kubernetes   │
                                                                         └─────────────┬────────────┘
                                                                         9. virada do DNS e rollback
```

| Fase | Resultado |
| --- | --- |
| 1. Inventário | lista de tudo que a aplicação usa no servidor atual |
| 2. Mapeamento | cada item do inventário associado a uma instrução Docker |
| 3. Preparar a aplicação | configuração por variável de ambiente, logs no terminal |
| 4. Dockerfile | imagem que roda a aplicação sem nada instalado no host |
| 5. docker-compose local | o servidor inteiro reproduzido na sua máquina |
| 6. Registry | imagem versionada e disponível para qualquer servidor |
| 7A. Servidor com Docker | deploy com `docker compose` |
| 7B. Kubernetes | deploy com manifests |
| 8. Dados | banco e arquivos copiados para o novo ambiente |
| 9. Virada | tráfego apontado para o novo ambiente, com plano de volta |

---

## Fase 1 — Inventário do servidor atual

Antes de escrever qualquer Dockerfile, descubra **tudo** que a aplicação usa. O que ficar de fora do
inventário é exatamente o que vai quebrar depois da migração.

### Como a aplicação é iniciada

Na maioria dos servidores Linux a aplicação é um serviço do `systemd`. O arquivo do serviço já responde
metade do inventário: usuário, pasta, variáveis, comando e política de reinício

```bash
systemctl list-units --type=service --state=running
systemctl cat notes.service
```

Exemplo do que costuma aparecer:

```ini
[Service]
User=notes
WorkingDirectory=/opt/notes
EnvironmentFile=/etc/notes/notes.env
ExecStart=/usr/bin/java -Xmx512m -jar /opt/notes/notes.jar --spring.config.additional-location=/etc/notes/
Restart=always
```

Sem `systemd`, procure o processo e a linha de comando completa

```bash
ps aux | grep -E "java|node|python"
cat /proc/<pid>/cmdline | tr '\0' ' '
```

### Versões de runtime

A imagem base do Dockerfile precisa usar a **mesma versão** que roda hoje

```bash
java -version
node --version
nginx -v
psql --version
```

### Variáveis de ambiente e arquivos de configuração

Variáveis do processo em execução (inclui as vindas do `EnvironmentFile`)

```bash
sudo cat /proc/<pid>/environ | tr '\0' '\n'
```

Arquivos de configuração que o processo tem abertos, e onde eles ficam

```bash
sudo ls -l /proc/<pid>/cwd
sudo lsof -p <pid> | grep -E "\.(properties|yml|yaml|json|conf|env)$"
```

### Portas e dependências de rede

Portas em que a aplicação escuta

```bash
sudo ss -tlnp
```

Conexões de saída: banco, cache, filas, APIs externas. Cada destino vira um serviço no Compose ou uma
variável de ambiente

```bash
sudo ss -tnp | grep <pid>
```

### Arquivos em disco

Pastas onde a aplicação **escreve**: uploads, relatórios gerados, logs. Tudo que for escrito e precisar
sobreviver vira volume

```bash
sudo lsof -p <pid> | grep -v -E "\.jar|\.so|/proc|/dev"
du -sh /opt/notes/* /var/lib/notes 2>/dev/null
```

### Tarefas agendadas, proxy e certificados

```bash
crontab -l -u notes
ls /etc/cron.d/
ls /etc/nginx/sites-enabled/ && cat /etc/nginx/sites-enabled/*
ls /etc/letsencrypt/live/ 2>/dev/null
```

### Planilha do inventário

Preencha uma tabela assim para cada projeto:

| Item | Servidor atual (exemplo) |
| --- | --- |
| Runtime | Java 25 |
| Artefato | `/opt/notes/notes.jar` (código-fonte no Git: sim/não) |
| Comando | `java -Xmx512m -jar notes.jar` |
| Usuário | `notes` |
| Porta | 8080, atrás do nginx na 443 |
| Configuração | `/etc/notes/notes.env`, `application.properties` |
| Segredos | senha do banco dentro do `notes.env` |
| Banco | Postgres 18 local, banco `notes` |
| Arquivos gravados | `/var/lib/notes/uploads` |
| Logs | `/var/log/notes/app.log` |
| Tarefas agendadas | `cron`: limpeza diária às 03h |
| Reinício automático | `Restart=always` |
| Domínio e TLS | `notes.example.com`, Let's Encrypt |

---

## Fase 2 — Mapear o servidor para Docker e Kubernetes

Cada linha do inventário tem um lugar certo no novo ambiente:

| No servidor atual | No Dockerfile | No docker-compose | No Kubernetes |
| --- | --- | --- | --- |
| Runtime instalado (`java`, `node`) | `FROM` | — | — |
| Build (`mvn package`, `npm run build`) | estágio de build (multi-stage) | `build:` (só local) | — |
| `ExecStart=` | `ENTRYPOINT` / `CMD` | `command:` | `command:` / `args:` |
| `User=` | `USER` | `user:` | `securityContext` |
| `WorkingDirectory=` | `WORKDIR` | `working_dir:` | `workingDir:` |
| Porta da aplicação | `EXPOSE` | `ports:` | `Service` + `Ingress` |
| `EnvironmentFile=` / variáveis | — (nunca na imagem) | `environment:` + `.env` | `ConfigMap` |
| Senhas | — (nunca na imagem) | `.env` fora do Git | `Secret` |
| Arquivo de configuração | `COPY` (se for igual em todo ambiente) | volume do arquivo | `ConfigMap` montado |
| Pasta de dados / uploads | — | volume nomeado | `PersistentVolumeClaim` |
| Logs em arquivo | — | logs no stdout + `logging:` | logs no stdout |
| `Restart=always` | — | `restart: unless-stopped` | padrão do `Deployment` |
| Postgres local | — | serviço `db` | `StatefulSet` ou banco gerenciado |
| Ordem de inicialização | — | `depends_on` + `healthcheck` | `initContainers` + probes |
| Monitoramento de saúde | `HEALTHCHECK` | `healthcheck:` | `readiness`/`liveness` probes |
| `-Xmx512m` e limite de memória | — | `deploy.resources.limits` | `resources.limits` |
| `cron` | — | cron do host ou serviço dedicado | `CronJob` |
| nginx + certificado | — | serviço de proxy (nginx, Caddy, Traefik) | `Ingress` + cert-manager |

---

## Fase 3 — Preparar a aplicação

Uma aplicação em container precisa seguir três regras. Quase todo problema de migração vem de uma delas.

### Configuração por variável de ambiente

A **mesma imagem** roda em todos os ambientes; só as variáveis mudam. Procure no código e na configuração
por endereços, caminhos e senhas fixos

```bash
grep -rn -E "localhost|127\.0\.0\.1|/opt/|/var/|password" src/main/resources/
```

No Spring Boot não é preciso alterar código: qualquer propriedade pode ser sobrescrita por variável de
ambiente, trocando `.` por `_` e usando maiúsculas

| Propriedade | Variável de ambiente |
| --- | --- |
| `spring.datasource.url` | `SPRING_DATASOURCE_URL` |
| `server.port` | `SERVER_PORT` |
| `app.upload.dir` | `APP_UPLOAD_DIR` |

Em Node, leia `process.env.DATABASE_URL` em vez de valores fixos.

### Logs no terminal (stdout)

O Docker e o Kubernetes coletam o que o processo escreve no **stdout**. Log em arquivo dentro do container
some quando o container é recriado. Remova configurações como `logging.file.name` e appenders de arquivo.

### Nada de estado local

Container é descartável: tudo gravado fora de um volume se perde no próximo deploy. Arquivos enviados por
usuários vão para um volume (ou, melhor, para um storage de objetos como S3). No Kubernetes, com mais de uma
réplica, cada pod tem o próprio disco, então sessão em memória e uploads em disco local não funcionam.

### Encerramento limpo e endpoint de saúde

O Docker envia `SIGTERM` para parar o container. A aplicação precisa ser o processo principal (forma exec do
`ENTRYPOINT`, com colchetes) para receber o sinal. No Spring Boot, ative também o encerramento gracioso e
exponha o health check

```properties
server.shutdown=graceful
management.endpoints.web.exposure.include=health
```

---

## Fase 4 — Escrever o Dockerfile

### Com código-fonte (o caso ideal)

O Dockerfile compila o projeto, e o servidor não precisa de Maven, JDK nem Node. É o modelo da
[aula 03](03-dockerfile.md), usado em `examples/compose-app/Dockerfile`:

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

### Sem código-fonte (só o `.jar` do servidor)

Projetos antigos às vezes só existem como o artefato no servidor. Dá para migrar mesmo assim
("lift and shift"): copie o `.jar` para a sua máquina e empacote só a execução. Use a **mesma versão** de
Java encontrada no inventário

```bash
scp usuario@servidor-antigo:/opt/notes/notes.jar .
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

### Modelos para outras stacks

Pontos de partida: ajuste as versões para as encontradas no inventário.

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

Para Next.js, ative `output: "standalone"` no `next.config.js` e copie `.next/standalone`, `.next/static` e
`public` para a imagem final, rodando `node server.js`.

**Angular (frontend estático servido pelo nginx)**

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/<nome-do-projeto>/browser /usr/share/nginx/html
EXPOSE 80
```

`nginx.conf` mínimo, redirecionando as rotas do Angular para o `index.html`:

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**Quarkus**: o projeto gerado já traz Dockerfiles prontos em `src/main/docker/` (JVM e nativo). Parta deles.

### Memória da JVM

No servidor antigo, o `-Xmx512m` fixava o heap. Em container, prefira definir o **limite do container** e
deixar a JVM calcular o heap proporcionalmente

```yaml
JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=75
```

### .dockerignore

Evita mandar `target/`, `node_modules/`, `.git/` e principalmente `.env` para dentro da imagem (veja a
[aula 03](03-dockerfile.md#dockerignore))

```
target/
node_modules/
dist/
.git/
.env
```

### Testando a imagem sozinha

```bash
docker build -t notes:teste .
docker run --rm -p 8080:8080 -e SPRING_DATASOURCE_URL=... notes:teste
```

---

## Fase 5 — Reproduzir o servidor com docker-compose

Antes de tocar em qualquer servidor, recrie o ambiente inteiro na sua máquina: aplicação, banco e demais
dependências do inventário. Se funcionar aqui, funciona no destino.

É o `docker-compose.yml` explicado na [aula 06](06-docker-compose.md):

```bash
cd "examples/compose-app"
docker compose up -d --build --wait
curl localhost:8080/notes
```

Use o **mesmo major** do banco do servidor antigo (`postgres:18-alpine` para Postgres 18). Um dump de uma
versão mais nova nem sempre restaura numa versão mais antiga.

Este é também o momento de testar a restauração dos dados (veja a [Fase 8](#fase-8--migrar-os-dados)) com
uma cópia do banco de produção.

---

## Fase 6 — Versionar e publicar a imagem

O servidor de destino não compila nada: ele **baixa** a imagem de um registry. Os comandos abaixo são o
processo manual; a [aula 08](08-ci-cd-github-actions.md) faz o mesmo pelo GitHub Actions,
publicando no GitHub Container Registry.

Autentica no registry (Docker Hub; para GitHub use `docker login ghcr.io`)

```bash
docker login
```

Gera a imagem com o nome do registry e uma **versão**. Nunca faça deploy de `latest`: não dá para saber o
que está rodando nem voltar para a versão anterior

```bash
docker build -t docker.io/<usuario>/compose-app:1.0.0 .
```

Uma alternativa comum é usar o hash do commit como versão

```bash
docker build -t docker.io/<usuario>/compose-app:$(git rev-parse --short HEAD) .
```

Se o servidor tem arquitetura diferente da sua máquina (Mac com Apple Silicon → servidor AMD64), gere para as
duas

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t docker.io/<usuario>/compose-app:1.0.0 --push .
```

Envia ao registry

```bash
docker push docker.io/<usuario>/compose-app:1.0.0
```

---

## Fase 7A — Deploy em servidor com Docker

O compose de produção é diferente do local: não tem `build`, não monta código-fonte e é mais rígido com
senhas, memória e logs.

### docker-compose.prod.yml

#### Arquivo completo

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

#### O que muda em relação ao compose local

Não existe `build`: a imagem vem do registry, com nome e versão definidos no `.env`. O `:?` faz o Compose
**parar com erro** se a variável não existir, em vez de subir com um valor errado

```yaml
image: ${APP_IMAGE:?set APP_IMAGE in .env}:${APP_VERSION:?set APP_VERSION in .env}
```

A senha do banco não tem valor padrão: é obrigatória

```yaml
POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
```

A porta é publicada só em `127.0.0.1`: ninguém acessa a aplicação direto pela internet, apenas o proxy
reverso instalado no servidor (que cuida do HTTPS)

```yaml
ports:
  - "127.0.0.1:${APP_PORT:-8080}:8080"
```

Limite de memória do container, substituindo o `-Xmx` do servidor antigo. O `MaxRAMPercentage` faz a JVM
usar 75% desse limite como heap

```yaml
JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=75
...
deploy:
  resources:
    limits:
      memory: 512m
```

Rotação de logs. Sem isso, o arquivo de log do container cresce até encher o disco do servidor

```yaml
logging:
  driver: json-file
  options:
    max-size: 10m
    max-file: "3"
```

O `db` também ganha `restart: unless-stopped`, para voltar sozinho se o servidor reiniciar.

### .env.prod.example

#### Arquivo completo

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

### Preparando o servidor

Instala o Docker (Ubuntu/Debian) e libera o usuário para usar o Docker sem `sudo`

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

Cria a pasta do projeto e envia **apenas** o compose e o exemplo de `.env`. Nenhum código-fonte vai para o
servidor

```bash
ssh usuario@servidor-novo "mkdir -p ~/apps/compose-app"
scp deploy/docker-compose.prod.yml usuario@servidor-novo:~/apps/compose-app/docker-compose.yml
scp deploy/.env.prod.example usuario@servidor-novo:~/apps/compose-app/.env
```

No servidor, edita o `.env` com a versão e as senhas reais e protege o arquivo

```bash
cd ~/apps/compose-app
nano .env
chmod 600 .env
```

### Subindo e atualizando

Confere se todas as variáveis foram resolvidas

```bash
docker compose config
```

Baixa as imagens e sobe tudo

```bash
docker compose pull
docker compose up -d --wait
docker compose ps
```

Nova versão: altere o `APP_VERSION` no `.env` e rode de novo. Só o container do `app` é recriado. A
[aula 08](08-ci-cd-github-actions.md) automatiza isso a cada commit com o `deploy.sh`

```bash
docker compose pull app
docker compose up -d --wait app
```

Voltar para a versão anterior é o mesmo comando, com o `APP_VERSION` antigo.

### Proxy reverso

O nginx do servidor antigo pode ser reaproveitado: basta apontar o `proxy_pass` para a porta publicada em
`127.0.0.1`

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Com vários projetos no mesmo servidor, dê um `APP_PORT` diferente para cada um (8080, 8081, ...) e um bloco
`server` por domínio.

---

## Fase 7B — Deploy em Kubernetes

O Kubernetes não lê `docker-compose.yml`, mas cada bloco do compose tem um equivalente direto. A imagem
publicada na Fase 6 é **a mesma**.

| docker-compose | Kubernetes | Arquivo |
| --- | --- | --- |
| `name:` (projeto) | `Namespace` | `namespace.yaml` |
| `environment:` sem senha | `ConfigMap` | `configmap.yaml` |
| `.env` com senhas | `Secret` (criado fora do Git) | `secret.example.yaml` |
| serviço `db` + volume | `StatefulSet` + `volumeClaimTemplates` + `Service` | `postgres.yaml` |
| serviço `app` | `Deployment` | `app.yaml` |
| nome do serviço na rede (`db`, `app`) | `Service` | `postgres.yaml`, `app.yaml` |
| `depends_on` + `condition` | `initContainers` | `app.yaml` |
| `healthcheck` | `readinessProbe`, `livenessProbe`, `startupProbe` | `app.yaml` |
| `deploy.resources.limits` | `resources` | `app.yaml` |
| `ports:` + proxy reverso | `Ingress` | `ingress.yaml` |
| `restart:` | automático | — |
| `docker compose up` | `kubectl apply -k` | `kustomization.yaml` |

> A ferramenta [Kompose](https://kompose.io) (`kompose convert -f docker-compose.yml`) gera manifests a partir
> de um compose. É um bom rascunho, mas revise o resultado: ela não cria probes adequadas, `initContainers`
> nem `Secret`.

### kustomization.yaml

#### Arquivo completo

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

#### Explicação

Lista os arquivos aplicados juntos e coloca todos no namespace `compose-app`. Com isso, `kubectl apply -k`
funciona como o `docker compose up`

```yaml
namespace: compose-app
resources:
  - namespace.yaml
  ...
```

Troca o nome da imagem em todos os manifests. Para publicar uma nova versão, só o `newTag` muda

```yaml
images:
  - name: compose-app
    newName: ghcr.io/your-user/compose-app
    newTag: 1.0.0
```

O `secret.example.yaml` **não** está na lista de propósito: assim um `kubectl apply -k` (feito à mão ou pelo
pipeline da [aula 08](08-ci-cd-github-actions.md)) nunca sobrescreve a senha real do cluster.

### namespace.yaml

#### Arquivo completo

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: compose-app
```

#### Explicação

Agrupa os recursos do projeto, assim como o `name:` do compose. Vários projetos convivem no mesmo cluster,
cada um no seu namespace.

### secret.example.yaml

#### Arquivo completo

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

#### Explicação

Equivale às senhas do `.env`. O `stringData` aceita o valor em texto; o Kubernetes guarda em base64, o que
**não** é criptografia. O arquivo serve só de exemplo para testes locais. Em produção, crie o secret uma única
vez pelo terminal

```bash
kubectl -n compose-app create secret generic db-credentials \
  --from-literal=POSTGRES_USER=app \
  --from-literal=POSTGRES_PASSWORD='senha-forte'
```

### configmap.yaml

#### Arquivo completo

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

#### Explicação

Equivale às variáveis do `environment:` que não são segredo. A URL continua usando `db` como host: no
Kubernetes, o nome do `Service` é resolvido pelo DNS do cluster, igual ao nome do serviço no Compose.

### postgres.yaml

#### Arquivo completo

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

#### Explicação

`Service` sem IP (`clusterIP: None`, chamado de *headless*). Cria o nome `db` na rede do cluster apontando
para o pod do banco

```yaml
kind: Service
metadata:
  name: db
spec:
  clusterIP: None
```

`StatefulSet` em vez de `Deployment`: garante nome fixo para o pod (`db-0`) e o mesmo disco mesmo se o pod
for recriado

```yaml
kind: StatefulSet
```

As variáveis vêm do `ConfigMap` (`POSTGRES_DB`) e do `Secret` (todas as chaves de `db-credentials`, com
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

Equivalente ao `healthcheck` do compose: o pod só recebe conexões quando o `pg_isready` passa

```yaml
readinessProbe:
  exec:
    command: ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\""]
```

Equivalente ao volume nomeado `db-data`: pede ao cluster um disco de 1 GiB (`PersistentVolumeClaim`)

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

> Em produção, considere um banco gerenciado (RDS, Cloud SQL, Azure Database). Aí o `postgres.yaml` sai e só
> o `SPRING_DATASOURCE_URL` do `ConfigMap` muda.

### app.yaml

#### Arquivo completo

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

#### Explicação

`Deployment` com duas réplicas: o Kubernetes mantém dois pods rodando e troca um de cada vez nas atualizações,
sem indisponibilidade

```yaml
kind: Deployment
spec:
  replicas: 2
```

Substitui o `depends_on`: o `initContainer` roda **antes** da aplicação e só termina quando o banco responde

```yaml
initContainers:
  - name: wait-for-db
    image: postgres:18-alpine
    command: ["sh", "-c", "until pg_isready -h db -p 5432; do echo waiting for db; sleep 2; done"]
```

O nome `compose-app` é trocado pelo `images:` do `kustomization.yaml`

```yaml
image: compose-app
```

Carrega todas as variáveis do `ConfigMap` e mapeia as chaves do `Secret` para os nomes que o Spring Boot espera

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

`requests` é o que o pod reserva no nó; `limits` é o teto, igual ao `deploy.resources.limits` do compose

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    memory: 512Mi
```

O `healthcheck` do compose vira três probes. O Spring Boot Actuator detecta que está no Kubernetes e cria os
endpoints `/liveness` e `/readiness` sozinho

| Probe | Pergunta | Se falhar |
| --- | --- | --- |
| `startupProbe` | a aplicação já terminou de subir? | espera (até 30 × 5s) antes de checar as outras |
| `readinessProbe` | pode receber tráfego agora? | tira o pod do `Service`, sem reiniciar |
| `livenessProbe` | o processo travou? | reinicia o container |

A liveness **não** verifica o banco: se o banco cair, reiniciar a aplicação não resolve nada.

O `Service` dá o nome `app` aos pods e distribui as requisições entre as réplicas

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

#### Arquivo completo

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

#### Explicação

Substitui o nginx do servidor: recebe as requisições do domínio e encaminha para o `Service` `app`. Precisa de
um Ingress Controller no cluster (ingress-nginx, Traefik). O HTTPS normalmente é adicionado com o
[cert-manager](https://cert-manager.io).

### Comandos do deploy

Confere o resultado final, com o namespace e a imagem já substituídos, sem aplicar nada

```bash
kubectl kustomize deploy/k8s
```

Cria o namespace e o secret (só na primeira vez). Para um teste local, o arquivo de exemplo serve

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/secret.example.yaml
```

Aplica todos os manifests

```bash
kubectl apply -k deploy/k8s
```

Acompanha a subida

```bash
kubectl -n compose-app rollout status statefulset/db
kubectl -n compose-app rollout status deployment/app
kubectl -n compose-app get pods,svc,ingress,pvc
```

Logs da aplicação (de todas as réplicas)

```bash
kubectl -n compose-app logs -f deployment/app
```

Testa sem Ingress, redirecionando a porta do `Service` para a sua máquina

```bash
kubectl -n compose-app port-forward svc/app 8080:80
curl localhost:8080/notes
```

Nova versão: altere o `newTag` no `kustomization.yaml` e aplique. O Kubernetes substitui os pods um a um.
A [aula 08](08-ci-cd-github-actions.md) automatiza isso a cada commit

```bash
kubectl apply -k deploy/k8s
kubectl -n compose-app rollout status deployment/app
```

Volta para a versão anterior

```bash
kubectl -n compose-app rollout undo deployment/app
```

---

## Fase 8 — Migrar os dados

### Banco de dados

No **servidor antigo**, gera o dump. `--no-owner` evita erro caso o usuário do banco tenha outro nome no destino,
e `--clean --if-exists` permite repetir a restauração

```bash
pg_dump -U app -d notes --no-owner --clean --if-exists > notes.sql
```

Copia o dump para a sua máquina ou para o servidor novo

```bash
scp usuario@servidor-antigo:~/notes.sql .
```

**Destino Docker**: sobe só o banco, restaura e depois sobe a aplicação. O `-T` desliga o terminal interativo
para permitir o redirecionamento do arquivo com `<`

```bash
docker compose up -d --wait db
docker compose exec -T db psql -U app -d notes < notes.sql
docker compose up -d --wait
```

Depois de restaurar, crie um registro novo para conferir. Se aparecer `duplicate key value violates unique
constraint`, a **sequence** ficou atrás dos dados (comum quando os dados foram inseridos à mão ou vieram de
outro banco, como MySQL). Avance a sequence para depois do maior id

```bash
docker compose exec db psql -U app -d notes -c "select setval('note_seq', (select max(id) from note))"
```

**Destino Kubernetes**: mesmo processo, executando o `psql` dentro do pod `db-0`

```bash
kubectl -n compose-app exec -i db-0 -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < notes.sql
```

### Arquivos (uploads)

Para um **bind mount** no servidor Docker, copie direto para a pasta do host

```bash
rsync -avz usuario@servidor-antigo:/var/lib/notes/uploads/ ~/apps/compose-app/uploads/
```

Para um **volume nomeado**, copie usando um container temporário que monta o volume

```bash
docker run --rm -v compose-app_uploads:/dados -v "$PWD/uploads":/origem alpine cp -a /origem/. /dados/
```

No **Kubernetes**, copie para dentro do pod que monta o volume

```bash
kubectl -n compose-app cp ./uploads <nome-do-pod>:/app/uploads
```

---

## Fase 9 — Virada e plano de volta

1. **Dias antes**: reduza o TTL do registro DNS (por exemplo, para 300 segundos), para a troca propagar rápido.
2. **Ensaio**: com o novo ambiente no ar e uma cópia dos dados, teste a aplicação acessando pelo IP ou por um
   domínio temporário.
3. **Janela de manutenção**: pare a aplicação no servidor antigo (`sudo systemctl stop notes`) para que não
   entrem dados novos.
4. **Sincronização final**: gere um dump novo e restaure no destino (Fase 8). Repita o `rsync` dos arquivos.
5. **Troca do DNS**: aponte o domínio para o servidor novo (ou para o Ingress do cluster).
6. **Verificação**: rode os testes de fumaça, acompanhe os logs e as métricas.
7. **Plano de volta**: se algo falhar, aponte o DNS de volta e rode `sudo systemctl start notes` no servidor
   antigo. **Não desligue** o servidor antigo por alguns dias.

Testes de fumaça depois da virada

```bash
curl -fsS https://notes.example.com/actuator/health
curl -fsS https://notes.example.com/notes
```

---

## Checklist por projeto

Copie para cada projeto a ser migrado:

```markdown
### <nome do projeto>

- [ ] Inventário preenchido (runtime, comando, portas, variáveis, segredos, banco, arquivos, cron, domínio)
- [ ] Configuração lida de variáveis de ambiente; nenhum endereço ou senha fixo
- [ ] Logs no stdout
- [ ] Endpoint de saúde exposto
- [ ] Dockerfile multi-stage, com versão de runtime igual à do inventário e USER sem privilégios
- [ ] .dockerignore (inclui .env)
- [ ] docker-compose.yml local sobe o ambiente completo
- [ ] Restauração dos dados testada localmente
- [ ] Imagem publicada no registry com versão (não latest)
- [ ] Destino Docker: docker-compose.prod.yml + .env no servidor, proxy reverso configurado
- [ ] Destino Kubernetes: manifests aplicados, Secret criado fora do Git, probes funcionando
- [ ] Pipeline de CI/CD configurado (aula 08)
- [ ] Backup do banco no novo ambiente configurado
- [ ] Virada feita, testes de fumaça ok
- [ ] Servidor antigo desligado após o período de segurança
```
