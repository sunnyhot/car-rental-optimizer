# Monitor Workspace and Sheets Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the full UI refactor by turning price monitoring into a Route Blueprint workspace and unifying create-monitor and platform-login sheets without changing their business behavior.

**Architecture:** Retain `MonitorCenterViewModel`, scheduler, persistence, WebKit views, and cookie vaults. Restyle the integrated monitor master/detail workspace with the shared search components, then add a small reusable sheet action/location chrome consumed by the create-monitor and login sheets.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts, WebKit, AppKit adaptive colors, SF Symbols, Swift Testing, existing monitoring and login types.

## Global Constraints

- Execute after `2026-07-10-search-workspace-refactor.md`.
- Preserve monitor filters, attention-first order, health counts, batch pause/resume/check, trend data, events, snapshots, scheduler state, and stored JSON format.
- Preserve Ehi and CAR Inc WebView URLs, user agents, captcha handling, reload/reset tokens, cookie persistence, and completion callbacks.
- Keep create-monitor request, frequency, price-drop rules, notification setting, and save callbacks unchanged.
- Use Route Blueprint tokens and shared components; do not add a second visual language.
- Keep sheet dimensions stable as status copy changes.
- States must include text or icons in addition to color.
- Respect reduced motion and system keyboard focus.
- Do not add third-party dependencies or external assets.
- Run `swift build`, `swift test`, bundle build, and launch verification before completion.

---

## Scope Check

This is plan 4 of 4. It completes the approved full-app visual refactor after the shell, comparison feature, and search workspace are independently working.

## File Structure

- `Sources/CarRentalOptimizer/MonitorCenterView.swift`: integrated monitor list, health strip, detail, chart, events, and snapshots.
- `Sources/CarRentalOptimizer/BlueprintSheetComponents.swift`: shared stable action bar and WebView location/status chrome.
- `Sources/CarRentalOptimizer/CreateMonitorSheet.swift`: monitor creation form and save-state feedback.
- `Sources/CarRentalOptimizer/EhiLoginSheet.swift`: Ehi chrome/captcha UX; WebView implementation remains unchanged.
- `Sources/CarRentalOptimizer/PlatformLoginSheet.swift`: CAR Inc chrome/fee explanation; WebView implementation remains unchanged.
- `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`: monitor and sheet adoption source contracts.
- `Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift`: existing monitor behavior regression suite.
- `Tests/CarRentalOptimizerTests/EhiLoginSessionTests.swift`: existing captcha/refresh behavior regression suite.

### Task 1: Integrated Monitor Health and List

