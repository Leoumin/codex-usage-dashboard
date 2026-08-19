# Codex Usage iOS Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal iOS dashboard and small/medium widgets that receive the Mac Codex access credential through iCloud Keychain and display usage plus reset-credit expiries.

**Architecture:** A dependency-free `CodexUsageCore` Swift package owns credential coding, Keychain access, response parsing, network fetching, and snapshot caching. XcodeGen creates macOS, iOS, and WidgetKit targets with one shared Keychain group; the existing macOS HUD publishes the current access token during its existing 60-second refresh.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, Security, URLSession, XCTest, SwiftPM, XcodeGen, iOS 17+, macOS 13+.

## Global Constraints

- Sync only `access_token`, `account_id`, and `last_refresh`; never sync `refresh_token`.
- Store credentials only in a synchronizable Keychain item; App Group storage contains sanitized snapshots only.
- Use Apple Development Team `AXX22S6S2N`, Keychain group `$(AppIdentifierPrefix)com.zhaoxh.codexusage.shared`, and App Group `group.com.zhaoxh.codexusage`.
- Follow the approved gpt-taste native mapping: asymmetric summary, Geist display type, no dead grid cells, no nested cards, no web-only animation patterns.
- The workspace is not a Git repository, so commit steps are omitted.

---

### Task 1: Shared Credential and Usage Core

**Files:**
- Create: `work/CodexUsageCore/Package.swift`
- Create: `work/CodexUsageCore/Tests/CodexUsageCoreTests/CodexUsageCoreTests.swift`
- Create: `work/CodexUsageCore/Sources/CodexUsageCore/CodexUsageCore.swift`

**Interfaces:**
- Produces: `CodexCredential`, `CodexAuthFile.read(data:)`, `KeychainCredentialStore.save(_:)`, `KeychainCredentialStore.load()`, `UsageParser.snapshot(usageData:creditData:fetchedAt:)`, `CodexUsageService.fetch(credential:)`, `SnapshotStore.load()` and `SnapshotStore.save(_:)`.

- [ ] **Step 1: Add package scaffolding and failing XCTest cases**

Tests assert that auth parsing excludes the refresh token, usage parsing computes remaining percentages, available credits are sorted by expiry, cache round trips preserve a snapshot, and 401 maps to the Mac-refresh message.

- [ ] **Step 2: Verify red**

Run: `swift test --package-path work/CodexUsageCore`

Expected: compilation fails because the tested public types do not exist.

- [ ] **Step 3: Implement the minimum shared core**

Use `JSONSerialization` for private endpoint payloads, `Codable` for local credential/snapshot persistence, `SecItemAdd/Update/CopyMatching` with `kSecAttrSynchronizable`, and `URLSession.data(for:)` for the two GET requests.

- [ ] **Step 4: Verify green**

Run: `swift test --package-path work/CodexUsageCore`

Expected: all XCTest cases pass with zero failures.

### Task 2: macOS Credential Publisher

**Files:**
- Modify: `work/CodexUsageHUD/Package.swift`
- Modify: `work/CodexUsageHUD/Sources/CodexUsageHUD/main.swift`

**Interfaces:**
- Consumes: `CodexAuthFile.read(data:)` and `KeychainCredentialStore.save(_:)` from Task 1.
- Produces: a synchronizable Keychain credential refreshed whenever the existing HUD fetch runs.

- [ ] **Step 1: Add a failing self-test for refresh-token exclusion**

Extend `SelfTest.run()` with an auth JSON containing both token types and assert the parsed `CodexCredential` contains no refresh-token property.

- [ ] **Step 2: Verify red**

Run: `swift run --package-path work/CodexUsageHUD CodexUsageHUD --self-test`

Expected: compilation fails until the local package dependency and import are added.

- [ ] **Step 3: Add the local package dependency and publish credentials**

Read `~/.codex/auth.json` once per dashboard refresh, save the safe credential payload to the configured Keychain group, and reuse its access token for both existing HTTP calls. A Keychain failure is reported without exposing token text and does not discard successfully fetched usage.

- [ ] **Step 4: Verify green**

Run: `swift run --package-path work/CodexUsageHUD CodexUsageHUD --self-test`

Expected: exit code 0.

### Task 3: Xcode Project, Capabilities, and Font

