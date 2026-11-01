# 03: 主行 / 节点行 / 降级可读标记

来源：`docs/游戏主机状态接入计划.md` C3，以及 `docs/C1-C2b-C0-checklist.md` 备注里的展示欠账。

**What to build:** 补齐文本出口这一轮的缺口：

- 主行仍**只认手机**——带电池的 macos / linux 节点不得抢主行（台账 C2b-7 的口径）
- macos / linux 节点各一行：在线 / 离线 + 电量
- console 的 `🎮 <主机名> <状态>` 行保留
- 降级通道在文本里有可读标记（如 `(LAN)`），不要只活在 JSON 里
- BLE 外设一行

**Blocked by:** nekotrak-integration 04（presence 文本来源迁到 `write_to_obs.ps1` 之后再改，否则同一段逻辑要返工两次）

**Status:** implemented（合成快照验证）

- [x] 用合成快照断言：主行仍是手机；只有节点时回退 `📱 -- | 🔋 -- | 🎵 --`
- [x] 节点行、console 🎮 行、BLE 行、降级标记按预期出现
- [x] 图标与措辞和 display-polish 01 / 02 一致
- [x] 改完 NekoTrak 日志仍零 `custom_text_command_failed`（不得把这一行写回超时线）

## Comments

**2026-11-01 — 完成。**

`ultimate_status.ps1` 补了三处：

1. **主行降级标记**：`transport.degraded === true` 时手机行后加 `(<通道大写>)`，例如 `📱 主力机 (LAN) | 🔋 未知 | 🎵 暂无播放`。「只拿到存活信息」现在在文本里看得见，不再只活在 JSON。
2. **`Get-NodeTexts`**：`macos` / `linux` 各一行，`💻`/`🐧` + 名称 + 在线/离线（优先取 `node.statusText`）+ 有电池时 `🔋 55%⚡` + 降级时 `· 仅探活`。
3. **`Get-BleTexts`**：`ble` 一行，`📶` + 名称 + 已连接/已发现未连接/未发现 + `🔋%` + `❤️ N BPM`。

主行筛选逻辑没动：仍然只认 `ios`/`android`，带电池的 macos 节点不会抢主行。

验证（mock `/status/` + `-MockHardware`，两组合成快照）：

```text
📱 主力机 (LAN) | 🔋 未知 | 🎵 暂无播放 | … | 🎮 客厅 PS5 在线 | 💻 MacBook 在线 · 🔋 55% | 🐧 NUC 离线 · 仅探活 | 📶 AirPods Pro 已连接 · 🔋 85% | 📶 心率带 已连接 · ❤️ 78 BPM
📱 -- | 🔋 -- | 🎵 -- | … | 💻 MacBook 在线 · 🔋 55%
```

第二组证明「只有节点时主行回退」，第一组覆盖 console/节点/BLE/降级四类行。

**关于最后一条验收**：NekoTrak 现在读的是 `obs_status.txt`（由 `write_to_obs.ps1 -Style presence` 写，走的是读 `/status/` 的快路径），`ultimate_status.ps1` 已不在 NekoTrak 的调用链上，所以这一行变长不会再顶到 5 秒超时。超时本身由 04 修复。