**Files:**
- Modify: `Sources/CarRentalOptimizer/MonitorCenterView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: plan-1 app shell and existing `MonitorCenterViewModel` state/actions.
- Produces: a full-height main workspace with Route Blueprint health metrics, filters, status feedback, list, and batch commands.

- [ ] **Step 1: Update the monitor source contract**

Replace `monitorCenterUsesCommandSurfaces()` expectations with:

```swift
@Test("Monitor center is an integrated Route Blueprint workspace")
func monitorCenterIsIntegratedRouteBlueprintWorkspace() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/MonitorCenterView.swift", encoding: .utf8)

    #expect(source.contains("title: \"价格监控\""))
    #expect(source.contains("MonitorHealthStrip"))
    #expect(source.contains("BlueprintMetricTile("))
    #expect(source.contains("MonitorFilterBar"))
    #expect(source.contains("runShownChecks()"))
    #expect(source.contains("pauseMonitors(ids:"))
    #expect(source.contains("resumeMonitors(ids:"))
    #expect(!source.contains(".frame(minWidth: 920, minHeight: 620)"))
}
```

- [ ] **Step 2: Run the source test and verify it fails**

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because the existing view still owns its sheet-sized frame and old title/health tiles.

- [ ] **Step 3: Make the monitor view consume all shell space**

In `MonitorCenterView.body`, remove:

```swift
.frame(minWidth: 920, minHeight: 620)
```

Keep the `HSplitView`, `.task`, `.onChange`, and create-monitor sheet behavior. Change the list panel identity to:

```swift
WorkbenchPanel(
    title: "价格监控",
    subtitle: monitorListSubtitle,
    trailing: AnyView(
        Button {
            showingCreateSheet = true
        } label: {
            Label("新建", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkbenchStyle.decisionBlue)
        .help("新建价格监控")
    )
)
```

- [ ] **Step 4: Replace health tiles with compact Route Blueprint metrics**

Replace `MonitorHealthStrip.body` with:

```swift
WorkbenchCard(fill: WorkbenchStyle.panelSurface, padding: 10) {
    VStack(alignment: .leading, spacing: 9) {
        BlueprintSectionHeader(
            icon: "heart.text.square.fill",
            title: "巡查健康",
            step: "STATUS",
            trailing: backgroundMonitoringEnabled ? "后台开启" : "手动巡查"
        )
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            BlueprintMetricTile(title: "总数", value: "\(summary.totalCount)", icon: "number", tone: .idle)
            BlueprintMetricTile(
                title: "需处理",
                value: "\(summary.needsAttentionCount)",
                icon: "exclamationmark.triangle.fill",
                tone: summary.needsAttentionCount > 0 ? .warning : .idle
            )
            BlueprintMetricTile(
                title: "近期降价",
                value: "\(summary.recentPriceDropCount)",
                icon: "arrow.down.circle.fill",
                tone: summary.recentPriceDropCount > 0 ? .success : .idle
            )
            BlueprintMetricTile(title: "今日巡查", value: "\(summary.dueTodayCount)", icon: "calendar.badge.clock", tone: .active)
        }
    }
}
```

Keep `columns` adaptive at a 98pt minimum so the list pane remains usable.

- [ ] **Step 5: Strengthen monitor row information and non-color status**

In `MonitorListRow`, replace the status pill with:

```swift
Label(
    monitor.status.label,
    systemImage: monitor.status == .needsAttention ? "exclamationmark.triangle.fill" : "circle.fill"
)
.font(.caption2.weight(.semibold))
.foregroundStyle(monitor.status == .needsAttention ? WorkbenchStyle.riskAmber : WorkbenchStyle.decisionBlue)
```

Add this final row below the existing next-check text:

```swift
Text("\(monitor.request.originLabel) · \(monitor.targetVehicleQuery.isEmpty ? "未指定车型" : monitor.targetVehicleQuery)")
    .font(.caption2)
    .foregroundStyle(WorkbenchStyle.muted)
    .lineLimit(1)
```

Keep the existing combined accessibility label and append the origin label to it.

- [ ] **Step 6: Run tests, build, and commit**

```bash
swift test --filter UIEffectsSourceTests
swift test --filter MonitorCenterViewModelTests
swift build
git add Sources/CarRentalOptimizer/MonitorCenterView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "refactor: integrate route blueprint monitor list"
```

Expected: all commands pass and batch actions still call the same view-model methods.

### Task 2: Monitor Decision Detail, Trend, and Historical States

**Files:**
- Modify: `Sources/CarRentalOptimizer/MonitorCenterView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: selected monitor, `PriceTrendSummary`, snapshots, events, and existing actions.
- Produces: decision-focused monitor detail with explicit empty/loading/history semantics.

- [ ] **Step 1: Add monitor-detail source contracts**

Append to the monitor test:

```swift
#expect(source.contains("BlueprintStatePanel("))
#expect(source.contains("BlueprintSectionHeader(icon: \"chart.xyaxis.line\""))
#expect(source.contains("历史快照，可能已失效"))
#expect(source.contains("chartForegroundStyleScale"))
```

- [ ] **Step 2: Run the source test and verify it fails**

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because the monitor detail has not adopted the Blueprint state/header/chart scale.

- [ ] **Step 3: Replace the no-selection state**

Replace the detail `EmptyStateBlock` with:

