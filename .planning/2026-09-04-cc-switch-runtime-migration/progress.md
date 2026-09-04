# Progress Log

## Session: 2026-09-04

### Current Status
- **Phase:** Complete
- **Started:** 2026-09-04

### Actions Taken
- 用户将目标澄清为迁移 CC Switch 的 Codex / Claude 完整独立运行能力。
- 已确认前一版只完成可直接写入客户端配置的字段和 CC Switch 风格编辑体验。
- 已定位并读取本地 CC Switch 的 `BasicFormFields.tsx` 与 `ClaudeFormFields.tsx`，确认代理依赖字段清单。
- 初始化独立规划目录，后续按运行时链路推进。
- 通过 CC Switch CodeGraph 盘点本地代理目录：66 个 Rust 文件，确认 Codex 与 Claude 转换、SSE、接管和故障处理是完整运行时子系统。
- 核对 MIT 许可证、Cargo 依赖、ProxyServer 路由和 ProxyService 接管事务；排除直接链接未修改 cc-switch crate 的方案，因为其数据库路径固定为 `~/.cc-switch`。
- 使用 OneBoard CodeGraph 确认 AppDelegate 驻留生命周期和 PrivateDataRepository 可作为原生代理的启动点与唯一持久化存储。
- 统计 CC Switch 转换核心约 55k 行并检查其测试 home 重定向；决定避免高风险 Swift 重写，转向内置 MIT Rust sidecar + OneBoard SQLite 适配方案。
- 找到 `Database::memory()` 及公开的供应商/代理服务 API，确定 sidecar 可以零磁盘持久化运行；OneBoard SQLite 保持唯一配置与密钥来源。
- 确定 OneBoard 自主管理客户端配置备份/恢复，sidecar 仅负责协议代理；进程启动通过 stdin/stdout JSON 交换快照与实际端口。
- 通过 Homebrew 安装 Rust/Cargo；sidecar `cargo check` 与单元测试通过。
- Swift 侧完成 sidecar 生命周期、动态端口握手、SQLite Key 运行快照、客户端占位认证接管与退出停止。
- 编辑页新增协议格式、完整 URL、User-Agent、备用端点、测速/择优、请求覆盖、缓存与 Codex→Anthropic 选项。
- CC Switch 导入扩展为读取备注、官网、代理 meta 和 provider_endpoints；持久化运行快照前剥离明文 Key。
- 本地请求级 mock 验证成功：Claude Messages→OpenAI Chat→Claude 与 Codex Responses→Anthropic Messages→Responses；Header/Body 覆盖和真实上游 Key 注入均符合预期。
- 正式 DMG 通过 `hdiutil verify`，只读挂载后确认内置 11 MiB arm64 Helper、MIT 许可证与整体深度签名均有效。
- 从 DMG 中直接运行 Helper，在空 HOME 中 `/health` 返回 healthy，且未创建 CC Switch 目录或数据库。
- 已正常退出并通过 Homebrew 卸载 CC Switch 3.16.1；`/Applications/CC Switch.app` 已移除，`~/.cc-switch/cc-switch.db` 保留作回滚数据。
- 卸载后从 DMG 启动 OneBoard，内置 Helper 独立监听 `127.0.0.1:15731`，`/health` 正常，Claude 客户端仅写入 `PROXY_MANAGED` 占位认证。
- 已将 `/Applications/OneBoard.app` 旧版移到废纸篓 `OneBoard-before-cc-switch-migration.app`，安装新版后重新验证签名、主进程与内置代理；卸载 DMG 后健康检查仍通过。
- 用户反馈 Claude Code `ECONNRESET`；最小 curl 稳定复现本地 `/v1/messages` 返回空响应，而健康检查始终正常。
- 独立 sidecar stderr 捕获到 Rustls 因多加密后端未选定默认 `CryptoProvider` 而 panic；启动时显式安装 ring provider 后，同一 HTTPS 请求和 SSE 流均返回 HTTP 200。
- 修复版已替换 `/Applications/OneBoard.app`；真实 Claude Code CLI 使用 `deepseek-v4-flash[1M]` 在 4.85 秒内返回“你好”，`stop_reason=end_turn`，无重试。

### Test Results

| Test | Expected | Actual | Status |
|---|---|---|---|
| Existing OneBoard suite | Baseline remains green before runtime migration | 139 tests, 0 failures | passed |
| Rust sidecar `cargo check` | standalone library boundary compiles | passed | passed |
| Rust sidecar unit test | app type boundary and TLS crypto initialization | 2 passed | passed |
| Swift focused AI tests | routing placeholder and runtime snapshot | 13 passed | passed |
| Swift CC Switch import test | metadata/endpoints imported; saved snapshot strips keys | 1 passed | passed |
| Claude protocol smoke | Anthropic request → OpenAI Chat upstream → Anthropic response | HTTP 200, converted response verified | passed |
| Codex protocol smoke | Responses request → Anthropic upstream → Responses response | HTTP 200, converted response verified | passed |
| Sidecar clean-home run | no `.cc-switch` or other files created | empty HOME remained empty | passed |
| Final OneBoard suite | all tests after runtime/UI/import changes | 142 tests, 0 failures | passed |
| Real CC Switch migration | copy providers/secrets into OneBoard SQLite | 6 imported, 1 keyless official entry skipped | passed |
| Persisted secret separation | API Key payloads absent from serialized profile state | 0 matches | passed |
| Formal DMG integrity | `hdiutil verify` and deep code-sign validation | valid | passed |
| Bundled helper isolation | run from DMG with empty HOME | healthy; no files created | passed |
| Post-uninstall runtime | OneBoard starts bundled proxy without CC Switch installed | `127.0.0.1:15731` healthy | passed |
| DMG SHA-256 | final artifact checksum after TLS fix | `405a45c91eddc8acc4796818b7092631298c209162d3fc79a29d8975a06fd8a8` | recorded |
| HTTPS reset regression | local `/v1/messages` used to return empty reply | HTTP 200 after CryptoProvider initialization | passed |
| Claude SSE over HTTPS | upstream event stream survives proxy | `message_start`, `message_delta`, `message_stop` | passed |
| Real Claude Code CLI | selected custom model returns without reset | 4.85s, `result=你好`, `stop_reason=end_turn` | passed |

### Errors

| Error | Resolution |
|---|---|
| `cargo check` 无法执行，系统未安装 Rust/Cargo | 已确认常见路径均不存在；需要安装工具链后继续 sidecar 编译验证 |
| 首次 Cargo 在沙盒内无法写 `~/.cargo` | 经用户授权后下载固定依赖并完成编译 |
| sidecar import 使用了上游 lib 名 `cc_switch_lib` | 按 Cargo 实际暴露名改为 `cc_switch` |
| 首次真实导入受沙盒限制，无法写 Application Support | 经用户授权后运行同一导入命令成功 |
| 取回压缩前的打包会话时进程 ID 已失效 | 校验已生成 DMG 的时间戳和完整性，再只读挂载验收最终内容 |
| Claude Code 请求 `ECONNRESET`，但代理 `/health` 正常 | Rustls worker 首次 HTTPS 连接时未找到默认 CryptoProvider；sidecar 启动时显式安装 ring provider |
