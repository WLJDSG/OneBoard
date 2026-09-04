# Task Plan: CC Switch Codex / Claude 独立运行能力迁移

## Goal
让 OneBoard 在卸载 CC Switch 后，仍能独立完成 Codex 与 Claude 的供应商管理、端点接管、协议转换、请求改写、测速和模型映射；API Key 只以 OneBoard SQLite 为持久化来源。

## Current Phase
Complete

## Phases

### Phase 1: Runtime Discovery
- [x] 追踪 CC Switch 的 Codex / Claude 编辑字段到数据库与本地代理运行时
- [x] 盘点 OneBoard 已有能力、缺口与可复用基础设施
- **Status:** complete

### Phase 2: Architecture & Compatibility Contract
- [x] 确定 OneBoard 原生代理进程、端口、生命周期和失败恢复边界
- [x] 定义 Codex / Claude 协议格式、端点、请求改写和测速数据模型
- [x] 明确 CC Switch 数据迁移和卸载后独立运行的验收标准
- **Status:** complete

### Phase 3: Runtime Implementation
- [x] 实现本地代理生命周期与 SQLite 配置读取
- [x] 实现 Claude 和 Codex 路由、鉴权、协议转换及请求改写
- [x] 实现客户端配置接管与恢复
- **Status:** complete

### Phase 4: Settings UI & Import
- [x] 对齐 CC Switch 的 Codex / Claude 可配置字段和端点管理体验
- [x] 实现测速、模型发现与错误展示
- [x] 完整导入运行所需数据且不依赖 CC Switch 文件
- **Status:** complete

### Phase 5: Tests, Docs & Release
- [x] 覆盖转换、流式代理核心、生命周期、迁移和安全边界回归测试
- [x] 同步文档、规则与开发日志
- [x] 全量测试、Release 构建、打包及 DMG 校验
- **Status:** complete

## Decisions Made

| Decision | Rationale |
|---|---|
| 以卸载 CC Switch 后独立运行作为目标 | 用户明确要求迁移运行时能力，而非仅复制表单 |
| 不展示没有对应运行时实现的配置项 | 防止产生保存成功但实际不生效的假功能 |
| 采用内置 MIT Rust sidecar 而非 Swift 重写 55k 行转换逻辑 | 保留协议和 SSE 兼容性，同时让 OneBoard 独立于已安装 CC Switch |
| sidecar 使用 CC Switch `Database::memory()`，配置经 stdin 注入 | API Key 与供应商只由 OneBoard SQLite 持久化，不创建 `~/.cc-switch` 数据库 |
| OneBoard 管理 live 配置备份与恢复，sidecar 只调用 `ProxyService::start()` | 避免把崩溃恢复状态放进 sidecar 的瞬时内存数据库 |

## Errors Encountered

| Error | Resolution |
|---|---|
| `cargo check`: `cargo: command not found` | 继续完成 Swift 侧接线；安装 Rust 工具链后编译验证并打包 sidecar |
| Rust 依赖的实际导入名是 `cc_switch`，不是其上游 lib 名 `cc_switch_lib` | 按 Cargo 暴露的依赖 crate 名修正 import |
| 打包后临时 `build/OneBoard.app` 被脚本清理 | 只读挂载最终 DMG，直接校验交付包中的 Helper、签名和许可证 |
| Claude Code 稳定 `ECONNRESET`，但 `/health` 仍为 200 | Rustls worker 在首次 HTTPS 转发时因未安装默认 CryptoProvider 而 panic；显式安装 ring provider 并添加回归测试 |
