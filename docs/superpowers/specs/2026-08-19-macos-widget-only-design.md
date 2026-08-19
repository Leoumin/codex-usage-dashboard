# macOS 桌面 Widget 设计

## 目标

macOS 只展示桌面 Widget，不再启动悬浮窗或常驻可见 App。宿主 App 仅用于承载 Widget 扩展和执行短暂后台刷新。

## 架构

- `CodexUsageHUD.app` 保留现有 bundle，改为无窗口 Widget 宿主。
- 新增 macOS WidgetKit 扩展，复用 iOS Widget 的小号和中号视图。
- 宿主读取 `~/.codex/auth.json` 并同步最小凭证到共享 Keychain。
- macOS Widget 使用自己的沙箱缓存，直接请求用量接口，不访问跨平台 App Group。
- LaunchAgent 每 60 秒检查 Codex/ChatGPT；运行时执行一次 `--refresh-widget` 后退出。
- Widget 自身按系统时间线调度刷新，并在失败时展示缓存。

## 行为边界

- 双击宿主 App 只刷新 Widget，不显示窗口或 Dock 图标。
- 不保留 HUD 关闭标记，不自动 `open` 宿主 App。
- 不新增菜单栏图标、设置页、通知或第三方依赖。
- macOS 桌面 Widget 要求 macOS 14 或更高版本。

## 验证

- Core 测试与 HUD self-test 通过。
- macOS Release 签名构建包含 Widget 扩展。
- 安装后 `pluginkit` 能识别扩展。
- `--refresh-widget` 成功同步 Keychain 凭证、触发 WidgetKit 刷新且进程退出。
