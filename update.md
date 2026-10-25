# NekoTool Update

> 最后更新：2026-10-25  
> 用途：记录本轮更新、已验证路径和仍需复测/决策的事项。

## 本轮更新

- 新增本地 Web Dashboard：`web/dashboard.html`、`scripts/dashboard_server.py`。
- 新增原生 WinUI 3 桌面外壳 `NekoTool.App`：深色 NavigationView、Mica 背景、
  Steam 状态卡、OBS Expander、插件列表与右侧原生编辑器、设置页，以及按需打开的
  独立 `PreviewWindow`。
- 主界面 100% 原生控件，无 WebView2 嵌套；当前使用内存假数据，尚未连接 Python API。
- Steam 资料从注册表 + `loginusers.vdf` 读取，头像经 Steam 社区资料 XML 获取。
- 预览窗口关闭时释放 WebView2；主窗口关闭不影响 Python Dashboard / StatusCast。
- iPhone 原生 Wi-Fi 预研结论：经典 AMDS 19.4.0.10 + iOS 27.0 仍未注册
  `[Network]`；当前继续使用 USB。
- 本文件同时作为待测清单；详细 Wi-Fi 记录见
  [StatusCast 预研文档](https://github.com/ganmayou2333/StatusCast/blob/main/docs/iphone-wireless-notes.md)。

## StatusCast

### 已完成

- [x] USB iPhone：`status_core.py` 读取型号、电量、充电状态
- [x] `status_core.py` schema-3 JSON 输出，单设备异常隔离
- [x] C# `StatusService` 解析 JSON `devices` 数组
- [x] `status_core_android.py` 旧 STATUS 行兼容 CLI
- [x] iPhone Wi-Fi 预研脚本：`collectors/iphone_wireless_test.py`
- [x] Bonjour/mobdev2 能发现 iPhone 并完成 lockdown
- [x] 预研文档：`docs/iphone-wireless-notes.md`

### 待测 / 待决策

- [ ] **iPhone 原生 Wi-Fi 采集**：经典 AMDS 19.4.0.10 + iOS 27.0 下，
      `usbmuxd` 仍不出现 `[Network]`；已尝试重启服务、强制重新勾选
      iTunes Wi-Fi 同步、重启 Windows、经典 iTunes，均失败。
      需要等 Apple 更新 AMDS/iOS，或改用快捷指令桥接。
- [ ] **iPhone Wi-Fi 电量服务**：Bonjour 能连接，但
      `com.apple.mobile.diagnostics_relay` 返回 `ConnectionTerminatedError`；
      需在 AMDS 能注册 `[Network]` 后复测。
- [ ] **iPhone 媒体元数据**：Now Playing / MediaRemote 为 iOS 私有接口，
      `pymobiledevice3` 无可用服务；当前 `mediaTitle` 为 `null`。
- [ ] **Android ADB 采集**：本机未安装 Android Platform Tools / `adb`，
      前台应用和媒体字段未验证。
- [ ] **StatusCast API 5099 启动问题**：本机测试时曾出现
      `API 启动失败：另一个程序正在使用此文件`；需单独排查端口/HTTP.sys/残留进程。

## NekoTool Web Dashboard

### 已完成

- [x] `dashboard_server.py` 启动、`/api/health`
- [x] `/api/status` 代理 StatusCast，离线态正常
- [x] `/api/plugins`、插件内容读取
- [x] `.ps1` ↔ `.ps1.disabled` 重命名开关
- [x] 插件保存：`.bak` 备份、UTF-8 BOM、CRLF
- [x] 路径穿越返回 400，缺少 CSRF 头返回 403
- [x] `ultimate_status.ps1` 预览与 25 秒超时
- [x] Edge headless 验证离线态和 mock 在线态 UI

### 待测

- [ ] 真实浏览器里点击插件、编辑、保存的完整 UI 流程（API 已测）
- [ ] 同时修改多个插件时的并发保护
- [ ] 禁用插件后预览结果变化
- [ ] WebView2 外壳关闭后 Python 服务仍在运行的长期稳定性

## NekoTool.App（原生 WinUI 3 + 独立预览）

### 已完成

- [x] `dotnet build -c Debug` 0 警告 0 错误
- [x] Windows App SDK 1.8 + WinUI 3 项目
- [x] 深色主题 + Mica 背景，Windows 10 回退 Acrylic
- [x] NavigationView：顶部「插件管理」、Footer「设置」
- [x] 全局 12px 圆角、半透明深灰卡片
- [x] Steam 状态卡：注册表路径 + `loginusers.vdf` + 社区头像
- [x] OBS 设置 Expander：主题、透明背景、生成链接、独立预览
- [x] 插件 ListView：拖拽图标、开关、编辑/删除按钮
- [x] 右侧 `SplitView` 原生等宽字体编辑器 + 保存按钮
- [x] 设置页：开机自启、静默运行、端口校验
- [x] `PreviewWindow` 异步 `EnsureCoreWebView2Async()`；关闭时释放 WebView2
- [x] 主界面无 WebView2 嵌套
- [x] 假数据驱动 UI，未连接 Python API

### 待测 / 下一步

- [ ] 用 `/api/plugins`、`/api/plugins/content`、`/api/plugins/toggle`、
      `/api/plugins/save` 替换假数据
- [ ] 插件拖拽排序的真实行为
- [ ] 未安装 WebView2 Runtime 时的错误提示
- [ ] `-FrameworkDependent` 框架依赖发布
- [ ] 高分屏 / 多显示器下的窗口与 WebView2 缩放
- [ ] Windows 10 上 Acrylic 回退的实际效果
- [ ] 真实 Steam 账号名/头像的离线与在线路径

## 文档

### 已完成

- [x] StatusCast `README.md`：Roadmap、FAQ、Wi-Fi/媒体限制
- [x] StatusCast `docs/iphone-wireless-notes.md`
- [x] NekoTool `README.md`：Dashboard、NekoTool.App、目录结构
- [x] NekoTool `CHANGELOG.md`：Dashboard、App、文档变更

### 待完成

- [ ] Wi-Fi 最终结论（原生放弃 / 快捷指令桥接）
- [ ] 本清单随每次版本更新
- [ ] 提交并推送两个仓库

## 复测触发条件

- Apple 发布新的 Apple Mobile Device Support / iTunes 版本；
- iPhone 升级 iOS 后；
- 切换到另一台 Windows 机器；
- 新增 iPhone 快捷指令桥接实现后。
