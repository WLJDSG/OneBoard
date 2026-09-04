# Task Plan: Touch ID 敏感操作授权

## Goal
让网关切换及其他当前依赖管理员密码的应用内操作优先使用 Touch ID/设备密码确认，同时保留首次安装特权 Helper 的系统管理员授权和既有白名单安全边界。

## Current Phase
Complete

## Phases

### Phase 1: Requirements & Discovery
- [x] Understand user intent
- [x] Identify constraints
- [x] Document in findings.md
- **Status:** complete

### Phase 2: Authorization Design
- [x] Define the biometric authentication seam and fallback behavior
- [x] Define the privileged Helper lifecycle without broadening permissions
- **Status:** complete

### Phase 3: Implementation & Tests
- [x] Add shared biometric authorization and gateway integration
- [x] Remove recurring password prompts through narrowly scoped Helper commands
- [x] Add regression tests
- **Status:** complete

### Phase 4: Documentation & Verification
- [x] Synchronize README, requirements/design/implementation docs, rules, and daily log
- [x] Run focused and full tests, Release build, package, and DMG verification
- **Status:** complete

### Phase 5: Delivery
- [x] Review outputs
- [x] Deliver to user
- **Status:** complete

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Do not treat LocalAuthentication as root authorization | Touch ID verifies user presence but cannot itself grant root privileges |
| Keep one system-controlled admin authorization for first Helper installation | Protected system locations require OS authorization; bypassing it would weaken security |
| Use the existing narrow root Helper after installation | Gateway changes can then require biometric confirmation without recurring administrator-password dialogs |

## Errors Encountered
| Error | Resolution |
|-------|------------|
| First phase-status patch matched the phase label in the wrong position | Split it into exact smaller replacements |
| Combined shell check ran SwiftPM from repository root and could not find Package.swift | Kept the successful shell audit and reran Swift tests from nested `OneBoard/` package root |
