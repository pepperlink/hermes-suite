#!/bin/bash
# =============================================================================
# build.sh — Build the Hermes Suite container image
#
# Reads pinned versions from versions.env by default.
# Override with: ./build.sh --agent v2026.5.7 --webui v0.51.61
#
# Build modes:
#   (default)       Podman — child logs to /dev/stdout (docker logs)
#   --docker        Docker — child logs to files with rotation (rootful compat)
#   --docker-nolog  Docker — child logs to /dev/null (smallest footprint)
# =============================================================================
set -e

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_MODE="podman"
BUILD_CMD="podman"

# --- Load pinned versions from versions.env ---
if [ -f "${BUILD_DIR}/versions.env" ]; then
    eval "$(grep -E '^(AGENT_VERSION|WEBUI_VERSION)=' "${BUILD_DIR}/versions.env")"
else
    echo "ERROR: versions.env not found in ${BUILD_DIR}"
    exit 1
fi

# --- Allow overrides via CLI args ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --agent)
            AGENT_VERSION="$2"; shift 2 ;;
        --webui)
            WEBUI_VERSION="$2"; shift 2 ;;
        --docker)
            BUILD_MODE="docker"; BUILD_CMD="docker"; shift ;;
        --docker-nolog)
            BUILD_MODE="docker-nolog"; BUILD_CMD="docker"; shift ;;
        *)
            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Strip 'v' prefix for the compound tag (Docker convention: no 'v')
AGENT_VER_CLEAN="${AGENT_VERSION#v}"
WEBUI_VER_CLEAN="${WEBUI_VERSION#v}"
IMAGE_TAG="ascensionoid/hermes-suite:${AGENT_VER_CLEAN}-${WEBUI_VER_CLEAN}"

# --- Patch supervisord.conf for Docker modes ---
if [ "$BUILD_MODE" = "docker" ]; then
    sed -i \
        -e 's|stdout_logfile=/dev/stdout|stdout_logfile=/var/log/supervisor/%(program_name)s-stdout.log|' \
        -e 's|stderr_logfile=/dev/stderr|stderr_logfile=/var/log/supervisor/%(program_name)s-stderr.log|' \
        -e 's|stdout_logfile_maxbytes=0|stdout_logfile_maxbytes=10MB|' \
        -e 's|stderr_logfile_maxbytes=0|stderr_logfile_maxbytes=10MB|' \
        "${BUILD_DIR}/supervisord.conf"
    echo "Docker mode: child logs to /var/log/supervisor/ with 10MB rotation"
elif [ "$BUILD_MODE" = "docker-nolog" ]; then
    sed -i \
        -e 's|stdout_logfile=/dev/stdout|stdout_logfile=/dev/null|' \
        -e 's|stderr_logfile=/dev/stderr|stderr_logfile=/dev/null|' \
        "${BUILD_DIR}/supervisord.conf"
    echo "Docker nolog mode: child logs discarded"
fi

echo "=========================================="
echo " Building Hermes Suite"
echo "=========================================="
echo " Agent version:  ${AGENT_VERSION}"
echo " WebUI version:  ${WEBUI_VERSION}"
echo " Image tag:      ${IMAGE_TAG}"
echo " Build mode:     ${BUILD_MODE}"
echo " Build context:  ${BUILD_DIR}"
echo "=========================================="

${BUILD_CMD} build \
    --build-arg AGENT_VERSION="${AGENT_VERSION}" \
    --build-arg HERMES_WEBUI_VERSION="${WEBUI_VERSION}" \
    -t "${IMAGE_TAG}" \
    $([ "${BUILD_CMD}" = "podman" ] && echo "--format docker") \
    "${BUILD_DIR}"

# --- Restore supervisord.conf after Docker builds ---
if [ "$BUILD_MODE" != "podman" ]; then
    git -C "${BUILD_DIR}" checkout -- supervisord.conf 2>/dev/null \
        || sed -i \
            -e 's|stdout_logfile=/var/log/supervisor/%(program_name)s-stdout.log|stdout_logfile=/dev/stdout|' \
            -e 's|stderr_logfile=/var/log/supervisor/%(program_name)s-stderr.log|stderr_logfile=/dev/stderr|' \
            -e 's|stdout_logfile=/dev/null|stdout_logfile=/dev/stdout|' \
            -e 's|stderr_logfile=/dev/null|stderr_logfile=/dev/stderr|' \
            -e 's|stdout_logfile_maxbytes=10MB|stdout_logfile_maxbytes=0|' \
            -e 's|stderr_logfile_maxbytes=10MB|stderr_logfile_maxbytes=0|' \
            "${BUILD_DIR}/supervisord.conf"
    echo "Restored supervisord.conf to Podman defaults"
fi

echo ""
echo "=========================================="
echo " Build complete: ${IMAGE_TAG}"
echo "=========================================="
echo ""
echo " Run as a Service (Compose):"
echo "   ${BUILD_CMD}-compose -f ${BUILD_DIR}/docker-compose.yaml up -d"
echo ""
echo " Run Manually (Interactive/Debug):"
echo "   ${BUILD_CMD} run --rm -it \\"
echo "     -v ~/.hermes:/opt/data:Z \\"
echo "     -p 8642:8642 -p 8787:8787 -p 9119:9119 \\"
echo "     ${IMAGE_TAG}"
