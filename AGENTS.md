# eul2

Apple Silicon 菜单栏监视器。Swift / AppKit / SwiftUI，最低 macOS 13，scheme `eul`，安装名 `eul2.app`（Xcode 产物仍是 `eul.app`）。

## Commands

本机 `/Applications/eul2.app` 就是开发环境。改了会编进 `eul.app` 的代码或资源后，同一轮交付做完两件事：Debug 构建成功，并立刻用这份产物覆盖安装、打开。完成标准：`xcodebuild` 退出码 0 且 `BUILD SUCCEEDED`；`/Applications/eul2.app/Contents/MacOS/eul` 与刚编出的二进制 SHA-256 相同；有进程从该路径起来。只改文档或 PRD 不必装。

```bash
xcodebuild -project eul.xcodeproj -scheme eul -destination 'platform=macOS,arch=arm64' -configuration Debug build
```

构建不加签名开关。DerivedData 里可能有多份 `eul-*`，按 `Contents/MacOS/eul` 的 mtime 取最新这一份再覆盖：

```bash
BIN=$(ls -t "$HOME/Library/Developer/Xcode/DerivedData"/eul-*/Build/Products/Debug/eul.app/Contents/MacOS/eul | head -1)
APP="${BIN%/Contents/MacOS/eul}"
killall eul 2>/dev/null || true
rm -rf /Applications/eul2.app
ditto "$APP" /Applications/eul2.app
open /Applications/eul2.app
```

scheme 没有测试 target。新增 `.swift` 文件写入 `eul.xcodeproj` 的 PBXBuildFile / PBXFileReference 和对应 group。

## OS version

产品行为在 macOS 13 到当前系统上同一套：菜单内容、居中弹出、钉住、齿轮/退出、额度。`#available` 只包旧系统没有的符号或系统入口（27 的 `NSStatusItem` expanded session、26 的 `glassEffect`）。宿主可以分叉，分叉之上共用同一套 UI 与定位。数据源有无按能力分支。布局、宽度、文案、对齐不绑系统版本。不保留 macOS 12 兼容分支。

MCP 中枢是 2.2.0 能力，规格在 `docs/prd-mcp-hub-2.2.0.md`。目录在 `$HOME/Library/Application Support/eul2/`，不进应用包。
