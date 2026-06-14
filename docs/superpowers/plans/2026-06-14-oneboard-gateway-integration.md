# OneBoard Gateway Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add OneBoard-native gateway switching with profiles, a switcher panel, configurable hotkey, helper management, and synchronized authorization state.

**Architecture:** Implement the gateway feature as `OneBoard/Modules/Gateway`, following the app's MVVM + Service pattern. Keep system command execution behind a small runner protocol so tests verify command generation without touching network settings. Move system capability controls into an authorization tab and drive UI state from actual system/helper status.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, KeyboardShortcuts, LaunchAtLogin, SwiftPM tests.

---

## File Map

- Create `OneBoard/Modules/Gateway/Models/GatewayProfile.swift`: profile model, switch mode, validation, default profiles.
- Create `OneBoard/Modules/Gateway/Models/NetworkSnapshot.swift`: current network snapshot and active profile matching.
- Create `OneBoard/Modules/Gateway/Services/GatewayCommandRunner.swift`: testable command runner abstraction.
- Create `OneBoard/Modules/Gateway/Services/GatewayRouteParser.swift`: parse `route` and `networksetup` outputs.
- Create `OneBoard/Modules/Gateway/Services/NetworkInspector.swift`: collect current route, service, IP, subnet, DNS.
- Create `OneBoard/Modules/Gateway/Services/GatewayProfileStore.swift`: UserDefaults JSON profile storage.
- Create `OneBoard/Modules/Gateway/Services/OneBoardGatewayHelper.swift`: helper install/uninstall/status/whitelist paths.
- Create `OneBoard/Modules/Gateway/Services/GatewaySwitcher.swift`: execute gateway + DNS or DNS-only switching.
- Create `OneBoard/Modules/Gateway/Services/GatewayService.swift`: app-facing orchestration.
- Create `OneBoard/Modules/Gateway/ViewModels/GatewayViewModel.swift`: panel/settings state and operations.
- Create `OneBoard/Modules/Gateway/ViewModels/GatewayProfileEditorViewModel.swift`: editor validation.
- Create `OneBoard/Modules/Gateway/Views/GatewaySwitcherPanelView.swift`: quick switch panel.
- Create `OneBoard/Modules/Gateway/Views/GatewaySettingsView.swift`: settings tab.
- Create `OneBoard/Modules/Gateway/Views/GatewayProfileEditorView.swift`: profile editor sheet.
- Modify `OneBoard/Core/Utilities/Constants.swift`: add gateway profile key and notification key if needed.
- Modify `OneBoard/Shared/HotkeyManager.swift`: add `showGatewaySwitcher` default `Command+Shift+G`.
- Modify `OneBoard/Shared/MenuBarManager.swift`: add gateway panel, menu item, clear authorization flow.
- Modify `OneBoard/Shared/PermissionManager.swift`: add system capability notification and clear authorization sync.
- Modify `OneBoard/App/OneBoardApp.swift`: split authorization tab, add gateway tab and shortcut recorder.
- Modify `OneBoard/App/AppDelegate.swift`: initialize gateway defaults and sync capability state.
- Create `OneBoard/Tests/GatewayProfileTests.swift`: model and parsing tests.
- Create `OneBoard/Tests/GatewaySwitcherTests.swift`: command generation tests.
- Create `OneBoard/Tests/GatewayCapabilityTests.swift`: helper path and capability state tests.
- Modify `README.md`, `docs/开发步骤/README.md`, `开发日志/2026-06/2026-06-14.md`: update implementation status after verification.

---

### Task 1: Gateway Models and Profile Store

**Files:**
- Create: `OneBoard/Modules/Gateway/Models/GatewayProfile.swift`
- Create: `OneBoard/Modules/Gateway/Models/NetworkSnapshot.swift`
- Create: `OneBoard/Modules/Gateway/Services/GatewayProfileStore.swift`
- Create: `OneBoard/Tests/GatewayProfileTests.swift`
- Modify: `OneBoard/Core/Utilities/Constants.swift`

- [x] **Step 1: Write failing model tests**

Create tests for default profiles, DNS parsing, validation, and active profile matching:

