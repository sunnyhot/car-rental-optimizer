# Route Blueprint Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the Route Blueprint design tokens and replace the modal monitor entry point with a keyboard-aware two-workspace macOS application shell.

**Architecture:** Keep the existing search and monitor view models unchanged. Add a small navigation model, a reusable navigation rail/status bar, and compose the existing search and monitor views inside the new shell so later comparison and page-refactor plans can build on a stable frame.

**Tech Stack:** Swift 6, SwiftUI, AppKit adaptive colors, SF Symbols, Swift Testing, existing `CarRentalDomain` models.

## Global Constraints

- macOS 14 or newer and Swift 6 remain the supported runtime/toolchain.
- Do not change official platform APIs, candidate ranking, price calculation, login cookies, monitor persistence, or release behavior.
- Do not add third-party dependencies, external fonts, or remote visual assets.
- Use SwiftUI, SF Symbols, SF Pro system typography, and AppKit adaptive colors.
- Keep the main window minimum width at approximately 1280px.
- Every state must use text or an icon in addition to color.
- Motion must respect `Environment(\.accessibilityReduceMotion)` and stay within 150–300ms for normal transitions.
- Preserve all existing menu commands and keyboard shortcuts.
- Run `swift build` and `swift test` before completing the plan.

---

## Scope Check

This is plan 1 of 4. It is independently shippable: the app gains the approved shell and visual foundation while still rendering the existing search, monitor, and sheet contents. Execute the plans in this order:

1. `2026-07-10-route-blueprint-shell.md`
2. `2026-07-10-decision-comparison-workspace.md`
3. `2026-07-10-search-workspace-refactor.md`
4. `2026-07-10-monitor-sheets-refactor.md`

## File Structure

- `.gitignore`: excludes local visual-companion artifacts under `.superpowers/`.
- `Sources/CarRentalOptimizer/WorkbenchStyle.swift`: owns Route Blueprint adaptive colors and shared route/status primitives.
- `Sources/CarRentalOptimizer/AppNavigation.swift`: owns `AppWorkspace` and `AppNavigationModel`; it has no SwiftUI view responsibilities.
- `Sources/CarRentalOptimizer/AppShellView.swift`: owns the compact navigation rail, top status bar, and workspace switch.
- `Sources/CarRentalOptimizer/MainView.swift`: owns app-level notification routing and composes `AppShellView`.
- `Sources/CarRentalOptimizer/AppWindowLayout.swift`: owns widths for the navigation rail and search workbench.
- `Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift`: source-contract tests for Route Blueprint tokens/primitives.
- `Tests/CarRentalOptimizerTests/AppNavigationTests.swift`: behavior tests for workspace navigation.
- `Tests/CarRentalOptimizerTests/AppWindowLayoutTests.swift`: verifies the rail plus three-column minimum width.
- `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`: source-contract tests for shell adoption.

### Task 1: Route Blueprint Tokens and Local Artifact Hygiene

**Files:**
- Modify: `.gitignore`
- Modify: `Sources/CarRentalOptimizer/WorkbenchStyle.swift`
- Modify: `Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift`

**Interfaces:**
- Consumes: existing `WorkbenchStyle`, `StatusLightRail`, `WorkbenchBackground`, and legacy token call sites.
- Produces:
  - `WorkbenchStyle.blueprintMist: Color`
  - `WorkbenchStyle.routeInk: Color`
  - `WorkbenchStyle.decisionBlue: Color`
  - `WorkbenchStyle.signalTeal: Color`
  - `WorkbenchStyle.riskAmber: Color`
  - `struct BlueprintRouteTrail: View`
  - Legacy aliases `commandBlue`, `amberAlert`, `consoleBase`, `accent`, and `orange` remain available.

- [ ] **Step 1: Extend the shared style source-contract tests**

Append to `Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift`:

