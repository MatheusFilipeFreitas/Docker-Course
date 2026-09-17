
Lista os containers rodando na máquina

```bash
docker ps
```

Baixa e roda uma imagem de teste do docker

```bash
docker run hello-world
```

Lista os processos que rodaram na máquina

```bash
docker ps -a
```

Baixa e roda uma imagem do ubuntu (sem processo para manter o ubuntu vivo)

```bash
docker run ubuntu
```

Baixa e roda uma imagem do ubuntu iniciando o processo do bash

```bash
docker run -it ubuntu bash
```

Para a execução do container pelo seu id

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

Gera uma imagem a partir de um Dockerfile

```bash
docker build -t <image-name>:<tag-version> .
```
eg:
```bash
docker build -t first-app:1.0 .
```

Envia ao registry

```bash
docker push <user-name>/<image-name>:<tag-version>
```
p.s:
Gere uma imagem com o seu username local
```bash
docker build -t <user-name>/<image-name>:<tag-version>
```

Quando tivermos um erro de kernel nas imagens

```bash
docker build --platform linux/amd64 -t <image-name>:<tag-version> .
```
## Docker Compose

Sobe todos os serviços definidos no `docker-compose.yml`, com os logs na tela

```bash
docker compose up
```

Sobe os serviços em background (modo detached)

```bash
docker compose up -d
```

Reconstrói as imagens antes de subir (usar após alterar um Dockerfile)

```bash
docker compose up --build
```

Apenas constrói as imagens, sem subir os serviços

```bash
docker compose build
```

Constrói ignorando o cache das camadas

```bash
docker compose build --no-cache
```

Lista os serviços do projeto e seus status

```bash
docker compose ps
```

Mostra os logs de todos os serviços

```bash
docker compose logs
```

Acompanha os logs de um serviço específico em tempo real

```bash
docker compose logs -f <service-name>
```

Executa um comando dentro de um serviço que já está rodando

```bash
docker compose exec <service-name> bash
```

Roda um comando pontual num container novo, removido ao terminar

```bash
docker compose run --rm <service-name> mvn test
```

Para os serviços sem remover os containers

```bash
docker compose stop
```

Inicia novamente os serviços parados

```bash
docker compose start
```

Reinicia um serviço

```bash
docker compose restart <service-name>
```

Para e remove containers e rede do projeto (mantém os volumes)

```bash
docker compose down
```

Para e remove também os volumes nomeados

```bash
docker compose down -v
```

Usa um arquivo de compose com outro nome ou caminho

```bash
docker compose -f <file-name>.yml up
```

Mostra o arquivo final já com as variáveis resolvidas (útil para conferir erros)

```bash
docker compose config
```
