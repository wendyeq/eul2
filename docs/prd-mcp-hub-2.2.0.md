# PRD：eul2 MCP 中枢

| 项 | 内容 |
|---|---|
| 产品 | eul2 |
| 版本 | **2.2.0**（不进入 2.1.0） |
| 状态 | 已实现（feat/mcp-hub） |
| 最低系统 | macOS 13（2.1.0 已统一，本功能依赖官方 Swift MCP SDK） |

## 1. 问题

本机多个 agent（Cursor、Claude Desktop、Claude Code、Codex、Grok）各自维护一份 MCP 配置。每加一个 server，就要改一遍。MCP Router 曾经用「一份目录 + 一个本地入口」解决这件事，但已于 2026-09-18 停更，且其 HTTP 聚合在多客户端下不稳定。

要保住的是这个理念，不是那个 Electron 应用：在 eul2 里用 Swift 重写中枢。各 agent 只连接一次；之后只改 eul2 的目录。

## 2. 目标

1. 一份 MCP 目录，增删和开关只改这一处。
2. 五个客户端各留一条名为 `eul2-mcp` 的连接，不再为每个 server 单独配置。
3. 打开下拉菜单能看出中枢是否在跑、各 server 是否启用、**上次有没有被调用**。
4. 会话结束后能用一份无参数的调用记录核对「到底有没有打到中枢」。

成功标准：目录里加一个测试 server 后，五个客户端不改各自配置就能调到新工具；关掉则四处同时消失；菜单能显示「几分钟前」或「从未」；JSONL 里能对上这次调用。

## 3. 非目标

- 不移植 MCP Router（许可证与技术栈都不允许）。
- 不引入第二个 MCP 管理产品或 Node 运行时。
- 不做 DXT、工作区、项目分组、工具目录搜索、云同步、每应用 token。
- 不做 SQLite、统计页、图表、按客户端汇总。
- 不记录工具参数、请求体、资源原文。
- 2.2.0 不做「添加 server」大表单（改 catalog 文件 + 菜单开关）。
- 不做 MCP Router JSON 导入。
- 不把手写 JSON-RPC 来迁就 macOS 12。
- 不把本功能合进 `release/2.1.0`。

## 4. 谁用、怎么用

主用户是本机同时开多个 agent 的人。日常路径：

1. 偏好 → **MCP**（一级栏目）→ 打开「MCP 中枢」（默认关，避免一安装就在后台拉 `npx`）。
2. 打开配置文件，直接编辑 catalog。
3. 点「连接 agent」一次。
4. 之后只在 eul2 里开关 server。需要看有没有用上时，打开下拉菜单；需要事后核对时，看 JSONL。

eul2 退出，中枢停止。目录和调用记录仍留在用户主目录的 Application Support 里，删掉 `eul2.app` 也不会消失。

## 5. 产品行为

### 5.1 生命周期

| 条件 | 行为 |
|---|---|
| `mcpHubEnabled = false`（默认） | 不听端口、不拉子进程 |
| 打开总开关 | 主进程启动中枢，与下拉菜单是否展示无关 |
| 睡眠 | 中枢不拆（和额度暂停轮询不是一类事） |
| 退出 eul2 / 关掉总开关 | 停 HTTP、结束子进程 |

菜单「MCP」块默认不在菜单视图里，和额度、蓝牙、磁盘一样。关掉菜单块不影响中枢。

### 5.2 目录

路径：`$HOME/Library/Application Support/eul2/mcp-catalog.json`  
权限：`0600`

```json
{
  "version": 1,
  "port": 18732,
  "servers": [
    {
      "id": "context7",
      "enabled": true,
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"],
      "env": {},
      "cwd": null
    },
    {
      "id": "luckin",
      "enabled": true,
      "url": "https://example.com/mcp",
      "headers": { "Authorization": "Bearer …" }
    }
  ]
}
```

