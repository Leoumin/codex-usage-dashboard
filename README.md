# Codex Usage Dashboard

个人使用的 Codex 用量仪表盘，包含 macOS 悬浮窗、iOS 主应用和桌面 Widget。

## 功能

- 展示 5 小时、周等用量窗口的剩余百分比与重置时间。
- 展示可用重置次数及每次重置额度的到期时间。
- macOS HUD 跟随 Codex 启动，每 60 秒自动刷新。
- Mac 将最小化凭证通过 iCloud Keychain 同步到 iPhone。
- iOS App 支持手动刷新；Widget 使用系统时间线刷新并在失败时回退到缓存。

## 目录

```text
work/CodexUsageCore    共享模型、网络、Keychain 与缓存
work/CodexUsageHUD     macOS 悬浮窗源码
work/CodexUsageMobile  iOS App、Widget 和 XcodeGen 工程
outputs                已构建产物与 macOS 安装脚本
docs                   设计、计划、截图与项目上下文
```

## 开发

```bash
swift test --package-path work/CodexUsageCore
swift run --package-path work/CodexUsageHUD CodexUsageHUD --self-test

cd work/CodexUsageMobile
xcodegen generate
open CodexUsageMobile.xcodeproj
```

无签名的 iOS 编译检查：

```bash
xcodebuild \
  -project work/CodexUsageMobile/CodexUsageMobile.xcodeproj \
  -scheme CodexUsage \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 安装 macOS HUD

```bash
outputs/install-codex-usage-hud-launcher.sh
```

脚本默认安装同目录的 `CodexUsageHUD.app` 到 `~/Applications`，并更新
`local.codex.usage-hud.follow-codex` LaunchAgent。

## 安全边界

Mac 不会把 Codex 的 `refresh_token` 同步到手机。iPhone 独立登录后，自己的
`refresh_token` 仅保存在主 App 私有、本机 Keychain；不会进入共享 Keychain、
App Group、Widget、源码、文档或日志。

当前实现与已确认决策见 [docs/PROJECT_CONTEXT.md](docs/PROJECT_CONTEXT.md)。
