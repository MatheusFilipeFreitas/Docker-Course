# 02 - Commands

🌐 **English** · [Português (Brasil)](../pt-br/02-commands.md)

Reference of Docker CLI commands, without Dockerfile or Compose. The commands for each file are in the matching
lesson:

- `docker build` and `docker run` for the production image: [03 - Dockerfile](03-dockerfile.md)
- development environment with Compose: [04 - Dockerfile.dev](04-dockerfile-dev.md)
- full `docker compose` reference: [06 - Docker Compose](06-docker-compose.md)

## Containers

Lists the containers running on the machine

```bash
docker ps
```

Lists all containers, including stopped ones

```bash
docker ps -a
```

Downloads and runs Docker's test image

```bash
docker run hello-world
```

Downloads and runs an Ubuntu image (no process keeps it alive, so the container exits right away)

```bash
docker run ubuntu
```

Downloads and runs an Ubuntu image starting an interactive bash process

```bash
docker run -it ubuntu bash
```

Gives the container a name, to use it in commands instead of the id

```bash
docker run --name <container-name> <image-name>
```

Removes the container automatically when it exits

```bash
docker run --rm -it ubuntu bash
```

Stops a container by its id (or name)

```bash
docker stop <container-id>
```

Starts a stopped container by its id

```bash
docker start <container-id>
```

Runs and interacts with a process inside a running container

```bash
docker exec -it <container-id> bash
```

Shows a container's logs, following them in real time with `-f`

```bash
docker logs -f <container-id>
```

Shows every detail of a container or image as JSON (ports, volumes, network, variables)

```bash
docker inspect <container-id>
```

Removes a stopped container

```bash
docker rm <container-id>
```

## Images

Builds an image from a Dockerfile

```bash
docker build -t <image-name>:<tag-version> .
```

Example

```bash
docker build -t first-app:1.0 .
```

Lists the images on the machine

```bash
docker images
```

Shows the layers of an image and the size of each one

```bash
docker image history <image-name>:<tag-version>
```

Removes an image

```bash
docker rmi <image-name>:<tag-version>
```

Builds the image for another architecture. Needed when the image is built on an Apple Silicon Mac (ARM) and will
run on an AMD64 server — without it the container fails with `exec format error`

```bash
docker build --platform linux/amd64 -t <image-name>:<tag-version> .
```

## Registry (Docker Hub)

Logs in to Docker Hub

```bash
docker login
```

To push to the registry, the image name must include your username. Build the image with it

```bash
docker build -t <user-name>/<image-name>:<tag-version> .
```

Or create a new tag pointing to an existing image

```bash
docker tag <image-name>:<tag-version> <user-name>/<image-name>:<tag-version>
```

Pushes to the registry

```bash
docker push <user-name>/<image-name>:<tag-version>
```

Downloads an image from the registry without running it

```bash
docker pull <user-name>/<image-name>:<tag-version>
```

## Volumes and networks

Lists the volumes

```bash
docker volume ls
```

Removes a volume

```bash
docker volume rm <volume-name>
```

Lists the networks

```bash
docker network ls
```

## Cleanup

Shows how much space images, containers, volumes and build cache use

```bash
docker system df
```

Removes stopped containers, unused networks, untagged images and build cache

```bash
docker system prune
```

Also removes images without containers and unused volumes (careful: deletes volume data)

```bash
docker system prune -a --volumes
```
