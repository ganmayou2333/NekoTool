# 03: 主行 / 节点行 / 降级可读标记

来源：`docs/游戏主机状态接入计划.md` C3，以及 `docs/C1-C2b-C0-checklist.md` 备注里的展示欠账。

**What to build:** 补齐文本出口这一轮的缺口：

- 主行仍**只认手机**——带电池的 macos / linux 节点不得抢主行（台账 C2b-7 的口径）
- macos / linux 节点各一行：在线 / 离线 + 电量
- console 的 `🎮 <主机名> <状态>` 行保留
- 降级通道在文本里有可读标记（如 `(LAN)`），不要只活在 JSON 里
- BLE 外设一行

**Blocked by:** nekotrak-integration 04（presence 文本来源迁到 `write_to_obs.ps1` 之后再改，否则同一段逻辑要返工两次）

**Status:** ready-for-agent

- [ ] 用合成快照断言：主行仍是手机；只有节点时回退 `📱 -- | 🔋 -- | 🎵 --`
- [ ] 节点行、console 🎮 行、BLE 行、降级标记按预期出现
- [ ] 图标与措辞和 display-polish 01 / 02 一致
- [ ] 改完 NekoTrak 日志仍零 `custom_text_command_failed`（不得把这一行写回超时线）
