# 更改记录

本分支基于 [gao-sun/eul](https://github.com/gao-sun/eul) 继续开发。上游最后广泛使用的 Intel 版本为 **[1.6.2](https://github.com/gao-sun/eul/releases/tag/1.6.2)**。

## [2.2.4] — 2026-10-08

面向 **Apple Silicon（arm64）**、**macOS 13+**。营销版本 **2.2.4**（build 75）。安装仍为 **`eul2.app`** / `com.wendyeq.eul2`。ad-hoc 签名，首次需右键打开。

### 内存

- 修复 IOReport 硬件采样的内存泄漏：动态加载的 Create/Copy 函数显式转移返回对象的所有权，旧采样和临时差值对象不再随刷新持续积累。
- 增加真实硬件采样回归测试，检查连续刷新时的内存增长；不改变硬件数据显示或刷新频率。

### 额度

- 钉住额度菜单时，额度行每分钟刷新，保持倒计时与窗口进度更新。

## [2.2.3] — 2026-09-29

面向 **Apple Silicon（arm64）**、**macOS 13+**。营销版本 **2.2.3**（build 74）。安装仍为 **`eul2.app`** / `com.wendyeq.eul2`。ad-hoc 签名，首次需右键打开。

### MCP 中枢

- 中枢关闭后，拖动排序或切换 server 只保存目录，不再重新打开本机监听或拉起上游。
- 关闭与正在建立的监听、上游连接交叉时，旧任务不再把端口或连接装回去。

### 额度

- Antigravity 刷新遇到 `invalid_client`（含 HTTP 401）时，显示客户端认证失败，并提示检查 eul2 更新；不再当成未登录。
- 失败时仍保留上次额度，并标明当前显示的是上次数据。

### 菜单

- 硬件与额度列表拖拽时，让位行按被拖行高度加上行间距平移，减少不等高行松手时的跳动。

## [2.2.2] — 2026-09-28

面向 **Apple Silicon（arm64）**、**macOS 13+**。营销版本 **2.2.2**（build 73）。安装仍为 **`eul2.app`** / `com.wendyeq.eul2`。ad-hoc 签名，首次需右键打开。

### Antigravity 额度

- 新增 Antigravity 订阅额度，沿用现有额度菜单、显隐开关和可拖拽排序；与其他供应商并行刷新。
- 固定展示顺序：Gemini 5h、Gemini 周额度、Claude/GPT 5h、Claude/GPT 周额度。按官方剩余比例计算用量，重置时间用于窗口时间刻度。
- 每次刷新按 Keychain、jetski、旧版只读 state.vscdb 的顺序读取凭据；存在 Antigravity IDE 目录时不回退到 Antigravity 目录。
- 有 refresh token 时，即使 IDE 未运行也走官方接口；无凭据才尝试本机 language_server RPC。
- 凭据仅在刷新调用内使用，不写回、不导入、不切换账号，不读取 Gemini CLI 的 oauth_creds.json。认证失效提示打开 Antigravity 登录，其他失败沿用上次额度。
- 偏好 → 菜单 → 额度 → Antigravity 新增「显示 Claude/GPT 额度」开关，默认开启；关闭只隐藏这两行，不影响 Gemini 或取数。
- 所有已有额度语言资源新增 Antigravity 标签；增加注入命令与 HTTP 响应的离线测试。

## [2.2.1] — 2026-09-24

面向 **Apple Silicon（arm64）**、**macOS 13+**。营销版本 **2.2.1**（build 72）。安装仍为 **`eul2.app`** / `com.wendyeq.eul2`。ad-hoc 签名，首次需右键打开。

### 菜单

- 状态下拉分成硬件、额度、MCP 三页；多于一页时在顶栏切换。
- 偏好 → 菜单视图：打开菜单时的默认页；硬件、额度、MCP 页可分别显示或隐藏。
- 硬件组件、额度供应商、MCP server 可拖拽排序。
- MCP 配置从侧栏并入菜单视图。

### MCP 中枢

- 「连接 agent」增加 Pi：upsert `~/.pi/agent/mcp.json` 的 `eul2-mcp`，stdio `eul mcp-connect`。
- 「连接 agent」增加 DeepSeek Harness：在 `~/.dsh/cordis.patch.yml` upsert `@deepseek-ai/dsh-mcp-client`，Streamable HTTP 指向中枢。不改 `profiles/*/cordis.patch.yml`。
- 打开中枢后先听 `127.0.0.1:18732`，不再等上游握手；单个 server 握手超过 60 秒记失败，不拖住端口。
- 偏好 MCP 与菜单中每个 server 独立显示：连接中 / 已连接 / 失败 / 未连接。中枢「已监听」只表示端口，不代表 gitnexus / playwright 都连上。
- 菜单里 MCP 图标与额度图标分开。server 上次调用按秒、分钟、小时、天、周、月、年显示。

## [2.2.0] — 2026-09-20

面向 **Apple Silicon（arm64）**、**macOS 13+**。营销版本 **2.2.0**（build 71）。安装仍为 **`eul2.app`** / `com.wendyeq.eul2`。ad-hoc 签名，首次需右键打开。

### MCP 中枢

- 一份 MCP 目录：`$HOME/Library/Application Support/eul2/mcp-catalog.json`（`0600`）；本地回环只服务本机，默认 `127.0.0.1:18732/mcp`。
- 五个 agent 只连接一次：入口名 **`eul2-mcp`**。Cursor / Claude Desktop / Claude Code 走 `eul mcp-connect`；Codex / Grok 走 HTTP。
- 「连接 agent」只 upsert `eul2-mcp`，不删用户已有的 `mcp-router` 等其它条目。
- 工具对外名 **`{id}--{原名}`**（如 `gitnexus--list_repos`），避免 Grok 再套 `eul2-mcp__…` 时出现第二段 `__`。
- 偏好侧栏一级栏目 **MCP**：总开关默认关、连接 agent、打开配置文件、按 server 开关。无添加表单、无 MCP Router JSON 导入。
- 菜单 MCP 块（默认不展示，在菜单视图中添加）：标题旁显示已监听 / 已停止 / 失败；各 server 上次调用相对时间。
- 无参数调用记录：`$HOME/Library/Application Support/eul2/mcp-calls.jsonl`。删掉 `eul2.app` 后目录和 JSONL 仍在。

## [2.1.0] — 2026-09-19

面向 **Apple Silicon（arm64）**、**macOS 13+**。营销版本 **2.1.0**（build 70）。安装仍为 **`eul2.app`** / `com.wendyeq.eul2`。ad-hoc 签名，首次需右键打开。

### 平台

- 最低系统从 **macOS 12.0** 提升为 **macOS 13.0**（App、Widget、SharedLibrary、SelfUpdate 一致）。2.0.0 仍支持 12.0。
- 产品功能在 13 到当前系统上同一套；`#available` 只包旧系统没有的符号或系统入口（如 27 的 expanded session、26 的 `glassEffect`）。

### 菜单

- 下拉顶栏 **偏好 / 退出 / 钉住菜单**；钉住后菜单保持打开。
- 弹出位置相对状态栏图标 **居中**（macOS 13–27 同一套）。
- 13–26 与 27 共用展开 chrome（滚动、圆角壳、图标按钮）；26+ 为玻璃材质，更早系统走菜单 visual effect。
- 等 SwiftUI 量到真实高度再显示，避免首次打开闪矮面板。

### 额度

- 下拉新增 **额度** 区块（默认关闭，在偏好 → 菜单视图中添加）：Cursor / Grok / Codex **订阅额度**。
- 三个供应商并行请求，谁先返回谁先填，不必等全部结束。
- Grok access token 过期时静默续期并写回 `~/.grok/auth.json` 的 `key` / `refresh_token` / `expires_at`。Credits 返回 HTTP 200 空 body 或 `grpc-status: 16` 时会续期重试，不再一直显示「失败」。

## [2.0.0] — 2026-09-18

面向 **Apple Silicon（arm64）**、**macOS 12+**。安装包名为 **`eul2.app`**，Bundle ID **`com.wendyeq.eul2`**（与 Homebrew / 上游 `com.gaosun.eul` 的 1.6.2 并存，偏好与登录项不互通）。Intel Mac 请继续使用上游 **1.6.2**。

### 平台与分发

- 仅构建 **arm64**，移除 Intel SMC / SP78 路径，改为 M 系列传感器与 IOReport 等实现。
- 最低系统 **macOS 12.0**（App、Widget、SharedLibrary、SelfUpdate 一致）。
- 营销版本 **2.0.0**（build 55）；Finder 显示名 **eul2**。
- 应用内「检查更新」、GitHub 链接与 Release zip 指向 **[wendyeq/eul2](https://github.com/wendyeq/eul2)**。

### 菜单栏与展开下拉

- **Expanded interface** 下拉面板（键盘可聚焦），在较新系统上使用 **Liquid Glass** 外壳与更扁平的行样式（数字与图表保持不透明，不铺玻璃）。
- 顶栏 **偏好 / 退出 / 钉住菜单** 等 SF Symbol 按钮；长列表时顶栏固定。
- **网络** 区块 **四列网格**：实时上/下行与会话/今日/开机累计流量（累计流量默认展示）。
- **CPU / 内存 / 网络** 进程列表：Finder 显示、结束进程；**将某进程钉在列表顶部**（列表钉选，不激活前台应用、不关闭菜单）。
- 菜单栏 extra 保持 **紧凑双行** 芯片式展示（含网络上传/下载等）；配合系统「菜单栏」显隐与 `isVisible` / `autosaveName`。
- 蓝牙菜单 **每台设备一行** 电量；磁盘 **已用/可用** 与 **实时读/写速率**；**内存压力** 读数。

### Apple Silicon 监控

- CPU / GPU **温度**、**风扇转速**、GPU **占用**、**ANE**、内存 **带宽**（在 IOReport 可用时）。
- SMC 键位与 `IOHIDEventSystemClient` 回退（`SMC.swift` / `SmcControl.swift`）。
- 电池 **剩余时间** 等 IOPS 字段加固（不含 BLE GATT 电量恢复）。

### 小组件与共享

- **GPU Widget** 与 `containerBackground` 等与当前 Widget API 对齐。
- App Group：**`com.wendyeq.eul2.shared`**（与 1.6.2 隔离）。

### 偏好设置

- 窗口质感更接近 **系统设置**（侧栏材质、分组行、浅/深/自动外观，自动模式跟随系统）。
- **组件** 页：列表 + 开关 + 拖拽排序（非胶囊条）；表单行 **mini 开关**、控件 **右对齐**、标签 **单行**。
- 右侧详情区固定宽度，「可用」组件 **换行** 展示。

### 无障碍与视觉

- 关键控件 **VoiceOver** 标签与对比度改进；菜单栏 **SF Symbol** / 模板图标方向。

### 相对上游 1.6.2 不做的范围

- 不恢复 **Intel** 构建；不做风扇 **控制**、传感器墙、公网 IP、Bartender 式藏图标、完整历史 CSV、公证/Developer ID 分发。
- 原生差距项 **8、9**（菜单栏 extra 字数、自定义图标全面模板化）按规划不做。

### 致谢

- 基于 [Gao Sun](https://github.com/gao-sun) 的 **[eul](https://github.com/gao-sun/eul)**（MIT）。本 2.0 线为 fork 延续，非官方发布。

---

## 与 1.6.2 对照（摘要）

| | 上游 1.6.2 | 本版 2.0.0 |
|---|---|---|
| 架构 | Intel + Apple Silicon | **仅 arm64** |
| 安装名 / Bundle ID | `eul.app` / `com.gaosun.eul` | **`eul2.app` / `com.wendyeq.eul2`** |
| 典型安装 | Homebrew、官方 zip | 自构建或 **eul2.app.zip**（ad-hoc，首次需右键打开） |
| 下拉菜单 | 经典 NSMenu 风格 | **Expanded interface** + Liquid Glass（新系统） |
| M 系列传感器 | 有限 / Intel 键位 | **温度、风扇、GPU、ANE、带宽、内存压力** 等 |
| 网络 / 磁盘 | 基础用量 | **四列网格、累计流量、磁盘读写速率** |
| 偏好 | 原版布局 | **系统设置式** 分组与开关行 |

更早的 1.7.x 内部迭代已并入上述 2.0.0 能力，不再单独发版说明。
