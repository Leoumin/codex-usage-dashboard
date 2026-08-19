# iPhone 独立 Codex 登录实施计划

1. 在 `CodexUsageCoreTests` 添加 OAuth 请求、响应和 token 轮换测试，先确认测试因实现缺失而失败。
2. 在 `CodexUsageCore` 增加设备码 OAuth 客户端、refresh token 私有存储和可配置 Keychain 同步属性。
3. 在 iOS App 中优先使用手机独立凭证，401/403 时刷新并重试一次；增加设备码登录 sheet。
4. Widget 优先读取手机独立 access token，缺失时回退旧 Mac 同步凭证。
5. 更新安全边界文档，运行测试、构建、真机签名安装与登录验证。

