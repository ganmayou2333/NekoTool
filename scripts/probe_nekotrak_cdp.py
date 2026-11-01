#!/usr/bin/env python3
"""Probe NekoTrak's WebView2 for pomodoro state over CDP (opt-in spike).

Why this exists: the plaintext NekoTrak data root has no pomodoro *session*
state. Every database under ``%APPDATA%\\NekoTrak`` is encrypted (no SQLite
header) and ``tracker-heartbeat.json`` is NKSC ciphertext, so the remaining
time is only reachable from inside the running app.

NekoTrak must be started with::

    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222

Nothing here changes a launch configuration, writes a setting or ships with the
collector: it is a read-only probe of a port the user enabled by hand. The
default collection path (L1 plaintext) never imports this module.

The probe deliberately does not guess Tauri command names. It reports what the
page actually exposes -- target list, ``__TAURI_INTERNALS__`` keys, interesting
global names, storage keys and any visible ``mm:ss`` countdown -- because the
spike's question is "is the timer reachable at all", not "which of our guesses
happens to be right".

Usage:
    python scripts/probe_nekotrak_cdp.py
    python scripts/probe_nekotrak_cdp.py --json
    python scripts/probe_nekotrak_cdp.py --endpoint http://127.0.0.1:9223
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from typing import Any

try:
    import websocket  # websocket-client, already required by hr_collector
except ImportError:  # pragma: no cover - only on a broken install
    websocket = None

DEFAULT_ENDPOINT = "http://127.0.0.1:9222"
PROBE_TIMEOUT_SECONDS = 2.0

# Runs inside the page. Everything is defensive: a broken page must produce a
# partial report, never an exception that hides what *is* visible.
INSPECT_SCRIPT = r"""
(() => {
  const result = {
    url: location.href,
    title: document.title,
    tauriKeys: [],
    globals: [],
    storageKeys: [],
    countdowns: [],
    bodySample: "",
  };

  try {
    const tauri = window.__TAURI_INTERNALS__;
    result.tauriKeys = tauri ? Object.getOwnPropertyNames(tauri).slice(0, 40) : [];
  } catch (error) {
    result.tauriKeys = ["<error: " + error + ">"];
  }

  try {
    result.globals = Object.getOwnPropertyNames(window)
      .filter((name) => /pomodoro|timer|focus|session|interval/i.test(name))
      .slice(0, 40);
  } catch (error) {
    result.globals = [];
  }

  try {
    result.storageKeys = Object.keys(window.localStorage).slice(0, 40);
  } catch (error) {
    result.storageKeys = [];
  }

  try {
    const text = document.body ? document.body.innerText : "";
    // The visible countdown is the cheapest signal that the timer is running.
    const matches = text.match(/\b\d{1,3}:\d{2}\b/g) || [];
    result.countdowns = [...new Set(matches)].slice(0, 10);
    result.bodySample = text.replace(/\s+/g, " ").trim().slice(0, 400);
  } catch (error) {
    result.bodySample = "<error: " + error + ">";
  }

  return JSON.stringify(result);
})()
"""


def _http_json(url: str, timeout: float) -> Any:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - loopback only
        return json.loads(response.read(2 * 1024 * 1024).decode("utf-8", "replace"))


def discover_targets(endpoint: str, timeout: float = PROBE_TIMEOUT_SECONDS) -> dict[str, Any]:
    """List CDP targets, or explain why the port is not available."""

    deadline = time.perf_counter() + timeout
    last_error: str | None = None
    for path in ("/json/list", "/json"):
        remaining = deadline - time.perf_counter()
        if remaining <= 0.05:
            last_error = "CDP discovery timed out"
            break
        try:
            payload = _http_json(endpoint.rstrip("/") + path, remaining)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = f"not enabled: {exc}"
            continue
        except (json.JSONDecodeError, ValueError) as exc:
            last_error = f"response was not JSON: {exc}"
            continue

        targets = []
        for item in payload if isinstance(payload, list) else []:
            if not isinstance(item, dict):
                continue
            targets.append(
                {
                    "id": item.get("id"),
                    "type": item.get("type"),
                    "title": item.get("title"),
                    "url": item.get("url"),
                    "webSocketDebuggerUrl": item.get("webSocketDebuggerUrl"),
                }
            )
        return {"available": True, "targets": targets, "error": None}

    return {"available": False, "targets": [], "error": last_error or "unavailable"}


def _pick_page(targets: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Pick the app window, not a browser-internal page.

    A WebView2 host can expose several page targets (first-run dialogs, sync
    prompts, devtools). Choosing ``targets[0]`` picks whichever Chromium
    happened to open first, which is how the first run of this probe ended up
    inspecting ``edge://sync-confirmation-dialog`` instead of the app.
    """

    pages = [
        target
        for target in targets
        if target.get("type") == "page"
        and target.get("webSocketDebuggerUrl")
        and not (target.get("url") or "").lower().startswith(("devtools://",))
    ]
    if not pages:
        return None

    def rank(target: dict[str, Any]) -> int:
        url = (target.get("url") or "").lower()
        if "tauri.localhost" in url or "nekotrak" in url:
            return 0
        if url.startswith(("http://", "https://")):
            return 1
        if url.startswith("file://"):
            return 2
        if url in ("about:blank", ""):
            return 4
        return 3  # edge://, chrome://, other browser internals

    return min(pages, key=rank)