```swift
@Test("Workbench style exposes Route Blueprint semantic tokens")
func workbenchStyleExposesRouteBlueprintTokens() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/WorkbenchStyle.swift", encoding: .utf8)

    #expect(source.contains("static let blueprintMist"))
    #expect(source.contains("static let routeInk"))
    #expect(source.contains("static let decisionBlue"))
    #expect(source.contains("static let signalTeal"))
    #expect(source.contains("static let riskAmber"))
    #expect(source.contains("struct BlueprintRouteTrail"))
    #expect(source.contains("accessibilityReduceMotion"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter WorkbenchStyle
```

Expected: FAIL because `blueprintMist`, `routeInk`, `decisionBlue`, `riskAmber`, and `BlueprintRouteTrail` do not exist.

- [ ] **Step 3: Add semantic tokens while preserving compatibility aliases**

At the start of `WorkbenchStyle`, add the semantic palette and update the existing aliases to use it:

```swift
static let blueprintMist = adaptiveColor(
    light: NSColor(calibratedRed: 0.918, green: 0.945, blue: 0.961, alpha: 1),
    dark: NSColor(calibratedRed: 0.035, green: 0.075, blue: 0.114, alpha: 1)
)
static let routeInk = adaptiveColor(
    light: NSColor(calibratedRed: 0.090, green: 0.224, blue: 0.325, alpha: 1),
    dark: NSColor(calibratedRed: 0.780, green: 0.866, blue: 0.925, alpha: 1)
)
static let decisionBlue = adaptiveColor(
    light: NSColor(calibratedRed: 0.141, green: 0.412, blue: 0.827, alpha: 1),
    dark: NSColor(calibratedRed: 0.345, green: 0.631, blue: 1.000, alpha: 1)
)
static let signalTeal = adaptiveColor(
    light: NSColor(calibratedRed: 0.051, green: 0.608, blue: 0.588, alpha: 1),
    dark: NSColor(calibratedRed: 0.290, green: 0.855, blue: 0.820, alpha: 1)
)
static let riskAmber = adaptiveColor(
    light: NSColor(calibratedRed: 0.851, green: 0.541, blue: 0.133, alpha: 1),
    dark: NSColor(calibratedRed: 1.000, green: 0.690, blue: 0.290, alpha: 1)
)

static let commandBlue = decisionBlue
static let amberAlert = riskAmber
static let consoleBase = blueprintMist
static let accent = decisionBlue
static let orange = riskAmber
```

Keep `routeGreen`, `criticalRed`, `panelSurface`, `elevatedSurface`, `hairline`, `cardShadow`, `glowLine`, `ink`, `muted`, `line`, `background`, `panel`, and `surface`. Remove the old duplicate declarations for `commandBlue`, `signalTeal`, `amberAlert`, `consoleBase`, `accent`, and `orange` so every semantic role has one source.

Change the existing rail tone declaration to support equality in later route-step presentation:

```swift
enum WorkbenchRailTone: Equatable {
```

- [ ] **Step 4: Add the Route Blueprint trail primitive**

Add below `StatusLightRail` in `WorkbenchStyle.swift`:

```swift
struct BlueprintRouteTrail: View {
    let stops: [WorkbenchRailTone]
    var activeIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, tone in
                Circle()
                    .fill(tone.color)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(WorkbenchStyle.panelSurface, lineWidth: 2))
                    .scaleEffect(activeIndex == index && !reduceMotion ? 1.12 : 1)

                if index < stops.count - 1 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [tone.color.opacity(0.75), stops[index + 1].color.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                }
            }
        }
        .animation(reduceMotion ? nil : WorkbenchStyle.motionStandard, value: activeIndex)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 5: Ignore visual-companion artifacts**

Append to `.gitignore`:

```gitignore
# Local Superpowers visual-companion artifacts
.superpowers/
```

Run:

```bash
git check-ignore .superpowers/brainstorm
swift test --filter WorkbenchStyle
```

Expected: `.superpowers/brainstorm` is reported as ignored and the focused Swift tests PASS.

- [ ] **Step 6: Commit the design foundation**

```bash
git add .gitignore Sources/CarRentalOptimizer/WorkbenchStyle.swift Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift
git commit -m "feat: add route blueprint design foundation"
```

### Task 2: Workspace Navigation Model

**Files:**
- Create: `Sources/CarRentalOptimizer/AppNavigation.swift`
- Create: `Tests/CarRentalOptimizerTests/AppNavigationTests.swift`

**Interfaces:**
- Consumes: no app view model or persistence state.
- Produces:
  - `enum AppWorkspace: String, CaseIterable, Identifiable`
  - `AppWorkspace.title: String`
  - `AppWorkspace.systemImage: String`
  - `@MainActor final class AppNavigationModel: ObservableObject`
  - `AppNavigationModel.selectedWorkspace: AppWorkspace`
  - `showComparison()` and `showMonitoring()`.

- [ ] **Step 1: Write navigation behavior tests**

Create `Tests/CarRentalOptimizerTests/AppNavigationTests.swift`:

```swift
import Testing
@testable import CarRentalOptimizer

