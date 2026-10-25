#!/usr/bin/env python3
"""NekoTool local dashboard server.

Zero-dependency control backend for the NekoTool web dashboard:

- serves ``web/dashboard.html``
- proxies StatusCast's local ``/status/`` API
- lists, toggles and edits files under ``plugins/``
- runs ``scripts/ultimate_status.ps1`` for the live preview

The server binds to loopback only. It is intentionally not part of StatusCast
and never touches the C# daemon.
"""

from __future__ import annotations

import argparse
import codecs
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent if SCRIPT_DIR.name.lower() == "scripts" else SCRIPT_DIR
WEB_DIR = PROJECT_ROOT / "web"
PLUGIN_DIR = PROJECT_ROOT / "plugins"
ULTIMATE_SCRIPT = PROJECT_ROOT / "scripts" / "ultimate_status.ps1"
DASHBOARD_HTML = WEB_DIR / "dashboard.html"
WIDGET_HTML = WEB_DIR / "widget.html"


def _ensure_standard_streams() -> None:
    """pythonw.exe starts with sys.stdout/sys.stderr set to None.

    The desktop shell prefers pythonw.exe so no console window flashes. Without
    this guard, the server's startup banner and request logging would fail on
    the first write. Redirect missing streams to the null device instead.
    """

    if sys.stdout is None:
        sys.stdout = open(os.devnull, "w", encoding="utf-8")
    if sys.stderr is None:
        sys.stderr = open(os.devnull, "w", encoding="utf-8")


_ensure_standard_streams()


STATUS_URL = "http://127.0.0.1:5099/status/"
DEFAULT_STATUS_URL = STATUS_URL
MAX_BODY_BYTES = 4 * 1024 * 1024
MAX_PLUGIN_BYTES = 2 * 1024 * 1024
PREVIEW_TIMEOUT_SECONDS = 25.0
STATUS_TIMEOUT_SECONDS = 3.0

PLUGIN_LOCK = threading.Lock()
PREVIEW_LOCK = threading.Lock()


class ApiError(Exception):
    """An expected API error that should be shown to the user."""

    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.message = message
        self.status = status


def _json_bytes(payload: object) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def _send_json(handler: BaseHTTPRequestHandler, payload: object, status: int = 200) -> None:
    data = _json_bytes(payload)
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.end_headers()
    handler.wfile.write(data)


def _send_web_file(handler: BaseHTTPRequestHandler, path) -> None:
    try:
        data = path.read_bytes()
    except FileNotFoundError as exc:
        raise ApiError(f"页面文件不存在：{path}", 500) from exc

    handler.send_response(200)
    handler.send_header("Content-Type", "text/html; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Cache-Control", "no-cache")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.end_headers()
    handler.wfile.write(data)


def _read_json_body(handler: BaseHTTPRequestHandler) -> dict:
    try:
        length = int(handler.headers.get("Content-Length", "0"))
    except ValueError as exc:
        raise ApiError("Content-Length 无效", 400) from exc

    if length <= 0:
        raise ApiError("请求体为空", 400)
    if length > MAX_BODY_BYTES:
        raise ApiError("请求体过大", 413)

    content_type = (handler.headers.get("Content-Type") or "").split(";", 1)[0].strip().lower()
    if content_type != "application/json":
        raise ApiError("Content-Type 必须是 application/json", 415)

    raw = handler.rfile.read(length)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ApiError("JSON 解析失败", 400) from exc

    if not isinstance(payload, dict):
        raise ApiError("JSON 顶层必须是对象", 400)
    return payload


def _require_write_headers(handler: BaseHTTPRequestHandler) -> None:
    """Require the dashboard's custom header and a local Origin.

    The dashboard is same-origin, so a normal fetch sets the header. This blocks
    simple cross-site form posts against localhost.
    """

    if handler.headers.get("X-NekoTool-Dashboard") != "1":
        raise ApiError("缺少 X-NekoTool-Dashboard 请求头", 403)

    origin = handler.headers.get("Origin")
    if origin:
        parsed = urlparse(origin)
        host = (parsed.hostname or "").lower()
        if host not in {"127.0.0.1", "localhost"}:
            raise ApiError("不允许的 Origin", 403)


