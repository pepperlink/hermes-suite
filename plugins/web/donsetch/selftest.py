#!/usr/bin/env python3
"""Offline mapping checks for DonSeTch web provider (stdlib only)."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("donsetch_provider", _ROOT / "provider.py")
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load provider.py")
_provider = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_provider)

_map_fetch_jsonrpc_body = _provider._map_fetch_jsonrpc_body
_map_fetch_payload = _provider._map_fetch_payload
_map_search_jsonrpc_body = _provider._map_search_jsonrpc_body
_map_search_payload = _provider._map_search_payload

SEARCH_FIXTURE = {
    "result": {
        "_meta": {
            "com.donsetch/search-debug": {
                "cached": False,
                "elapsed_ms": 4613,
                "rerank": "on",
                "weak": False,
                "intent": "Web",
                "engines": [
                    {"engine": "bing", "hits": 10, "status": "ok"},
                    {"engine": "brave", "hits": 0, "status": "blocked:429"},
                ],
                "results": [
                    {
                        "title": "Notes | Kubernetes",
                        "url": "https://v1-34.docs.kubernetes.io/releases/notes/",
                        "snippet": "Release notes can be found by reading the Changelog...",
                        "score": 2.473,
                        "consensus": 1,
                        "engines": ["ddg"],
                    }
                ],
            }
        },
        "content": [
            {
                "type": "text",
                "text": "# Search results 1. Notes | Kubernetes ...",
            }
        ],
        "structuredContent": {
            "weak": False,
            "results": [
                {
                    "handle": "abc123",
                    "rank": 1,
                    "url": "https://...",
                }
            ],
        },
    }
}

FETCH_FIXTURE = {
    "result": {
        "_meta": {
            "com.donsetch/fetch-debug": {
                "title": "Example Domain",
                "tier": "1",
                "verdict": "ContentOk",
                "status": 200,
                "quality": 0.433,
                "tokens_est": 49,
                "total_chars": 196,
                "via": None,
                "escalation": [
                    {
                        "action": "domain-profile",
                        "outcome": "cold",
                        "tier": "route",
                    },
                    {
                        "action": "http-fetch",
                        "ms": 26,
                        "outcome": "ContentOk status=200",
                        "tier": "1",
                    },
                ],
            }
        },
        "content": [
            {
                "type": "text",
                "text": "# Example Domain\nhttps://example.com/\n\nThis domain is for use...",
            }
        ],
        "structuredContent": {
            "url": "https://example.com/",
            "changed": "unchanged",
            "content_kind": "Page",
            "content_ok": True,
            "lang": "en",
            "server_modified": "Fri, 09 Oct 2026 20:19:47 GMT",
        },
    }
}

JSONRPC_ERROR_FIXTURE = {
    "error": {"code": -32600, "message": "Invalid Request"},
}


def _fail(msg: str) -> None:
    print(f"FAIL {msg}", file=sys.stderr)
    sys.exit(1)


def _pass(label: str) -> None:
    print(f"PASS {label}")


def main() -> None:
    mapped = _map_search_payload(SEARCH_FIXTURE["result"], limit=5)
    if not mapped.get("success"):
        _fail("search mapping success is True")
    _pass("search mapping success is True")

    web = mapped.get("data", {}).get("web", [])
    if len(web) != 1:
        _fail(f"search mapping len(data['web']) == 1 (got {len(web)})")
    _pass("search mapping len(data['web']) == 1")

    expected_row = {
        "title": "Notes | Kubernetes",
        "url": "https://v1-34.docs.kubernetes.io/releases/notes/",
        "description": "Release notes can be found by reading the Changelog...",
        "position": 1,
    }
    if web[0] != expected_row:
        _fail(f"search row mismatch: {web[0]!r}")
    _pass("search mapping row fields")

    body_mapped = _map_search_jsonrpc_body(SEARCH_FIXTURE, limit=5)
    if body_mapped.get("success") is not True or body_mapped["data"]["web"][0] != expected_row:
        _fail("search JSON-RPC body wrapper")
    _pass("search JSON-RPC body wrapper")

    fetch = _map_fetch_payload(FETCH_FIXTURE["result"], "https://example.com")
    if not fetch.get("content", "").startswith("# Example Domain"):
        _fail("fetch content prefix")
    _pass("fetch content starts with # Example Domain")

    if fetch.get("title") != "Example Domain":
        _fail("fetch title")
    _pass("fetch title == Example Domain")

    tier = (fetch.get("metadata") or {}).get("tier")
    if tier != "1":
        _fail(f"fetch metadata tier (got {tier!r})")
    _pass('fetch metadata["tier"] == "1"')

    err_search = _map_search_jsonrpc_body(JSONRPC_ERROR_FIXTURE, limit=5)
    if err_search.get("success") is not False:
        _fail("JSON-RPC error search success is False")
    if "Invalid Request" not in (err_search.get("error") or ""):
        _fail("JSON-RPC error search message")
    _pass("JSON-RPC error maps to search success False + message")

    err_fetch = _map_fetch_jsonrpc_body(
        JSONRPC_ERROR_FIXTURE, "https://example.com"
    )
    if "error" not in err_fetch:
        _fail("JSON-RPC error fetch row missing error")
    if "Invalid Request" not in err_fetch["error"]:
        _fail("JSON-RPC error fetch message")
    _pass("JSON-RPC error maps to per-URL fetch error row")

    print("All assertions passed.")


if __name__ == "__main__":
    main()
