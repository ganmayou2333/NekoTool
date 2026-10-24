# Changelog

All notable changes to NekoTool are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Starting with StatusCast v3.2, NekoTool follows the same version number as the
StatusCast release it targets.

## [Unreleased]

- Planned: more sample plugins, richer OBS widgets and a plugin manager UI.

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