@MainActor
@Suite("App navigation")
struct AppNavigationTests {
    @Test("App starts in the comparison workspace")
    func appStartsInComparisonWorkspace() {
        let model = AppNavigationModel()
        #expect(model.selectedWorkspace == .comparison)
    }

    @Test("Navigation commands switch between main workspaces")
    func commandsSwitchWorkspaces() {
        let model = AppNavigationModel()

        model.showMonitoring()
        #expect(model.selectedWorkspace == .monitoring)

        model.showComparison()
        #expect(model.selectedWorkspace == .comparison)
    }

    @Test("Workspace metadata is stable and user facing")
    func workspaceMetadataIsStable() {
        #expect(AppWorkspace.allCases.map(\.title) == ["比价工作台", "价格监控"])
        #expect(AppWorkspace.comparison.systemImage == "point.3.connected.trianglepath.dotted")
        #expect(AppWorkspace.monitoring.systemImage == "chart.xyaxis.line")
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
swift test --filter AppNavigation
```

Expected: FAIL because `AppNavigationModel` and `AppWorkspace` are undefined.

- [ ] **Step 3: Implement the navigation model**

Create `Sources/CarRentalOptimizer/AppNavigation.swift`:

```swift
import SwiftUI

enum AppWorkspace: String, CaseIterable, Identifiable {
    case comparison
    case monitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comparison: return "比价工作台"
        case .monitoring: return "价格监控"
        }
    }

    var systemImage: String {
        switch self {
        case .comparison: return "point.3.connected.trianglepath.dotted"
        case .monitoring: return "chart.xyaxis.line"
        }
    }
}

@MainActor
final class AppNavigationModel: ObservableObject {
    @Published var selectedWorkspace: AppWorkspace = .comparison

    func showComparison() {
        selectedWorkspace = .comparison
    }

    func showMonitoring() {
        selectedWorkspace = .monitoring
    }
}
```

- [ ] **Step 4: Run the focused tests and verify they pass**

Run:

```bash
swift test --filter AppNavigation
```

Expected: PASS with 3 tests.

- [ ] **Step 5: Commit the navigation model**

```bash
git add Sources/CarRentalOptimizer/AppNavigation.swift Tests/CarRentalOptimizerTests/AppNavigationTests.swift
git commit -m "feat: add primary workspace navigation model"
```

### Task 3: Window Geometry for the Navigation Rail

**Files:**
- Modify: `Sources/CarRentalOptimizer/AppWindowLayout.swift`
- Modify: `Tests/CarRentalOptimizerTests/AppWindowLayoutTests.swift`

**Interfaces:**
- Consumes: existing three-panel width constants.
- Produces:
  - `AppWindowLayout.navigationRailWidth == 56`
  - Search/result/detail minimum widths that fit with the rail inside `minimumWidth == 1280`.

- [ ] **Step 1: Update the layout contract test**

Replace the first test in `AppWindowLayoutTests.swift` with:

```swift
@Test("Minimum window width covers navigation and the three-column workbench")
func minimumWindowWidthCoversNavigationAndWorkbench() {
    let requiredWidth = AppWindowLayout.navigationRailWidth
        + AppWindowLayout.searchPanelMinimumWidth
        + AppWindowLayout.resultsPanelMinimumWidth
        + AppWindowLayout.detailPanelMinimumWidth
        + AppWindowLayout.splitHandleReserveWidth

    #expect(AppWindowLayout.navigationRailWidth == 56)
    #expect(AppWindowLayout.minimumWidth >= requiredWidth)
    #expect(AppWindowLayout.minimumWidth == 1280)
    #expect(AppWindowLayout.defaultWidth >= AppWindowLayout.minimumWidth)
}
```

- [ ] **Step 2: Run the layout tests and verify they fail**

Run:

```bash
swift test --filter AppWindowLayout
```

Expected: FAIL because `navigationRailWidth` is undefined.

- [ ] **Step 3: Adjust layout constants**

Replace the width declarations in `AppWindowLayout.swift` with:

```swift
static let navigationRailWidth: CGFloat = 56