def _safe_plugin_name(raw_name: object) -> str:
    if not isinstance(raw_name, str):
        raise ApiError("缺少插件名", 400)

    name = raw_name.strip()
    if name.endswith(".ps1.disabled"):
        name = name[: -len(".disabled")]
    if not name.endswith(".ps1"):
        raise ApiError("插件名必须以 .ps1 结尾", 400)

    if (
        not name
        or name in {".ps1", "..", "."}
        or "/" in name
        or "\\" in name
        or ":" in name
        or "\x00" in name
        or Path(name).name != name
    ):
        raise ApiError("非法的插件名", 400)

    return name


def _plugin_paths(base_name: str) -> tuple[Path, Path]:
    return PLUGIN_DIR / base_name, PLUGIN_DIR / (base_name + ".disabled")


def _find_plugin(raw_name: object) -> tuple[str, Path, bool]:
    base_name = _safe_plugin_name(raw_name)
    enabled_path, disabled_path = _plugin_paths(base_name)

    enabled = enabled_path.is_file() and not enabled_path.is_symlink()
    disabled = disabled_path.is_file() and not disabled_path.is_symlink()

    if enabled and disabled:
        raise ApiError(f"插件同时存在启用和禁用文件：{base_name}", 409)
    if enabled:
        return base_name, enabled_path, True
    if disabled:
        return base_name, disabled_path, False
    raise ApiError(f"插件不存在：{base_name}", 404)


def _plugin_list() -> list[dict]:
    if not PLUGIN_DIR.is_dir():
        return []

    entries: list[dict] = []
    for path in sorted(PLUGIN_DIR.iterdir(), key=lambda item: item.name.lower()):
        if not path.is_file() or path.is_symlink():
            continue

        if path.name.endswith(".ps1"):
            name = path.name
            enabled = True
        elif path.name.endswith(".ps1.disabled"):
            name = path.name[: -len(".disabled")]
            enabled = False
        else:
            continue

        try:
            stat = path.stat()
        except OSError:
            continue

        entries.append(
            {
                "name": name,
                "enabled": enabled,
                "size": stat.st_size,
                "modified": int(stat.st_mtime),
            }
        )

    return entries


def _decode_text(raw: bytes) -> tuple[str, str]:
    if raw.startswith(codecs.BOM_UTF8):
        return raw.decode("utf-8-sig"), "utf-8-sig"
    try:
        return raw.decode("utf-8"), "utf-8"
    except UnicodeDecodeError:
        pass
    try:
        return raw.decode("gbk"), "gbk"
    except UnicodeDecodeError:
        return raw.decode("utf-8", errors="replace"), "utf-8"


def _read_plugin(path: Path) -> tuple[str, str]:
    return _decode_text(path.read_bytes())


def _write_plugin(path: Path, content: str) -> None:
    if len(content.encode("utf-8")) > MAX_PLUGIN_BYTES:
        raise ApiError("插件内容超过 2 MB 限制", 413)

    # Normalize to CRLF and always write UTF-8 BOM so Windows PowerShell 5.1
    # can read Chinese text in the plugin.
    normalized = content.replace("\r\n", "\n").replace("\r", "\n")
    if not normalized.endswith("\n"):
        normalized += "\n"
    data = codecs.BOM_UTF8 + normalized.replace("\n", "\r\n").encode("utf-8")

    backup_path = path.with_name(path.name + ".bak")
    try:
        shutil.copy2(path, backup_path)
    except OSError as exc:
        raise ApiError(f"备份插件失败：{exc}", 500) from exc

    fd, tmp_name = tempfile.mkstemp(
        prefix=".dashboard-", suffix=".tmp", dir=str(path.parent)
    )
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    except OSError as exc:
        raise ApiError(f"保存插件失败：{exc}", 500) from exc
    finally:
        try:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
        except OSError:
            pass


def _powershell_path() -> str:
    found = shutil.which("powershell.exe") or shutil.which("powershell")
    if found:
        return found

    system_root = os.environ.get("SystemRoot", r"C:\Windows")
    candidate = (
        Path(system_root)
        / "System32"
        / "WindowsPowerShell"
        / "v1.0"
        / "powershell.exe"
    )
    if candidate.is_file():
        return str(candidate)
    return "powershell.exe"


