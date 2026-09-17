# 03 - first-app

A minimal Spring Boot web application used as the "first app" exercise of the Docker course:
a small, self-contained service to package into a container image.

## Stack

| Item | Version |
| --- | --- |
| Java | 25 |
| Spring Boot | 4.1.1 |
| Build tool | Maven (via the bundled `mvnw` wrapper) |
| Starters | `spring-boot-starter-webmvc`, `spring-boot-starter-webmvc-test` (test) |

Maven coordinates: `com.mathffreitas:docker:0.0.1-SNAPSHOT`

## Project layout

```
03 - first-app/
├── Dockerfile                  # empty — to be written as part of the exercise
├── pom.xml
├── mvnw, mvnw.cmd, .mvn/       # Maven wrapper
└── src/
    ├── main/
    │   ├── java/com/mathffreitas/docker/
    │   │   ├── Application.java              # @SpringBootApplication entry point
    │   │   └── controller/HelloController.java
    │   └── resources/application.properties
    └── test/java/com/mathffreitas/docker/
        └── ApplicationTests.java             # context-load smoke test
```

## Running locally

```bash
./mvnw spring-boot:run
```

The app starts on the Spring Boot default port, <http://localhost:8080>.

## Building

```bash
./mvnw clean package
```

Produces `target/docker-0.0.1-SNAPSHOT.jar`, which can be run directly:

```bash
java -jar target/docker-0.0.1-SNAPSHOT.jar
```

## Tests

```bash
./mvnw test
```

`ApplicationTests.contextLoads` only verifies that the Spring context starts.

## Docker

The `Dockerfile` in this directory is currently **empty** — writing it is the point of the
exercise. A typical starting point, once the jar has been built with `./mvnw clean package`:

```dockerfile
FROM eclipse-temurin:25-jre
WORKDIR /app
COPY target/docker-0.0.1-SNAPSHOT.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Then:

```bash
docker build -t first-app .
docker run --rm -p 8080:8080 first-app
```

Spring Boot can also build an OCI image without a Dockerfile:

```bash
./mvnw spring-boot:build-image
```

## Known gap: the `/hello` endpoint

`HelloController` is annotated with `@Controller` and `@RequestMapping("/hello")`, but
`sayHello()` has no method-level mapping and the class does not use `@RestController` or
`@ResponseBody`. As written, requesting `/hello` will **not** return `Hello World!`.

To make it work, either annotate the method and add `@ResponseBody`, or switch the class to
`@RestController`:

```java
@RestController
@RequestMapping("/hello")
public class HelloController {

    @GetMapping
    public String sayHello() {
        return "Hello World!";
    }
}
```

## Further reading

See [HELP.md](HELP.md) for the generated Spring Boot reference links.
