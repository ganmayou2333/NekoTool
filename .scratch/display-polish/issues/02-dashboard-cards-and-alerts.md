# 02: dashboard 卡片 + 在线/离线告警

来源：`docs/游戏主机状态接入计划.md` C3。

**What to build:** dashboard 与 widget 用同一套卡片约定渲染全部平台，并在设备「在线 ↔ 离线」切换时弹 toast。dashboard 已有 toast 基建，直接用。

注意首轮加载不误报：首帧拿到的状态是基线，不产生告警；只有观测到状态变化才弹。

**Blocked by:** 01（复用同一套卡片约定，避免两个界面各写一套、慢慢漂移）

**Status:** ready-for-agent

- [ ] 同一设备在 dashboard 与 widget 上显示一致：同图标、同降级标记、同离线文案
- [ ] 在线→离线、离线→在线各弹一次 toast
- [ ] 首轮加载与页面刷新不误报离线
- [ ] 多设备同时变化时 toast 不刷屏（有上限或合并策略）
