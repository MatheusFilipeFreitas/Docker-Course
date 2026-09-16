# Dev Container

Open the folder in VS Code and run **Dev Containers: Reopen in Container**
(requires the *Dev Containers* extension).

Inside the container:

- `mvn spring-boot:run` — starts the app on <http://localhost:8080/hello>
- saving a `.java` file makes the VS Code Java extension write new classes to
  `target/classes`, and Spring Boot DevTools restarts the context automatically
- port `5005` is open for `Attach to JVM` (see `.vscode/launch.json`)

Running `docker compose up` (without VS Code) uses the same image, but the
container's entrypoint watches `src/` and runs `mvn compile` itself.
