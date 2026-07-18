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

IMAGE_NAME="ghcr.io/docs-as-code-toolkit/docs-toolbox:v1.3.1"
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

# Personal and site build variables the Gradle build reads via env(). They are
# forwarded into the container only when set on the host, so a present value
# (for example from CI secrets) reaches the build without an empty -e clobbering
# a value coming from .env locally.
PASS_ENV=(
    SITE_EMAIL SITE_ADDRESS_NAME SITE_STREET SITE_PLZ SITE_CITY SITE_TEL
    SITE_BASE_URL REQUIRE_SITE_BASE_URL
    CONTACT_STREET CONTACT_PLZ CONTACT_CITY CONTACT_TEL CONTACT_TEL_PRINT CONTACT_EMAIL
)
ENV_ARGS=()
for var in "${PASS_ENV[@]}"; do
    if [ -n "${!var+x}" ]; then
        ENV_ARGS+=(-e "$var")
    fi
done

# Gradle cache location. Defaults to a named volume for local reuse; CI overrides
# it with a host path (for example $HOME/.gradle) so actions/cache can persist it.
GRADLE_CACHE="${GRADLE_CACHE:-gradle-cache}"

# Run
$ENGINE run --rm \
    $ENV_FILE \
    "${ENV_ARGS[@]}" \
    -v "$PWD":/app \
    -v "$GRADLE_CACHE":/root/.gradle \
    -w /app \
    "$IMAGE_NAME" \
    ./gradlew --no-daemon "$@"