static let searchPanelMinimumWidth: CGFloat = 320
static let searchPanelIdealWidth: CGFloat = 360
static let searchPanelMaximumWidth: CGFloat = 430

static let resultsPanelMinimumWidth: CGFloat = 520
static let resultsPanelIdealWidth: CGFloat = 680

static let detailPanelMinimumWidth: CGFloat = 340
static let detailPanelIdealWidth: CGFloat = 400
static let detailPanelMaximumWidth: CGFloat = 460

static let splitHandleReserveWidth: CGFloat = 40

static let minimumWidth: CGFloat = 1280
static let minimumHeight: CGFloat = 760
static let defaultWidth: CGFloat = 1380
static let defaultHeight: CGFloat = 860
```

- [ ] **Step 4: Run the layout tests and verify they pass**

Run:

```bash
swift test --filter AppWindowLayout
```

Expected: PASS with both layout tests.

- [ ] **Step 5: Commit the geometry update**

```bash
git add Sources/CarRentalOptimizer/AppWindowLayout.swift Tests/CarRentalOptimizerTests/AppWindowLayoutTests.swift
git commit -m "refactor: reserve space for app navigation rail"
```

### Task 4: Route Blueprint Application Shell

**Files:**
- Create: `Sources/CarRentalOptimizer/AppShellView.swift`
- Modify: `Sources/CarRentalOptimizer/MainView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes:
  - `AppNavigationModel.selectedWorkspace`
  - `SearchViewModel`, `MonitorCenterViewModel`
  - existing `SearchPanelView`, `ResultPanelView`, `DetailPanelView`, and `MonitorCenterView`.
- Produces:
  - `struct AppShellView: View`
  - `struct PrimaryNavigationRail: View`
  - `struct BlueprintStatusBar: View`
  - `MainView` notification routing that switches workspaces rather than presenting the monitor sheet.

- [ ] **Step 1: Add shell adoption source-contract tests**

Append to `UIEffectsSourceTests.swift`:

```swift
@Test("Main view routes app commands through the primary workspace shell")
func mainViewRoutesCommandsThroughWorkspaceShell() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/MainView.swift", encoding: .utf8)
    let shell = try String(contentsOfFile: "Sources/CarRentalOptimizer/AppShellView.swift", encoding: .utf8)

    #expect(source.contains("AppNavigationModel"))
    #expect(source.contains("AppShellView(navigationModel:"))
    #expect(source.contains("navigationModel.showMonitoring()"))
    #expect(source.contains("navigationModel.showComparison()"))
    #expect(!source.contains("showingMonitorCenter"))
    #expect(shell.contains("PrimaryNavigationRail"))
    #expect(shell.contains("BlueprintStatusBar"))
    #expect(shell.contains("MonitorCenterView()"))
}
```

Replace the existing `mainViewUsesCommandCenterShellComponents()` test with:

