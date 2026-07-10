# Search Workspace Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fully restyle the trip configuration, candidate browser, and decision detail into the approved Route Blueprint search workspace while preserving every current search behavior.

**Architecture:** Keep `SearchViewModel` and all domain/network services intact. Add focused Route Blueprint workspace components, then migrate the existing three panels one at a time so each task is buildable and the comparison feature from plan 2 remains continuously usable.

**Tech Stack:** Swift 6, SwiftUI, AppKit adaptive colors and clipboard integration, SF Symbols, Swift Testing, existing search and vehicle-insight presentation types.

## Global Constraints

- Execute after `2026-07-10-decision-comparison-workspace.md`.
- Preserve address suggestions, rail-station selection, date validation, vehicle suggestions, platform toggles, login entry points, search diagnostics, filters, sorting, stale results, monitoring actions, and official-page actions.
- Do not change platform APIs, ranking, price calculation, route estimation, login cookies, monitor persistence, or release behavior.
- Use the Route Blueprint palette and route trail as the only signature visual device.
- Use SF Pro system typography; monospaced digits only for price, distance, duration, time, and percentages.
- Selection, advantage, risk, and loading states must not rely on color alone.
- Respect reduced motion; normal transitions must stay within 150–300ms.
- Keep the main window usable at 1280px minimum width in light and dark appearance.
- Do not add third-party dependencies or external assets.
- Run `swift build` and `swift test` before completion.

---

## Scope Check

This is plan 3 of 4. It changes only the search workspace UI and shared workspace presentation components. The comparison state/matrix is already complete and remains the acceptance baseline throughout this plan.

## File Structure

- `Sources/CarRentalOptimizer/BlueprintWorkspaceComponents.swift`: shared section headers, metrics, vertical route path, and state surface used by search pages.
- `Sources/CarRentalOptimizer/SearchPanelView.swift`: trip configuration and platform recovery UI.
- `Sources/CarRentalOptimizer/ResultPanelView.swift`: candidate browser, filters, loading/empty/recovery states, and comparison selection.
- `Sources/CarRentalOptimizer/DetailPanelView.swift`: selected recommendation decision path, costs, insight, routes, risk, and actions.
- `Tests/CarRentalOptimizerTests/BlueprintWorkspaceComponentTests.swift`: source-contract tests for focused shared components.
- `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`: page-level adoption, accessibility, and regression contracts.

### Task 1: Shared Route Blueprint Workspace Components

**Files:**
- Create: `Sources/CarRentalOptimizer/BlueprintWorkspaceComponents.swift`
- Create: `Tests/CarRentalOptimizerTests/BlueprintWorkspaceComponentTests.swift`

**Interfaces:**
- Consumes: plan-1 `WorkbenchStyle`, `WorkbenchCard`, `WorkbenchRailTone`.
- Produces:
  - `BlueprintSectionHeader`
  - `BlueprintMetricTile`
  - `BlueprintRouteStep`
  - `BlueprintRoutePath`
  - `BlueprintStatePanel`

- [ ] **Step 1: Write the component source contracts**

Create `Tests/CarRentalOptimizerTests/BlueprintWorkspaceComponentTests.swift`:

```swift
import Foundation
import Testing

@Suite("Route Blueprint workspace components")
struct BlueprintWorkspaceComponentTests {
    @Test("Workspace component file exposes the approved focused primitives")
    func componentFileExposesApprovedPrimitives() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/BlueprintWorkspaceComponents.swift", encoding: .utf8)

        #expect(source.contains("struct BlueprintSectionHeader"))
        #expect(source.contains("struct BlueprintMetricTile"))
        #expect(source.contains("struct BlueprintRouteStep"))
        #expect(source.contains("struct BlueprintRoutePath"))
        #expect(source.contains("struct BlueprintStatePanel"))
        #expect(source.contains("accessibilityReduceMotion"))
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
swift test --filter BlueprintWorkspaceComponentTests
```

Expected: FAIL because `BlueprintWorkspaceComponents.swift` does not exist.

- [ ] **Step 3: Implement the workspace primitives**

Create `Sources/CarRentalOptimizer/BlueprintWorkspaceComponents.swift`:

```swift
import SwiftUI

struct BlueprintSectionHeader: View {
    let icon: String
    let title: String
    var step: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(WorkbenchStyle.signalTeal)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                if let step {
                    Text(step.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(WorkbenchStyle.muted)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.muted)
                    .monospacedDigit()
            }
        }
    }
}

struct BlueprintMetricTile: View {
    let title: String
    let value: String
    let icon: String
    var tone: WorkbenchRailTone = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.muted)
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(tone.color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(WorkbenchStyle.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(tone.color.opacity(0.20), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

struct BlueprintRouteStep: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    var tone: WorkbenchRailTone = .idle
}

struct BlueprintRoutePath: View {
    let steps: [BlueprintRouteStep]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle().fill(step.tone.color.opacity(0.16))
                            Image(systemName: step.systemImage)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(step.tone.color)
                        }
                        .frame(width: 22, height: 22)

                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [step.tone.color.opacity(0.55), steps[index + 1].tone.color.opacity(0.35)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 2)
                                .frame(minHeight: 28)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.ink)
                        Text(step.detail)
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, index < steps.count - 1 ? 10 : 0)

                    Spacer(minLength: 8)
                }
            }
        }
        .animation(reduceMotion ? nil : WorkbenchStyle.motionStandard, value: steps)
    }
}

struct BlueprintStatePanel: View {
    let icon: String
    let title: String
    let message: String
    var tone: WorkbenchRailTone = .idle
    var isActive = false

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: tone.color.opacity(0.24), padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(tone.color)
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Spacer()
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                StatusLightRail(isActive: isActive, tone: tone)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: Run the focused test and commit**

```bash
swift test --filter BlueprintWorkspaceComponentTests
git add Sources/CarRentalOptimizer/BlueprintWorkspaceComponents.swift Tests/CarRentalOptimizerTests/BlueprintWorkspaceComponentTests.swift
git commit -m "feat: add route blueprint workspace components"
```

Expected: test passes and the commit succeeds.

### Task 2: Trip Configuration Panel

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: all existing search input components and plan-3 shared components.
- Produces: a four-step configuration path with stable search and login behavior.

- [ ] **Step 1: Replace the search-panel source contract**

Update `searchPanelUsesCommandConsoleComponents()` in `UIEffectsSourceTests.swift` so its final expectations are:

```swift
#expect(source.contains("QueryConsoleSection(step: \"01\""))
#expect(source.contains("QueryConsoleSection(step: \"02\""))
#expect(source.contains("QueryConsoleSection(step: \"03\""))
#expect(source.contains("QueryConsoleSection(step: \"04\""))
#expect(source.contains("BlueprintSectionHeader("))
#expect(source.contains("BlueprintRouteTrail("))
#expect(source.contains("PlatformSignalToggleButton"))
#expect(source.contains("CompareCommandButton"))
#expect(source.contains("VehicleSuggestionField("))
#expect(source.contains("OriginSuggestionDropdown"))
```

- [ ] **Step 2: Run the source test and verify it fails**

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because the numbered sections and route trail are absent.

- [ ] **Step 3: Update panel identity and add the configuration trail**

Change the `WorkbenchPanel` identity in `SearchPanelView.body` to:

```swift
WorkbenchPanel(
    title: "行程配置",
    subtitle: "位置 → 租期 → 车辆 → 平台",
    trailing: AnyView(
        StatusPill(
            text: "官方实时",
            color: WorkbenchStyle.decisionBlue,
            systemImage: "bolt.horizontal.circle.fill"
        )
    )
)
```

At the start of `searchControls`, add:

```swift
BlueprintRouteTrail(
    stops: [.active, .idle, .idle, .idle],
    activeIndex: viewModel.isSearching ? searchTrailIndex : nil
)
.padding(.horizontal, 4)
```

Add to `SearchPanelView`:

```swift
private var searchTrailIndex: Int {
    switch viewModel.searchProgressPhase {
    case .idle, .resolvingLocation: return 0
    case .queryingPlatforms: return 3
    case .rankingRoutes, .completed: return 3
    case .failed: return 0
    }
}
```

- [ ] **Step 4: Number and rename the four real workflow sections**

Add `step:` and update `title:` on the four existing `QueryConsoleSection` initializers. Do not modify their content closures:

```swift
QueryConsoleSection(step: "01", icon: "mappin.and.ellipse", title: "行程坐标")
QueryConsoleSection(step: "02", icon: "car", title: "车辆与范围")
QueryConsoleSection(step: "03", icon: "arrow.triangle.2.circlepath", title: "取还规则")
QueryConsoleSection(step: "04", icon: "link", title: "报价平台")
```

These are exact initializer prefixes: the first retains `OriginLocationField` and `DateRangeField`; the second retains `VehicleSuggestionField`, radius slider, and explanatory copy; the third retains the return-mode picker; the fourth retains platform toggles and status rows.

Replace `QueryConsoleSection` with:

```swift
private struct QueryConsoleSection<Content: View>: View {
    let step: String
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: WorkbenchStyle.hairline, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                BlueprintSectionHeader(icon: icon, title: title, step: step)
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
            }
        }
    }
}
```

- [ ] **Step 5: Make the fixed action area explicit and accessible**

Above `compareButton` in the fixed footer, add:

```swift
Text(viewModel.hasBlockingPreflightIssues ? "修正上方阻断项后可开始" : "将读取官方报价并计算到店成本")
    .font(.caption2)
    .foregroundStyle(viewModel.hasBlockingPreflightIssues ? WorkbenchStyle.riskAmber : WorkbenchStyle.muted)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.top, 8)