def _decode_process_output(raw: bytes) -> str:
    if not raw:
        return ""
    if raw.startswith(codecs.BOM_UTF8):
        return raw.decode("utf-8-sig", errors="replace")
    if b"\x00" in raw[:8]:
        try:
            return raw.decode("utf-16-le")
        except UnicodeDecodeError:
            pass
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        try:
            return raw.decode("gbk")
        except UnicodeDecodeError:
            return raw.decode("utf-8", errors="replace")


def _run_preview() -> dict:
    if not ULTIMATE_SCRIPT.is_file():
        raise ApiError(f"预览脚本不存在：{ULTIMATE_SCRIPT}", 500)

    cmd = [
        _powershell_path(),
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ULTIMATE_SCRIPT),
    ]
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"

    started = time.monotonic()
    try:
        completed = subprocess.run(
            cmd,
            cwd=str(PROJECT_ROOT),
            capture_output=True,
            timeout=PREVIEW_TIMEOUT_SECONDS,
            check=False,
            env=env,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "output": "",
            "error": f"预览超时（>{PREVIEW_TIMEOUT_SECONDS:g}s）",
            "elapsedMs": int((time.monotonic() - started) * 1000),
        }

    stdout = _decode_process_output(completed.stdout).strip()
    stderr = _decode_process_output(completed.stderr).strip()
    elapsed_ms = int((time.monotonic() - started) * 1000)
    return {
        "ok": completed.returncode == 0,
        "output": stdout,
        "error": stderr if completed.returncode != 0 else "",
        "exitCode": completed.returncode,
        "elapsedMs": elapsed_ms,
    }


def _fetch_status() -> dict:
    try:
        request = urllib.request.Request(
            STATUS_URL,
            headers={"Accept": "application/json", "User-Agent": "NekoTool-Dashboard/1.0"},
        )
        with urllib.request.urlopen(request, timeout=STATUS_TIMEOUT_SECONDS) as response:
            raw = response.read()
        return {
            "online": True,
            "status": json.loads(raw.decode("utf-8")),
            "fetchedAt": int(time.time()),
        }
    except Exception as exc:  # noqa: BLE001 - offline state is part of the UI
        return {
            "online": False,
            "error": f"{type(exc).__name__}: {exc}",
            "fetchedAt": int(time.time()),
        }


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "NekoToolDashboard/1.0"

    def log_message(self, fmt: str, *args) -> None:
        # Polling would otherwise spam the console every 2 seconds.
        if self.path.startswith("/api/status"):
            return
        try:
            if sys.stderr is not None:
                sys.stderr.write("[dashboard] " + (fmt % args) + "\n")
        except Exception:
            pass

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parsed = urlparse(self.path)
        path = parsed.path

        try:
            if path in {"/", "/index.html", "/dashboard.html"}:
                _send_web_file(self, DASHBOARD_HTML)
                return

            if path in {"/widget.html", "/preview"}:
                _send_web_file(self, WIDGET_HTML)
                return

            if path == "/favicon.ico":
                self.send_response(204)
                self.end_headers()
                return

            if path == "/api/health":
                _send_json(
                    self,
                    {
                        "ok": True,
                        "pluginCount": len(_plugin_list()),
                        "statusUrl": STATUS_URL,
                        "root": str(PROJECT_ROOT),
                    },
                )
                return

            if path == "/api/status":
                _send_json(self, _fetch_status())
                return

            if path == "/api/plugins":
                plugins = _plugin_list()
                _send_json(
                    self,
                    {
                        "plugins": plugins,
                        "enabled": sum(1 for item in plugins if item["enabled"]),
                        "disabled": sum(1 for item in plugins if not item["enabled"]),
                    },
                )
                return

            if path == "/api/plugins/content":
                query = parse_qs(parsed.query)
                name = (query.get("name") or [""])[0]
                base_name, plugin_path, enabled = _find_plugin(name)
                content, encoding = _read_plugin(plugin_path)
                _send_json(
                    self,
                    {
                        "name": base_name,
                        "enabled": enabled,
                        "content": content,
                        "encoding": encoding,
                    },
                )
                return

            raise ApiError("未知路径", 404)
        except ApiError as exc:
            _send_json(self, {"error": exc.message}, exc.status)
        except Exception as exc:  # noqa: BLE001 - keep the API JSON-only
            _send_json(self, {"error": f"{type(exc).__name__}: {exc}"}, 500)

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parsed = urlparse(self.path)
        path = parsed.path

        try:
            if path == "/api/preview":
                _require_write_headers(self)
                with PREVIEW_LOCK:
                    result = _run_preview()
                _send_json(self, result)
                return

            payload = _read_json_body(self)
            _require_write_headers(self)

            if path == "/api/plugins/toggle":
                name = payload.get("name")
                enabled = payload.get("enabled")
                if not isinstance(enabled, bool):
                    raise ApiError("enabled 必须是布尔值", 400)
                _send_json(self, _toggle_plugin(name, enabled))
                return

            if path == "/api/plugins/save":
                _send_json(self, _save_plugin(payload))
                return

            raise ApiError("未知路径", 404)
        except ApiError as exc:
            _send_json(self, {"error": exc.message}, exc.status)
        except Exception as exc:  # noqa: BLE001 - keep the API JSON-only
            _send_json(self, {"error": f"{type(exc).__name__}: {exc}"}, 500)


