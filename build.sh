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

IMAGE_NAME="ghcr.io/docs-as-code-toolkit/docs-toolbox:v1.0.2"
echo "📥 Versuche, Image $IMAGE_NAME von GHCR zu pullen..."
if $ENGINE pull "$IMAGE_NAME"; then
    echo "✅ Image aus GHCR gezogen"
else
    echo "💻 Konnte Image $IMAGE_NAME nicht ziehen. Baue lokal"
    ./gradlew "$@"
    exit 0
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