- `id` 只允许 `[a-z0-9-]`。
- 有 `url` 为远程，有 `command` 为本地进程，二者不能同时出现。
- `cwd` 缺省为用户家目录。
- 改文件后约 0.5s 热加载：停掉去掉的、拉起新增的、向已连接的 agent 发 `tools/list_changed`。
- 端口默认 `18732`，只绑 `127.0.0.1`。IANA 未分配该端口；本机当前无进程在听。MCP Router 用的是 `3282`，不会撞。只通过 catalog 的 `port` 改，不做偏好项。启动时若绑定失败，中枢标失败并停，不抢别人的口。
- 增删 server 只手写 catalog。偏好页「打开配置文件」用默认应用打开该 JSON。

### 5.3 对外入口

只绑 `127.0.0.1`，不绑 `0.0.0.0`。无 token 体系。

| 客户端 | 配置文件 | 连接方式 |
|---|---|---|
| Cursor | `~/.cursor/mcp.json` | stdio：`eul mcp-connect` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | 同上 |
| Claude Code | `~/.claude.json` 顶层 `mcpServers` | 同上 |
| Codex | `~/.codex/config.toml` | `url = "http://127.0.0.1:18732/mcp"` |
| Grok | `~/.grok/config.toml` | 同上 |

`eul mcp-connect` 是同一条二进制：`argv[1] == mcp-connect` 时不进菜单栏，只做 stdio → 中枢 HTTP。中枢 2 秒连不上则 stderr + 退出码 1。

「连接 agent」只 upsert 名为 `eul2-mcp` 的条目。不改其它条目（例如已有的 `mcp`、`mcp-router` / `mcp_router`、Codex 的 `my-coffee`、Claude 的 `mcpServers.disabled`）。`command` 指向**当前正在运行**的 `Bundle.main.executableURL`。回环 HTTP 路径仍是 `/mcp`（协议入口，不是 server 名）。

工具对外名称：`{id}--{原名}`（例如 `gitnexus--list_repos`）。中枢名里不用 `__`：Grok 会再套一层 `eul2-mcp__…`，第二段 `__` 会被 session admission 丢掉。`--` 仍能切开 id 和原名。Cursor / Claude / Codex 共用同一份 `tools/list`。

### 5.4 有没有用上

不做分析产品。只保留两种信号：

**菜单（当下）**  
每条 server 一行，密度对齐蓝牙：名称、开/关、`3分钟前` / `从未` / `失败`。

**JSONL（事后）**  
路径：`$HOME/Library/Application Support/eul2/mcp-calls.jsonl`  
权限：`0600`  
每行仅：`time`、`id`、`tool`、`ms`、`ok|error`（短错误码）。不写参数。约 2MB 从文件头截断。无轮转 UI，无「是否记录」开关，无 SQLite，无统计。

打点只来自聚合器的 `tools/call`（以及上游进程挂掉）。

### 5.5 界面

偏好侧栏现有三级：**通用 / 组件 / 菜单视图**。MCP 不塞进「通用」。中枢是一套独立设置（开关、连接、配置文件），和启动登录、外观不是一类；塞进通用会把该页变成杂物抽屉。额度只是下拉里多一块，所以只出现在「菜单视图」；MCP 还要管常驻进程和客户端接线，值得单独一栏。

