# Dev Container

🌐 **English** · [Português (Brasil)](README.pt-BR.md)

Open the `examples/first-app` folder in VS Code and run **Dev Containers: Reopen in Container**
(requires the *Dev Containers* extension).

Inside the container:

- `mvn spring-boot:run` — starts the app on <http://localhost:8080/hello>
- saving a `.java` file makes the VS Code Java extension write the new classes to
  `target/classes`, and Spring Boot DevTools restarts the context automatically
- port `5005` is open for the debugger (see `.vscode/launch.json`)

Running `docker compose up` (without VS Code) uses the same image, but the
container entrypoint watches `src/` and runs `mvn compile` by itself.

Full explanation in lesson [05 - VS Code Dev Containers](../../../docs/en/05-vscode-dev-containers.md).