```swift
@Test("Main shell uses Route Blueprint status components")
func mainShellUsesRouteBlueprintStatusComponents() throws {
    let main = try String(contentsOfFile: "Sources/CarRentalOptimizer/MainView.swift", encoding: .utf8)
    let shell = try String(contentsOfFile: "Sources/CarRentalOptimizer/AppShellView.swift", encoding: .utf8)

    #expect(main.contains("AppShellView(navigationModel:"))
    #expect(shell.contains("WorkbenchBackground()"))
    #expect(shell.contains("BlueprintStatusBar"))
    #expect(shell.contains("StatusLightRail("))
    #expect(shell.contains("TaskStatusTile("))
    #expect(shell.contains("tone: .active"))
    #expect(shell.contains("tone: .success"))
    #expect(shell.contains("tone: .warning"))
}
```

- [ ] **Step 2: Run the source-contract test and verify it fails**

Run:

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because `AppShellView.swift` does not exist and `MainView` still uses `showingMonitorCenter`.

- [ ] **Step 3: Create the shell view**

Create `Sources/CarRentalOptimizer/AppShellView.swift` with these complete view declarations:

```swift
import SwiftUI

struct AppShellView: View {
    @ObservedObject var navigationModel: AppNavigationModel
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var monitorViewModel: MonitorCenterViewModel

    var body: some View {
        ZStack {
            WorkbenchBackground()

            VStack(spacing: 0) {
                BlueprintStatusBar()

                HStack(spacing: 0) {
                    PrimaryNavigationRail(navigationModel: navigationModel)
                        .frame(width: AppWindowLayout.navigationRailWidth)

                    Group {
                        switch navigationModel.selectedWorkspace {
                        case .comparison:
                            searchWorkspace
                        case .monitoring:
                            MonitorCenterView()
                                .environmentObject(searchViewModel)
                                .environmentObject(monitorViewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var searchWorkspace: some View {
        HSplitView {
            SearchPanelView()
                .frame(
                    minWidth: AppWindowLayout.searchPanelMinimumWidth,
                    idealWidth: AppWindowLayout.searchPanelIdealWidth,
                    maxWidth: AppWindowLayout.searchPanelMaximumWidth
                )
            ResultPanelView()
                .frame(
                    minWidth: AppWindowLayout.resultsPanelMinimumWidth,
                    idealWidth: AppWindowLayout.resultsPanelIdealWidth
                )
            DetailPanelView()
                .frame(
                    minWidth: AppWindowLayout.detailPanelMinimumWidth,
                    idealWidth: AppWindowLayout.detailPanelIdealWidth,
                    maxWidth: AppWindowLayout.detailPanelMaximumWidth
                )
        }
    }
}

struct PrimaryNavigationRail: View {
    @ObservedObject var navigationModel: AppNavigationModel

    var body: some View {
        VStack(spacing: 10) {
            ForEach(AppWorkspace.allCases) { workspace in
                Button {
                    navigationModel.selectedWorkspace = workspace
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: workspace.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(workspace.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        navigationModel.selectedWorkspace == workspace
                            ? WorkbenchStyle.decisionBlue
                            : WorkbenchStyle.muted
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                navigationModel.selectedWorkspace == workspace
                                    ? WorkbenchStyle.decisionBlue.opacity(0.12)
                                    : Color.clear
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(workspace.title)
                .help(workspace.title)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .background(WorkbenchStyle.panelSurface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(WorkbenchStyle.hairline).frame(width: 1)
        }
    }
}

struct BlueprintStatusBar: View {
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var monitorViewModel: MonitorCenterViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [WorkbenchStyle.decisionBlue, WorkbenchStyle.signalTeal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.appName).font(.headline.weight(.bold))
                    Text("Route Blueprint · v\(AppInfo.version)")
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                }

                Spacer(minLength: 12)

                TaskStatusTile(
                    title: "上次搜索",
                    value: searchViewModel.lastSuccessfulSearchAt.map(formatCompactDateTime) ?? "--",
                    icon: "clock.badge.checkmark",
                    tone: searchViewModel.lastSuccessfulSearchAt == nil ? .idle : .success
                )
                TaskStatusTile(
                    title: "当前推荐",
                    value: searchViewModel.selected.map { formatMoney($0.bestTotal) } ?? "--",
                    icon: "yensign.circle",
                    tone: searchViewModel.selected == nil ? .idle : .active
                )
                TaskStatusTile(
                    title: "监控状态",
                    value: monitorValue,
                    icon: "bell.badge",
                    tone: monitorViewModel.healthSummary.needsAttentionCount > 0 ? .warning : .success
                )
                StatusPill(
                    text: searchViewModel.isSearching ? "查询中" : "官方 API",
                    color: searchViewModel.isSearching ? WorkbenchStyle.riskAmber : WorkbenchStyle.decisionBlue,
                    systemImage: searchViewModel.isSearching ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle.fill"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            StatusLightRail(
                isActive: searchViewModel.isSearching,
                tone: searchViewModel.isSearching ? .active : .idle
            )
        }
        .background(WorkbenchStyle.panelSurface)
    }

    private var monitorValue: String {
        let summary = monitorViewModel.healthSummary
        guard summary.totalCount > 0 else { return "0" }
        return summary.needsAttentionCount > 0
            ? "\(summary.needsAttentionCount)/\(summary.totalCount) 需处理"
            : "\(summary.activeCount)/\(summary.totalCount) 正常"
    }
}
```