macOS 设置窗口用多个 pane 分组相关设置（[HIG Settings · macOS](https://developer.apple.com/design/human-interface-guidelines/settings)，核验 2026-09-19）。侧栏切换沿用现有点击，不加额外动效。

侧栏顺序：通用、组件、菜单视图、**MCP**。

**偏好 → MCP**（配置，不常改）

- 开关：MCP 中枢（默认关）
- 按钮：连接 agent
- 按钮：打开配置文件
- 已有 server 列表与启用开关（写回 catalog）

**偏好 → 菜单视图**

- 与额度相同：只决定下拉里**显不显示** MCP 块，不启动中枢

**下拉菜单 MCP 块**（需在菜单视图中启用）

- 中枢是否在听端口
- 各 server 上次调用：`3分钟前` / `从未` / `失败`
- 可开关 server（与偏好 MCP 页同一 `McpStore`）

形态跟额度块：分组、左对齐标题、菜单宽度 345pt。

## 6. 技术约束（产品合同，不是实现清单）

- 实现语言：Swift，eul2 主进程。协议库：官方 [Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk)。
- 官方 `StdioTransport` 只绑当前进程 stdin/stdout，连子进程必须自写 `Process` 管道。
- 官方 HTTP transport 不听端口：用 `Network.framework` 在回环上适配 `/mcp`。
- **每个 MCP 会话一个** Stateful HTTP transport，禁止全局单例（MCP Router 多客户端 HTTP 500 的根因）。
- 菜单栏进程的 `PATH` 须补上 `/opt/homebrew/bin:/usr/local/bin`。
- 上游 stdio 子进程挂了：重拉一次，再挂则菜单标失败，不空转重试。
- 不把 Node、Electron 或 MCP Router 源码编进工程。

```
偏好 / 菜单 → McpStore → McpHub
                         ├ Catalog
                         ├ 上游（Process / HTTP Client）
                         ├ Aggregator
                         └ 回环 HTTP
mcp-connect CLI ──────────────────┘
```

## 7. 数据与卸载

| 路径 | 删 `eul2.app` 后 |
|---|---|
| `/Applications/eul2.app` | 消失 |
| `$HOME/Library/Application Support/eul2/mcp-catalog.json` | 仍在 |
| `$HOME/Library/Application Support/eul2/mcp-calls.jsonl` | 仍在 |
| `UserDefaults`（含 `mcpHubEnabled`） | 仍在 |

要清目录和记录，须手动删 Application Support 下该文件夹。不做「拖到废纸篓就清 catalog」——会丢掉命令和凭据，macOS 也没有可靠卸载钩子。

## 8. 验收

1. Debug 构建通过：`xcodebuild -project eul.xcodeproj -scheme eul -destination 'platform=macOS,arch=arm64' -configuration Debug build`
2. 总开关默认关；打开后 `127.0.0.1:18732` 可连。
3. 「打开配置文件」用默认应用打开 `mcp-catalog.json`；手写 server 后热加载。
4. 「连接 agent」后五个客户端都有 `eul2-mcp`；Codex / Claude 里原有其它 MCP 条目仍在。
5. `grok mcp doctor` 通过；Cursor / Claude 能列出带 `id--` 前缀的工具。
6. catalog 里关掉一条，五端同时少那组工具，且不用重配客户端。
7. 调一次工具后，菜单该行从「从未」变为相对时间；JSONL 多一行且无参数字段。
8. 关掉中枢后，`eul mcp-connect` 在 3 秒内以退出码 1 结束。
9. 两个客户端同时调工具，不出现「第一请求之后全部 500」。
10. 删掉 `/Applications/eul2.app` 后，catalog 与 JSONL 仍在。

## 9. 回滚

关总开关；各客户端配置里删除 `eul2-mcp` 那一条；catalog 与 JSONL 保留。不改用户其它 MCP。

## 10. 发布

- 代码：2.1.0 合入之后的树，开 `feat/mcp-hub`，再进 `release/2.2.0`。
- 2.2.0 合入后即可用，不依赖后续的添加表单。
- SSE 回环适配若翻车：Grok / Codex 可退回 `mcp-connect`，中枢与目录不变。

## 11. 已确认决定

1. 理念进 eul2，Swift 重写，不用第三方管理应用。
2. 最低 macOS 13，不做 12 兼容分支。
3. 目录在 Application Support，不在应用包内；删 app 不删目录。
4. 本功能只上 2.2.0。
5. 总开关默认关。
6. 五客户端：Grok / Codex 走 HTTP，其余走 `mcp-connect`。
7. 可见性只要上次调用 + 无参数 JSONL；不要 SQLite、不要统计。
8. 偏好侧栏增加一级栏目「MCP」；「通用」不放中枢配置；「菜单视图」只控制下拉是否显示该块。
