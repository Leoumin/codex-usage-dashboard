# macOS 桌面 Widget 实施计划

1. 在 XcodeGen 工程新增 macOS WidgetKit 扩展并嵌入宿主 App。
2. 宿主只同步共享 Keychain 凭证；macOS Widget 使用自身沙箱缓存和出站网络权限。
3. 默认启动和 `--refresh-widget` 均执行一次刷新后退出，不创建 NSPanel。
4. 将 LaunchAgent 改为 60 秒静默刷新，不再拉起可见 App。
5. 签名构建、安装，检查扩展注册、快照刷新和无常驻 HUD。