**Files:**
- Create: `work/CodexUsageMobile/project.yml`
- Create: `work/CodexUsageMobile/Config/CodexUsageHUD.entitlements`
- Create: `work/CodexUsageMobile/Config/CodexUsage.entitlements`
- Create: `work/CodexUsageMobile/Config/CodexUsageWidget.entitlements`
- Create: `work/CodexUsageMobile/Widget/Info.plist`
- Add: `work/CodexUsageMobile/Resources/Geist-VariableFont_wght.ttf`

**Interfaces:**
- Consumes: the `CodexUsageCore` local package and existing macOS HUD source.
- Produces: schemes `CodexUsageHUD`, `CodexUsage`, and `CodexUsageWidget` with matching Team, Keychain group, App Group, and embedded widget extension.

- [ ] **Step 1: Write XcodeGen configuration and entitlements**

Configure generated Info.plists, deployment targets, bundle identifiers `com.zhaoxh.CodexUsageHUD`, `com.zhaoxh.CodexUsage`, and `com.zhaoxh.CodexUsage.Widget`, plus the custom `CodexUsageKeychainAccessGroup` Info key.

- [ ] **Step 2: Fetch the single Geist variable font asset**

Source: Google Fonts `ofl/geist/Geist[wght].ttf`. Include it in both iOS targets and declare `UIAppFonts`.

- [ ] **Step 3: Generate and validate the project**

Run: `cd work/CodexUsageMobile && xcodegen generate && xcodebuild -project CodexUsageMobile.xcodeproj -list`

Expected: all three schemes and the core package dependency are listed.

### Task 4: iOS Dashboard and Widget

**Files:**
- Create: `work/CodexUsageMobile/App/CodexUsageApp.swift`
- Create: `work/CodexUsageMobile/Widget/CodexUsageWidget.swift`

**Interfaces:**
- Consumes: `KeychainCredentialStore`, `CodexUsageService`, and `SnapshotStore`.
- Produces: an iOS dashboard with manual/pull refresh and `.systemSmall`/`.systemMedium` widgets with 30-minute requested timeline refresh.

- [ ] **Step 1: Implement the app data model and dashboard**

On launch and pull-to-refresh, load the synchronized credential, fetch usage, persist only `UsageSnapshot`, and call `WidgetCenter.shared.reloadAllTimelines()`. Keep the last cache on errors and show the exact stale/auth status from the design spec.

- [ ] **Step 2: Implement the approved visual system**

Use an asymmetric two-column metric header, fixed-size percentage metrics, 8-point corners, teal/amber/red semantic status colors, Geist display numerals, native progress bars, one expandable reset ledger, and an icon-only accessible refresh button.

- [ ] **Step 3: Implement WidgetKit timelines**

The provider loads cache immediately, tries a Keychain-backed refresh when WidgetKit requests a timeline, falls back to cache on failure, and schedules `.after(Date().addingTimeInterval(1800))`.

- [x] **Step 4: Build for the simulator**

Run: `xcodebuild -project work/CodexUsageMobile/CodexUsageMobile.xcodeproj -scheme CodexUsage -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED` with the widget embedded.

### Task 5: Package, Visual QA, and Entitlement Verification

**Files:**
- Replace: `outputs/CodexUsageHUD.app`
- Keep: `outputs/install-codex-usage-hud-launcher.sh`

**Interfaces:**
- Produces: a signed macOS HUD installed at `~/Applications/CodexUsageHUD.app`, plus simulator-verified and device-signed iOS app/widget artifacts.

- [x] **Step 1: Build and install the macOS target**

Run `xcodebuild` with Team `AXX22S6S2N`, keep the resulting `CodexUsageHUD.app` in `outputs`, install a metadata-clean copy to `~/Applications`, then reinstall the existing LaunchAgent.

- [x] **Step 2: Verify code signatures and entitlements**

Run `codesign -dvvv --entitlements :-` on the macOS bundle and device-built iOS app/widget. Confirm the shared Keychain group and the iOS App Group identifiers are present where applicable.

- [x] **Step 3: Run all automated checks**

Run the core tests, Mac self-test, Xcode simulator build, `zsh -n outputs/install-codex-usage-hud-launcher.sh`, and `plutil -lint` on all plist/entitlement files.

- [x] **Step 4: Perform simulator visual checks**

Launch the app with deterministic sample data, capture iPhone 17 Pro portrait screenshots, and inspect text fit, contrast, grid occupancy, controls, and loading/error states. Correct any visual defects and repeat the build/screenshot check.

- [x] **Step 5: State the real-device boundary**

Do not claim cross-device sync is proven until the signed Mac app and signed iOS app run under the same iCloud account on physical devices. Provide the exact Xcode scheme and one-time device-install step.
