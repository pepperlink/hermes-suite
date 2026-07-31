#!/bin/bash
# =============================================================================
# up.sh — Start hermes-suite via docker compose / podman-compose
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yaml"

if [ -f "${SCRIPT_DIR}/versions.env" ]; then
    eval "$(grep -E '^(AGENT_VERSION|WEBUI_VERSION|CONTAINER_RUNTIME|USE_SUDO|HERMES_DASHBOARD|HERMES_WEBUI)=' "${SCRIPT_DIR}/versions.env")"
fi

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
USE_SUDO="${USE_SUDO:-false}"
HERMES_DASHBOARD="${HERMES_DASHBOARD:-0}"
HERMES_WEBUI="${HERMES_WEBUI:-0}"

export AGENT_VERSION WEBUI_VERSION HERMES_DASHBOARD HERMES_WEBUI
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
        $SUDO_PREFIX env \
            AGENT_VERSION="${AGENT_VERSION}" \
            WEBUI_VERSION="${WEBUI_VERSION}" \
            HERMES_SUITE_IMAGE_TAG="${HERMES_SUITE_IMAGE_TAG}" \
            HERMES_DASHBOARD="${HERMES_DASHBOARD}" \
            HERMES_WEBUI="${HERMES_WEBUI}" \
            "$(command -v podman-compose)" -f "${COMPOSE_FILE}" up -d
        ;;
    docker)
        $SUDO_PREFIX env \
            AGENT_VERSION="${AGENT_VERSION}" \
            WEBUI_VERSION="${WEBUI_VERSION}" \
            HERMES_SUITE_IMAGE_TAG="${HERMES_SUITE_IMAGE_TAG}" \
            HERMES_DASHBOARD="${HERMES_DASHBOARD}" \
            HERMES_WEBUI="${HERMES_WEBUI}" \
            docker compose -f "${COMPOSE_FILE}" up -d
        ;;
    *)
        echo "ERROR: Unknown CONTAINER_RUNTIME: $CONTAINER_RUNTIME"
        exit 1
        ;;
esac

echo ""
echo "Hermes Suite is running (stock agent entrypoint + optional webui)"
echo "  Gateway:    http://localhost:8642"
if [ "${HERMES_WEBUI}" = "1" ] || [ "${HERMES_WEBUI}" = "true" ] || [ "${HERMES_WEBUI}" = "yes" ]; then
    echo "  WebUI:      http://localhost:8787"
else
    echo "  WebUI:      disabled (set HERMES_WEBUI=1)"
fi
if [ "${HERMES_DASHBOARD}" = "1" ] || [ "${HERMES_DASHBOARD}" = "true" ] || [ "${HERMES_DASHBOARD}" = "yes" ]; then
    echo "  Dashboard:  http://localhost:9119"
else
    echo "  Dashboard:  disabled (set HERMES_DASHBOARD=1)"
fi
echo ""
echo "Logs: ./logs.sh"
echo "Stop: ./down.sh"
