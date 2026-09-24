# CodexBar 近期更新（2026-09-24）

对象：[steipete/CodexBar](https://github.com/steipete/CodexBar)，按 GitHub 官方稳定版发布说明整理。截取 v0.62.0–v0.65.0（2026-09-19 至 09-23）；“近期”不表示自 eul2 某个版本以来的差异。

| 版本 | 新增 / 变化 | 主要修复 |
| --- | --- | --- |
| [v0.65.0](https://github.com/steipete/CodexBar/releases/tag/v0.65.0)（09-23） | 新增 Charm Hyper、GitKraken AI、Bifrost，官方称覆盖 **80 个 provider**；Kimi 网页多账号、豆包 Ark API Key 多账号、OpenCode Go 每账号 API Key；Zed 可选浏览器账单查看花费与余额；Omarchy 紧凑栏主题配色 logo。 | Claude CLI 刷新时保留模型级周额度；Codex 零用量周重置确认；减少额度图与本地费用历史重复计算；Antigravity 离线回退提示与账号处理。 |
| [v0.64.1](https://github.com/steipete/CodexBar/releases/tag/v0.64.1)（09-22） | Cursor 的 Grok Bot 百分比可固定在菜单栏；Kimi 可选中国/国际区。 | 菜单栏图标超出显示器边界时恢复位置；OpenRouter 高负载时避免余额请求因等待调度而过早超时；Linux Antigravity 额度池去重。 |
| [v0.64.0](https://github.com/steipete/CodexBar/releases/tag/v0.64.0)（09-21） | 新增 Helmcode、v0、TypeSafe 额度/账单来源；**两个 provider 合并为一个双行菜单栏图标**；Usage & Spend 按 provider 分组浏览来源和模型；Antigravity 本地历史费用估算；手动检查更新与版本显示。 | 修正 Codex 分叉会话继承的费用总量；防止超大历史值导致崩溃；改进 OpenCode Console 数据恢复和 Claude 账号切换。 |
| [v0.63.0](https://github.com/steipete/CodexBar/releases/tag/v0.63.0)（09-20） | **Pi / OMP 本地 token 和估算费用历史**进入应用、CLI、概览、Usage & Spend 和小组件，避免与 Claude / Codex 重复计数；小组件支持 DeepSeek 和 OpenRouter 余额；网页面板可显示 provider 报告的 30 天美元花费。 | 修正 Codex 分页会话历史成本重复计数；强化配置文件替换后的变更检测与临时 Keychain 读取失败恢复。 |
| [v0.62.0](https://github.com/steipete/CodexBar/releases/tag/v0.62.0)（09-19） | Codex / Claude 可按当前及近期**周额度周期**对照本地 token/费用历史；概览新增紧凑布局和隐藏 provider 详情；支持分享概览；小组件固定指定账号；可选 `usage_updated` hook 在成功刷新后执行命令；CLI 可对照 SSH 主机上的 Codex 本地费用；Warp 终端操作。 | 修复 Codex 费用缓存中多余请求行及中断扫描的历史保留。 |

## 对 eul2 值得留意的方向

- 菜单栏密度：v0.64.0 的双 provider 单图标、v0.62.0 的紧凑概览和隐藏详情，体现对多数据源场景的布局控制；这是产品参考，不意味着 eul2 应直接复制实现。来源：[v0.64.0](https://github.com/steipete/CodexBar/releases/tag/v0.64.0)、[v0.62.0](https://github.com/steipete/CodexBar/releases/tag/v0.62.0)。
- 统计边界：v0.63.0 的 Pi / OMP 历史去重、v0.62.0 的周额度周期对齐、v0.65.0 的零用量重置确认，说明多来源成本和额度展示需要明确归属、时间窗口与未知值。来源：[v0.63.0](https://github.com/steipete/CodexBar/releases/tag/v0.63.0)、[v0.62.0](https://github.com/steipete/CodexBar/releases/tag/v0.62.0)、[v0.65.0](https://github.com/steipete/CodexBar/releases/tag/v0.65.0)。

以上仅概括官方发布说明，不验证功能在本机的实际运行情况。
