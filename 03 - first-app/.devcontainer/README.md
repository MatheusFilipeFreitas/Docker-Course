# Dev Container

Abra a pasta no VS Code e rode **Dev Containers: Reopen in Container**
(requer a extensão *Dev Containers*).

Dentro do container:

- `mvn spring-boot:run` — sobe a aplicação em <http://localhost:8080/hello>
- salvar um `.java` faz a extensão Java do VS Code gravar as novas classes em
  `target/classes`, e o Spring Boot DevTools reinicia o contexto sozinho
- a porta `5005` fica aberta para o debugger (veja `.vscode/launch.json`)

Rodar `docker compose up` (sem o VS Code) usa a mesma imagem, mas o entrypoint
do container vigia o `src/` e roda `mvn compile` por conta própria.

Explicação completa na aula [06 - VS Code on Docker](../../06%20-%20VS%20Code%20on%20Docker.md).
