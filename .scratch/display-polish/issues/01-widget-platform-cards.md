# 01: widget 平台卡片

来源：`docs/游戏主机状态接入计划.md` C3，以及各 spec 文末「展示留 C3」的欠账。

**What to build:** widget 不再把所有非 android 平台当 iOS 渲染。console / steam（🎮）、macos（💻）、linux（🐧）、ble 各有一张卡，卡片显示：

- 机型或别名
- 电量（无电量设备显示「未知」，不是 `null` 或空白）
- 在线 / 离线
- `transport.degraded` 为 true 时的降级标记（如「LAN 探活」「Wi-Fi」），让「能拿到多少报多少」在界面上可见

数据侧已全部就绪：`console` / `node` / `ble` / `transport` 都在 schema 3 里。这张票只改展示，现在就能开工。

**Blocked by:** None（可立即开始）

**Status:** ready-for-agent

- [ ] 合成 devices 覆盖并正确渲染：console 在线、console 离线（用配置的 `offlineText`）、ble 已连接、ble 已发现未连接、iPhone USB → LAN 降级
- [ ] console 条目不再被渲染成 iOS 卡
- [ ] 未知平台有兜底卡片，不崩溃、不丢整页
- [ ] 无电量设备显示「未知」
- [ ] 现有 iOS / Android 卡片外观与字段不回归
