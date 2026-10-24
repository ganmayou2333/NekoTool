# NekoTool

**StatusCast 专属的桌面聚合工具箱。**

NekoTool 不负责 USB 采集。它只做一件事：把 **StatusCast** 已经整理好的手机状态，和 Windows 的 CPU、内存、网速、时间缝合在一起，然后输出给 NekoTrak、OBS 或其他桌面挂件。

> 底层采集由 [StatusCast](https://github.com/ganmayou2333/StatusCast) 负责。  
> NekoTool 是它旁边的轻量级客户端层。

![NekoTool preview](web/preview-mock.png)

## 无需安装，直接看效果

即使没有连接手机、甚至没有启动 StatusCast，也可以先用内置模拟数据预览效果：

```powershell
.\scripts\ultimate_status.ps1 -MockMode
```

输出示例：

```text
📱 主力机 | 🔋 87% ⚡ | 🎵 Yesterday - The Beatles | 🖥 33% | 🧠 63% | 🌐 ↓1.2M ↑86K | 🕐 21:53 | 🌤 晴 25℃
```

如果想让 CPU / 内存 / 网速也使用固定演示值，加上 `-MockHardware`：

```powershell
.\scripts\ultimate_status.ps1 -MockMode -MockHardware
```

重新生成 README 里的预览图：

```powershell
.\scripts\generate_preview.ps1
```

脚本会自动调用 Edge / Chrome 无头模式，把 `web/preview-mock.png` 生成出来。

## v3.0 生态架构

StatusCast 只负责底层采集和标准 JSON API：

```text
iPhone --USB--> status_core.py ─┐
Android --ADB--> status_core_android.py ─┤
                                         ▼
                               StatusCast HTTP API
                               localhost:5099/status/
```

NekoTool 负责所有聚合、插件和展示：

```text
StatusCast API ──▶ 手机状态
Windows CIM ─────▶ CPU / 内存 / 网速
plugins/*.ps1 ───▶ 天气 / 温度 / 自定义状态
        │
        ▼
  ultimate_status.ps1
        │
        ├─▶ NekoTrak 文本
        ├─▶ write_to_obs.ps1 → obs_status.txt → OBS 文本源
        └─▶ widget.html → OBS 浏览器源
```

这样核心保持纯净，展示层可以独立演进。

## 目录结构

```text
NekoTool/
├─ README.md
├─ LICENSE
├─ .gitignore
├─ obs_status.txt                 # write_to_obs.ps1 运行时生成，不提交
├─ scripts/
│  ├─ pull_status.ps1             # 基础版：只读手机状态
│  ├─ ultimate_status.ps1         # 终极版：手机 + 系统 + 插件
│  ├─ write_to_obs.ps1            # OBS 专用：循环写入本地 txt
│  ├─ mock_data.json              # StatusCast 模拟数据
│  └─ generate_preview.ps1        # 无头浏览器生成预览图
├─ plugins/
│  └─ weather_mock.ps1            # 示例插件：返回一行天气
└─ web/
   ├─ widget.html                 # OBS 浏览器源控制台
   └─ preview-mock.png            # README 预览图
```

## 环境要求

- Windows 10 / 11
- PowerShell 5.1 或 PowerShell 7+
- [StatusCast](https://github.com/ganmayou2333/StatusCast) 正在运行
- OBS 28+（仅使用 OBS 功能时需要）

NekoTool 本身不需要 Python、.NET 或管理员权限。

## 快速开始

```powershell
git clone https://github.com/ganmayou2333/NekoTool.git
cd NekoTool
```

先确认 StatusCast API 正常：

```powershell
Invoke-RestMethod -Uri 'http://localhost:5099/status/' -UseBasicParsing
```

### 1. 基础版：只读手机状态

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\pull_status.ps1
```

输出：

```text
📱 14 Pro Max | 🔋 87% ⚡ | 🎵 暂无播放
```

也可以输出 JSON，方便其他脚本继续处理：

```powershell
.\scripts\pull_status.ps1 -Json
```

### 2. 终极版：手机 + 电脑 + 网络 + 时间

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ultimate_status.ps1
```

输出示例：

```text
📱 14 Pro Max | 🔋 87% ⚡ | 🎵 Yesterday - The Beatles | 🖥 12% | 🧠 63% | 🌐 ↓1.2M ↑86K | 🕐 20:59
```

说明：

- `🖥`：CPU 总占用率
- `🧠`：物理内存使用率
- `🌐`：当前网络下行 / 上行速度
- `🕐`：本机时间，24 小时制

网络速度默认采样 1 秒。如果觉得 NekoTrak 刷新时延迟明显，可以缩短采样：

```powershell
.\scripts\ultimate_status.ps1 -SampleSeconds 0.5
```

### 3. OBS 文本源：循环写入 txt

启动后台循环：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\write_to_obs.ps1
```

默认每 5 秒把状态写入：

```text
NekoTool\obs_status.txt
```

也可以指定路径：

```powershell
.\scripts\write_to_obs.ps1 -OutputPath 'D:\OBS\status.txt' -IntervalSeconds 3
```

在 OBS 中：

1. 添加 **文本（GDI+）** 源；
2. 勾选 **从文件读取**；
3. 选择生成的 `obs_status.txt`；
4. 建议使用等宽或圆体字体，并加一层深色描边。

### 4. OBS 浏览器源：动态挂件

在 OBS 中添加 **浏览器** 源，选择：

```text
G:\NekoTool\web\widget.html
```

建议尺寸：

```text
800 × 300
```

背景设为透明，即可得到一个跟随 StatusCast 实时更新的电量圆弧挂件。

![NekoTool OBS widget](web/preview-mock.png)

如果 API 不在默认地址，可以在 URL 后面覆盖：

```text
file:///G:/NekoTool/web/widget.html?url=http://127.0.0.1:5099/status/
```

浏览器源每 2 秒拉取一次状态；API 不可用时会显示 `OFFLINE`，不会卡住 OBS。

## NekoTool 插件机制

NekoTool 的插件就是独立的 PowerShell 脚本。把 `.ps1` 放进 `plugins/`，
`ultimate_status.ps1` 会自动遍历执行，每个插件只需要返回一段短文本。

```text
plugins/
├─ weather_mock.ps1
├─ cpu_temp.ps1
└─ my_service.ps1
```

### 编写一个插件

创建 `plugins/hello.ps1`：

```powershell
Write-Output "👋 NekoTool"
```

运行：

```powershell
.\scripts\ultimate_status.ps1 -MockMode -MockHardware
```

输出末尾会自动追加：

```text
... | 👋 NekoTool
```

### 插件约定

- 每个插件只输出 **一行短文本**；
- 不要等待用户输入；
- 不要修改 `plugins/` 之外的文件；
- 默认超过 **2 秒** 会被停止并跳过；
- 插件报错不会影响主流程；
- 可用 `-PluginTimeoutSeconds` 调整超时时间。

### 带参数的插件

插件本身是普通 `.ps1`，可以直接读取环境变量或调用 API：

```powershell
$response = Invoke-RestMethod -Uri "https://wttr.in/?format=3" -TimeoutSec 2
Write-Output "🌤 $response"
```

如果天气服务失败，脚本会报错；NekoTool 会跳过它并继续输出手机和系统状态。

## NekoTrak 接入

### 基础状态

在 NekoTrak 自定义文本中填入：

```text
${(Invoke-RestMethod -Uri 'http://localhost:5099/status/' -UseBasicParsing).text}
```

或调用脚本：

```text
{powershell.exe -NoProfile -ExecutionPolicy Bypass -File "G:\NekoTool\scripts\pull_status.ps1"}
```

### 终极缝合状态

```text
{powershell.exe -NoProfile -ExecutionPolicy Bypass -File "G:\NekoTool\scripts\ultimate_status.ps1"}
```

如果 NekoTrak 的刷新间隔比较短，建议使用 `-SampleSeconds 0.5`，避免每次采样占用太久：

```text
{powershell.exe -NoProfile -ExecutionPolicy Bypass -File "G:\NekoTool\scripts\ultimate_status.ps1" -SampleSeconds 0.5}
```

## 脚本参数

### pull_status.ps1

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-StatusUrl` | `http://localhost:5099/status/` | StatusCast API 地址 |
| `-Json` | 关闭 | 输出 JSON 而不是友好文本 |

### ultimate_status.ps1

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-StatusUrl` | `http://localhost:5099/status/` | StatusCast API 地址 |
| `-SampleSeconds` | `1.0` | 网速采样时长，范围 0.2–5 秒 |
| `-MockMode` | 关闭 | 从 `scripts/mock_data.json` 读取手机状态，不请求 API |
| `-MockHardware` | 关闭 | CPU / 内存 / 网速使用固定演示值 |
| `-PluginTimeoutSeconds` | `2` | 单个插件超时时间，范围 1–30 秒 |

### generate_preview.ps1

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-BrowserPath` | 自动查找 Edge / Chrome | 指定无头浏览器路径 |

### write_to_obs.ps1

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-OutputPath` | `..\obs_status.txt` | 输出文件路径 |
| `-IntervalSeconds` | `5` | 刷新间隔 |
| `-StatusUrl` | `http://localhost:5099/status/` | StatusCast API 地址 |

## 常见问题

### API 连不上

先确认 StatusCast 正在运行：

```powershell
Invoke-RestMethod -Uri 'http://localhost:5099/status/' -UseBasicParsing
```

如果报连接失败，检查：

- StatusCast 窗口是否打开；
- 端口 `5099` 是否被其他程序占用；
- 是否被安全软件拦截。

### 中文或 Emoji 乱码

- 使用 PowerShell 5.1 时，请确保脚本保存为 **UTF-8 with BOM**；
- OBS 文本源建议使用支持 Emoji 的字体，例如 `Segoe UI Emoji` 或 `Microsoft YaHei UI`；
- `write_to_obs.ps1` 写入的是 UTF-8 无 BOM，兼容 OBS。

### OBS 浏览器源显示 OFFLINE

- 确认 StatusCast API 可以访问；
- 如果使用 `file://` 打开页面，检查浏览器源是否允许访问 `localhost`；
- 尝试在 URL 后追加 `?url=http://127.0.0.1:5099/status/`。

### CPU / 内存 / 网速显示 `--`

这些指标来自 Windows CIM / 网络适配器统计。部分精简系统或虚拟机可能禁用相关服务，此时只影响对应字段，不影响手机状态。

## Roadmap

- [ ] 可配置的状态段开关（只显示 CPU / 内存 / 网速）
- [ ] 主题参数（颜色、圆角、字体）
- [ ] OBS WebSocket 直接推流
- [ ] 多 StatusCast 实例支持
- [ ] 托盘常驻版

## License

MIT License，详见 [LICENSE](LICENSE)。
