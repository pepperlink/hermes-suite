"""DonSeTch MCP web search and extract provider."""

from __future__ import annotations

import json
import logging
import os
import re
from typing import Any

logger = logging.getLogger(__name__)

_SEARCH_DEBUG_KEY = "com.donsetch/search-debug"
_FETCH_DEBUG_KEY = "com.donsetch/fetch-debug"

_MARKDOWN_RESULT_RE = re.compile(
    r"^\s*(\d+)\.\s+(.+?)\s+·\s+(.+?)\s+·\s+(.+?)\s*$"
)


def _env(key: str, default: str = "") -> str:
    try:
        from hermes_cli.config import get_env_value

        val = get_env_value(key)
    except Exception:
        val = None
    if val is None:
        val = os.getenv(key, "")
    return (val or default).strip()


def _jsonrpc_error_message(body: dict[str, Any]) -> str:
    err = body.get("error") or {}
    msg = err.get("message") or "unknown JSON-RPC error"
    code = err.get("code")
    if code is not None:
        return f"{msg} (code={code})"
    return str(msg)


def _result_text_and_meta(result: dict[str, Any]) -> tuple[str, dict[str, Any], dict[str, Any]]:
    content = result.get("content") or []
    text = ""
    if content and isinstance(content[0], dict):
        text = content[0].get("text") or ""
    meta = result.get("_meta") or {}
    struct = result.get("structuredContent") or {}
    return text, meta, struct


def _log_search_degradation(debug: dict[str, Any], struct: dict[str, Any]) -> None:
    weak = struct.get("weak")
    if weak is None:
        weak = debug.get("weak")
    if weak:
        logger.warning("donsetch web_search: weak retrieval (rerank/consensus degraded)")

    engines = debug.get("engines") or []
    if engines:
        ok = sum(1 for e in engines if (e.get("status") or "").startswith("ok"))
        if ok < len(engines) / 2:
            logger.warning(
                "donsetch web_search: minority of engines answered (%s/%s ok)",
                ok,
                len(engines),
            )


