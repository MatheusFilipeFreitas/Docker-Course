# 03 - Dockerfile

🌐 [English](../en/03-dockerfile.md) · **Português (Brasil)**

Imagem de **produção** da aplicação de exemplo: compila o projeto e gera uma imagem pequena, contendo
só a JRE e o `.jar`.

**Arquivos referenciados**

- [`examples/first-app/Dockerfile`](../../examples/first-app/Dockerfile)
- [`examples/first-app/.dockerignore`](../../examples/first-app/.dockerignore)

## Arquivo completo

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

## Estágio 1: build

Define a imagem base e dá um nome ao estágio (`build`), para poder referenciá-lo depois. A imagem
`maven` traz o JDK e o Maven completos, necessários para compilar

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25 AS build
```

Define o diretório de trabalho das instruções seguintes (equivale a um `cd` que persiste). Declarado
logo no início, permite usar caminhos relativos nos `COPY` e `RUN`

```dockerfile
WORKDIR /app
```

Copia só o `pom.xml` do contexto de build (a máquina local) para `/app` e baixa as dependências

```dockerfile
COPY pom.xml .
RUN mvn -B dependency:go-offline
```

Copia o código e gera o `.jar` em `/app/target`. O `-B` (batch mode) deixa o log do Maven limpo, sem
barras de progresso

```dockerfile
COPY src ./src
RUN mvn -B package
```

### Cache de camadas

Cada instrução gera uma camada, e o Docker reaproveita do cache todas as camadas até a primeira que
mudou. Por isso a ordem importa: o que muda pouco vem antes, o que muda muito vem depois.

Editar um `.java` invalida só o `COPY src` e o `mvn package`: as dependências já baixadas continuam no
cache. Se o `src` fosse copiado antes do `pom.xml`, qualquer alteração no código baixaria tudo de novo.

## Estágio 2: imagem final

Começa uma imagem **nova**, a partir de uma base que tem apenas a JRE (sem Maven, sem JDK). Tudo que foi
feito no estágio anterior fica para trás, exceto o que for copiado explicitamente

```dockerfile
FROM eclipse-temurin:25-jre-alpine

WORKDIR /app
```

Cria um grupo e um usuário de sistema (`-S`) chamados `app`. Por padrão o processo do container roda como
`root`: se a aplicação for comprometida, o invasor tem permissão total dentro do container

```dockerfile
RUN addgroup -S app && adduser -S app -G app
```

Copia o `.jar` vindo do estágio `build`, em vez de vir da máquina local. O curinga `*.jar` evita quebrar o
build quando a versão no `pom.xml` muda

```dockerfile
COPY --from=build /app/target/*.jar app.jar
```

Troca o usuário que executa o processo do container. Vem depois do `RUN addgroup` porque criar usuários
exige `root`

```dockerfile
USER app
```

Documenta qual porta o processo escuta dentro do container. **Não** publica a porta: isso é feito no
`docker run -p`

```dockerfile
EXPOSE 8080
```

Define o executável que roda quando o container sobe

```dockerfile
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Por que multi-stage

Só o `.jar` atravessa para a imagem final. O código-fonte, o Maven e o repositório de dependências
ficam no estágio de build, e a imagem final fica muito menor.

### CMD vs ENTRYPOINT

`ENTRYPOINT` define o executável fixo do container. `CMD` define um comando padrão que é
**substituído** por qualquer argumento passado no `docker run`

```dockerfile
CMD ["java", "-jar", "app.jar"]
```

```bash
docker run first-app:1.0 sh   # com CMD: roda `sh` no lugar da aplicação
```

Usados juntos, o `CMD` vira os argumentos padrão do `ENTRYPOINT`

```dockerfile
ENTRYPOINT ["java", "-jar", "app.jar"]
CMD ["--server.port=8080"]
```

## .dockerignore

Antes do build, o Docker envia a pasta indicada (o `.` do `docker build`) para o daemon: é o
**contexto de build**. O `.dockerignore` tira arquivos desse envio, com a mesma sintaxe do `.gitignore`

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

Isso deixa o build mais rápido, evita invalidar o cache por arquivos irrelevantes e impede que arquivos
locais (como um `target/` antigo) acabem dentro da imagem por um `COPY`.

## Comandos no terminal

Todos rodam dentro da pasta `examples/first-app`.

Gera a imagem a partir do Dockerfile do diretório atual

```bash
docker build -t first-app:1.0 .
```

Roda a imagem publicando a porta 8080 do container na porta 8080 da máquina. Teste em
<http://localhost:8080/hello>

```bash
docker run --rm -p 8080:8080 first-app:1.0
```

Roda em background (modo detached), com um nome para o container

```bash
docker run -d --name first-app -p 8080:8080 first-app:1.0
```

Confere com qual usuário o processo está rodando (deve responder `app`)

```bash
docker run --rm --entrypoint whoami first-app:1.0
```

Mostra as camadas da imagem e o tamanho de cada uma

```bash
docker image history first-app:1.0
```

Compara o tamanho da imagem final com o da imagem de build

```bash
docker images
```

Para e remove o container, e depois a imagem

```bash
docker rm -f first-app
docker rmi first-app:1.0
```
