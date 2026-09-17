#!/usr/bin/env bash
# Dev entrypoint: runs the Spring Boot app and keeps target/classes in sync with
# the bind-mounted sources. Spring Boot DevTools watches target/classes and
# restarts the application context whenever a .class file changes.
set -euo pipefail

STAMP=/tmp/.last-compile

echo "[dev] compiling sources..."
mvn -q compile
touch "$STAMP"

echo "[dev] starting spring-boot:run..."
# Profile and DevTools polling come from the environment set in docker-compose.yml.
mvn spring-boot:run \
  -Dspring-boot.run.jvmArguments="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005" &
APP_PID=$!

# Stop the whole container cleanly on Ctrl+C / docker compose down.
trap 'kill -TERM "$APP_PID" 2>/dev/null || true; exit 0' INT TERM

echo "[dev] watching src/ for changes (recompile -> devtools restart)..."
while kill -0 "$APP_PID" 2>/dev/null; do
  CHANGED=$(find src pom.xml -newer "$STAMP" -type f \
    \( -name '*.java' -o -name '*.properties' -o -name '*.yml' -o -name '*.yaml' -o -name 'pom.xml' -o -path 'src/main/resources/*' \) \
    -print -quit 2>/dev/null || true)

  if [ -n "$CHANGED" ]; then
    touch "$STAMP"
    echo "[dev] change detected ($CHANGED) -> mvn compile"
    mvn -q compile || echo "[dev] compilation failed, keeping previous classes"
  fi

  sleep 2
done

wait "$APP_PID"
