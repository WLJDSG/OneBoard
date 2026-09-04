# Findings & Decisions

## Requirements
- 网关切换优先弹出 Touch ID；没有可用生物识别时由 macOS 提供设备登录密码回退。
- 盘点并覆盖 OneBoard 内其他管理员密码入口，但不接管网页 OAuth 密码或验证码。
- 保留 Gateway Helper 白名单业务拒绝语义，不允许失败后回退到广泛管理员 shell。

## Research Findings
- 当前管理员弹框来自 `do shell script ... with administrator privileges`：网关 Helper 安装/卸载、Helper 不可用时的网关切换，以及彻底卸载脚本中的网关残留清理。
- 已安装的 Gateway Helper 通过 sudoers `NOPASSWD` 运行，并在自身脚本内校验网关/DNS 白名单；正常切换本应不再弹管理员密码。
- Apple 官方说明 Authorization Services 将认证 UI 与应用隔离，并允许系统未来采用 Touch ID 等认证方式；LocalAuthentication 本身只验证设备所有者，不授予 root。
- Apple 推荐 macOS 13+ 使用 SMAppService 管理 bundle 内 LaunchDaemon；完整迁移需要新的签名 Helper/XPC 协议和打包结构，超出本次“最小且安全”改动。

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| 使用 `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` | 系统优先 Touch ID，并自然回退到设备登录密码 |
| Helper 不可用时不再静默回退管理员 shell | 防止一次切换突然索要管理员密码，也保留 Helper 白名单边界 |
| 首次 Helper 安装继续由 macOS 管理员授权 | Touch ID 用户确认不能替代写 `/usr/local/bin`、`/etc` 所需的 root 授权 |

## Issues Encountered
| Issue | Resolution |
|-------|------------|

## Resources
- Apple Authorization Services: https://developer.apple.com/documentation/security/authorization-services
- Apple Service Management migration: https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos
