# 01: widget 平台卡片

来源：`docs/游戏主机状态接入计划.md` C3，以及各 spec 文末「展示留 C3」的欠账。

**What to build:** widget 不再把所有非 android 平台当 iOS 渲染。console / steam（🎮）、macos（💻）、linux（🐧）、ble 各有一张卡，卡片显示：

- 机型或别名
- 电量（无电量设备显示「未知」，不是 `null` 或空白）
- 在线 / 离线
- `transport.degraded` 为 true 时的降级标记（如「LAN 探活」「Wi-Fi」），让「能拿到多少报多少」在界面上可见

数据侧已全部就绪：`console` / `node` / `ble` / `transport` 都在 schema 3 里。这张票只改展示，现在就能开工。

**Blocked by:** None（可立即开始）

**Status:** implemented（headless Edge 验证，未在真 OBS 里跑过）

- [x] 合成 devices 覆盖并正确渲染：console 在线、console 离线（用配置的 `offlineText`）、ble 已连接、ble 已发现未连接、iPhone USB → LAN 降级
- [x] console 条目不再被渲染成 iOS 卡
- [x] 未知平台有兜底卡片，不崩溃、不丢整页
- [x] 无电量设备显示「未知」
- [x] 现有 iOS / Android 卡片外观与字段不回归

## Comments

**2026-11-01 — 完成（提交 `7b4d09b`）。**

实现要点：

- 卡片按 `platform` 分派 kind：`ios/android`→phone、`console/steam`→🎮、`macos/linux`→node、`ble`→📶、其余→`unknown` 兜底卡（❔）。未知平台不会丢整页。
- 在线判定优先取平台块自己的标志（`console.online` / `node.online` / `ble.connected`），再回退 `transport.online`；**`device.error` 永远优先**，陈旧快照不会误报在线。
- 降级标记：`transport.degraded === true` 时卡片末行显示金色胶囊「⚠️ 降级 · LAN 探活 / TCP 探活 / BLE …」，`title` 里带 `detail`；有降级时不显示原通道行（通道名已在胶囊里）。
- 无电量设备：圆环内与 meta 都显示「未知」，且不显示 `%`；原来显示 `--` + `OFFLINE`，后者会误导。
- 表头计数从「设备总数」改为「实际在线数」（Screenshot 里 12 台显示 9 ONLINE）。这是超出票面的一句，但和在线/离线语义一致；如不接受回退 3 行即可。

验证：headless Edge（Chromium）+ DOM 断言 9 项全 ok，8 张截图已人工逐张看过；harness 在仓库外 `G:\StatusCast\.tmp-b01\`，复现命令 `python G:\StatusCast\.tmp-b01\capture.py`。

**未验证（诚实清单）：**

- 只在 headless Edge 验证；没有 Firefox/Safari，也没在真 OBS Browser Source 里跑过。
- 数据是合成 schema-3 JSON，没有起真实 daemon 打 `/status/`（形状参照 `StatusCoordinator.BuildDevicePayload` 只读核对）。
- 800×300 下超过 2 张卡仍会溢出——这是旧卡片高度（每卡约 140px）造成的老问题，本票没有加剧也没有修；多设备验证用的是 800×420 / 1000×470 / 1400×1180。

**遗留缺口 → 见 04**：`platform:"windows"`（NekoTrak，02 引入）不在本票列表里，落到了 ❔ 兜底卡；能显示但不该显示成「未知平台」。
