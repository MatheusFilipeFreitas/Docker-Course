# 08 - CI/CD with GitHub Actions

🌐 **English** · [Português (Brasil)](../pt-br/08-ci-cd-github-actions.md)

Automates what [lesson 07](07-migrating-to-docker-and-kubernetes.md) did by hand: every commit on `main` becomes an
image on the **GitHub Container Registry (GHCR)**, identified by the **commit hash**, and the server (Docker or
Kubernetes) pulls and starts running that version automatically.

**Referenced files**

- [`examples/compose-app/.github/workflows/ci.yml`](../../examples/compose-app/.github/workflows/ci.yml)
- [`examples/compose-app/.github/workflows/cd.yml`](../../examples/compose-app/.github/workflows/cd.yml)
- [`examples/compose-app/deploy/deploy.sh`](../../examples/compose-app/deploy/deploy.sh)
- reuses the `Dockerfile`, `deploy/docker-compose.prod.yml` and `deploy/k8s/` from the previous lessons

## Overview

```
 pull request ──► CI: docker build (no push) ──► review and merge
                                                      │
 push to main ──► CD ─────────────────────────────────┘
                   │
                   ├─ build ──► ghcr.io/<owner>/compose-app:<commit hash>
                   │
                   ├─ deploy-docker      (DEPLOY_TARGET=docker)
                   │    ssh to the server ─► deploy.sh <hash>
                   │                          ├─ .env: APP_VERSION=<hash>
                   │                          ├─ docker compose pull + up --wait
                   │                          └─ failed? back to the previous hash
                   │
                   └─ deploy-kubernetes  (DEPLOY_TARGET=kubernetes)
                        kustomization.yaml: newTag=<hash>
                        kubectl apply -k + rollout status
                        failed? kubectl rollout undo
```

---

## Why the commit hash as the tag

| Tag | Problem or advantage |
| --- | --- |
| `latest` | changes on every build: you cannot tell what is running or go back to the previous version |
| `1.0.0` | someone must remember to bump the number on every release |
| `3f9c2a1...` (hash) | generated automatically, **never changes** and points to the exact code: `git show <hash>` |

With tags that never change, "the latest version" is not discovered by the server looking at the registry: the
**pipeline** tells the server which hash to run. The full flow is:

1. commit `3f9c2a1` lands on `main`;
2. GitHub Actions publishes `ghcr.io/<owner>/compose-app:3f9c2a1...`;
3. the pipeline writes that hash on the server (`APP_VERSION` in `.env`, or `newTag` on Kubernetes);
4. the server runs `docker compose pull` / Kubernetes creates the new pods, and **pulls the image for that hash**.

If the server reboots, `restart: unless-stopped` (or Kubernetes) starts the **same** recorded version again, with no
need for the registry or a new deploy. Going back a version is just pointing to a previous hash.

---

## Where the workflows live

GitHub only runs workflows from **`.github/workflows/` at the repository root**. In a repository dedicated to the
project, the layout is

```
compose-app/                 ← repository root
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

In this course repository, the folder lives inside `examples/compose-app/` only as study material, so the workflows
**do not run**. To use them in a monorepo (several projects in the same repository), see
[Multiple projects in the same repository](#multiple-projects-in-the-same-repository).

---

## GitHub Container Registry

Image addresses look like `ghcr.io/<owner>/<image-name>:<tag>`.

- **Names are always lowercase**: GHCR rejects `ghcr.io/MatheusFilipeFreitas/...`. The workflow converts the
  repository owner to lowercase.
- **Authentication in the pipeline**: the workflow's own `GITHUB_TOKEN` publishes the image, as long as the job has
  `permissions: packages: write`. No token needs to be created.
- **Visibility**: the image starts **private**. To pull it on the server, log in with a token (see
  [Preparing the Docker server](#preparing-the-docker-server)) or make the package public under
  *Profile → Packages → compose-app → Package settings*.
- **Link to the repository**: the `org.opencontainers.image.source` label makes the package show up on the
  repository page.

---

## ci.yml

### Full file

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

### Explanation

Runs on every pull request opened against `main`

```yaml
on:
  pull_request:
    branches: [main]