def _parse_markdown_search_results(text: str, limit: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        m = _MARKDOWN_RESULT_RE.match(line)
        if not m:
            continue
        pos = int(m.group(1))
        title = m.group(2).strip()
        site = m.group(3).strip()
        snippet = m.group(4).strip()
        url = site if site.startswith("http") else f"https://{site}"
        rows.append(
            {
                "title": title,
                "url": url,
                "description": snippet,
                "position": pos,
            }
        )
        if len(rows) >= limit:
            break
    return rows[:limit]


def _map_search_payload(result: dict[str, Any], limit: int) -> dict[str, Any]:
    if result.get("isError"):
        text, _, _ = _result_text_and_meta(result)
        return {"success": False, "error": text or "donsetch web_search returned isError"}

    text, meta, struct = _result_text_and_meta(result)
    debug = meta.get(_SEARCH_DEBUG_KEY) or {}
    _log_search_degradation(debug, struct)

    raw_results = debug.get("results") or []
    web: list[dict[str, Any]] = []
    for i, r in enumerate(raw_results[:limit]):
        web.append(
            {
                "title": r.get("title") or "",
                "url": r.get("url") or "",
                "description": r.get("snippet") or "",
                "position": i + 1,
            }
        )

    if not web and text.strip():
        web = _parse_markdown_search_results(text, limit)

    return {"success": True, "data": {"web": web}}


def _map_search_jsonrpc_body(body: dict[str, Any], limit: int) -> dict[str, Any]:
    if "error" in body and "result" not in body:
        return {"success": False, "error": _jsonrpc_error_message(body)}
    result = body.get("result")
    if not isinstance(result, dict):
        return {"success": False, "error": "invalid MCP response: missing result"}
    return _map_search_payload(result, limit)


def _map_fetch_payload(result: dict[str, Any], url: str) -> dict[str, Any]:
    if result.get("isError"):
        text, _, _ = _result_text_and_meta(result)
        return {
            "url": url,
            "title": "",
            "content": text,
            "raw_content": text,
            "error": text or "donsetch web_fetch returned isError",
        }

    text, meta, struct = _result_text_and_meta(result)
    debug = meta.get(_FETCH_DEBUG_KEY) or {}

    row: dict[str, Any] = {
        "url": struct.get("url") or url,
        "title": debug.get("title") or "",
        "content": text,
        "raw_content": text,
        "metadata": {
            "tier": debug.get("tier"),
            "verdict": debug.get("verdict"),
        },
    }
    if struct.get("content_ok") is False:
        row["error"] = (
            f"donsetch {debug.get('verdict')} (status={debug.get('status')})"
        )
    return row


def _map_fetch_jsonrpc_body(body: dict[str, Any], url: str) -> dict[str, Any]:
    if "error" in body and "result" not in body:
        return {
            "url": url,
            "title": "",
            "content": "",
            "raw_content": "",
            "error": _jsonrpc_error_message(body),
        }
    result = body.get("result")
    if not isinstance(result, dict):
        return {
            "url": url,
            "title": "",
            "content": "",
            "raw_content": "",
            "error": "invalid MCP response: missing result",
        }
    return _map_fetch_payload(result, url)


class _DonsetchWebSearchProviderBase:
    """Web search/extract via DonSeTch MCP (stateless tools/call)."""

    name = "donsetch"
    display_name = "DonSeTch"

    def _mcp_url(self) -> str:
        return _env("DONSETCH_MCP_URL", "http://donsetch:8765/mcp")

    def _timeout(self) -> float:
        try:
            return float(_env("DONSETCH_TIMEOUT", "60"))
        except ValueError:
            return 60.0

    def _headers(self) -> dict[str, str]:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        token = _env("DONSETCH_MCP_TOKEN", "")
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return headers

    def _fetch_tier(self) -> str:
        return _env("DONSETCH_FETCH_TIER", "auto")

    def is_available(self) -> bool:
        return bool(_env("DONSETCH_MCP_URL", "http://donsetch:8765/mcp"))

    def supports_search(self) -> bool:
        return True

    def supports_extract(self) -> bool:
        return True

    def _tools_call_payload(self, tool_name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        return {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": arguments},
        }

    def _parse_response_json(self, raw: str) -> dict[str, Any]:
        raw = raw.strip()
        if raw.startswith("{"):
            return json.loads(raw)
        for line in raw.splitlines():
            line = line.strip()
            if line.startswith("data:"):
                payload = line[5:].strip()
                if payload.startswith("{"):
                    return json.loads(payload)
        return json.loads(raw)

    def search(self, query: str, limit: int = 5) -> dict:
        import requests

        url = self._mcp_url()
        payload = self._tools_call_payload(
            "web_search",
            {"query": query, "max_results": limit},
        )
        try:
            resp = requests.post(
                url,
                headers=self._headers(),
                json=payload,
                timeout=self._timeout(),
            )
            resp.raise_for_status()
            body = self._parse_response_json(resp.text)
        except requests.RequestException as exc:
            return {"success": False, "error": str(exc)}
        except json.JSONDecodeError as exc:
            return {"success": False, "error": f"invalid JSON: {exc}"}

        return _map_search_jsonrpc_body(body, limit)

    async def extract(self, urls, **kwargs) -> list:
        import httpx

        # tier may escalate to DonSeTch's headless browser on bot walls;
        # escalation list in fetch-debug _meta is the audit trail.
        tier = self._fetch_tier()
        mcp_url = self._mcp_url()
        timeout = self._timeout()
        headers = self._headers()
        out: list[dict[str, Any]] = []

        async with httpx.AsyncClient(timeout=timeout) as client:
            for u in urls:
                url_str = str(u)
                payload = self._tools_call_payload(
                    "web_fetch",
                    {"url": url_str, "tier": tier},
                )
                try:
                    resp = await client.post(mcp_url, headers=headers, json=payload)
                    resp.raise_for_status()
                    body = self._parse_response_json(resp.text)
                    out.append(_map_fetch_jsonrpc_body(body, url_str))
                except httpx.HTTPError as exc:
                    out.append(
                        {
                            "url": url_str,
                            "title": "",
                            "content": "",
                            "raw_content": "",
                            "error": str(exc),
                        }
                    )
                except json.JSONDecodeError as exc:
                    out.append(
                        {
                            "url": url_str,
                            "title": "",
                            "content": "",
                            "raw_content": "",
                            "error": f"invalid JSON: {exc}",
                        }
                    )
                except Exception as exc:
                    out.append(
                        {
                            "url": url_str,
                            "title": "",
                            "content": "",
                            "raw_content": "",
                            "error": str(exc)[:200],
                        }
                    )
        return out


try:
    from agent.web_search_provider import WebSearchProvider as _WebSearchProvider

    class DonsetchWebSearchProvider(_DonsetchWebSearchProviderBase, _WebSearchProvider):
        pass
except ImportError:

    class DonsetchWebSearchProvider(_DonsetchWebSearchProviderBase):
        pass
