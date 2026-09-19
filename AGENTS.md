# eul2

Apple Silicon 菜单栏监视器。Swift / AppKit / SwiftUI，最低 macOS 12，scheme `eul`，安装名 `eul2.app`（Xcode 产物仍是 `eul.app`）。

## Commands

```bash
xcodebuild -project eul.xcodeproj -scheme eul -destination 'platform=macOS,arch=arm64' -configuration Debug build
```

验证改动时跑上面这一条，不要加签名开关。装到本机：

```bash
killall eul 2>/dev/null || true
rm -rf /Applications/eul2.app
ditto "$HOME/Library/Developer/Xcode/DerivedData"/eul-*/Build/Products/Debug/eul.app /Applications/eul2.app
open /Applications/eul2.app
```

scheme 没有测试 target。新增 `.swift` 文件写入 `eul.xcodeproj` 的 PBXBuildFile / PBXFileReference 和对应 group。

## OS version

产品行为在 macOS 12 到当前系统上同一套：菜单内容、居中弹出、钉住、齿轮/退出、额度。`#available` 只包旧系统没有的符号或系统入口（27 的 `NSStatusItem` expanded session、26 的 `glassEffect`）。宿主可以分叉，分叉之上共用同一套 UI 与定位。数据源有无按能力分支。布局、宽度、文案、对齐不绑系统版本。
