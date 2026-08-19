# 项目上下文

更新日期：2026-07-16

## 当前成果

- macOS HUD 已签名并安装在 `~/Applications/CodexUsageHUD.app`。
- LaunchAgent `local.codex.usage-hud.follow-codex` 已启用。
- iOS App 与 Widget 已完成真机签名、安装和桌面验证。
- iOS App 已配置自定义 App Icon，源文件位于
  `work/CodexUsageMobile/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`。
- 发布产物位于 `outputs`。

## 已确认的行为

### macOS

- HUD 读取 `~/.codex/auth.json`，请求 ChatGPT 的用量与重置额度接口。
- 启动环境没有代理变量时，会通过 `scutil --proxy` 读取系统 HTTP、HTTPS 或 SOCKS 代理。
- HUD 使用 RunLoop 上的 `Timer` 每 60 秒触发一次刷新，刷新本身不会持续占用 CPU。
- LaunchAgent 每 20 秒检查一次 Codex 与 HUD 进程；HUD 未运行时会静默同步最新凭证，但不请求用量。
- 关闭按钮会写入当前 Codex 会话的关闭标记，防止 LaunchAgent 立即重新拉起 HUD。
- 关闭标记只阻止浮窗显示，不会停止凭证同步。
- Codex 完全退出后关闭标记被清除，下次启动 Codex 时 HUD 会再次出现。

### iOS 与 Widget

- Mac 从本地 Codex 登录文件提取最小凭证并写入可同步的 iCloud Keychain。
- 手机端直接请求：
  - `https://chatgpt.com/backend-api/wham/usage`
  - `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`
- iOS App 在首次无数据时自动刷新，也支持下拉和右上角按钮手动刷新。
- App 与 Widget 通过 App Group 共享最后一次成功的 `UsageSnapshot`。
- Widget 请求约 30 分钟后刷新，但 iOS 可以延后或合并调度。
- Widget 显示 `缓存` 时，说明本次网络或凭证刷新失败，画面来自上一次成功快照。

## 安全决策

- 不把完整 Codex session 或 `auth.json` 同步到 iPhone。
- 不同步 `refresh_token`，避免手机获得长期刷新 Codex 会话的能力。
- 只同步 `access_token`、`account_id` 和 `last_refresh`。
- 凭证使用 `kSecAttrSynchronizable` 的 Keychain 条目，并限制在共享 Keychain group。
- 文档、截图、测试样例和构建日志不得包含真实凭证。

## 视觉方向

- macOS HUD：轻量、紧凑、低干扰，与 Codex 桌面客户端的用量信息层级一致。
- Widget：深色背景、白色标题、青色主数值、琥珀色异常状态。
- 中号 Widget 的核心顺序为：标题与状态、周剩余、进度与重置时间、可用重置次数。
- `docs/assets` 保存 macOS 视觉迭代截图；`outputs/codex-usage-ios-preview.png` 保存 iOS 预览。
- 后续界面调整继续使用 `gpt-taste` 约束，避免花哨装饰和信息过载。

## 已知限制

- iCloud Keychain 同步和 Widget 时间线刷新都由系统调度，不能保证即时到达。
- access token 过期后，用户需要在 Mac 上打开 Codex，让 Mac 端重新同步新凭证。
- 项目依赖 ChatGPT 当前内部接口结构；接口字段变化时需同步更新解析器和测试。
