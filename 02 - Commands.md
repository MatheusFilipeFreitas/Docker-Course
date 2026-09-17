# 02 - Commands

Referência dos comandos da CLI do Docker, sem Dockerfile nem Compose. Os comandos de cada arquivo
ficam na aula correspondente:

- `docker build` e `docker run` da imagem de produção: [04 - Dockerfile](04%20-%20Dockerfile.md)
- ambiente de desenvolvimento com Compose: [05 - Dockerfile.dev](05%20-%20Dockerfile.dev.md)
- referência completa do `docker compose`: [08 - Docker Compose](08%20-%20Docker%20Compose.md)

## Containers

Lista os containers rodando na máquina

```bash
docker ps
```

Lista todos os containers, inclusive os parados

```bash
docker ps -a
```

Baixa e roda uma imagem de teste do docker

```bash
docker run hello-world
```

Baixa e roda uma imagem do ubuntu (sem processo para manter o ubuntu vivo, o container encerra na hora)

```bash
docker run ubuntu
```

Baixa e roda uma imagem do ubuntu iniciando o processo do bash, de forma interativa

```bash
docker run -it ubuntu bash
```

Dá um nome ao container, para usá-lo nos comandos no lugar do id

```bash
docker run --name <container-name> <image-name>
```

Remove o container automaticamente quando ele encerrar

```bash
docker run --rm -it ubuntu bash
```

Para a execução do container pelo seu id (ou nome)

```bash
docker stop <container-id>
```

Inicia a execução do container pelo seu id

```bash
docker start <container-id>
```

Executa e interage com o processo de um container iniciado

```bash
docker exec -it <container-id> bash
```

Mostra os logs de um container, acompanhando em tempo real com `-f`

```bash
docker logs -f <container-id>
```

Mostra todos os detalhes de um container ou imagem em JSON (portas, volumes, rede, variáveis)

```bash
docker inspect <container-id>
```

Remove um container parado

```bash
docker rm <container-id>
```

## Imagens

Gera uma imagem a partir de um Dockerfile

```bash
docker build -t <image-name>:<tag-version> .
```
eg:
```bash
docker build -t first-app:1.0 .
```

Lista as imagens presentes na máquina

```bash
docker images
```

Mostra as camadas de uma imagem e o tamanho de cada uma

```bash
docker image history <image-name>:<tag-version>
```

Remove uma imagem

```bash
docker rmi <image-name>:<tag-version>
```

Gera a imagem para outra arquitetura. Necessário quando a imagem é construída num Mac com Apple
Silicon (ARM) e vai rodar num servidor AMD64 — sem isso o container falha com `exec format error`

```bash
docker build --platform linux/amd64 -t <image-name>:<tag-version> .
```

## Registry (Docker Hub)

Autentica no Docker Hub

```bash
docker login
```

Para enviar ao registry, a imagem precisa ter o seu username no nome. Gere a imagem já com ele

```bash
docker build -t <user-name>/<image-name>:<tag-version> .
```

Ou crie uma nova tag apontando para uma imagem que já existe

```bash
docker tag <image-name>:<tag-version> <user-name>/<image-name>:<tag-version>
```

Envia ao registry

```bash
docker push <user-name>/<image-name>:<tag-version>
```

Baixa uma imagem do registry sem rodá-la

```bash
docker pull <user-name>/<image-name>:<tag-version>
```

## Volumes e redes

Lista os volumes

```bash
docker volume ls
```

Remove um volume

```bash
docker volume rm <volume-name>
```

Lista as redes

```bash
docker network ls
```

## Limpeza

Mostra quanto espaço imagens, containers, volumes e cache de build ocupam

```bash
docker system df
```

Remove containers parados, redes sem uso, imagens sem tag e cache de build

```bash
docker system prune
```

Inclui também imagens sem container e volumes sem uso (cuidado: apaga dados de volumes)

```bash
docker system prune -a --volumes
```