def _toggle_plugin(raw_name: object, target_enabled: bool) -> dict:
    with PLUGIN_LOCK:
        base_name, current_path, currently_enabled = _find_plugin(raw_name)
        if currently_enabled == target_enabled:
            return {"name": base_name, "enabled": currently_enabled}

        enabled_path, disabled_path = _plugin_paths(base_name)
        target_path = enabled_path if target_enabled else disabled_path
        if target_path.exists():
            raise ApiError(f"目标文件已存在：{target_path.name}", 409)

        try:
            current_path.rename(target_path)
        except OSError as exc:
            raise ApiError(f"切换插件失败：{exc}", 500) from exc

        return {"name": base_name, "enabled": target_enabled}


def _save_plugin(payload: dict) -> dict:
    raw_name = payload.get("name")
    content = payload.get("content")
    if not isinstance(content, str):
        raise ApiError("缺少 content 文本", 400)

    with PLUGIN_LOCK:
        base_name, plugin_path, enabled = _find_plugin(raw_name)
        if plugin_path.is_symlink():
            raise ApiError("拒绝写入符号链接", 400)
        _write_plugin(plugin_path, content)

    return {
        "ok": True,
        "name": base_name,
        "enabled": enabled,
        "backup": plugin_path.name + ".bak",
    }


class DashboardServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    global STATUS_URL

    parser = argparse.ArgumentParser(description="NekoTool local web dashboard")
    parser.add_argument("--host", default="127.0.0.1", help="bind address (default: loopback)")
    parser.add_argument("--port", type=int, default=5100, help="listen port (default: 5100)")
    parser.add_argument("--open", action="store_true", help="open the dashboard in a browser")
    parser.add_argument("--status-url", default=DEFAULT_STATUS_URL, help="StatusCast status endpoint")
    args = parser.parse_args()

    STATUS_URL = args.status_url

    if not DASHBOARD_HTML.is_file():
        print(f"[dashboard] 缺少页面文件：{DASHBOARD_HTML}", file=sys.stderr)
        return 2

    try:
        server = DashboardServer((args.host, args.port), DashboardHandler)
    except OSError as exc:
        print(
            f"[dashboard] 无法监听 {args.host}:{args.port}：{exc}\n"
            "           端口可能被占用，可用 --port 换一个端口。",
            file=sys.stderr,
        )
        return 2

    browser_host = "127.0.0.1" if args.host in {"0.0.0.0", "::"} else args.host
    url = f"http://{browser_host}:{args.port}/"

    print("")
    print("  NekoTool · Dashboard")
    print(f"  URL     : {url}")
    print(f"  Plugins : {PLUGIN_DIR}")
    print(f"  Status  : {STATUS_URL}")
    print("  Ctrl+C to stop")
    print("")

    if args.open:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever(poll_interval=0.4)
    except KeyboardInterrupt:
        print("\n[dashboard] 已停止。")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