```swift
BlueprintStatePanel(
    icon: "bell.badge",
    title: "暂无监控",
    message: "从候选方案创建监控，或点击左上角“新建”手动配置巡查条件。",
    tone: .idle,
    isActive: false
)
.padding(16)
```

- [ ] **Step 4: Replace summary pills with decision metrics**

Replace `MonitorSummaryBox.body` with:

```swift
WorkbenchCard(
    fill: WorkbenchStyle.decisionBlue.opacity(0.08),
    stroke: WorkbenchStyle.decisionBlue.opacity(0.24),
    padding: 12
) {
    VStack(alignment: .leading, spacing: 10) {
        BlueprintSectionHeader(
            icon: "waveform.path.ecg.rectangle",
            title: "监控摘要",
            step: "LIVE",
            trailing: monitor.status.label
        )
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            BlueprintMetricTile(title: "最近租车价", value: trend.latestPlatformRentalPrice.map(formatMoney) ?? "--", icon: "yensign.circle", tone: .active)
            BlueprintMetricTile(
                title: "相比上次",
                value: formatSignedMoney(trend.platformRentalDelta),
                icon: "arrow.left.arrow.right",
                tone: (trend.platformRentalDelta ?? 0) < 0 ? .success : .idle
            )
            BlueprintMetricTile(title: "下次巡查", value: monitor.nextCheckAt.map(formatCompactDateTime) ?? "--", icon: "clock.badge", tone: .idle)
            BlueprintMetricTile(title: "历史低点", value: trend.lowestPlatformRentalPrice.map(formatMoney) ?? "--", icon: "arrow.down.circle", tone: .success)
            BlueprintMetricTile(title: "历史高点", value: trend.highestPlatformRentalPrice.map(formatMoney) ?? "--", icon: "arrow.up.circle", tone: .idle)
            BlueprintMetricTile(
                title: "首次至今",
                value: formatSignedMoney(trend.platformRentalDeltaFromFirst),
                icon: "calendar.badge.clock",
                tone: (trend.platformRentalDeltaFromFirst ?? 0) < 0 ? .success : .idle
            )
        }
    }
}
.accessibilityLabel("监控摘要，最近租车价 \(trend.latestPlatformRentalPrice.map(formatMoney) ?? "暂无")")
```

- [ ] **Step 5: Give command surfaces and charts stable semantic headers**

Replace `MonitorCommandSurface` with this exact declaration:

```swift
private struct MonitorCommandSurface<Content: View>: View {
    let title: String
    let icon: String
    var step = "HISTORY"
    @ViewBuilder let content: Content

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.elevatedSurface, stroke: WorkbenchStyle.hairline, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                BlueprintSectionHeader(icon: icon, title: title, step: step)
                content
            }
        }
    }
}
```

Change the trend call site to:

```swift
MonitorCommandSurface(title: "价格趋势", icon: "chart.xyaxis.line", step: "TREND") {
    Chart {
        ForEach(points) { snapshot in
            if let price = snapshot.platformRentalPrice {
                LineMark(
                    x: .value("时间", snapshot.checkedAt),
                    y: .value("价格", price)
                )
                .foregroundStyle(by: .value("口径", "平台租车价"))
            }
            if let total = snapshot.recommendationTotalCost {
                LineMark(
                    x: .value("时间", snapshot.checkedAt),
                    y: .value("价格", total)
                )
                .foregroundStyle(by: .value("口径", "推荐总成本"))
            }
        }
    }
    .chartLegend(position: .bottom)
    .chartForegroundStyleScale([
        "平台租车价": WorkbenchStyle.decisionBlue,
        "推荐总成本": WorkbenchStyle.signalTeal,
    ])
}
```

The `Chart` body remains the two existing exhaustive `if let` branches for `snapshot.platformRentalPrice` and `snapshot.recommendationTotalCost`; do not change their x/y values. Add this modifier after `.chartLegend`:

```swift
.chartForegroundStyleScale([
    "平台租车价": WorkbenchStyle.decisionBlue,
    "推荐总成本": WorkbenchStyle.signalTeal,
])
```

