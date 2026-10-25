# Changelog

All notable changes to NekoTool are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Starting with StatusCast v3.2, NekoTool follows the same version number as the
StatusCast release it targets.

## [Unreleased]

- Planned: more sample plugins, richer OBS widgets and a plugin manager UI.

### Added

- Web Dashboard (`web/dashboard.html`, `scripts/dashboard_server.py`,
  `scripts/dashboard.ps1`): local-only glassmorphism control center with:
  - live iPhone/Android cards from the StatusCast API;
  - plugin list with `.ps1` ↔ `.ps1.disabled` toggles;
  - in-browser plugin editor with atomic saves, `.bak` backups and UTF-8 BOM output;
  - live `ultimate_status.ps1` preview with a 25-second timeout.
- Zero-dependency Python stdlib backend on `127.0.0.1:5100`; no Node.js,
  frontend framework, Flask or StatusCast C# changes.
- `NekoTool.App` native WinUI 3 desktop shell:
  - pure native main window: `NavigationView`, dark theme, Mica backdrop with
    Acrylic fallback, 12px translucent cards;
  - plugins view with a Steam presence card, OBS settings `Expander`, plugin
    `ListView` with drag handle, toggle, edit/delete actions;
  - seamless right-side `SplitView` editor using a native monospace `TextBox`;
  - settings view for startup, silent-run and local port;
  - Steam profile is read from `HKCU\Software\Valve\Steam` and
    `config\loginusers.vdf`, with the avatar resolved from the community profile XML;
  - OBS link generation and an on-demand `PreviewWindow`; WebView2 exists only
    inside that window and is released when it closes;
  - this stage uses in-memory demo plugin data; Dashboard API hookup is next;
  - self-contained single-file publish via `scripts/build_app.ps1`.

### Documentation

- Added `update.md`: 已测/待测项 for StatusCast USB/Wi-Fi,
  Dashboard, NekoTool.App, and the remaining Apple service compatibility checks.
- README now links the update/checklist file from a dedicated 待测清单 section
  and lists `update.md` in the project tree.

### Changed

- 文档补充 iPhone 限制说明：真实 iPhone 不提供歌曲/歌手元数据（iOS MediaRemote
  私有接口），`-MockMode` 中的媒体示例仅为模拟数据；Android 媒体需要 ADB。
- 文档补充 iPhone Wi-Fi 采集现状：Microsoft Store 版 Apple Devices 不提供 Wi-Fi
  发现，StatusCast 当前只使用 USB；Roadmap 标记 Wi-Fi 与 iPhone 媒体为暂缓项。

## [3.3.0] - 2026-10-25

### Added

- 心率数据采集接入：`collectors/hr_collector.py` 监听心率软件 WebSocket，
  原子写入 `data/heart_rate.json`；`plugins/heart_rate.ps1` 读取并在 10 秒内
  输出 `❤️ <bpm> BPM`。
- 自动更新检查：`scripts/update.ps1` 支持 GitHub Release / Commit 检查、
  `git pull --ff-only` 和最近 3 条 commit 的青色日志。
- `launch_and_pull.ps1` 每 6 小时静默调用 `update.ps1 -Quiet -AutoUpdate`，
  不阻塞状态刷新。

### Changed

- 目录结构优化：`scripts/`（核心流程）、`collectors/`（后台采集）、
  `plugins/`（PowerShell 插件）、`data/`（运行时数据）、`web/`（挂件）。
- `setup.ps1` 移入 `scripts/`，同时兼容源码目录和发布包根目录。
- `build_release.ps1` 打包 `collectors/`、`requirements-nekotool.txt`，
  并在发布包根目录生成 `setup.ps1`。
- `launch_and_pull.ps1` 移除旧 WinUI 包装器回退，直接启动
  `StatusCast.Daemon.exe`。
- 天气示例插件由 `weather_mock.ps1` 更名为 `weather.ps1`。

### Removed

- `post-demo.html` / `post-demo.png` 演示文件。
- 旧 `publish/` 构建目录与 `StatusCast_v3.1.0_Release.zip`。
- Python `__pycache__` 目录。

## [3.2.0] - 2026-10-25

开发检查点：与 StatusCast v3.2 的版本对齐；心率与更新相关工作的正式记录见
`3.3.0`。

## [1.0.0] - 2026-10-24

### Added

- First stable NekoTool release, aligned with StatusCast v3.0.
- 800×300 glassmorphism OBS browser console (`web/widget.html`).
- Dynamic multi-device cards from the StatusCast v3 `devices` array.
- Animated battery rings, charging pulse, CPU/MEM/NET gauges and plugin stream.
- `?mock=true` standalone preview and headless preview generator.
- PowerShell plugin pipeline (`plugins/*.ps1`) with a 2-second timeout and
  error isolation.
- `ultimate_status.ps1 -MockMode` / `-MockHardware`.
- `pull_status.ps1`, `write_to_obs.ps1` and NekoTrak/OBS integration docs.

### Compatibility

- StatusCast v3.0+ (pure `devices` JSON).
- Windows PowerShell 5.1 and PowerShell 7+.
