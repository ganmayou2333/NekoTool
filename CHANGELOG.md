# Changelog

All notable changes to NekoTool are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Starting with StatusCast v3.2, NekoTool follows the same version number as the
StatusCast release it targets.

## [Unreleased]

- Planned: more sample plugins, richer OBS widgets and a plugin manager UI.

## [3.2.0] - 2026-10-25

### Added

- `collectors/hr_collector.py`: WebSocket heart-rate collector with reconnect,
  atomic JSON writes and support for common BPM payload shapes
  (default `ws://localhost:8406/chat`).
- `plugins/heart_rate.ps1`: shows `❤️ <bpm> BPM` for readings younger than
  10 seconds, otherwise `❤️ --`.
- `scripts/update.ps1`: checks the latest GitHub Release (falls back to the
  latest commit), runs `git pull --ff-only` for git checkouts after fetching,
  prints the latest 3 commits in cyan, and never modifies zip installs.
- `data/` runtime directory with `.gitkeep`; generated JSON is ignored by Git.
- Silent update check in `launch_and_pull.ps1`, throttled to once every
  6 hours and run in a hidden background process.

### Changed

- Standardized layout: core scripts in `scripts/`, background collectors in
  `collectors/`, PowerShell plugins in `plugins/`, runtime data in `data/`,
  web widget in `web/`.
- `setup.ps1` moved to `scripts/setup.ps1` and now works from both the source
  checkout and the packaged release root.
- `launch_and_pull.ps1` no longer carries the old WinUI wrapper fallback; it
  starts `StatusCast.Daemon.exe` directly.
- `build_release.ps1` now packages `collectors/` and ships `setup.ps1` at the
  release root.
- Weather sample plugin renamed from `weather_mock.ps1` to `weather.ps1`.

### Removed

- `post-demo.html` / `post-demo.png` demo artifacts.
- Generated `publish/` folder and old `StatusCast_v3.1.0_Release.zip`.
- Python `__pycache__` directories.

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