```

Checks out the commit code on the runner (GitHub's virtual machine)

```yaml
- uses: actions/checkout@v5
```

Enables **Buildx**, the Docker builder that supports remote cache and multiple architectures

```yaml
- uses: docker/setup-buildx-action@v3
```

Runs `docker build` without publishing (`push: false`). Since the `Dockerfile` runs `mvn package`, the project tests
also run here: if they fail, the PR turns red

```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    push: false
```

Stores the layers in the GitHub Actions cache (`gha`). Maven dependencies are only downloaded again when `pom.xml`
changes, the same cache logic as [lesson 03](03-dockerfile.md#layer-cache)

```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

---

## cd.yml

### Full file

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

### Triggers and concurrency

Runs on every push to `main` (including PR merges). `workflow_dispatch` adds the **Run workflow** button to the
*Actions* tab, to trigger a deploy manually

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
```

Ensures one deploy at a time. If two commits arrive together, the second waits for the first to finish instead of
both changing the server at the same time

```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: false
```

### build job

`GITHUB_TOKEN` permissions in this job: read the code and **publish packages** to GHCR

```yaml
permissions:
  contents: read
  packages: write
```

Exposes the image name to the deploy jobs

```yaml
outputs:
  image: ${{ steps.image.outputs.name }}
```

Builds the image name. `${GITHUB_REPOSITORY_OWNER,,}` is bash syntax for converting to lowercase

```yaml
- name: Image name
  id: image
  run: echo "name=ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/compose-app" >> "$GITHUB_OUTPUT"
```

Logs in to GHCR with the workflow's automatic token

```yaml
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

Builds and publishes. The tag is `github.sha`, the **full hash of the commit** that triggered the workflow. The
labels record in the image which repository and commit it came from

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

### deploy-docker job

Only runs if the repository variable `DEPLOY_TARGET` is `docker`, and only after `build` succeeds

```yaml
deploy-docker:
  if: vars.DEPLOY_TARGET == 'docker'
  needs: build
```

