# 02: dashboard 卡片 + 在线/离线告警

来源：`docs/游戏主机状态接入计划.md` C3。

**What to build:** dashboard 与 widget 用同一套卡片约定渲染全部平台，并在设备「在线 ↔ 离线」切换时弹 toast。dashboard 已有 toast 基建，直接用。

注意首轮加载不误报：首帧拿到的状态是基线，不产生告警；只有观测到状态变化才弹。

**Blocked by:** 01（复用同一套卡片约定，避免两个界面各写一套、慢慢漂移）

**Status:** implemented（headless Edge 验证）

- [x] 同一设备在 dashboard 与 widget 上显示一致：同图标、同降级标记、同离线文案
- [x] 在线→离线、离线→在线各弹一次 toast
- [x] 首轮加载与页面刷新不误报离线
- [x] 多设备同时变化时 toast 不刷屏（有上限或合并策略）

## Comments

**2026-11-01 — 完成。**

`renderDevices` 重写：按 kind 分派（phone / console / node / ble / app / unknown），图标、名称回退、在线文案与降级胶囊都对齐 widget 的约定。新增：

- `deviceState`：`console` 用 `console.online`、`node` 用 `node.online`、`ble` 用 `ble.connected`（未连接时金色「已发现未连接」/「未发现」），`device.error` 永远优先。离线文案取平台块自己的 `statusText`。
- `degradedChip`：`transport.degraded === true` 时在详情区显示金色「⚠️ 降级 · LAN 探活 / TCP 探活 / …」。
- `announceTransitions`：首轮只播种不弹；单台变化弹一条「X 已上线/已离线」；同一轮多台变化合并成一条「N 台设备状态变化（上线 a / 离线 b）」，避免网络抖动时刷屏。

**顺手修了一个存量 bug**：`Number.isFinite(Number(device.batteryLevel))` 对 `null` 恒为真（`Number(null) === 0`），所以没有电池的主机/节点会渲染成 **0%**。现在 null/undefined/"" 先判空，环里显示 `?`。

验证：真实 headless Edge + 合成 `/api/status`，8 项断言全绿——console 卡不再显示成 IPHONE、ble 已连接/已发现未连接、node 卡、降级胶囊、未知平台兜底、首轮无 toast、转变后出现 toast。截图 `G:\StatusCast\.tmp-b02\dashboard-b02.png`。

**未验证**：只测了 Chromium（无 Firefox/Safari）；「上线」方向的 toast 与「离线」走同一分支，但没有单独构造用例；toast 4.2 秒后自动消失，是靠轮询采样捕捉的。
