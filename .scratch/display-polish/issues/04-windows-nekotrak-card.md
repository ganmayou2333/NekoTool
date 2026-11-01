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

**Status:** implemented（headless Edge 验证）

- [x] `platform:"windows"` 渲染为 🖥 专属卡，不再出现「未知平台」文案与 ❔ 图标
- [x] 卡片显示 tracker 状态、运行时长、当前游戏（空则「挂台中」）
- [x] 无电量时不出现「未知电量」圆环；`warns` 非空时有可见提示
- [x] `transport.active="process"` 不产生 `PROCESS` 这类生硬标签
- [x] 用合成 devices 截图验证，且 iOS/Android/console/node/ble 卡片不回归

## Comments

**2026-11-01 — 完成。**

`windows` → 新 kind `app`：🖥 图标、`NekoTrak` 兜底名。这张卡**不复用电量骨架**——body 换成 `TRACKER 追踪中/已暂停` + `运行中` 状态胶囊，不再出现「未知电量」圆环（app 卡里既没有 `BATTERY` 标签也没有 `battery-value`）。

底行两行：`⏱️ 运行 59m`，以及 `🎮 <游戏>` 或 `🎮 挂台中`，后面跟 `emoji + 宠物名`（`pet.lastEvent` 不拿出来，只有名字）。`warns` 非空时头部出现金色「⚠️ N 条提示」胶囊，`title` 里是全部条目；空数组不显示。`TRANSPORT_LABELS` 补了 `process: "本地进程"` 兜底。

验证：真实 headless Edge + 合成 devices，12 项断言全绿（含「app 卡里没有电量环」「手机卡仍有电量环」「windows 不再走到 unknown 卡」）。截图 `G:\StatusCast\.tmp-b04\shot-widget-nekotrak.png`。

**过程记录**：这张票最初派给 teammate 实现，但它汇报完成后磁盘上 `web/widget.html` 的 mtime 仍是 10:52（早于上一次提交），改动实际没落盘。由 lead 重做并验证。以后派工要检查文件 mtime 与 `git status` 再采信汇报。

**未验证**：只有 Chromium；`pomodoro`、`nekotrak.source` 等票外字段没有展示；截图用的是合成数据，没起真 daemon。

**2026-11-01 11:34 — 追加：真实 daemon 数据下的端到端验证（不是合成 payload）。**

起真实 `StatusCast.Daemon.exe` 后：

- `GET /health` → `{"ok":true,"deviceCount":3,"generatedAt":...,"schema":3}`
- `GET /status/` 的 device ids = `["iphone","android","nekotrak"]`；`nekotrak` 条目的键集合**恰好**是契约里的 13 个，`error:null`、`transport.active:"process"`、`uptimeSec:6351`、`trackerActive:true`
- widget 用 `?url=http://127.0.0.1:5099/status/` 加载真实快照：渲染出 3 张卡、`class="device app` 卡存在、显示 TRACKER 与「挂台中」
- `write_to_obs.ps1 -Once` 一轮 **0.1 秒**，写出 `🎮 挂台中 · 🔋 未知`
