# Hermes Suite

Thin image on top of official [`nousresearch/hermes-agent`](https://hub.docker.com/r/nousresearch/hermes-agent):

- **Same entrypoint** as upstream (`/init` + s6-overlay)
- **Same** gateway / dashboard / profile supervision
- **Plus** optional [hermes-webui](https://github.com/nesquena/hermes-webui) as an s6 service

With `HERMES_WEBUI` unset or `0`, this image is a drop-in replacement for the official agent container.

## Quick start

```bash
# Build (pins from versions.env)
./build.sh

# Run like official agent
docker run --rm -it \
  -v ~/.hermes:/opt/data \
  -p 8642:8642 \
  hermes-suite:2026.9.7-0.52.113 \
  gateway run

# Enable WebUI (and optionally dashboard)
docker run --rm -it \
  -v ~/.hermes:/opt/data \
  -p 8642:8642 -p 8787:8787 -p 9119:9119 \
  -e HERMES_WEBUI=1 \
  -e HERMES_DASHBOARD=1 \
  -e HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin \
  -e HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=admin \
  hermes-suite:2026.9.7-0.52.113 \
  gateway run
```

Or use compose helpers:

```bash
# edit versions.env — set HERMES_WEBUI=1 if desired
./up.sh
./logs.sh
./down.sh
```

## Environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `HERMES_WEBUI` | unset/`0` | Start hermes-webui on `:8787` (suite s6 service) |
| `HERMES_DASHBOARD` | unset/`0` | Start upstream dashboard on `:9119` |
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` / `_PASSWORD` | — | Required for non-loopback dashboard |
| `HERMES_UID` / `HERMES_GID` | — | Remap `hermes` user (official stage2) |

WebUI knobs (optional): `HERMES_WEBUI_HOST`, `HERMES_WEBUI_PORT`, `HERMES_WEBUI_STATE_DIR`, `HERMES_WEBUI_DEFAULT_WORKSPACE`, `HERMES_WEBUI_AGENT_DIR`.

## How WebUI is supervised

Upstream s6 pattern (same as dashboard):

- `/etc/s6-overlay/s6-rc.d/hermes-webui/run` — starts only when `HERMES_WEBUI` is truthy
- `finish` exits `125` when disabled so s6 does not restart-loop

PID 1 remains `/init`. Do **not** override the image entrypoint.

## Kubernetes

Use this image exactly like `nousresearch/hermes-agent`. Leave the entrypoint alone; set env vars and ports as needed. Example:

```yaml
env:
  - name: HERMES_WEBUI
    value: "1"
ports:
  - containerPort: 8642
  - containerPort: 8787
```

## Versions

Pins live in `versions.env`. CI builds multi-arch (or amd64) images to GHCR with suite semver + upstream compound tags.

## Build & deploy

- **Image:** `ghcr.io/pepperlink/hermes-suite` — tags: suite semver (e.g. `0.3.2`, moving `0.3`, `latest`) plus compound upstream pins (e.g. `2026.9.14-0.52.113`). Built for `linux/amd64`; the arm64 line in the build is commented out.
- **Build:** GitHub Actions [`.github/workflows/build.yml`](.github/workflows/build.yml) on pushes to `main` touching `versions.env`, `Dockerfile` or `docker/**` (also `v*` tags, manual dispatch). Renovate bumps the pins in `versions.env`; each build auto-bumps the suite semver, pushes the image, and creates the git tag + GitHub Release.
- **Deploy:** `pepperlink/home` → ArgoCD app `ai/hermes-agent` (`kubernetes/applications/ai/hermes-agent.yaml`); Renovate opens the tag-bump PRs — merging deploys.
- **Manual:** upstream merges from `sunnysktsang/hermes-suite` are done by hand.

## License

MIT — see `LICENSE`. Upstream: hermes-agent (Nous Research), hermes-webui (nesquena).
