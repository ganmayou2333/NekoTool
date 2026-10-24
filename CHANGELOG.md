# Changelog

## [1.0.0] - 2026-10-24

First stable NekoTool release, aligned with StatusCast v3.0.

### Added

- 800×300 glassmorphism OBS browser console (`web/widget.html`).
- Dynamic multi-device cards from the StatusCast v3 `devices` array.
- Animated battery rings, charging pulse, CPU/MEM/NET gauges and plugin stream.
- `?mock=true` standalone preview mode.
- One-command headless preview generator (`scripts/generate_preview.ps1`).
- PowerShell plugin pipeline (`plugins/*.ps1`) with a 2-second default timeout and error isolation.
- `ultimate_status.ps1 -MockMode` and `-MockHardware`.
- `pull_status.ps1`, `write_to_obs.ps1`, and NekoTrak/OBS integration docs.

### Compatibility

- StatusCast v3.0+ (pure `devices` JSON).
- Windows PowerShell 5.1 and PowerShell 7+.