Uses the GitHub **environment** `production`: the secrets are stored in it, and a manual approval can be required
before deploying (see [GitHub configuration](#github-configuration))

```yaml
environment: production
```

Builds the SSH address from the secrets and the project folder on the server from a variable

```yaml
env:
  SERVER: ${{ secrets.SSH_USER }}@${{ secrets.SSH_HOST }}
  APP_DIR: ${{ vars.APP_DIR }}
```

Writes the private key and the server fingerprint on the runner. Secrets go through environment variables (and not
straight into the script with `${{ }}`), which prevents a value with special characters from breaking or changing
the command. `known_hosts` guarantees the runner is talking to the right server

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

Sends the compose file and the deploy script **on every deploy**. This way infrastructure changes (a new variable, a
memory limit) are also delivered by commit, without anyone editing files on the server

```yaml
- name: Copy compose file and deploy script
  run: |
    scp deploy/docker-compose.prod.yml "$SERVER:$APP_DIR/docker-compose.yml"
    scp deploy/deploy.sh "$SERVER:$APP_DIR/deploy.sh"
```

Runs `deploy.sh` on the server, passing the commit hash

```yaml
- name: Deploy
  run: |
    # The variables are expanded on the runner on purpose.
    # shellcheck disable=SC2029
    ssh "$SERVER" bash "$APP_DIR/deploy.sh" "$GITHUB_SHA"
```

### deploy-kubernetes job

Installs `kubectl` on the runner and writes the kubeconfig (cluster access credentials) from the secrets

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

Replaces the image and tag in `kustomization.yaml` **only inside the runner** (the file in Git does not change). The
tag goes **in quotes**: without them, a hash like `1e53...` or one made only of digits is read by YAML as a number
and kustomize rejects the file. `grep` checks the replacement worked before applying

```yaml
- name: Point the manifests to the new image
  run: |
    sed -i "s|newName: .*|newName: $IMAGE|; s|newTag: .*|newTag: \"$GITHUB_SHA\"|" deploy/k8s/kustomization.yaml
    kubectl kustomize deploy/k8s | grep "image: $IMAGE"
```

Applies **all** manifests, not only the image: a change in `configmap.yaml` or in the probes is also delivered by
the commit. `secret.example.yaml` stays out of `kustomization.yaml` so the pipeline never overwrites the real
password

```yaml
- name: Apply
  run: kubectl apply -k deploy/k8s
```

Waits for the new pods to become ready. If they are not ready within 5 minutes (missing image, application crashing
on startup, failing probe), it rolls the `Deployment` back to the previous version and marks the job as failed

```yaml
- name: Wait for rollout (roll back on failure)
  run: |
    if ! kubectl -n compose-app rollout status deployment/app --timeout=300s; then
      kubectl -n compose-app rollout undo deployment/app
      exit 1
    fi
```

While the new pods are not ready, the old ones keep serving requests: a broken deploy does not take the application
down.

---

## deploy.sh

Runs **on the server**, in the folder with `docker-compose.yml` and `.env`.

### Full file

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

### Explanation

Stops the script on the first error (`-e`), on an undefined variable (`-u`) or on a failure in the middle of a pipe
(`pipefail`)

```bash
set -euo pipefail
```

Moves into the script's own folder, so it works no matter where it is called from

```bash
cd "$(dirname "$0")"
```

Saves the version running now, to be able to go back

```bash
PREVIOUS_VERSION=$(grep '^APP_VERSION=' .env | cut -d= -f2)
```

Replaces the `APP_VERSION=` line in `.env`. `-i.bak` behaves the same on Linux and macOS

```bash
set_version() {
  sed -i.bak "s/^APP_VERSION=.*/APP_VERSION=$1/" .env && rm -f .env.bak
}
```

Writes the new hash, **pulls the image** and recreates only the `app` service. `--wait` only succeeds once the
container `healthcheck` passes; `--wait-timeout 180` limits the wait to 3 minutes

```bash
set_version "$NEW_VERSION"

if docker compose pull app && docker compose up -d --wait --wait-timeout 180 app; then
```

If `pull` fails (missing tag, no access to the registry) or the container does not become healthy, it writes the
previous version back, starts the old container and exits with an error. The GitHub job turns red

```bash
else
  set_version "$PREVIOUS_VERSION"
  docker compose up -d --wait --wait-timeout 180 app
  exit 1
fi
```

| Situation | Result |
| --- | --- |
| healthy new image | `.env` with the new hash, new container running |
| tag does not exist on GHCR | `pull` fails before touching the container; `.env` restored |
| new application never becomes healthy | old container recreated; `.env` restored |

On Docker (unlike Kubernetes) there is **brief downtime** during the switch: the old container stops before the new
one starts. For zero-downtime switches, use Kubernetes or a proxy that alternates between two containers.

---

## GitHub configuration

In the repository *Settings*:

### Environment

*Settings → Environments → New environment* → `production`. Optional: tick **Required reviewers** so every deploy
waits for someone's approval.

### Variables

*Settings → Secrets and variables → Actions → Variables*

| Variable | Example | Purpose |
| --- | --- | --- |
| `DEPLOY_TARGET` | `docker` or `kubernetes` | which deploy job runs |
| `APP_DIR` | `apps/compose-app` | folder on the server, relative to the SSH user's home |

### Secrets of the `production` environment

*Settings → Environments → production → Environment secrets*

| Secret | Target | Content |
| --- | --- | --- |
| `SSH_HOST` | Docker | server IP or domain |
| `SSH_USER` | Docker | deploy user (e.g. `deploy`) |
| `SSH_PRIVATE_KEY` | Docker | private key generated for the pipeline |
| `SSH_KNOWN_HOSTS` | Docker | output of `ssh-keyscan` for the server |
| `KUBECONFIG` | Kubernetes | kubeconfig content with access to the namespace |

`GITHUB_TOKEN` does not need to be registered: GitHub creates one for each run.

---

## Preparing the Docker server

Done **once** per server. After that, every deploy comes from the pipeline.

Creates a user just for deploys, with access to Docker

```bash
sudo adduser --disabled-password deploy
sudo usermod -aG docker deploy
```

On **your machine**, generates a key pair exclusive to the pipeline (no passphrase)

```bash
ssh-keygen -t ed25519 -C "github-actions" -f deploy_key -N ""
```

Authorizes the public key on the server

```bash
ssh-copy-id -i deploy_key.pub deploy@<server>
```

Generates the content of the `SSH_KNOWN_HOSTS` secret

```bash
ssh-keyscan <server>
```

Store the content of `deploy_key` in `SSH_PRIVATE_KEY` and delete the local key files.

On the **server**, as the `deploy` user, log in to GHCR to be able to pull private images. Use a
*Personal access token (classic)* created under *GitHub → Settings → Developer settings* with only the
`read:packages` permission. The login is stored in `~/.docker/config.json`

```bash
echo "<token>" | docker login ghcr.io -u <github-user> --password-stdin
```

Creates the project folder and `.env`, with the real passwords. `APP_VERSION` gets the hash of a commit that already
has a published image (see the *Actions* tab or *Packages*)

```bash
mkdir -p ~/apps/compose-app && cd ~/apps/compose-app
nano .env
chmod 600 .env
```

From here on, a push to `main` triggers the first deploy.

---

## Preparing the Kubernetes cluster

Also done **once**.

Creates the namespace and the database secret with the real password

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl -n compose-app create secret generic db-credentials \
  --from-literal=POSTGRES_USER=app \
  --from-literal=POSTGRES_PASSWORD='strong-password'
```

For private images, creates a secret with the `read:packages` token and makes every pod in the namespace use it
when pulling images

```bash
kubectl -n compose-app create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<github-user> \
  --docker-password=<token>
kubectl -n compose-app patch serviceaccount default \
  -p '{"imagePullSecrets": [{"name": "ghcr-pull"}]}'
```

Generates the content of the `KUBECONFIG` secret. Ideally use a kubeconfig of a *ServiceAccount* with permissions
only on the `compose-app` namespace, not the cluster admin kubeconfig

```bash
kubectl config view --minify --raw
```

---

## Multiple projects in the same repository

In a monorepo such as this course, the workflow lives at the root and points to the project folder. These changes
to `cd.yml` are enough:

Only triggers when something inside the project folder changes

```yaml
on:
  push:
    branches: [main]
    paths:
      - "examples/compose-app/**"
```

Every `run` command runs inside the project folder

```yaml
defaults:
  run:
    working-directory: examples/compose-app
```

The build context points to the folder (`uses:` actions do not follow `working-directory`)

```yaml
- uses: docker/build-push-action@v6
  with:
    context: examples/compose-app
```

With several projects, each one gets its own file (`cd-compose-app.yml`, `cd-other-project.yml`), with its own
`paths` and image name.

---

## Maintenance

Every commit creates a new image, and they pile up.

**On the server**, removes images without containers older than 30 days. Careful: it applies to **every** image on
the server, including other projects, and old versions are no longer available locally for a quick rollback (they
remain on GHCR)

```bash
docker image prune -a --filter "until=720h"
```

**On GHCR**, delete old versions under *Packages → compose-app → Manage versions*, or automate it with the
[`actions/delete-package-versions`](https://github.com/actions/delete-package-versions) action, keeping the last N.

---

## Terminal commands

### Workflow

Creates a branch, commits and opens the pull request: **CI** runs

```bash
git switch -c my-change
git commit -am "Change the message"
git push -u origin my-change
```

After merging into `main`, **CD** runs. The hash that becomes the image tag is

```bash
git switch main && git pull
git rev-parse HEAD
```

### Checking the version in production

Pulls on your machine exactly the image of a commit

```bash
docker pull ghcr.io/<owner>/compose-app:<hash>
```

Shows which commit an image came from, through the label written at build time

```bash
docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' ghcr.io/<owner>/compose-app:<hash>
```

**Docker server**: recorded version and image of the running container

```bash
cd ~/apps/compose-app
grep APP_VERSION .env
docker compose ps app --format '{{.Image}}'
```

**Kubernetes**: `Deployment` image and version history

```bash
kubectl -n compose-app get deployment app -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl -n compose-app rollout history deployment/app
```

Which commit is in production (replace `<hash>` with the value found above)

```bash
git show --stat <hash>
```

### Going back a version

On GitHub: open the CD run of the desired commit in the *Actions* tab and use **Re-run all jobs**. Since the tag is
that commit's hash, the old image is deployed again.

Directly on the Docker server

```bash
bash ~/apps/compose-app/deploy.sh <previous-hash>
```

Directly on Kubernetes

```bash
kubectl -n compose-app rollout undo deployment/app
```

A new push to `main` deploys the latest commit again.
