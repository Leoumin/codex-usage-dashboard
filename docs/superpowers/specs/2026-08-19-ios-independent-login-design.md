# iPhone 独立 Codex 登录设计

## 目标

iOS 主 App 使用独立于 Mac Codex 的 OAuth 会话自动续期，不再依赖 Mac HUD 同步 access token。Widget 继续展示主 App 保存的最新用量与短期 access token。

## 登录流程

1. 主 App 请求 Codex device code。
2. 用户在 Safari 打开 OpenAI 验证页并输入一次性验证码。
3. 主 App 轮询授权结果并用 PKCE authorization code 换取 token。
4. access token 写入 App 与 Widget 共享的本机 Keychain 条目；refresh token 写入仅主 App 可读的本机 Keychain 条目。

## 刷新流程

- 主 App 请求用量遇到 HTTP 401 或 403 时，使用 refresh token 刷新一次。
- 刷新响应若返回轮换后的 refresh token，必须先覆盖保存，再重试用量请求。
- 单次刷新只重试一次，避免无限循环。
- Widget 不读取 refresh token、不执行刷新；失败时继续显示缓存，等待主 App 下次前台刷新。

## 凭证隔离

- Mac 同步凭证保留原 service，作为迁移期回退。
- iPhone access token 使用新的非 iCloud 同步 service，避免被 Mac HUD 覆盖。
- iPhone refresh token 使用主 App 默认 Keychain group，不指定共享 access group，因此 Widget 无权读取。
- refresh token 不写入日志、UserDefaults、App Group、快照或源码。

## 错误处理

- 设备码或 token exchange 失败：保留现有缓存并显示登录失败。
- refresh token 失效、撤销或重复使用：清除手机独立登录，提示重新登录。
- 网络失败：不清除凭证，保留缓存。

## 验证

- Core 单元测试覆盖设备码解析、OAuth exchange、refresh token 轮换与旧 token 保留。
- Core 全量测试与 HUD self-test 通过。
- iOS 无签名构建通过。
- 真机签名安装后完成一次设备码登录，并验证 App 与 Widget 进程运行。

