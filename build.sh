#!/bin/bash
# =============================================================================
# build.sh — Build hermes-suite (official agent + optional webui layer)
# Reads AGENT_VERSION / WEBUI_VERSION from versions.env
# =============================================================================
set -e

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "${BUILD_DIR}/versions.env" ]; then
    eval "$(grep -E '^(AGENT_VERSION|WEBUI_VERSION|CONTAINER_RUNTIME|USE_SUDO)=' "${BUILD_DIR}/versions.env")"
else
    echo "ERROR: versions.env not found in ${BUILD_DIR}"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --agent) AGENT_VERSION="$2"; shift 2 ;;
        --webui) WEBUI_VERSION="$2"; shift 2 ;;
        --podman) CONTAINER_RUNTIME="podman"; shift ;;
        --docker) CONTAINER_RUNTIME="docker"; shift ;;
        --sudo) USE_SUDO="true"; shift ;;
        -h|--help)
            echo "Usage: $0 [--agent VER] [--webui VER] [--podman|--docker] [--sudo]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
USE_SUDO="${USE_SUDO:-false}"

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

AGENT_VER_CLEAN="${AGENT_VERSION#v}"
WEBUI_VER_CLEAN="${WEBUI_VERSION#v}"
IMAGE_TAG="hermes-suite:${AGENT_VER_CLEAN}-${WEBUI_VER_CLEAN}"

echo "=========================================="
echo " Building hermes-suite"
echo " Agent:  ${AGENT_VERSION}"
echo " WebUI:  ${WEBUI_VERSION}"
echo " Image:  ${IMAGE_TAG}"
echo " Runtime:${CONTAINER_RUNTIME}"
echo "=========================================="

case "$CONTAINER_RUNTIME" in
    podman)
        $SUDO_PREFIX podman build \
            --build-arg AGENT_VERSION="${AGENT_VERSION}" \
            --build-arg HERMES_WEBUI_VERSION="${WEBUI_VERSION}" \
            -t "${IMAGE_TAG}" \
            "${BUILD_DIR}"
        ;;
    docker)
        $SUDO_PREFIX docker build \
            --build-arg AGENT_VERSION="${AGENT_VERSION}" \
            --build-arg HERMES_WEBUI_VERSION="${WEBUI_VERSION}" \
            -t "${IMAGE_TAG}" \
            "${BUILD_DIR}"
        ;;
    *)
        echo "ERROR: Unknown CONTAINER_RUNTIME: $CONTAINER_RUNTIME"
        exit 1
        ;;
esac

echo "Build complete: ${IMAGE_TAG}"
echo "Drop-in agent:  docker run --rm -it -v ~/.hermes:/opt/data ${IMAGE_TAG} gateway run"
echo "With WebUI:     docker run --rm -e HERMES_WEBUI=1 -p 8787:8787 -v ~/.hermes:/opt/data ${IMAGE_TAG} gateway run"