- [ ] **Step 4: Reduce MainView to app-level routing**

Replace `MainView.swift` with:

```swift
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var viewModel: SearchViewModel
    @EnvironmentObject private var monitorViewModel: MonitorCenterViewModel
    @StateObject private var navigationModel = AppNavigationModel()

    var body: some View {
        AppShellView(navigationModel: navigationModel)
            .onReceive(NotificationCenter.default.publisher(for: .openMonitorCenter)) { _ in
                navigationModel.showMonitoring()
            }
            .onReceive(NotificationCenter.default.publisher(for: .retryLatestSearch)) { _ in
                navigationModel.showComparison()
                Task { await viewModel.retrySearch() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .runDueMonitorChecks)) { _ in
                Task { await monitorViewModel.runDueChecks() }
            }
    }
}
```

- [ ] **Step 5: Run focused and full tests**

Run:

```bash
swift test --filter AppNavigation
swift test --filter UIEffectsSourceTests
swift build
swift test
```

Expected: all commands exit 0. The source-contract suite reads shell components from `AppShellView.swift`; no assertion references the removed private `WorkbenchHeader`.

- [ ] **Step 6: Commit the application shell**

```bash
git add Sources/CarRentalOptimizer/AppShellView.swift Sources/CarRentalOptimizer/MainView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "feat: integrate route blueprint app shell"
```

### Task 5: App Bundle Smoke Verification

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the complete plan-1 application shell.
- Produces: build, test, bundle, and launch evidence for handoff to plan 2.

- [ ] **Step 1: Verify repository state and Swift tests**

Run:

```bash
git status --short
swift build
swift test
```

Expected: only intentional plan-1 changes are committed, `swift build` exits 0, and the full test suite passes.

- [ ] **Step 2: Build and launch the application bundle**

Run:

```bash
scripts/build-app.sh
scripts/verify-launch.sh build/租车比价助手.app
```

Expected: both scripts exit 0 and the app opens in the comparison workspace.

- [ ] **Step 3: Perform the focused manual shell check**

Verify all of the following:

- “比价工作台” is selected on launch.
- “价格监控” switches to the existing monitor view without opening a sheet.
- `⇧⌘M` switches to the monitor workspace.
- `⌘R` switches back to comparison and retries the latest search.
- At 1280px width, the navigation rail and all three search panels remain readable.
- Light and dark appearances show readable Route Blueprint tokens.

- [ ] **Step 4: Record verification without creating a release commit**

Run:

```bash
git status --short
```

Expected: clean working tree. Do not change version numbers, tags, appcast, release notes, or ZIP artifacts.