Keep the event and snapshot call sites on the default `step == "HISTORY"`.

- [ ] **Step 6: Preserve historical-data warnings and restyle sections**

Remove the now-unused `MonitorSectionTitleRow` declaration. Keep successful snapshot rows showing the exact copy “历史快照，可能已失效”, and keep failure snapshot messages unchanged.

- [ ] **Step 7: Run tests and commit**

```bash
swift test --filter UIEffectsSourceTests
swift test --filter MonitorCenterViewModelTests
swift build
git add Sources/CarRentalOptimizer/MonitorCenterView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "refactor: clarify monitor decisions and history"
```

Expected: tests/build pass with unchanged monitor data behavior.

### Task 3: Shared Sheet Chrome and Create-Monitor Save State

**Files:**
- Create: `Sources/CarRentalOptimizer/BlueprintSheetComponents.swift`
- Modify: `Sources/CarRentalOptimizer/CreateMonitorSheet.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: plan-1 `WorkbenchSheetShell` and plan-3 `BlueprintSectionHeader`.
- Produces:
  - `BlueprintSheetActionBar<Content: View>`
  - `BlueprintWebLocationBar`
  - Stable create-monitor form grouping and save progress.

- [ ] **Step 1: Add sheet source contracts**

Append to `UIEffectsSourceTests.swift`:

```swift
@Test("Sheets share Route Blueprint action and location chrome")
func sheetsShareRouteBlueprintChrome() throws {
    let shared = try String(contentsOfFile: "Sources/CarRentalOptimizer/BlueprintSheetComponents.swift", encoding: .utf8)
    let create = try String(contentsOfFile: "Sources/CarRentalOptimizer/CreateMonitorSheet.swift", encoding: .utf8)

    #expect(shared.contains("struct BlueprintSheetActionBar"))
    #expect(shared.contains("struct BlueprintWebLocationBar"))
    #expect(create.contains("BlueprintSheetActionBar"))
    #expect(create.contains("isSaving"))
    #expect(create.contains("行程与方案"))
    #expect(create.contains("提醒规则"))
}
```

- [ ] **Step 2: Run the source test and verify it fails**

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because the shared sheet file and create-monitor save state do not exist.

- [ ] **Step 3: Create the shared sheet chrome**

Create `Sources/CarRentalOptimizer/BlueprintSheetComponents.swift`:

```swift
import SwiftUI

struct BlueprintSheetActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(WorkbenchStyle.elevatedSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(WorkbenchStyle.hairline).frame(height: 1)
        }
    }
}