```swift
import XCTest
@testable import OneBoard

final class GatewayProfileTests: XCTestCase {
    func testDefaultProfilesMatchHomeGateways() {
        let profiles = GatewayProfile.defaults
        XCTAssertEqual(profiles.map(\.gateway), ["192.168.31.1", "192.168.31.2", "192.168.31.3"])
        XCTAssertTrue(profiles.allSatisfy { $0.mode == .gatewayAndDNS })
        XCTAssertEqual(profiles[0].dnsServers, ["192.168.31.1"])
    }

    func testParseDNSServersAcceptsCommaWhitespaceAndNewlines() {
        XCTAssertEqual(
            GatewayProfile.parseDNSServers("192.168.31.1, 8.8.8.8\n1.1.1.1"),
            ["192.168.31.1", "8.8.8.8", "1.1.1.1"]
        )
    }

    func testDNSOnlyProfileDoesNotRequireGateway() {
        let profile = GatewayProfile(title: "DNS", mode: .dnsOnly, gateway: "", dnsServers: ["1.1.1.1"], description: "")
        XCTAssertNoThrow(try profile.validate())
    }

    func testGatewayAndDNSRequiresValidGateway() {
        let profile = GatewayProfile(title: "Bad", mode: .gatewayAndDNS, gateway: "999.1.1.1", dnsServers: ["1.1.1.1"], description: "")
        XCTAssertThrowsError(try profile.validate())
    }

    func testSnapshotFindsActiveProfileByGateway() {
        let snapshot = NetworkSnapshot(gateway: "192.168.31.3", interfaceName: "en0", serviceName: "Wi-Fi", localIPv4: "192.168.31.42", subnetMask: "255.255.255.0", dnsServers: ["192.168.31.3"])
        XCTAssertEqual(snapshot.activeProfile(from: GatewayProfile.defaults)?.title, "代理网关")
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd OneBoard && swift test --filter GatewayProfileTests`

Expected: fails because gateway model types do not exist.

- [x] **Step 3: Implement models and store**

Add `GatewaySwitchMode`, `GatewayProfile`, `NetworkSnapshot`, and `GatewayProfileStore` with JSON UserDefaults storage using `Constants.UserDefaultsKeys.gatewayProfiles`.

- [x] **Step 4: Run test to verify it passes**

Run: `cd OneBoard && swift test --filter GatewayProfileTests`

Expected: all `GatewayProfileTests` pass.

### Task 2: Route Parsing and Gateway Switching Commands

**Files:**
- Create: `OneBoard/Modules/Gateway/Services/GatewayCommandRunner.swift`
- Create: `OneBoard/Modules/Gateway/Services/GatewayRouteParser.swift`
- Create: `OneBoard/Modules/Gateway/Services/NetworkInspector.swift`
- Create: `OneBoard/Modules/Gateway/Services/GatewaySwitcher.swift`
- Create: `OneBoard/Modules/Gateway/Services/GatewayService.swift`
- Create: `OneBoard/Tests/GatewaySwitcherTests.swift`

- [x] **Step 1: Write failing service tests**

Test parsing and commands with a fake runner:

```swift
import XCTest
@testable import OneBoard

final class GatewaySwitcherTests: XCTestCase {
    func testParseDefaultRouteAndHardwarePorts() {
        let route = GatewayRouteParser.parseDefaultRoute("gateway: 192.168.31.1\ninterface: en0\n")
        XCTAssertEqual(route.gateway, "192.168.31.1")
        XCTAssertEqual(route.interfaceName, "en0")

        let ports = GatewayRouteParser.parseHardwarePorts("Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: aa:bb\n")
        XCTAssertEqual(ports["en0"], "Wi-Fi")
    }

    func testGatewayAndDNSUsesManualRouteAndDNSCommands() throws {
        let runner = RecordingGatewayCommandRunner()
        let switcher = GatewaySwitcher(runner: runner, helper: .disabledForTests)
        let profile = GatewayProfile(title: "代理网关", gateway: "192.168.31.3", description: "")
        let snapshot = NetworkSnapshot(gateway: "192.168.31.1", interfaceName: "en0", serviceName: "Wi-Fi", localIPv4: "192.168.31.42", subnetMask: "255.255.255.0", dnsServers: [])

        try switcher.switchDefaultGateway(to: profile, snapshot: snapshot)

        let script = runner.commands.joined(separator: "\n")
        XCTAssertTrue(script.contains("networksetup -setmanual"))
        XCTAssertTrue(script.contains("192.168.31.42"))
        XCTAssertTrue(script.contains("192.168.31.3"))
        XCTAssertTrue(script.contains("networksetup -setdnsservers"))
    }

    func testDNSOnlyDoesNotChangeDefaultRoute() throws {
        let runner = RecordingGatewayCommandRunner()
        let switcher = GatewaySwitcher(runner: runner, helper: .disabledForTests)
        let profile = GatewayProfile(title: "DNS", mode: .dnsOnly, gateway: "", dnsServers: ["1.1.1.1"], description: "")
        let snapshot = NetworkSnapshot(gateway: "192.168.31.1", interfaceName: "en0", serviceName: "Wi-Fi", localIPv4: "192.168.31.42", subnetMask: "255.255.255.0", dnsServers: [])

        try switcher.switchDefaultGateway(to: profile, snapshot: snapshot)

        let script = runner.commands.joined(separator: "\n")
        XCTAssertFalse(script.contains("-setmanual"))
        XCTAssertFalse(script.contains("route -n change default"))
        XCTAssertTrue(script.contains("networksetup -setdnsservers"))
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd OneBoard && swift test --filter GatewaySwitcherTests`

