#!/bin/bash
# =============================================================================
# logs.sh — Follow hermes-suite container logs
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yaml"

if [ -f "${SCRIPT_DIR}/versions.env" ]; then
    eval "$(grep -E '^(AGENT_VERSION|WEBUI_VERSION|CONTAINER_RUNTIME|USE_SUDO)=' "${SCRIPT_DIR}/versions.env")"
fi

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
USE_SUDO="${USE_SUDO:-false}"
export HERMES_SUITE_IMAGE_TAG="${AGENT_VERSION#v}-${WEBUI_VERSION#v}"

if [ "$CONTAINER_RUNTIME" = "auto" ]; then
    if command -v docker &>/dev/null; then
        CONTAINER_RUNTIME="docker"
    elif command -v podman &>/dev/null; then
        CONTAINER_RUNTIME="podman"
    else
        echo "ERROR: Neither docker nor podman found."
        exit 1
    fi
fi

SUDO_PREFIX=""
[ "$USE_SUDO" = "true" ] && SUDO_PREFIX="sudo"

case "$CONTAINER_RUNTIME" in
    podman)
        export PATH="${HOME}/.local/bin:${PATH}"
        $SUDO_PREFIX env HERMES_SUITE_IMAGE_TAG="${HERMES_SUITE_IMAGE_TAG}" \
            "$(command -v podman-compose)" -f "${COMPOSE_FILE}" logs -f
        ;;
    docker)
        $SUDO_PREFIX env HERMES_SUITE_IMAGE_TAG="${HERMES_SUITE_IMAGE_TAG}" \
            docker compose -f "${COMPOSE_FILE}" logs -f
        ;;
    *)
        echo "ERROR: Unknown CONTAINER_RUNTIME: $CONTAINER_RUNTIME"
        exit 1
        ;;
esac