struct BlueprintWebLocationBar: View {
    let platformName: String
    let currentURL: String
    var message: String
    var tone: WorkbenchRailTone = .active

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(platformName)官方登录页")
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                Text(currentURL)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(tone.color.opacity(0.07))
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Group the create-monitor form and expose save progress**

Add state to `CreateMonitorSheet`:

```swift
@State private var isSaving = false
```

Replace the content inside `WorkbenchSheetShell` with:

```swift
VStack(spacing: 0) {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                BlueprintSectionHeader(icon: "point.3.connected.trianglepath.dotted", title: "行程与方案", step: "01")
                summary
            }
            VStack(alignment: .leading, spacing: 10) {
                BlueprintSectionHeader(icon: "bell.and.waves.left.and.right", title: "提醒规则", step: "02")
                controls
            }
            if let errorMessage {
                ActionStatusRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "保存失败",
                    message: errorMessage,
                    tone: .critical
                )
            }
        }
        .padding(20)
    }

    BlueprintSheetActionBar {
        if isSaving {
            ProgressView().controlSize(.small)
            Text("正在保存监控…")
                .font(.caption)
                .foregroundStyle(WorkbenchStyle.muted)
        }
        Spacer()
        Button("取消") { dismiss() }
            .disabled(isSaving)
        Button("保存监控") {
            Task { await save() }
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkbenchStyle.decisionBlue)
        .disabled(isSaving)
        .keyboardShortcut(.defaultAction)
    }
}
```

Use a stable sheet size:

```swift
.frame(width: 500, height: 560)
```

- [ ] **Step 5: Make save state deterministic**

Replace `save()` with:

```swift
private func save() async {
    guard !isSaving else { return }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }

    do {
        let rule = PriceDropRule(
            notifyOnAnyDecrease: notifyOnAnyDecrease,
            minimumDropAmount: Double(minimumDropAmount),
            minimumDropPercent: Double(minimumDropPercent).map { $0 / 100 }
        )
        if recommendation != nil {
            try await onSaveFromRecommendation(frequency, rule, systemNotificationsEnabled)
        } else {
            var manualRequest = request
            manualRequest.vehicleQuery = vehicleQuery
            try await onSaveManual(name, manualRequest, vehicleQuery, frequency, rule, systemNotificationsEnabled)
        }
        dismiss()
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

- [ ] **Step 6: Run tests and commit**

```bash
swift test --filter UIEffectsSourceTests
swift test --filter MonitorCenterViewModelTests
swift build
git add Sources/CarRentalOptimizer/BlueprintSheetComponents.swift Sources/CarRentalOptimizer/CreateMonitorSheet.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "refactor: unify monitor sheet workflow"
```

Expected: tests/build pass; save callbacks and rule construction remain unchanged.

### Task 4: Platform Login Sheet Unification

**Files:**
- Modify: `Sources/CarRentalOptimizer/EhiLoginSheet.swift`
- Modify: `Sources/CarRentalOptimizer/PlatformLoginSheet.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: existing WebView representables, reload/reset tokens, cookie vaults, and plan-4 sheet chrome.
- Produces: stable Route Blueprint login chrome with unchanged platform behavior.

- [ ] **Step 1: Extend login sheet source contracts**

Append to the shared sheet test:

```swift
let ehi = try String(contentsOfFile: "Sources/CarRentalOptimizer/EhiLoginSheet.swift", encoding: .utf8)
let platform = try String(contentsOfFile: "Sources/CarRentalOptimizer/PlatformLoginSheet.swift", encoding: .utf8)

#expect(ehi.contains("BlueprintWebLocationBar"))
#expect(ehi.contains("BlueprintSheetActionBar"))
#expect(ehi.contains("EhiCookieVault.save"))
#expect(ehi.contains("resetToken += 1"))
#expect(platform.contains("BlueprintWebLocationBar"))
#expect(platform.contains("BlueprintSheetActionBar"))
#expect(platform.contains("ZucheCookieVault.save"))
```

- [ ] **Step 2: Run the source test and verify it fails**

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because neither login sheet consumes the new shared chrome.

- [ ] **Step 3: Apply shared chrome to Ehi without touching WebView logic**

Inside the Ehi `VStack`, place this above `captchaWarningView`:

```swift
BlueprintWebLocationBar(
    platformName: "一嗨",
    currentURL: currentURL,
    message: "登录状态仅保存在本机，用于重新读取官方库存报价。",
    tone: captchaWarning == nil ? .active : .warning
)
```

Replace `loginActionBar`'s outer `HStack` and padding/background modifiers with:

```swift
BlueprintSheetActionBar {
    Spacer()
    Button {
        let action = EhiLoginSession.refreshAction(forCaptchaWarning: captchaWarning)
        captchaWarning = nil
        switch action {
        case .reload: reloadToken += 1
        case .resetChallenge: resetToken += 1
        }
    } label: {
        Label(captchaWarning == nil ? "刷新登录页" : "重置并刷新登录页", systemImage: "arrow.clockwise")
    }
    .buttonStyle(.bordered)

    Button("取消") { dismiss() }
        .keyboardShortcut(.cancelAction)

    Button("登录完成，重新比较") {
        Task { @MainActor in
            await EhiCookieVault.save(from: WKWebsiteDataStore.default().httpCookieStore)
            EhiLoginSession.notifyDidChange()
            dismiss()
            onCompleted()
        }
    }
    .buttonStyle(.borderedProminent)
    .tint(WorkbenchStyle.decisionBlue)
    .keyboardShortcut(.defaultAction)
}
```

Do not edit `EhiLoginWebView` or its `Coordinator`.

- [ ] **Step 4: Apply shared chrome to CAR Inc without touching WebView logic**

Inside the platform sheet `VStack`, place this above `platformInfoRow`:

```swift
BlueprintWebLocationBar(
    platformName: platform.label,
    currentURL: currentURL,
    message: "登录官网后可重新比较并尝试补全确认页基础服务费。"
)
```

Replace `platformActionBar` with:

```swift
BlueprintSheetActionBar {
    Spacer()
    Button {
        reloadToken += 1
    } label: {
        Label("刷新登录页", systemImage: "arrow.clockwise")
    }
    .buttonStyle(.bordered)

    Button("取消") { dismiss() }
        .keyboardShortcut(.cancelAction)

    Button("登录完成，重新比较") {
        Task { @MainActor in
            if platform == .carInc {
                await ZucheCookieVault.save(from: WKWebsiteDataStore.default().httpCookieStore)
            }
            dismiss()
            onCompleted()
        }
    }
    .buttonStyle(.borderedProminent)
    .tint(WorkbenchStyle.decisionBlue)
    .keyboardShortcut(.defaultAction)
}
```

Do not edit `PlatformLoginWebView` or its `Coordinator`.

- [ ] **Step 5: Run regression tests and commit**

```bash
swift test --filter EhiLoginSessionTests
swift test --filter UIEffectsSourceTests
swift build
git add Sources/CarRentalOptimizer/EhiLoginSheet.swift Sources/CarRentalOptimizer/PlatformLoginSheet.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "refactor: unify platform login sheets"
```

Expected: tests/build pass and login/captcha/cookie source contracts remain present.

### Task 5: Full-App Closure Verification

**Files:**
- Modify only if verification discovers a reproducible defect in the approved scope.

**Interfaces:**
- Consumes: all four implementation plans.
- Produces: final automated, app-bundle, visual, accessibility, and repository evidence.

- [ ] **Step 1: Run complete automated verification**

```bash
swift build
swift test
```

Expected: both commands exit 0 with all existing and newly added tests passing.

- [ ] **Step 2: Build and launch the app bundle**

```bash
scripts/build-app.sh
scripts/verify-app-bundle.sh build/租车比价助手.app
scripts/verify-launch.sh build/租车比价助手.app
```

Expected: all scripts exit 0 and the application launches.

- [ ] **Step 3: Verify full navigation and monitor behavior**

Check:

- App launches in “比价工作台”.
- Navigation and `⇧⌘M` open “价格监控” in the main window, not a large sheet.
- Monitor health counts match filters and list contents.
- Batch check/pause/resume act on the shown monitor IDs.
- Selecting a monitor loads summary, trend, events, and snapshots.
- Background monitoring toggle, pause/resume, and immediate check still work.
- Create-monitor save disables duplicate submission and reports errors without resizing the sheet.

- [ ] **Step 4: Verify login and visual states**

Check:

- Ehi refresh, captcha warning, challenge reset, cancel, and completion behave as before.
- CAR Inc refresh, fee explanation, cookie save, cancel, and completion behave as before.
- Search, comparison, monitor, create-monitor, and both login sheets are readable in light/dark mode.
- 1280px main window shows no overlap; login sheets keep at least 760×680 content.
- Keyboard focus and default/cancel actions work.
- Reduced Motion removes looping and offset motion.
- Status, advantage, warning, and selection remain understandable without color.

- [ ] **Step 5: Confirm repository and release boundaries**

```bash
git status --short
git log --oneline -12
```

Expected: clean tree; commits correspond to the plan tasks. No version, tag, appcast, release-guide, ZIP, signing, or notarization changes are present.
