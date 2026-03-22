#!/usr/bin/env bash
set -e

# Engine finden
if command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
else
    ENGINE=""
fi

if [ -z "$ENGINE" ]; then
    echo "💻 Keine Container-Engine – baue lokal"
    ./gradlew "$@"
    exit 0
fi

# Image-Tag aus Dockerfile ableiten
DOCKER_HASH=$(sha256sum Dockerfile .dockerignore | cut -c1-12)
IMAGE_NAME="ghcr.io/dieterbaier/docs-pipeline:$DOCKER_HASH"

echo "📦 Verwende Image: $IMAGE_NAME"

# Prüfen ob Image existiert
if ! $ENGINE image exists "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "📥 Versuche, Image von GHCR zu pullen..."
    if $ENGINE pull "$IMAGE_NAME"; then
        echo "✅ Image aus GHCR gezogen"
    else
        echo "🔨 Baue Docker Image lokal..."
        $ENGINE build -t "$IMAGE_NAME" .
    fi
else
    echo "✅ Image bereits vorhanden"
fi

ENV_FILE=""
[ -f .env ] && ENV_FILE="--env-file .env"

# Run
$ENGINE run --rm \
    $ENV_FILE \
    -v "$PWD":/app \
    -v gradle-cache:/root/.gradle \
    -w /app \
    "$IMAGE_NAME" \
    ./gradlew --no-daemon "$@"