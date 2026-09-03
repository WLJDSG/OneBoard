# Task Plan: Codex / ChatGPT 多账号快速切换

## Goal
在 OneBoard 中实现 Cockpit Tools 风格的 Codex OAuth 账号新增与管理：填写账号邮箱作为标识，打开 Codex 官方授权页，由浏览器完成密码和验证码，回调成功后自动将认证缓存安全保存到 macOS Keychain，再在 OneBoard 中切换、重命名和删除账号。

## Current Phase
Phase 16

## Phases

### Phase 1: Requirements & Discovery
- [x] Understand user intent
- [x] Inspect existing menu/settings architecture, persistence and app control capabilities
- [x] Confirm the supported Codex authentication mechanism from official and local evidence
- [x] Document findings and security constraints
- **Status:** complete

### Phase 2: Planning & Structure
- [x] Define account model, secure credential storage and switching lifecycle
- [x] Define UI entry points and verification-code state flow
- [x] Define regression coverage and documentation scope
- **Status:** complete

### Phase 3: Implementation Boundary
- [x] Record that implementation was not requested in this assessment turn
- **Status:** complete

### Phase 4: Read-only Verification
- [x] Verify official commands and installed Codex authentication status without exposing credentials
- [x] Confirm repository integration points and constraints
- **Status:** complete

### Phase 5: Delivery
- [x] Review assessment and security behavior
- [x] Deliver result and platform limitations
- **Status:** complete

### Phase 6: Implementation Discovery
- [x] Confirm desktop app bundle identity, process detection, auth cache path, and file behavior
- [x] Inspect existing model/store/view-model/test conventions
- [x] Define safe state machine for capture, pending switch, process exit, and cache restoration
- **Status:** complete

### Phase 7: Core Implementation
- [x] Implement account metadata persistence and secure auth-cache vault
- [x] Implement Codex process monitoring and atomic cache switching
- [x] Add account CRUD and status view model
- **Status:** complete

### Phase 8: UI Integration
- [x] Add a Codex account settings tab matching existing visual style
- [x] Add save-current, switch, rename, and delete flows
- [x] Add menu-bar shortcut if it fits the current interaction model
- **Status:** complete

### Phase 9: Regression Coverage and Documentation
- [x] Add focused unit tests without reading the real user auth cache
- [x] Update README, requirements, technical specification, implementation steps, rules, and daily log
- **Status:** complete

### Phase 10: Full Verification and Packaging
- [x] Run focused Codex account tests
- [x] Run full Swift tests
- [x] Run release build
- [x] Package and verify DMG
- [x] Review diff and report any live dual-account validation gap
- **Status:** complete

### Phase 11: Cockpit Tools Reference Audit
- [x] Inspect the referenced open-source repository and identify its actual Codex account-switching mechanism
- [x] Compare its persisted artifacts and process lifecycle with OneBoard's current implementation
- [x] Record reusable ideas, incompatible assumptions, and security implications
- **Status:** complete

### Phase 12: Targeted Improvement
- [x] Implement only the compatible behavior needed for automatic desktop account switching
- [x] Add regression coverage for every changed state transition
- [x] Update behavior documentation and daily log
- **Status:** complete

### Phase 13: Final Verification and Packaging
- [x] Run focused and full Swift tests
- [x] Run release build, package, and verify DMG
- [x] Review the final diff and report remaining real-account validation
- **Status:** complete

### Phase 14: OAuth-first Requirement Reset
- [x] Reassess the screenshots and the user's superseding Cockpit Tools requirement
- [x] Clone and inspect the reference implementation
- [x] Specify the minimal OAuth browser/callback/token persistence flow for OneBoard
- **Status:** complete

### Phase 15: OAuth Implementation and Regression Coverage
- [x] Replace save-current as the primary add-account UX with browser OAuth
- [x] Add PKCE/state, localhost callback, token exchange, cancellation, and safe persistence
- [x] Add account metadata management and focused unit tests
- **Status:** complete

### Phase 16: Documentation, Full Verification, and Packaging
- [x] Update all required behavior documents and daily log
- [x] Run full tests and release build
- [x] Package and verify DMG
- **Status:** complete

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Store passwords/tokens only in macOS Keychain | Credentials must not be persisted in SQLite, UserDefaults, logs or source files |
| Do not store ChatGPT passwords | Official ChatGPT authentication is browser OAuth; OneBoard should store only profile metadata and let the browser handle password/MFA |
| Treat CLI and desktop app as separate scopes | `CODEX_HOME` can isolate CLI credentials, but there is no documented account-selection API for the running desktop app |
| Browser owns all login input | OneBoard never stores passwords or verification codes; it only captures the official post-login auth cache |
| Never replace live credentials | OneBoard validates the target first, closes Codex, verifies exit, and only then commits credentials |
| OneBoard controls the switch lifecycle | The user's latest explicit choice adopts Cockpit's close, switch, and relaunch behavior |
| OAuth-first supersedes manual capture | The user explicitly rejected the save-current flow and requested Cockpit Tools-style browser authorization and automatic account creation |

## Errors Encountered
| Error | Resolution |
|-------|------------|
| First planning-file patch did not match the generated Phase 5 wording | Re-read the current plan and applied an exact narrow patch |
| A combined delete/add patch for the lifecycle file was rejected | Applied the delete and add as two explicit patches |
| Main-actor objects in default argument expressions failed to compile | Use optional injectable parameters and construct defaults inside the main-actor initializer body |
| Repository directory was externally renamed from the original workspace path to `OneBoard` | Moved the same dirty Git worktree back to the authorized original path without copying or recreating it |
