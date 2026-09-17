Instruções usadas no `03 - first-app/Dockerfile` (imagem de produção).

## Estrutura do arquivo

Define a imagem base a partir da qual a construção começa

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25
```

Define a imagem base e dá um nome ao estágio, para poder referenciá-lo depois (multi-stage build)

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25 AS build
```

Copia arquivos do contexto de build (a máquina local) para dentro da imagem

```dockerfile
COPY src /app/src
COPY pom.xml /app
```

Define o diretório de trabalho para os comandos seguintes (equivale a um `cd` que persiste)

```dockerfile
WORKDIR /app
```

Executa um comando durante a construção da imagem, gerando uma nova camada

```dockerfile
RUN mvn clean install
```

Copia um arquivo vindo de outro estágio do build, em vez de vir da máquina local

```dockerfile
COPY --from=build /app/target/docker-0.0.1-SNAPSHOT.jar /app/app.jar
```

Documenta qual porta o processo escuta dentro do container (não publica a porta sozinho)

```dockerfile
EXPOSE 8080
```

Define o comando padrão executado quando o container sobe

```dockerfile
CMD ["java", "-jar", "app.jar"]
```

## Por que multi-stage

O primeiro estágio usa a imagem `maven`, que traz o JDK e o Maven completos para compilar o projeto.
O segundo estágio usa a imagem `eclipse-temurin:25-jre-alpine`, que tem apenas a JRE.

```dockerfile
FROM maven:3.9.16-eclipse-temurin-25 AS build
...
FROM eclipse-temurin:25-jre-alpine
COPY --from=build /app/target/docker-0.0.1-SNAPSHOT.jar /app/app.jar
```

Só o `.jar` atravessa para a imagem final. O código-fonte, o Maven e o repositório de dependências
ficam para trás, no estágio de build, resultando numa imagem final muito menor.

## Comandos no terminal

Gera a imagem a partir do Dockerfile do diretório atual

```bash
docker build -t first-app:1.0 .
```

Roda a imagem publicando a porta 8080 do container na porta 8080 da máquina

```bash
docker run -p 8080:8080 first-app:1.0
```

Roda em background (modo detached)

```bash
docker run -d -p 8080:8080 first-app:1.0
```

Lista as imagens presentes na máquina

```bash
docker images
```

Remove uma imagem

```bash
docker rmi first-app:1.0
```