Expected: fails because parser and switcher do not exist.

- [x] **Step 3: Implement route parser, runner, inspector, switcher, service**

Port the existing `gateway-switch` parsing and switching behavior, but keep OneBoard-specific names and support DNS-only mode.

- [x] **Step 4: Run test to verify it passes**

Run: `cd OneBoard && swift test --filter GatewaySwitcherTests`

Expected: all gateway switcher tests pass.

### Task 3: Helper Management and System Capabilities

**Files:**
- Create: `OneBoard/Modules/Gateway/Services/OneBoardGatewayHelper.swift`
- Create: `OneBoard/Tests/GatewayCapabilityTests.swift`
- Modify: `OneBoard/Shared/PermissionManager.swift`
- Modify: `OneBoard/Shared/MenuBarManager.swift`
- Modify: `OneBoard/App/OneBoardApp.swift`

- [x] **Step 1: Write failing helper/capability tests**

Verify helper paths and clear-all state model:

```swift
import XCTest
@testable import OneBoard

final class GatewayCapabilityTests: XCTestCase {
    func testOneBoardHelperUsesOneBoardPaths() {
        XCTAssertEqual(OneBoardGatewayHelper.helperPath, "/usr/local/bin/oneboard-gateway-helper")
        XCTAssertEqual(OneBoardGatewayHelper.sudoersPath, "/etc/sudoers.d/oneboard-gateway")
        XCTAssertEqual(OneBoardGatewayHelper.allowedIPsPath, "/etc/oneboard-gateway-allowed-ips.conf")
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd OneBoard && swift test --filter GatewayCapabilityTests`

Expected: fails because helper type does not exist.

- [x] **Step 3: Implement helper management**

Add path constants, install/uninstall/status methods, whitelist sync, and a capability-change notification used by settings.

- [x] **Step 4: Run test to verify it passes**

Run: `cd OneBoard && swift test --filter GatewayCapabilityTests`

Expected: helper path tests pass.

### Task 4: ViewModel, Settings UI, Panel, Menu, and Hotkey

**Files:**
- Create: `OneBoard/Modules/Gateway/ViewModels/GatewayViewModel.swift`
- Create: `OneBoard/Modules/Gateway/ViewModels/GatewayProfileEditorViewModel.swift`
- Create: `OneBoard/Modules/Gateway/Views/GatewaySwitcherPanelView.swift`
- Create: `OneBoard/Modules/Gateway/Views/GatewaySettingsView.swift`
- Create: `OneBoard/Modules/Gateway/Views/GatewayProfileEditorView.swift`
- Modify: `OneBoard/Shared/HotkeyManager.swift`
- Modify: `OneBoard/Shared/MenuBarManager.swift`
- Modify: `OneBoard/App/OneBoardApp.swift`
- Modify: `OneBoard/App/AppDelegate.swift`

- [x] **Step 1: Write failing ViewModel/editor tests**

Add tests for editor DNS parsing and profile validation using `GatewayProfileEditorViewModel`.

- [x] **Step 2: Run test to verify it fails**

Run: `cd OneBoard && swift test --filter GatewayProfileEditor`

Expected: fails because view model does not exist.

- [x] **Step 3: Implement view models and UI**

Add gateway settings tab, authorization tab, shortcut recorder, panel, menu entry, and `showGatewaySwitcher` hotkey.

- [x] **Step 4: Run focused tests**

Run: `cd OneBoard && swift test --filter Gateway`

Expected: gateway tests pass.

### Task 5: Documentation, Build, and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/开发步骤/README.md`
- Modify: `开发日志/2026-06/2026-06-14.md`

- [x] **Step 1: Update docs**

Mark gateway module as implemented only after build/tests pass. Add notes about the new shortcut, authorization page, and helper.

- [x] **Step 2: Run full verification**

Run:

```bash
cd OneBoard && swift test
cd OneBoard && swift build
```

Expected: both commands exit 0.

- [x] **Step 3: Review git diff**

Run: `git diff --stat`

Expected: only gateway implementation, authorization/menu/hotkey wiring, tests, and docs are changed.
