# 08 - CI e CD com GitHub Actions

🌐 [English](../en/08-ci-cd-github-actions.md) · **Português (Brasil)**

Automatiza o que a [aula 07](07-migrating-to-docker-and-kubernetes.md) fazia à mão: cada commit
na `main` vira uma imagem no **GitHub Container Registry (GHCR)**, identificada pelo **hash do commit**, e o
servidor (Docker ou Kubernetes) baixa e passa a rodar essa versão automaticamente.

**Arquivos referenciados**

- [`examples/compose-app/.github/workflows/ci.yml`](../../examples/compose-app/.github/workflows/ci.yml)
- [`examples/compose-app/.github/workflows/cd.yml`](../../examples/compose-app/.github/workflows/cd.yml)
- [`examples/compose-app/deploy/deploy.sh`](../../examples/compose-app/deploy/deploy.sh)
- reaproveita o `Dockerfile`, o `deploy/docker-compose.prod.yml` e o `deploy/k8s/` das aulas anteriores

## Visão geral

```
 pull request ──► CI: docker build (sem publicar) ──► revisão e merge
                                                          │
 push na main ──► CD ─────────────────────────────────────┘
                   │
                   ├─ build ──► ghcr.io/<dono>/compose-app:<hash do commit>
                   │
                   ├─ deploy-docker      (DEPLOY_TARGET=docker)
                   │    ssh no servidor ─► deploy.sh <hash>
                   │                        ├─ .env: APP_VERSION=<hash>
                   │                        ├─ docker compose pull + up --wait
                   │                        └─ falhou? volta para o hash anterior
                   │
                   └─ deploy-kubernetes  (DEPLOY_TARGET=kubernetes)
                        kustomization.yaml: newTag=<hash>
                        kubectl apply -k + rollout status
                        falhou? kubectl rollout undo
```

---

## Por que o hash do commit como tag

| Tag | Problema ou vantagem |
| --- | --- |
| `latest` | muda a cada build: não dá para saber o que está rodando nem voltar para a versão anterior |
| `1.0.0` | alguém precisa lembrar de mudar o número a cada entrega |
| `3f9c2a1...` (hash) | gerada automaticamente, **nunca muda** e aponta para o código exato: `git show <hash>` |

Com tags que nunca mudam, "a versão mais recente" não é descoberta pelo servidor olhando o registry: é o
**pipeline** que diz ao servidor qual hash rodar. O fluxo completo é:

1. o commit `3f9c2a1` chega na `main`;
2. o GitHub Actions publica `ghcr.io/<dono>/compose-app:3f9c2a1...`;
3. o pipeline grava esse hash no servidor (`APP_VERSION` no `.env`, ou `newTag` no Kubernetes);
4. o servidor roda `docker compose pull` / o Kubernetes cria os pods novos, e **baixa a imagem daquele hash**.

Se o servidor reiniciar, o `restart: unless-stopped` (ou o Kubernetes) sobe de novo a **mesma** versão
gravada, sem depender do registry nem de um deploy novo. Voltar uma versão é só apontar para um hash anterior.

---

## Onde ficam os workflows

O GitHub só executa workflows em **`.github/workflows/` na raiz do repositório**. Num repositório próprio do
projeto, a estrutura fica

```
compose-app/                 ← raiz do repositório
├── .github/workflows/
│   ├── ci.yml
│   └── cd.yml
├── deploy/
│   ├── deploy.sh
│   ├── docker-compose.prod.yml
│   └── k8s/
├── Dockerfile
└── src/
```

