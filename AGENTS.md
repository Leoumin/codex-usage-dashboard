# Codex Usage Dashboard

## 沟通与执行

- 所有回复使用中文。
- 明确、低风险、可逆的工作直接完成，不停在方案层。
- 保持改动小且可验证，优先删除、复用和标准库，不引入不必要的依赖或抽象。
- 不提交、推送、发布或清理用户文件，除非用户明确要求。

## 产品边界

- 这是个人使用的只读 Codex 用量仪表盘，不做账号体系、服务端或多人共享。
- macOS 悬浮窗、iOS 主应用和 Widget 必须共享同一套用量模型与解析逻辑。
- iPhone 可使用独立设备码登录并刷新自己的 Codex 会话，不接管或覆盖 Mac Codex 会话。

## 架构

- `work/CodexUsageCore`：凭证模型、Keychain、接口请求、响应解析和快照缓存。
- `work/CodexUsageHUD`：macOS AppKit/SwiftUI 悬浮窗。
- `work/CodexUsageMobile`：XcodeGen 工程，包含 iOS App、WidgetKit 和 macOS 签名目标。
- `outputs`：已签名 macOS App、iOS 安装包和安装脚本。
- `docs/PROJECT_CONTEXT.md`：已确认的产品决策和当前状态。

## 不可破坏的约束

- 绝不记录、提交或展示真实 access token。
- Mac 到 iCloud Keychain 仍只同步 `access_token`、`account_id` 和 `last_refresh`。
- iPhone 独立登录的 `refresh_token` 只存主 App 私有、本机 Keychain，不进入共享 Keychain、App Group、Widget、日志或源码。
- Keychain group 保持 `$(AppIdentifierPrefix)com.zhaoxh.codexusage.shared`。
- App Group 保持 `group.com.zhaoxh.codexusage`。
- Apple Team 保持 `AXX22S6S2N`，除非用户明确更换签名账号。
- macOS HUD 必须读取系统代理或代理环境变量，避免启动环境缺少 HTTP 代理时出现超时。
- macOS HUD 每 60 秒刷新；LaunchAgent 每 20 秒只检查 Codex 是否运行及 HUD 是否需要拉起。
- 用户关闭 HUD 后，本次 Codex 会话内不得自动重开；Codex 完全退出后才清除关闭标记。
- Widget 的 `缓存` 表示实时刷新失败，当前显示上一次成功保存的数据，不代表数据无效。
- WidgetKit 的刷新时间由系统调度；代码中的 30 分钟是请求时间，不是精确定时器。

## 界面规则

- 视觉改动遵循 `gpt-taste` 约束并延续现有深色、紧凑、信息优先的仪表盘风格。
- 不做营销页、装饰性渐变球、嵌套卡片或无功能动画。
- 小组件优先保证一眼可读：剩余百分比、重置时间、可用重置次数和缓存状态。
- 使用 SF Symbols 与原生 SwiftUI/WidgetKit 控件；无明确收益时不增加第三方 UI 库。
- 视觉改动完成后，至少检查小号和中号 Widget，并尽量在真机截图上验证。

## 验证

完成相关改动后按影响范围执行：

```bash
swift test --package-path work/CodexUsageCore
swift run --package-path work/CodexUsageHUD CodexUsageHUD --self-test
cd work/CodexUsageMobile && xcodegen generate
xcodebuild -project work/CodexUsageMobile/CodexUsageMobile.xcodeproj \
  -scheme CodexUsage \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

涉及签名、Keychain、App Group、Widget 嵌入或图标时，再执行真机签名构建和安装验证。
