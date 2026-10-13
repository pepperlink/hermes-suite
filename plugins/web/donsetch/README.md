# DonSeTch web provider

Self-hosted web search and page extract for Hermes via the [DonSeTch](https://github.com/pepperlink/donsetch) MCP service over HTTP.

## Configuration

```yaml
web:
  search_backend: searxng
  extract_backend: donsetch
  keyless_rescue: false
plugins:
  enabled:
    - web/donsetch
```

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `DONSETCH_MCP_URL` | `http://donsetch:8765/mcp` | MCP JSON-RPC endpoint |
| `DONSETCH_MCP_TOKEN` | (empty) | Optional bearer token |
| `DONSETCH_FETCH_TIER` | `auto` | Fetch tier passed to `web_fetch` |
| `DONSETCH_TIMEOUT` | `60` | HTTP timeout (seconds) |

## Installation on agent pods

Copy this directory into the agent data volume:

```text
plugins/web/donsetch/  →  /opt/data/plugins/web/donsetch/
```

Restart or reload the agent so the plugin registry picks up `web/donsetch`. Ensure `DONSETCH_MCP_URL` points at your DonSeTch service (for example `http://donsetch:8765/mcp` in-cluster).

## Local checks

```sh
python3 -m py_compile plugins/web/donsetch/*.py
python3 plugins/web/donsetch/selftest.py
```