Neste repositório do curso, a pasta está dentro de `examples/compose-app/` apenas como material de estudo, então
os workflows **não rodam**. Para usá-los num monorepo (vários projetos no mesmo repositório), veja
[Vários projetos no mesmo repositório](#vários-projetos-no-mesmo-repositório).

---

## GitHub Container Registry

O endereço das imagens é `ghcr.io/<dono>/<nome-da-imagem>:<tag>`.

- **Nome sempre em minúsculas**: o GHCR recusa `ghcr.io/MatheusFilipeFreitas/...`. O workflow converte o dono
  do repositório para minúsculas.
- **Autenticação no pipeline**: o próprio `GITHUB_TOKEN` do workflow publica a imagem, desde que o job tenha
  `permissions: packages: write`. Não é preciso criar token.
- **Visibilidade**: a imagem nasce **privada**. Para baixar no servidor, faça login com um token (veja
  [Preparar o servidor Docker](#preparar-o-servidor-docker)) ou torne o pacote público em
  *Profile → Packages → compose-app → Package settings*.
- **Ligação com o repositório**: o label `org.opencontainers.image.source` faz o pacote aparecer na página do
  repositório.

---

## ci.yml

### Arquivo completo

```yaml
# Continuous integration: every pull request must produce a working image.
# Nothing is pushed: this only proves the Dockerfile builds (and the tests inside it pass).
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: docker/setup-buildx-action@v3

      - name: Build image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Explicação

Roda em todo pull request aberto para a `main`

```yaml
on:
  pull_request:
    branches: [main]
```

Baixa o código do commit no runner (a máquina virtual do GitHub)

```yaml
- uses: actions/checkout@v5
```

Habilita o **Buildx**, o builder do Docker que suporta cache remoto e múltiplas arquiteturas

```yaml
- uses: docker/setup-buildx-action@v3
```

Faz o `docker build` sem publicar (`push: false`). Como o `Dockerfile` roda o `mvn package`, os testes do
projeto também rodam aqui: se falharem, o PR fica vermelho

```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    push: false
```

Guarda as camadas no cache do GitHub Actions (`gha`). O download das dependências do Maven só se repete quando o
`pom.xml` muda, a mesma lógica de cache da [aula 03](03-dockerfile.md#cache-de-camadas)

```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

---

## cd.yml

### Arquivo completo

```yaml
# Continuous delivery: every commit on main becomes an image tagged with the commit hash
# on the GitHub Container Registry, and is deployed to the target set in the DEPLOY_TARGET variable.
name: CD

on:
  push:
    branches: [main]
  workflow_dispatch:

# One deploy at a time; a newer commit waits for the running deploy to finish.
concurrency:
  group: deploy-production
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      image: ${{ steps.image.outputs.name }}
    steps:
      - uses: actions/checkout@v5

      # GHCR only accepts lowercase names, and the repository owner may contain uppercase letters.
      - name: Image name
        id: image
        run: echo "name=ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/compose-app" >> "$GITHUB_OUTPUT"

      - uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.image.outputs.name }}:${{ github.sha }}
          labels: |
            org.opencontainers.image.source=${{ github.server_url }}/${{ github.repository }}
            org.opencontainers.image.revision=${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-docker:
    if: vars.DEPLOY_TARGET == 'docker'
    needs: build
    runs-on: ubuntu-latest
    environment: production
    env:
      SERVER: ${{ secrets.SSH_USER }}@${{ secrets.SSH_HOST }}
      APP_DIR: ${{ vars.APP_DIR }}
    steps:
      - uses: actions/checkout@v5

      - name: Configure SSH
        env:
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
          SSH_KNOWN_HOSTS: ${{ secrets.SSH_KNOWN_HOSTS }}
        run: |
          mkdir -p ~/.ssh
          printf '%s\n' "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
          printf '%s\n' "$SSH_KNOWN_HOSTS" > ~/.ssh/known_hosts
          chmod 600 ~/.ssh/id_ed25519

      - name: Copy compose file and deploy script
        run: |
          scp deploy/docker-compose.prod.yml "$SERVER:$APP_DIR/docker-compose.yml"
          scp deploy/deploy.sh "$SERVER:$APP_DIR/deploy.sh"

      - name: Deploy
        run: |
          # The variables are expanded on the runner on purpose.
          # shellcheck disable=SC2029
          ssh "$SERVER" bash "$APP_DIR/deploy.sh" "$GITHUB_SHA"

  deploy-kubernetes:
    if: vars.DEPLOY_TARGET == 'kubernetes'
    needs: build
    runs-on: ubuntu-latest
    environment: production
    env:
      IMAGE: ${{ needs.build.outputs.image }}
    steps:
      - uses: actions/checkout@v5

      - uses: azure/setup-kubectl@v4

      - name: Configure kubeconfig
        env:
          KUBECONFIG_DATA: ${{ secrets.KUBECONFIG }}
        run: |
          mkdir -p ~/.kube
          printf '%s\n' "$KUBECONFIG_DATA" > ~/.kube/config
          chmod 600 ~/.kube/config

      - name: Point the manifests to the new image
        run: |
          sed -i "s|newName: .*|newName: $IMAGE|; s|newTag: .*|newTag: \"$GITHUB_SHA\"|" deploy/k8s/kustomization.yaml
          kubectl kustomize deploy/k8s | grep "image: $IMAGE"

      - name: Apply
        run: kubectl apply -k deploy/k8s

      - name: Wait for rollout (roll back on failure)
        run: |
          if ! kubectl -n compose-app rollout status deployment/app --timeout=300s; then
            kubectl -n compose-app rollout undo deployment/app
            exit 1
          fi
```

### Gatilhos e concorrência

Roda a cada push na `main` (inclusive merge de PR). O `workflow_dispatch` adiciona o botão **Run workflow** na
aba *Actions*, para refazer um deploy manualmente

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
```

Garante um deploy por vez. Se dois commits chegarem juntos, o segundo espera o primeiro terminar, em vez de os
dois mexerem no servidor ao mesmo tempo

```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: false
```

### Job build

Permissões do `GITHUB_TOKEN` neste job: ler o código e **publicar pacotes** no GHCR

```yaml
permissions:
  contents: read
  packages: write
```

Expõe o nome da imagem para os jobs de deploy

```yaml
outputs:
  image: ${{ steps.image.outputs.name }}
```

Monta o nome da imagem. `${GITHUB_REPOSITORY_OWNER,,}` é a sintaxe do bash para converter em minúsculas

```yaml
- name: Image name
  id: image
  run: echo "name=ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/compose-app" >> "$GITHUB_OUTPUT"
```

Login no GHCR com o token automático do workflow

```yaml
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

Constrói e publica. A tag é `github.sha`, o **hash completo do commit** que disparou o workflow. Os labels
registram na imagem de qual repositório e commit ela veio

```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ${{ steps.image.outputs.name }}:${{ github.sha }}
    labels: |
      org.opencontainers.image.source=${{ github.server_url }}/${{ github.repository }}
      org.opencontainers.image.revision=${{ github.sha }}
```

### Job deploy-docker

Só roda se a variável `DEPLOY_TARGET` do repositório for `docker`, e só depois do `build` terminar com sucesso

```yaml
deploy-docker:
  if: vars.DEPLOY_TARGET == 'docker'
  needs: build
```

Usa o **environment** `production` do GitHub: os segredos ficam guardados nele, e é possível exigir aprovação
manual antes do deploy (veja [Configuração no GitHub](#configuração-no-github))

```yaml
environment: production
```

Monta o endereço SSH a partir dos segredos e a pasta do projeto no servidor a partir de uma variável

```yaml
env:
  SERVER: ${{ secrets.SSH_USER }}@${{ secrets.SSH_HOST }}
  APP_DIR: ${{ vars.APP_DIR }}
```

Grava a chave privada e a impressão digital do servidor no runner. Os segredos passam por variáveis de ambiente
(e não direto no script com `${{ }}`), o que evita que um valor com caracteres especiais quebre ou altere o
comando. O `known_hosts` garante que o runner está falando com o servidor certo

```yaml
- name: Configure SSH
  env:
    SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
    SSH_KNOWN_HOSTS: ${{ secrets.SSH_KNOWN_HOSTS }}
  run: |
    mkdir -p ~/.ssh
    printf '%s\n' "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
    printf '%s\n' "$SSH_KNOWN_HOSTS" > ~/.ssh/known_hosts
    chmod 600 ~/.ssh/id_ed25519
```

Envia o compose e o script de deploy **a cada deploy**. Assim, mudanças na infraestrutura (uma variável nova,
um limite de memória) também são entregues por commit, sem ninguém editar arquivos no servidor

```yaml
- name: Copy compose file and deploy script
  run: |
    scp deploy/docker-compose.prod.yml "$SERVER:$APP_DIR/docker-compose.yml"
    scp deploy/deploy.sh "$SERVER:$APP_DIR/deploy.sh"
```

Executa o `deploy.sh` no servidor, passando o hash do commit

```yaml
- name: Deploy
  run: |
    # The variables are expanded on the runner on purpose.
    # shellcheck disable=SC2029
    ssh "$SERVER" bash "$APP_DIR/deploy.sh" "$GITHUB_SHA"
```

### Job deploy-kubernetes

Instala o `kubectl` no runner e grava o kubeconfig (credenciais de acesso ao cluster) vindo dos segredos

```yaml
- uses: azure/setup-kubectl@v4

- name: Configure kubeconfig
  env:
    KUBECONFIG_DATA: ${{ secrets.KUBECONFIG }}
  run: |
    mkdir -p ~/.kube
    printf '%s\n' "$KUBECONFIG_DATA" > ~/.kube/config
    chmod 600 ~/.kube/config
```

Troca a imagem e a tag no `kustomization.yaml` **só dentro do runner** (o arquivo no Git não muda). A tag vai
**entre aspas**: sem elas, um hash como `1e53...` ou só com dígitos é lido pelo YAML como número e o kustomize
recusa o arquivo. O `grep` confere se a substituição funcionou antes de aplicar

```yaml
- name: Point the manifests to the new image
  run: |
    sed -i "s|newName: .*|newName: $IMAGE|; s|newTag: .*|newTag: \"$GITHUB_SHA\"|" deploy/k8s/kustomization.yaml
    kubectl kustomize deploy/k8s | grep "image: $IMAGE"
```

Aplica **todos** os manifests, não só a imagem: uma mudança no `configmap.yaml` ou nas probes também é entregue
pelo commit. O `secret.example.yaml` fica fora do `kustomization.yaml` para que o pipeline nunca sobrescreva a
senha real

```yaml
- name: Apply
  run: kubectl apply -k deploy/k8s
```

Espera os pods novos ficarem prontos. Se não ficarem em 5 minutos (imagem inexistente, aplicação quebrando na
subida, probe falhando), volta o `Deployment` para a versão anterior e marca o job como falho

```yaml
- name: Wait for rollout (roll back on failure)
  run: |
    if ! kubectl -n compose-app rollout status deployment/app --timeout=300s; then
      kubectl -n compose-app rollout undo deployment/app
      exit 1
    fi
```

Enquanto os pods novos não ficam prontos, os antigos continuam atendendo: um deploy quebrado não derruba a
aplicação.

---

## deploy.sh

Roda **no servidor**, na pasta com o `docker-compose.yml` e o `.env`.

### Arquivo completo

```bash
#!/usr/bin/env bash
# Runs on the server, next to docker-compose.yml and .env.
# Usage: deploy.sh <image-tag>   (the CD pipeline passes the commit hash)
# Pins the new version in .env, pulls it and recreates the app. If the new container
# does not become healthy, the previous version is restored.
set -euo pipefail

NEW_VERSION="$1"
cd "$(dirname "$0")"

PREVIOUS_VERSION=$(grep '^APP_VERSION=' .env | cut -d= -f2)

set_version() {
  sed -i.bak "s/^APP_VERSION=.*/APP_VERSION=$1/" .env && rm -f .env.bak
}

echo "[deploy] $PREVIOUS_VERSION -> $NEW_VERSION"
set_version "$NEW_VERSION"

if docker compose pull app && docker compose up -d --wait --wait-timeout 180 app; then
  echo "[deploy] version $NEW_VERSION is healthy"
else
  echo "[deploy] version $NEW_VERSION failed, rolling back to $PREVIOUS_VERSION"
  set_version "$PREVIOUS_VERSION"
  docker compose up -d --wait --wait-timeout 180 app
  exit 1
fi
```

### Explicação

Para o script no primeiro erro (`-e`), em variável não definida (`-u`) ou em falha no meio de um pipe
(`pipefail`)

```bash
set -euo pipefail
```

Entra na pasta do próprio script, para funcionar independente de onde foi chamado

```bash
cd "$(dirname "$0")"
```

Guarda a versão que está rodando agora, para poder voltar

```bash
PREVIOUS_VERSION=$(grep '^APP_VERSION=' .env | cut -d= -f2)
```

Troca a linha `APP_VERSION=` do `.env`. O `-i.bak` funciona igual no Linux e no macOS

```bash
set_version() {
  sed -i.bak "s/^APP_VERSION=.*/APP_VERSION=$1/" .env && rm -f .env.bak
}
```

Grava o hash novo, **baixa a imagem** e recria só o serviço `app`. O `--wait` só termina com sucesso quando o
`healthcheck` do container passa; `--wait-timeout 180` limita a espera a 3 minutos

```bash
set_version "$NEW_VERSION"

if docker compose pull app && docker compose up -d --wait --wait-timeout 180 app; then
```

Se o `pull` falhar (tag inexistente, sem acesso ao registry) ou o container não ficar saudável, grava a versão
anterior de volta, sobe o container antigo e sai com erro. O job do GitHub fica vermelho

```bash
else
  set_version "$PREVIOUS_VERSION"
  docker compose up -d --wait --wait-timeout 180 app
  exit 1
fi
```

| Situação | Resultado |
| --- | --- |
| imagem nova saudável | `.env` com o hash novo, container novo rodando |
| tag não existe no GHCR | `pull` falha antes de mexer no container; `.env` restaurado |
| aplicação nova não fica saudável | container antigo recriado; `.env` restaurado |

No Docker (diferente do Kubernetes) existe uma **pequena indisponibilidade** durante a troca: o container antigo
para antes de o novo subir. Para trocar sem nenhuma queda, use o Kubernetes ou um proxy que alterne entre dois
containers.

---

## Configuração no GitHub

Em *Settings* do repositório:

### Environment

*Settings → Environments → New environment* → `production`. Opcional: marque **Required reviewers** para que
cada deploy espere a aprovação de alguém.

### Variáveis

*Settings → Secrets and variables → Actions → Variables*

| Variável | Exemplo | Uso |
| --- | --- | --- |
| `DEPLOY_TARGET` | `docker` ou `kubernetes` | qual job de deploy roda |
| `APP_DIR` | `apps/compose-app` | pasta no servidor, relativa à home do usuário SSH |

### Segredos do environment `production`

*Settings → Environments → production → Environment secrets*

| Segredo | Destino | Conteúdo |
| --- | --- | --- |
| `SSH_HOST` | Docker | IP ou domínio do servidor |
| `SSH_USER` | Docker | usuário de deploy (ex.: `deploy`) |
| `SSH_PRIVATE_KEY` | Docker | chave privada gerada para o pipeline |
| `SSH_KNOWN_HOSTS` | Docker | saída do `ssh-keyscan` do servidor |
| `KUBECONFIG` | Kubernetes | conteúdo do kubeconfig com acesso ao namespace |

O `GITHUB_TOKEN` não precisa ser cadastrado: o GitHub cria um para cada execução.

---

## Preparar o servidor Docker

Feito **uma vez** por servidor. Depois disso, todo deploy vem do pipeline.

Cria um usuário só para deploy, com acesso ao Docker

```bash
sudo adduser --disabled-password deploy
sudo usermod -aG docker deploy
```

Na **sua máquina**, gera um par de chaves exclusivo para o pipeline (sem senha)

```bash
ssh-keygen -t ed25519 -C "github-actions" -f deploy_key -N ""
```

Autoriza a chave pública no servidor

```bash
ssh-copy-id -i deploy_key.pub deploy@<servidor>
```

Gera o conteúdo do segredo `SSH_KNOWN_HOSTS`

```bash
ssh-keyscan <servidor>
```

Cadastre o conteúdo de `deploy_key` em `SSH_PRIVATE_KEY` e apague os arquivos locais da chave.

No **servidor**, com o usuário `deploy`, faz login no GHCR para conseguir baixar imagens privadas. Use um
*Personal access token (classic)* criado em *GitHub → Settings → Developer settings* só com a permissão
`read:packages`. O login fica salvo em `~/.docker/config.json`

```bash
echo "<token>" | docker login ghcr.io -u <usuario-github> --password-stdin
```

Cria a pasta do projeto e o `.env`, com as senhas reais. O `APP_VERSION` recebe o hash de um commit que já tem
imagem publicada (veja na aba *Actions* ou em *Packages*)

```bash
mkdir -p ~/apps/compose-app && cd ~/apps/compose-app
nano .env
chmod 600 .env
```

A partir daqui, um push na `main` faz o primeiro deploy.

---

## Preparar o cluster Kubernetes

Também feito **uma vez**.

Cria o namespace e o secret do banco com a senha real

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl -n compose-app create secret generic db-credentials \
  --from-literal=POSTGRES_USER=app \
  --from-literal=POSTGRES_PASSWORD='senha-forte'
```

Para imagens privadas, cria um secret com o token `read:packages` e faz todos os pods do namespace usarem esse
secret ao baixar imagens

```bash
kubectl -n compose-app create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<usuario-github> \
  --docker-password=<token>
kubectl -n compose-app patch serviceaccount default \
  -p '{"imagePullSecrets": [{"name": "ghcr-pull"}]}'
```

Gera o conteúdo do segredo `KUBECONFIG`. O ideal é um kubeconfig de uma *ServiceAccount* com permissão apenas
no namespace `compose-app`, e não o kubeconfig de administrador do cluster

```bash
kubectl config view --minify --raw
```

---

## Vários projetos no mesmo repositório

Num monorepo como este curso, o workflow fica na raiz e aponta para a pasta do projeto. Estas mudanças no
`cd.yml` bastam:

Só dispara quando algo dentro da pasta do projeto muda

```yaml
on:
  push:
    branches: [main]
    paths:
      - "examples/compose-app/**"
```

Todos os comandos `run` passam a rodar dentro da pasta do projeto

```yaml
defaults:
  run:
    working-directory: examples/compose-app
```

O contexto do build aponta para a pasta (as actions `uses:` não seguem o `working-directory`)

```yaml
- uses: docker/build-push-action@v6
  with:
    context: examples/compose-app
```

Com vários projetos, cada um ganha seu próprio arquivo (`cd-compose-app.yml`, `cd-outro-projeto.yml`), com o
seu `paths` e o seu nome de imagem.

---

## Manutenção

Cada commit gera uma imagem nova, e elas se acumulam.

**No servidor**, remove imagens sem container há mais de 30 dias. Atenção: vale para **todas** as imagens do
servidor, inclusive de outros projetos, e as versões antigas deixam de estar disponíveis localmente para um
rollback rápido (continuam no GHCR)

```bash
docker image prune -a --filter "until=720h"
```

**No GHCR**, apague versões antigas em *Packages → compose-app → Manage versions*, ou automatize com a action
[`actions/delete-package-versions`](https://github.com/actions/delete-package-versions), mantendo as últimas N.

---

## Comandos no terminal

### Fluxo de trabalho

Cria uma branch, faz o commit e abre o pull request: o **CI** roda

```bash
git switch -c minha-alteracao
git commit -am "Altera a mensagem"
git push -u origin minha-alteracao
```

Depois do merge na `main`, o **CD** roda. O hash que vai virar a tag da imagem é

```bash
git switch main && git pull
git rev-parse HEAD
```

### Conferindo a versão em produção

Baixa na sua máquina exatamente a imagem de um commit

```bash
docker pull ghcr.io/<dono>/compose-app:<hash>
```

Mostra de qual commit uma imagem veio, pelo label gravado no build

```bash
docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' ghcr.io/<dono>/compose-app:<hash>
```

**Servidor Docker**: versão gravada e imagem do container em execução

```bash
cd ~/apps/compose-app
grep APP_VERSION .env
docker compose ps app --format '{{.Image}}'
```

**Kubernetes**: imagem do `Deployment` e histórico de versões

```bash
kubectl -n compose-app get deployment app -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl -n compose-app rollout history deployment/app
```

Qual commit está em produção (troque `<hash>` pelo valor encontrado acima)

```bash
git show --stat <hash>
```

### Voltando uma versão

Pelo GitHub: abra a execução do CD do commit desejado na aba *Actions* e use **Re-run all jobs**. Como a tag é o
hash daquele commit, a imagem antiga é implantada de novo.

Direto no servidor Docker

```bash
bash ~/apps/compose-app/deploy.sh <hash-anterior>
```

Direto no Kubernetes

```bash
kubectl -n compose-app rollout undo deployment/app
```

Um novo push na `main` volta a implantar o commit mais recente.
