#!/usr/bin/env python3
"""NekoTool heart-rate WebSocket collector (v3.2).

Listens to a local heart-rate app / bridge over WebSocket (default
``ws://localhost:8406/chat``), extracts the latest BPM and writes it atomically
to ``NekoTool/data/heart_rate.json``:

.. code-block:: json

    {"bpm": 82, "timestamp": 1792860000.123, "source": "ws://localhost:8406/chat"}

``plugins/heart_rate.ps1`` only shows the value while ``timestamp`` is less than
10 seconds old, so stopping this collector naturally makes the status line fall
back to ``❤️ --``.

Install the one dependency and start it in a separate terminal::

    pip install websocket-client
    python collectors/hr_collector.py

Useful options::

    python collectors/hr_collector.py --url ws://127.0.0.1:8406/chat
    python collectors/hr_collector.py --output data/heart_rate.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

NEKOTOOL_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_URL = os.environ.get("HR_WS_URL", "ws://localhost:8406/chat")
DEFAULT_OUTPUT = Path(os.environ.get("HR_OUTPUT", NEKOTOOL_ROOT / "data" / "heart_rate.json"))

MIN_BPM = 25
MAX_BPM = 250

# Keys commonly used by heart-rate bridges / apps.  Matching is case-insensitive.
_BPM_KEYS = {
    "bpm",
    "heartrate",
    "heart_rate",
    "heartratebpm",
    "heart_rate_bpm",
    "rate",
    "value",
}
_CONTAINER_KEYS = ("data", "payload", "result", "message", "event", "heart")


def _valid_bpm(value: float) -> int | None:
    """Round a numeric reading and reject values outside a sane BPM range."""
    if not (MIN_BPM <= value <= MAX_BPM):
        return None
    return int(round(value))


def extract_bpm(payload: Any) -> int | None:
    """Best-effort BPM extraction from JSON-like WebSocket payloads.

    Supports plain numbers, numeric strings, ``{"bpm": 82}``,
    ``{"heartRate": 82}``, ``{"data": {"heart_rate": 82}}`` and simple
    ``"82 bpm"`` text.  Unknown fields are ignored.
    """
    if isinstance(payload, bool):
        return None

    if isinstance(payload, (int, float)):
        return _valid_bpm(float(payload))

    if isinstance(payload, str):
        text = payload.strip()
        if not text:
            return None
        try:
            return _valid_bpm(float(text))
        except ValueError:
            pass
        try:
            return extract_bpm(json.loads(text))
        except Exception:
            pass
        match = re.search(
            r"(?:bpm[^0-9]{0,8}(\d{2,3}))|(?:(\d{2,3})\s*bpm)", text, re.IGNORECASE
        )
        if match:
            return _valid_bpm(float(match.group(1) or match.group(2)))
        return None

    if isinstance(payload, dict):
        lowered = {str(key).lower(): key for key in payload}
        for key in _BPM_KEYS:
            if key in lowered:
                result = extract_bpm(payload[lowered[key]])
                if result is not None:
                    return result
        for key in _CONTAINER_KEYS:
            if key in lowered:
                result = extract_bpm(payload[lowered[key]])
                if result is not None:
                    return result
        for lower, original in lowered.items():
            if "bpm" in lower or ("heart" in lower and "rate" in lower):
                result = extract_bpm(payload[original])
                if result is not None:
                    return result
        return None

    if isinstance(payload, list):
        for item in reversed(payload):
            result = extract_bpm(item)
            if result is not None:
                return result

    return None


def write_heart_rate(output: Path, bpm: int, source: str) -> dict[str, Any]:
    """Atomically write the latest reading so the PowerShell plugin never sees
    a half-written JSON file."""
    output.parent.mkdir(parents=True, exist_ok=True)
    now = time.time()
    record: dict[str, Any] = {
        "bpm": int(bpm),
        "timestamp": round(now, 3),
        "source": source,
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    probe = output.with_name(f"{output.name}.{os.getpid()}.tmp")
    probe.write_text(json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(probe, output)
    return record


def run_collector(
    url: str,
    output: Path,
    reconnect_min: float = 1.0,
    reconnect_max: float = 15.0,
) -> int:
    try:
        import websocket  # websocket-client
    except ImportError:
        print(
            "Missing dependency: websocket-client. Run: pip install -r requirements.txt",
            file=sys.stderr,
        )
        return 2

    reconnect_min = max(0.5, reconnect_min)
    reconnect_max = max(reconnect_min, reconnect_max)
    delay = reconnect_min
    ws = None

    print(f"[hr] data file: {output}", flush=True)
    while True:
        try:
            print(f"[hr] connecting {url} ...", flush=True)
            ws = websocket.create_connection(url, timeout=10)
            ws.settimeout(60)
            print("[hr] connected, waiting for heart-rate data ...", flush=True)
            delay = reconnect_min

            while True:
                try:
                    raw = ws.recv()
                except websocket.WebSocketTimeoutException:
                    # No data for 60 s: keep the socket open and wait.
                    continue
                if raw is None or raw == "":
                    raise ConnectionError("WebSocket closed")
                text = (
                    raw.decode("utf-8", "replace")
                    if isinstance(raw, (bytes, bytearray))
                    else str(raw)
                )
                bpm = extract_bpm(text)
                if bpm is None:
                    continue
                write_heart_rate(output, bpm, url)
                print(f"[hr] {bpm} BPM", flush=True)

        except KeyboardInterrupt:
            print("\n[hr] stopped", flush=True)
            return 0
        except Exception as exc:
            print(
                f"[hr] disconnected: {type(exc).__name__}: {exc}; "
                f"retrying in {delay:.1f}s",
                flush=True,
            )
            time.sleep(delay)
            delay = min(reconnect_max, delay * 2)
        finally:
            if ws is not None:
                try:
                    ws.close()
                except Exception:
                    pass
                ws = None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect heart-rate BPM from a WebSocket into NekoTool/data/heart_rate.json."
    )
    parser.add_argument("--url", default=DEFAULT_URL, help=f"WebSocket URL (default: {DEFAULT_URL})")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output JSON path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument("--reconnect-min", type=float, default=1.0)
    parser.add_argument("--reconnect-max", type=float, default=15.0)
    args = parser.parse_args()

    return run_collector(
        args.url,
        args.output.expanduser(),
        reconnect_min=args.reconnect_min,
        reconnect_max=args.reconnect_max,
    )


if __name__ == "__main__":
    sys.exit(main())