def evaluate(ws_url: str, expression: str, timeout: float = PROBE_TIMEOUT_SECONDS) -> dict[str, Any]:
    """Run one expression in the page via Runtime.evaluate."""

    if websocket is None:
        return {"ok": False, "error": "websocket-client is not installed", "value": None}

    connection = None
    try:
        connection = websocket.create_connection(ws_url, timeout=timeout)
        connection.send(json.dumps({
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {"expression": expression, "returnByValue": True, "awaitPromise": False},
        }))

        deadline = time.perf_counter() + timeout
        while time.perf_counter() < deadline:
            raw = connection.recv()
            if not raw:
                continue
            message = json.loads(raw)
            if message.get("id") != 1:
                continue  # ignore unsolicited events
            if "error" in message:
                return {"ok": False, "error": str(message["error"]), "value": None}
            result = message.get("result", {})
            if result.get("exceptionDetails"):
                return {
                    "ok": False,
                    "error": str(result["exceptionDetails"]),
                    "value": None,
                }
            remote = result.get("result", {})
            value = remote.get("value")
            if isinstance(value, str):
                try:
                    value = json.loads(value)
                except (json.JSONDecodeError, ValueError):
                    pass
            return {"ok": True, "error": None, "value": value}

        return {"ok": False, "error": "no Runtime.evaluate reply before the deadline", "value": None}
    except Exception as exc:  # noqa: BLE001 - a spike must report, never crash
        return {"ok": False, "error": str(exc), "value": None}
    finally:
        if connection is not None:
            try:
                connection.close()
            except Exception:  # noqa: BLE001
                pass


def probe(endpoint: str = DEFAULT_ENDPOINT, timeout: float = PROBE_TIMEOUT_SECONDS) -> dict[str, Any]:
    started = time.perf_counter()
    discovery = discover_targets(endpoint, timeout=timeout)
    report: dict[str, Any] = {
        "endpoint": endpoint,
        "available": discovery["available"],
        "targets": discovery["targets"],
        "page": None,
        "inspection": None,
        "summary": None,
        "error": discovery["error"],
        "latencyMs": None,
    }

    if not discovery["available"]:
        report["summary"] = (
            "CDP port is not open. Start NekoTrak with "
            "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222 and retry."
        )
        report["latencyMs"] = round((time.perf_counter() - started) * 1000.0, 1)
        return report

    page = _pick_page(discovery["targets"])
    if page is None:
        report["summary"] = "CDP is open but exposes no page target with a debugger URL."
        report["latencyMs"] = round((time.perf_counter() - started) * 1000.0, 1)
        return report

    report["page"] = {"id": page["id"], "title": page["title"], "url": page["url"]}
    evaluation = evaluate(page["webSocketDebuggerUrl"], INSPECT_SCRIPT, timeout=timeout)
    report["inspection"] = evaluation

    if not evaluation["ok"]:
        report["summary"] = f"Could not evaluate in the page: {evaluation['error']}"
    else:
        value = evaluation["value"] or {}
        countdowns = value.get("countdowns") or []
        tauri_keys = value.get("tauriKeys") or []
        if countdowns:
            report["summary"] = (
                f"Visible countdown(s) found: {', '.join(countdowns)}. "
                f"__TAURI_INTERNALS__ keys: {', '.join(tauri_keys) or 'none'}."
            )
        else:
            report["summary"] = (
                "No visible mm:ss countdown on screen. "
                f"__TAURI_INTERNALS__ keys: {', '.join(tauri_keys) or 'none'}; "
                f"needs a running timer or an IPC command name to go further."
            )

    report["latencyMs"] = round((time.perf_counter() - started) * 1000.0, 1)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    parser.add_argument("--timeout", type=float, default=PROBE_TIMEOUT_SECONDS)
    parser.add_argument("--json", action="store_true", help="print the raw report")
    args = parser.parse_args(argv)

    report = probe(args.endpoint, args.timeout)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"endpoint: {report['endpoint']}")
        print(f"available: {report['available']}  ({report['latencyMs']} ms)")
        if report["page"]:
            print(f"page: {report['page']['title']}  {report['page']['url']}")
        print(f"summary: {report['summary']}")
        if report["error"]:
            print(f"error: {report['error']}")
    return 0 if report["available"] else 2


if __name__ == "__main__":
    sys.exit(main())
