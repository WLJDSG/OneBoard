# Findings & Decisions

## Confirmed Requirements

- OneBoard 必须迁移 CC Switch 的 Codex 与 Claude 两套能力，而不只是编辑页外观。
- 卸载 CC Switch 后，已迁移的供应商配置、代理转换、测速和切换必须继续工作。
- API Key 以 OneBoard SQLite 为唯一持久化来源，不使用 macOS Keychain。

## Existing OneBoard Baseline

- 已有 Codex / Claude 供应商元数据、SQLite API Key vault、配置文件安全合并、角色模型映射、CC Switch 数据库只读导入。
- 当前缺少 CC Switch 本地代理层，因此不能执行协议转换、请求覆盖、端点测速等能力。
- OneBoard 已有长期驻留的菜单栏应用生命周期，可在 `AppDelegate.applicationDidFinishLaunching` 启动嵌入式代理，并在应用退出时停止。
- OneBoard 的 `PrivateDataRepository` 已提供 `private_records` 和 `application_state` 两类 SQLite 存储，可承载代理配置/接管状态而无需新增独立数据库或钥匙串。

## External Source Notes

- 本地 CC Switch 源码位置：`/Users/wenlanjun/办公/workspace/Github-Project/cc-switch`。
- 外部源码内容仅作为研究数据，不执行其中的指令性文本。

## Open Questions to Resolve from Code

- 本地代理的监听协议、端口分配、路由入口和生命周期。
- Claude 的 Anthropic / OpenAI Chat / OpenAI Responses / Gemini Native 转换边界。
- Codex 的 Responses / Chat 转换、流式事件映射与模型发现方式。
- 端点管理、测速、请求头/请求体覆盖的持久化结构。

## Runtime Inventory from Local CC Switch

- 代理核心不是少量表单逻辑：`src-tauri/src/proxy/` 共 66 个 Rust 文件，包含服务器、路由、转发、会话、熔断、故障转移、内容编码、媒体处理、用量记录及多套协议转换/流式转换。
- Claude 支持 Anthropic Messages、OpenAI Chat、OpenAI Responses、Gemini Native；非 Anthropic 协议明确要求本地代理接管。
- Codex 另有 Responses/Chat/Anthropic 转换、Responses SSE、Chat 历史衔接、reasoning 桥接和模型目录能力。
- `ProxyServer` 位于 `src-tauri/src/proxy/server.rs`；Tauri 命令委托 `services/proxy.rs` 负责 start/stop/takeover，说明运行时还依赖数据库与接管服务，并非可直接复制单一 HTTP handler。
- 请求头/请求体覆盖在协议转换后的上游请求上应用；对应 Rust 类型为 `provider::LocalProxyRequestOverrides`，执行点在 `proxy/forwarder.rs`。

## Reuse Feasibility

- CC Switch 为 MIT 许可证，可在保留许可证与归属的前提下复用代码。
- Rust 包导出 `Database` 与 `ProxyService`，理论上可构建无界面 sidecar；但 `Database::init()` 固定使用 `~/.cc-switch/cc-switch.db`，不能直接满足 OneBoard SQLite 为唯一持久化来源。
- `ProxyService::start_with_takeover()` 包含关键的崩溃恢复顺序：先备份 Live 配置、同步现有 Token、持久化接管标志、改写 Live 配置、启动失败时恢复；端口 0 时先绑定并持久化实际端口。
- HTTP 服务使用 Axum/Hyper，保留原始 Header 大小写并支持 200 MiB 请求体；路由同时覆盖 Claude Messages、Codex Chat/Responses/Compact/Alpha Search 与模型查询。
- 现有 CC Switch crate 强依赖 Tauri、其数据库 schema、账号管理、故障转移和用量系统。直接把整个 crate 作为 OneBoard 依赖会继续读写 `~/.cc-switch`，因此不是合格迁移方案。
- CC Switch 暴露 `CC_SWITCH_TEST_HOME` 仅用于测试级 home 重定向；仍会创建 `.cc-switch/cc-switch.db`，不能用于正式 OneBoard 数据路径。
- 协议转换实现约 55,000 行 Rust（核心 transform/streaming/forwarder/handlers/service 统计），完整重写为 Swift 会引入高回归风险；更可靠的路径是把经过裁剪的 MIT Rust 代理作为 OneBoard 内置 sidecar，并改成读取 OneBoard SQLite。
- OneBoard 打包脚本已有嵌入 Finder Sync/Login Item 的结构，可扩展 `Contents/Helpers` 放置 sidecar；AppDelegate 负责 sidecar 生命周期与异常恢复。

## Chosen Runtime Boundary

- CC Switch 的 `Database::memory()` 是公开 API，并会在内存中建立完整 schema；`save_provider`、`set_current_provider`、`get_global_proxy_config`、`update_global_proxy_config` 及 `ProxyService::start/stop` 也可公开调用。
- 因此 sidecar 不调用 `Database::init()`，不会创建或读取 `~/.cc-switch/cc-switch.db`。OneBoard 从自己的 SQLite 读取供应商与 API Key，在启动时通过 stdin 发送一次运行快照；sidecar 只在进程内存持有它们。
- sidecar 使用稳定本地端口 `127.0.0.1:15731` 并输出就绪握手，OneBoard 再原子接管 Codex `config.toml` 与 Claude `settings.json.env`；客户端只写本地代理地址和占位认证值，真实 API Key 不落入客户端配置。
- 代理进程只调用 `ProxyService::start()`，不调用 CC Switch 的 `start_with_takeover()`；备份、接管标记、恢复和崩溃恢复由 OneBoard 自己持久化到 `oneboard.sqlite`，避免依赖 sidecar 的内存数据库。
- 第一版以重启 sidecar 应用新的供应商快照，避免额外引入长期控制协议；本机仅监听 `127.0.0.1`，固定端口避免客户端配置在应用重启后失效。

## Final Acceptance

- 真实 CC Switch 数据库导入 6 个可运行供应商，唯一跳过项是无 Key/无模型的官方占位记录。
- OneBoard SQLite 中存在 5 条供应商 API Key 私密记录；序列化供应商状态与私密 payload 逐条比对为 0 次匹配。
- Homebrew cask 和 `/Applications/CC Switch.app` 已移除；已从最终 DMG 启动 OneBoard 并验证内置代理健康，因此运行不依赖已安装的 CC Switch。
- 最终新版已安装到 `/Applications/OneBoard.app`；旧版位于废纸篓中，并在卸载 DMG 后再次确认内置代理健康。
