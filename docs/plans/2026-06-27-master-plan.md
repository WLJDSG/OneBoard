# 综合方案总纲

**日期**：2026-06-27 | **版本**：v1.0

---

## 总览

| # | 任务 | 方案文档 | 优先级 |
|---|------|---------|--------|
| 1 | 截图闪退修复 | [bugfix-screenshot-menuBar.md](2026-06-27-bugfix-screenshot-menuBar.md) | 🔴 P0 |
| 2 | 菜单栏图标偏位修复 | [bugfix-screenshot-menuBar.md](2026-06-27-bugfix-screenshot-menuBar.md) | 🔴 P0 |
| 3 | 翻译默认设置 | 下方 | 🔴 P0 |
| 4 | 授权逻辑重新设计 | [authorization-redesign.md](2026-06-27-authorization-redesign.md) | 🔴 P0 |
| 5 | 全界面 UI 重构 | [ui-redesign-panels.md](2026-06-27-ui-redesign-panels.md) | 🟡 P1 |
| 6 | 统一风格收尾 | [ui-redesign-panels.md](2026-06-27-ui-redesign-panels.md) | 🟡 P1 |

---

## 翻译默认设置

### 改动内容

```
默认翻译服务:  Google（GoogleTranslationService）
默认源语言:    自动检测（空字符串 → TranslationLanguage.inferredSource）
默认目标语言:  中文简体（"zh-Hans"）
```

### 代码改动

**文件：`AppDelegate.swift`（`setupDefaultSettings`）**

```swift
// Before:
if defaults.object(forKey: keys.translationServiceType) == nil { defaults.set("third_party", forKey: keys.translationServiceType) }
if defaults.object(forKey: keys.translationTargetLanguage) == nil { defaults.set("en", forKey: keys.translationTargetLanguage) }

// After:
if defaults.object(forKey: keys.translationServiceType) == nil { defaults.set("google", forKey: keys.translationServiceType) }
if defaults.object(forKey: keys.translationTargetLanguage) == nil { defaults.set("zh-Hans", forKey: keys.translationTargetLanguage) }
```

### 注意
- `TranslationServiceType` 需要支持 `"google"` rawValue
- 源语言默认已经是空字符串（自动检测），无需修改

---

## 执行顺序

```
1. Bug 修复（截图 + 图标）     ← 先修 bug，确保可用
2. 翻译默认设置                 ← 简单改动
3. 构建验证                     ← 确保修复有效
4. 授权逻辑重新设计             ← 大改动，独立进行
5. 全界面 UI 重构              ← 在授权之后，避免冲突
6. 构建 → 卸载 → 安装 → 验证  ← 按新规则
```

---

## 总改动文件统计

| 模块 | 文件数 | 改动类型 |
|------|--------|---------|
| Bug 修复 | 3 | 小改 |
| 翻译默认 | 1 | 极小改 |
| 授权重设计 | 7 | 大改 |
| UI 重构 | 10 | 大改 |
| 统一组件 | 1（新增） | 新文件 |
| **合计** | **21** | — |

---

## 风险控制

1. **每次 Phase 完成后运行 `swift build`**
2. **UI 重构在 Phase 之间 commit（可回滚）**
3. **授权和 UI 分开做，避免大面积 merge conflict**
4. **重构一个面板 → 验证功能 → 下一个**