```

Keep the action text “开始比较”. Add to `CompareCommandButton`:

```swift
.accessibilityHint(isDisabled ? "搜索条件存在阻断项" : "读取所选平台的真实报价")
```

- [ ] **Step 6: Run tests, build, and commit**

```bash
swift test --filter UIEffectsSourceTests
swift build
git add Sources/CarRentalOptimizer/SearchPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "refactor: reshape trip configuration path"
```

Expected: tests and build pass without changing search behavior.

### Task 3: Candidate Browser and Decision Signals

**Files:**
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: plan-2 comparison selection, current filters/sorting/diagnostics, `QuoteCredibility`.
- Produces: scan-first candidate cards and consistent Route Blueprint loading/empty state surfaces.

- [ ] **Step 1: Replace candidate source contracts**

Replace `resultPanelUsesSignalCardsAndStagedLoading()` with:

```swift
@Test("Result panel uses Route Blueprint decision signals")
func resultPanelUsesRouteBlueprintDecisionSignals() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)

    #expect(source.contains("StagedSearchLoadingCard"))
    #expect(source.contains("ResultSignalCard"))
    #expect(source.contains("BlueprintStatePanel("))
    #expect(source.contains("BlueprintMetricTile("))
    #expect(source.contains("candidate-card-selection"))
    #expect(source.contains("commandCenterTransition(isEnabled: true, index: index)"))
    #expect(source.contains("comparisonViewModel.toggle(result)"))
    #expect(source.contains("QuoteCredibilityBadge"))
    #expect(source.contains("ActionStatusRow("))
    #expect(source.contains("hasExpandableVehicleMatches"))
}
```

- [ ] **Step 2: Run the source test and verify it fails**

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because the result panel has not adopted Blueprint state/metric components or the accessibility identifier.

- [ ] **Step 3: Restyle staged loading without changing phase data**

Replace the root content of `StagedSearchLoadingCard.body` with:

```swift
BlueprintStatePanel(
    icon: phase == .rankingRoutes ? "point.3.connected.trianglepath.dotted" : "arrow.triangle.2.circlepath",
    title: phase.title,
    message: phase.message,
    tone: phase == .failed ? .critical : .active,
    isActive: phase != .failed
)
.padding(16)
```

Keep `SearchProgressPhase` unchanged.

- [ ] **Step 4: Use the shared state surface for empty results**

At the start of `EmptyResultsView.body`, replace the current empty-state header with:

```swift
BlueprintStatePanel(
    icon: emptyStateIcon,
    title: emptyStateTitle,
    message: emptyStateMessage,
    tone: phase == .failed ? .critical : .idle,
    isActive: false
)
```

Keep the platform summary rows, recovery suggestions, and retry action below it. Do not remove typed platform status recovery behavior.

- [ ] **Step 5: Replace the result card metric row**

Replace `cardMetrics` with:

```swift
private var cardMetrics: some View {
    HStack(spacing: 7) {
        BlueprintMetricTile(
            title: "租车小计",
            value: formatMoney(recommendation.rentalTotal),
            icon: "car.fill",
            tone: .active
        )
        BlueprintMetricTile(
            title: "最优到店",
            value: formatMoney(bestRouteCost),
            icon: recommendation.bestRouteMode == .taxi ? "car.side" : "bus.fill",
            tone: .success
        )
        BlueprintMetricTile(
            title: "门店距离",
            value: String(format: "%.1f km", recommendation.listing.store.distanceKm),
            icon: "location.fill",
            tone: .idle
        )
        BlueprintMetricTile(
            title: "完整度",
            value: "\(Int((recommendation.listing.dataCompleteness * 100).rounded()))%",
            icon: "checkmark.shield.fill",
            tone: recommendation.listing.dataCompleteness >= 0.9 ? .success : .warning
        )
    }
}
```

Move the existing monitor button into a compact action row immediately below `QuoteCredibilityBadge`:

```swift
HStack {
    Label(rankingReason, systemImage: "arrow.up.arrow.down")
        .font(.caption2)
        .foregroundStyle(WorkbenchStyle.muted)
        .lineLimit(1)
    Spacer()
    Button {
        onMonitor()
    } label: {
        Label("监控", systemImage: "bell.badge")
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .accessibilityLabel("监控此租车方案")
}
```

- [ ] **Step 6: Strengthen selection structure and accessibility**

Add this overlay to the outer `WorkbenchCard` result:

```swift
.overlay(alignment: .leading) {
    RoundedRectangle(cornerRadius: 2)
        .fill(isSelected ? WorkbenchStyle.decisionBlue : Color.clear)
        .frame(width: 3)
        .padding(.vertical, 8)
}
.accessibilityIdentifier("candidate-card-selection")
```

Keep the plan-2 comparison checkbox and the normal card tap as separate controls with their existing accessibility labels.

- [ ] **Step 7: Run tests and commit**

```bash
swift test --filter UIEffectsSourceTests
swift build
git add Sources/CarRentalOptimizer/ResultPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "refactor: make candidate decisions scan first"
```

Expected: tests/build pass and comparison selection remains available.

### Task 4: Recommendation Decision Path

**Files:**
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: selected recommendation, request origin label, existing costs/routes/vehicle insight/warnings/actions.
- Produces: origin → transport → store path and a Route Blueprint decision receipt.

- [ ] **Step 1: Replace detail source contracts**

Replace `detailPanelUsesDecisionReceiptComponents()` with:

```swift
@Test("Detail panel renders a Route Blueprint decision path")
func detailPanelRendersRouteBlueprintDecisionPath() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/DetailPanelView.swift", encoding: .utf8)

    #expect(source.contains("DecisionReceiptHeader"))
    #expect(source.contains("BlueprintRoutePath("))
    #expect(source.contains("originLabel: viewModel.request.originLabel"))
    #expect(source.contains("decisionRouteSteps"))
    #expect(source.contains("BlueprintMetricTile("))
    #expect(source.contains("RouteDecisionCard"))
    #expect(source.contains("ReceiptActionBar"))
    #expect(source.contains("ActionStatusRow("))
}
```

- [ ] **Step 2: Run the source test and verify it fails**

```bash
swift test --filter UIEffectsSourceTests
```

Expected: FAIL because the detail view has no Blueprint route path.

- [ ] **Step 3: Pass the actual origin into recommendation detail**

Update the `RecommendationDetailView` call:

```swift
RecommendationDetailView(
    recommendation: recommendation,
    originLabel: viewModel.request.originLabel,
    vehicleInsight: viewModel.selectedVehicleInsight,
    isLoadingVehicleInsight: viewModel.isLoadingSelectedVehicleInsight
) {
    pendingMonitorRecommendation = recommendation
}
```

Add to `RecommendationDetailView`:

```swift
let originLabel: String
```

- [ ] **Step 4: Replace the top summary and route presentation**

Replace the two `TaskStatusTile` values below `DecisionReceiptHeader` with:

```swift
HStack(spacing: 8) {
    BlueprintMetricTile(title: "租车小计", value: formatMoney(recommendation.rentalTotal), icon: "car.fill", tone: .active)
    BlueprintMetricTile(title: "到店成本", value: formatMoney(bestRouteCost), icon: recommendation.bestRouteMode == .taxi ? "car.side" : "bus.fill", tone: .success)
}
```

Before the existing taxi/transit alternative cards, add:

```swift
SurfaceBox {
    VStack(alignment: .leading, spacing: 10) {
        BlueprintSectionHeader(icon: "point.3.connected.trianglepath.dotted", title: "决策路径", step: "ROUTE")
        BlueprintRoutePath(steps: decisionRouteSteps)
    }
}
```

Add to `RecommendationDetailView`:

```swift
private var decisionRouteSteps: [BlueprintRouteStep] {
    let route = recommendation.bestRouteMode == .taxi
        ? recommendation.taxiRoute
        : recommendation.transitRoute
    return [
        BlueprintRouteStep(
            id: "origin",
            title: originLabel,
            detail: "当前行程起点",
            systemImage: "mappin.circle.fill",
            tone: .active
        ),
        BlueprintRouteStep(
            id: "transport",
            title: recommendation.bestRouteMode.label,
            detail: "\(Int(route.durationMinutes.rounded())) 分钟 · \(String(format: "%.1f km", route.distanceKm)) · \(formatMoney(route.cost))",
            systemImage: recommendation.bestRouteMode == .taxi ? "car.side.fill" : "bus.fill",
            tone: .success
        ),
        BlueprintRouteStep(
            id: "store",
            title: recommendation.listing.store.name,
            detail: recommendation.listing.store.address,
            systemImage: "building.2.fill",
            tone: .success
        ),
    ]
}
```

- [ ] **Step 5: Restyle the receipt header without changing totals**

In `DecisionReceiptHeader`, change the card fill/stroke to:

```swift
fill: WorkbenchStyle.decisionBlue.opacity(0.11),
stroke: WorkbenchStyle.decisionBlue.opacity(0.34),
```

Change its main value font to:

```swift
.font(.system(size: 34, weight: .bold, design: .default))
```

Keep `recommendation.bestTotal`, `rentalTotal`, and `bestRouteCost` calculations unchanged.

- [ ] **Step 6: Run tests and commit**

```bash
swift test --filter UIEffectsSourceTests
swift build
git add Sources/CarRentalOptimizer/DetailPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "refactor: turn recommendation detail into decision path"
```

Expected: build/tests pass and all prior detail actions remain.

### Task 5: Search Workspace Regression and Visual Verification

**Files:**
- No source changes expected unless verification exposes a defect.

**Interfaces:**
- Consumes: complete Route Blueprint search workspace and comparison mode.
- Produces: automated, bundle, and visual evidence for plan 4.

- [ ] **Step 1: Run complete automated verification**

```bash
swift build
swift test
```

Expected: all commands exit 0, including SearchViewModel, comparison, vehicle insight, layout, and source-contract tests.

- [ ] **Step 2: Build and launch the app bundle**

```bash
scripts/build-app.sh
scripts/verify-launch.sh build/租车比价助手.app
```

Expected: both scripts exit 0.

- [ ] **Step 3: Verify search states at minimum width in light and dark modes**

Check all of these states:

- Initial/locating state.
- Address and rail-station suggestions.
- Date range popover.
- Vehicle suggestions.
- Blocking preflight issue.
- Querying platform and ranking route phases.
- No results with platform recovery actions.
- Successful results, active filters, filtered-empty state, and stale results.
- Candidate selection, comparison checkboxes, 2–4 item selection bar, and matrix entry/exit.
- Decision detail with local and network vehicle insight.
- Long vehicle/store names and warning text at 1280px.

- [ ] **Step 4: Verify accessibility and motion**

Check:

- Keyboard focus reaches navigation, search controls, filter controls, candidate selection, comparison controls, monitor action, and official-page action in a logical order.
- VoiceOver labels distinguish selecting a card from adding it to comparison.
- Reduced Motion removes looping/offset animation while status text and color still change.
- Selection, credibility, best values, and warnings remain understandable without color.

- [ ] **Step 5: Confirm a clean handoff**

```bash
git status --short
```

Expected: clean working tree; do not update version, appcast, changelog release section, tags, or ZIP files.
