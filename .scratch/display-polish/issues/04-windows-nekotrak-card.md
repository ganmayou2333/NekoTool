# 04: NekoTrak（platform=windows）专用卡片

来源：display-polish 01 实施时发现的缺口 + `nekotrak-integration` 02 引入的新平台。

**What to build:** widget 里给 `platform:"windows"`（NekoTrak 桌面应用）一张专属卡，不再落到「❔ 未知平台」兜底卡。

这张卡该显示的是「这台机器上 NekoTrak 自己的状态」，数据全在 `nekotrak` 附加对象里（契约见 `schema/status-contract.json`）：

- 名称：`model`（形如 `NekoTrak 1.2.0`）或 alias
- 主状态：`trackerActive`（追踪中 / 已暂停）
- 运行时长：`uptimeSec`（有现成的 `formatUptime` 可复用）
- 当前游戏：`currentGame`，为空时显示「挂台中」
- 宠物近况：`pet.emoji` + `pet.name` + `pet.lastEvent.summary`（可选，一行足够）
- `warns` 非空时给一个可展开/可悬停的提示，不要让用户以为一切正常

电量块不适用（永远为 null），别让圆环显示成「未知电量」——这张卡应该换掉电量区，而不是复用手机卡的骨架。

**注意**：`transport.active` 是 `"process"`，现有 `TRANSPORT_LABELS` 里没有这个键，降级胶囊会退化成 `PROCESS`。要么补标签，要么这张卡不显示降级胶囊（本地进程没有降级概念）。

**Blocked by:** 01（复用同一套卡片分派与 chip 组件）

**Status:** ready-for-agent

- [ ] `platform:"windows"` 渲染为 🖥 专属卡，不再出现「未知平台」文案与 ❔ 图标
- [ ] 卡片显示 tracker 状态、运行时长、当前游戏（空则「挂台中」）
- [ ] 无电量时不出现「未知电量」圆环；`warns` 非空时有可见提示
- [ ] `transport.active="process"` 不产生 `PROCESS` 这类生硬标签
- [ ] 用合成 devices 截图验证，且 iOS/Android/console/node/ble 卡片不回归
