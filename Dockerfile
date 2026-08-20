# =============================================================================
# Hermes Suite — hermes-agent + optional hermes-webui
#
# Thin layer on the official nousresearch/hermes-agent image:
#   - keeps stock s6-overlay PID 1 (/init) and entrypoint
#   - installs hermes-webui
#   - adds an s6-rc service (opt-in via HERMES_WEBUI=1)
#
# Drop-in replacement for the official agent image when HERMES_WEBUI is unset/0.
# =============================================================================

ARG AGENT_VERSION=v2026.8.18
FROM docker.io/nousresearch/hermes-agent:${AGENT_VERSION}

USER root

# git is needed to pin-clone hermes-webui; base image may already have it.
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install hermes-webui (pinned tag). Own venv + agent extras so in-process
# agent features work when the UI is enabled.
# ---------------------------------------------------------------------------
ARG HERMES_WEBUI_VERSION=v0.52.76
RUN cd /opt && \
    git clone --depth 1 --branch "${HERMES_WEBUI_VERSION}" \
        https://github.com/nesquena/hermes-webui.git hermes-webui && \
    uv venv /opt/hermes-webui/venv && \
    uv pip install --python /opt/hermes-webui/venv/bin/python3 --no-cache-dir \
        -r /opt/hermes-webui/requirements.txt && \
    uv pip install --python /opt/hermes-webui/venv/bin/python3 --no-cache-dir \
        -e "/opt/hermes[all,messaging,anthropic,bedrock,azure-identity,hindsight]" && \
    rm -rf /opt/hermes-webui/.git && \
    echo "__version__ = '${HERMES_WEBUI_VERSION}'" > /opt/hermes-webui/api/_version.py && \
    chown -R hermes:hermes /opt/hermes-webui

# ---------------------------------------------------------------------------
# s6-rc: add hermes-webui alongside upstream main-hermes + dashboard
# ---------------------------------------------------------------------------
COPY docker/s6-rc.d/hermes-webui /etc/s6-overlay/s6-rc.d/hermes-webui
COPY docker/s6-rc.d/user/contents.d/hermes-webui /etc/s6-overlay/s6-rc.d/user/contents.d/hermes-webui
RUN chmod 755 /etc/s6-overlay/s6-rc.d/hermes-webui/run \
              /etc/s6-overlay/s6-rc.d/hermes-webui/finish

# ---------------------------------------------------------------------------
# Labels / env (do not override ENTRYPOINT/CMD — keep stock /init)
# ---------------------------------------------------------------------------
ARG AGENT_VERSION=v2026.7.20
ARG HERMES_WEBUI_VERSION=v0.52.76

LABEL org.opencontainers.image.title="Hermes Suite" \
      org.opencontainers.image.description="Official hermes-agent plus optional hermes-webui (s6)" \
      org.opencontainers.image.source="https://github.com/pepperlink/hermes-suite" \
      hermes-suite.agent-version="${AGENT_VERSION}" \
      hermes-suite.webui-version="${HERMES_WEBUI_VERSION}"

ENV PATH="/opt/hermes-webui/venv/bin:${PATH}"
ENV HERMES_WEBUI_HOST=0.0.0.0
ENV HERMES_WEBUI_PORT=8787
ENV HERMES_WEBUI_STATE_DIR=/opt/data/webui
ENV HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace
ENV HERMES_WEBUI_AGENT_DIR=/opt/hermes

# WebUI port (agent already exposes 8642 / 9119)
EXPOSE 8787

# ENTRYPOINT/CMD inherited from nousresearch/hermes-agent:
#   ENTRYPOINT ["/init", "/opt/hermes/docker/main-wrapper.sh"]
#   CMD []
