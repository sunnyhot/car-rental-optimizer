# UI Effects Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the SwiftUI macOS app into a professional command-center workbench with restrained technology-inspired effects across the main workbench, monitor center, and sheets.

**Architecture:** Keep all rental search, platform integration, monitoring, storage, and release logic unchanged. Extend the existing `WorkbenchStyle.swift` design system first, then migrate each SwiftUI surface to the shared tokens/components so the visual upgrade stays consistent and reviewable.

**Tech Stack:** Swift 6, SwiftUI, AppKit adaptive colors, SF Symbols, Swift Charts, Swift Testing, existing `CarRentalDomain` models.

## Global Constraints

- 本次升级只改变 SwiftUI 视图层和共享设计组件，不改变平台 API、搜索排序、价格计算、监控调度、持久化格式或发布流程。
- 不新增租车平台。
- 不修改真实 API 查询、平台登录、Cookie 保存、价格监控调度逻辑。
- 不修改领域模型、排序规则、价格计算或监控存储格式。
- 不做发布版本号、签名、公证、Release 流程调整。
- 不将应用改成网页、落地页或营销型首页。
- 不引入第三方 UI 框架。
- 不新增图像资产或外部网络资源。
- 所有状态不能只靠颜色传达，必须有图标或文字。
- 动效必须接入 `Environment(\.accessibilityReduceMotion)`；减少动态时保留颜色和状态变化，去掉位移、脉冲和错峰。
- 常规 micro-interaction 控制在 150-300ms。
- 验证命令以 `swift build` 和 `swift test` 为主。

---

## Scope Check

The approved spec covers one coherent UI subsystem: the shared visual language and its application to all app surfaces. It does not need to be split into separate specs because every page depends on the same design tokens, status rail, card surface, and motion conventions.

## File Structure

- `Sources/CarRentalOptimizer/WorkbenchStyle.swift`: owns adaptive color tokens, elevated surfaces, status rail, shared sheet shell, metric tile, status row, and motion helpers.
- `Sources/CarRentalOptimizer/MainView.swift`: owns the workbench shell, command background, and top task status bar.
- `Sources/CarRentalOptimizer/SearchPanelView.swift`: owns the query console controls, platform toggles, preflight issue display, address dropdown, and compare button.
- `Sources/CarRentalOptimizer/ResultPanelView.swift`: owns staged loading, empty/recovery states, filters, and candidate result signal cards.
- `Sources/CarRentalOptimizer/DetailPanelView.swift`: owns the selected recommendation decision receipt, route decision cards, and action area.
- `Sources/CarRentalOptimizer/MonitorCenterView.swift`: owns the monitor center list, health summary, chart card, event rows, and snapshot rows.
- `Sources/CarRentalOptimizer/CreateMonitorSheet.swift`: owns the create-monitor form content while consuming shared sheet chrome.
- `Sources/CarRentalOptimizer/EhiLoginSheet.swift`: owns the one-hi login web view while consuming shared sheet chrome/status rows.
- `Sources/CarRentalOptimizer/PlatformLoginSheet.swift`: owns the platform login web view while consuming shared sheet chrome/status rows.
- `Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift`: source-contract tests for shared style tokens and components.
- `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`: source-contract tests for page-level adoption of shared UI/effect components.

## Task 1: Shared Design System

**Files:**
- Modify: `Sources/CarRentalOptimizer/WorkbenchStyle.swift`
- Modify: `Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift`

**Interfaces:**
- Consumes: existing `WorkbenchStyle`, `WorkbenchPanel`, `SurfaceBox`, `StatusPill`, `MetricPill`, `EmptyStateBlock`, `subtleDividerOverlay()`.
- Produces:
  - `WorkbenchStyle.commandBlue: Color`
  - `WorkbenchStyle.signalTeal: Color`
  - `WorkbenchStyle.routeGreen: Color`
  - `WorkbenchStyle.amberAlert: Color`
  - `WorkbenchStyle.criticalRed: Color`
  - `WorkbenchStyle.consoleBase: Color`
  - `WorkbenchStyle.panelSurface: Color`
  - `WorkbenchStyle.elevatedSurface: Color`
  - `WorkbenchStyle.hairline: Color`
  - `WorkbenchStyle.cardShadow: Color`
  - `WorkbenchStyle.motionFast: Animation`
  - `WorkbenchStyle.motionStandard: Animation`
  - `WorkbenchStyle.motionSlow: Animation`
  - `enum WorkbenchRailTone`
  - `struct StatusLightRail`
  - `struct WorkbenchBackground`
  - `struct WorkbenchCard<Content: View>`
  - `struct TaskStatusTile`
  - `struct ActionStatusRow`
  - `struct WorkbenchSheetShell<Content: View>`
  - `View.commandCenterTransition(isEnabled:index:)`

- [ ] **Step 1: Extend the shared style tests**

Append these tests to `Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift`:

```swift
@Test("Workbench style exposes command center color tokens")
func workbenchStyleExposesCommandCenterColorTokens() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/WorkbenchStyle.swift", encoding: .utf8)

    #expect(source.contains("static let commandBlue"))
    #expect(source.contains("static let signalTeal"))
    #expect(source.contains("static let routeGreen"))
    #expect(source.contains("static let amberAlert"))
    #expect(source.contains("static let criticalRed"))
    #expect(source.contains("static let consoleBase"))
    #expect(source.contains("static let panelSurface"))
    #expect(source.contains("static let elevatedSurface"))
}

@Test("Workbench style defines reusable surface and motion components")
func workbenchStyleDefinesReusableSurfaceAndMotionComponents() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/WorkbenchStyle.swift", encoding: .utf8)

    #expect(source.contains("enum WorkbenchRailTone"))
    #expect(source.contains("struct StatusLightRail"))
    #expect(source.contains("struct WorkbenchBackground"))
    #expect(source.contains("struct WorkbenchCard"))
    #expect(source.contains("struct TaskStatusTile"))
    #expect(source.contains("struct ActionStatusRow"))
    #expect(source.contains("struct WorkbenchSheetShell"))
    #expect(source.contains("accessibilityReduceMotion"))
    #expect(source.contains("commandCenterTransition"))
}
```

- [ ] **Step 2: Run the focused style tests and verify they fail**

Run:

```bash
swift test --filter WorkbenchStyle
```

Expected: failure because `commandBlue`, `StatusLightRail`, and `commandCenterTransition` are not defined yet.

- [ ] **Step 3: Replace the existing color token block with semantic tokens**

In `Sources/CarRentalOptimizer/WorkbenchStyle.swift`, replace the existing color token declarations from `static let accent` through `static let surface` with this block. The legacy names stay as aliases at the bottom of the block so existing call sites keep compiling:

```swift
static let commandBlue = adaptiveColor(
    light: NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.78, alpha: 1),
    dark: NSColor(calibratedRed: 0.32, green: 0.58, blue: 1.00, alpha: 1)
)
static let signalTeal = adaptiveColor(
    light: NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.56, alpha: 1),
    dark: NSColor(calibratedRed: 0.30, green: 0.86, blue: 0.90, alpha: 1)
)
static let routeGreen = Color(nsColor: .systemGreen)
static let amberAlert = Color(nsColor: .systemOrange)
static let criticalRed = Color(nsColor: .systemRed)
static let consoleBase = adaptiveColor(
    light: NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1),
    dark: NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.075, alpha: 1)
)
static let panelSurface = adaptiveColor(
    light: NSColor(calibratedRed: 0.985, green: 0.99, blue: 1.0, alpha: 1),
    dark: NSColor(calibratedRed: 0.085, green: 0.10, blue: 0.13, alpha: 1)
)
static let elevatedSurface = adaptiveColor(
    light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
    dark: NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.17, alpha: 1)
)
static let hairline = adaptiveColor(
    light: NSColor(calibratedWhite: 0.62, alpha: 0.24),
    dark: NSColor(calibratedWhite: 1.0, alpha: 0.13)
)
static let cardShadow = adaptiveColor(
    light: NSColor(calibratedWhite: 0.18, alpha: 0.10),
    dark: NSColor(calibratedWhite: 0.0, alpha: 0.38)
)
static let glowLine = adaptiveColor(
    light: NSColor(calibratedRed: 0.22, green: 0.58, blue: 1.0, alpha: 0.32),
    dark: NSColor(calibratedRed: 0.28, green: 0.78, blue: 1.0, alpha: 0.50)
)

static let motionFast = Animation.easeOut(duration: 0.16)
static let motionStandard = Animation.easeOut(duration: 0.24)
static let motionSlow = Animation.easeInOut(duration: 0.34)

static let accent = commandBlue
static let teal = signalTeal
static let green = routeGreen
static let orange = amberAlert
static let red = criticalRed
static let line = hairline
static let background = consoleBase
static let panel = panelSurface
static let surface = elevatedSurface
```

- [ ] **Step 4: Add shared components and motion helper**

Add these declarations below `WorkbenchStyle` and before `WorkbenchPanel`:

```swift
enum WorkbenchRailTone {
    case idle
    case active
    case success
    case warning
    case critical

    var color: Color {
        switch self {
        case .idle:
            return WorkbenchStyle.glowLine
        case .active:
            return WorkbenchStyle.commandBlue
        case .success:
            return WorkbenchStyle.routeGreen
        case .warning:
            return WorkbenchStyle.amberAlert
        case .critical:
            return WorkbenchStyle.criticalRed
        }
    }
}

struct StatusLightRail: View {
    let isActive: Bool
    var tone: WorkbenchRailTone = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tone.color.opacity(0.18))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tone.color.opacity(0.10),
                                tone.color.opacity(0.75),
                                tone.color.opacity(0.18),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: isActive && !reduceMotion ? max(84, proxy.size.width * 0.36) : proxy.size.width)
                    .offset(x: isActive && !reduceMotion ? (phase ? proxy.size.width : -proxy.size.width * 0.38) : 0)
            }
        }
        .frame(height: 2)
        .clipped()
        .onAppear {
            guard isActive && !reduceMotion else { return }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                phase = true
            }
        }
        .onChange(of: isActive) { _, active in
            phase = false
            guard active && !reduceMotion else { return }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                phase = true
            }
        }
    }
}

struct WorkbenchBackground: View {
    var body: some View {
        ZStack {
            WorkbenchStyle.consoleBase
            LinearGradient(
                colors: [
                    WorkbenchStyle.commandBlue.opacity(0.08),
                    Color.clear,
                    WorkbenchStyle.signalTeal.opacity(0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct WorkbenchCard<Content: View>: View {
    var fill: Color = WorkbenchStyle.elevatedSurface
    var stroke: Color = WorkbenchStyle.hairline
    var isHighlighted = false
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isHighlighted ? WorkbenchStyle.commandBlue.opacity(0.48) : stroke, lineWidth: isHighlighted ? 1.35 : 1)
                    )
                    .shadow(color: WorkbenchStyle.cardShadow.opacity(isHighlighted ? 0.78 : 0.46), radius: isHighlighted ? 14 : 8, x: 0, y: isHighlighted ? 7 : 3)
            )
    }
}

struct TaskStatusTile: View {
    let title: String
    let value: String
    let icon: String
    var tone: WorkbenchRailTone = .idle

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: tone.color.opacity(0.22), padding: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tone.color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .lineLimit(1)
                    Text(value)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

struct ActionStatusRow: View {
    let icon: String
    let title: String
    let message: String
    var tone: WorkbenchRailTone = .idle

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
    }
}

struct WorkbenchSheetShell<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    var tone: WorkbenchRailTone = .active
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tone.color)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WorkbenchStyle.ink)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(WorkbenchStyle.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                StatusLightRail(isActive: false, tone: tone)
            }
            .background(WorkbenchStyle.panelSurface)

            content
        }
        .background(WorkbenchStyle.panelSurface)
    }
}

private struct CommandCenterTransitionModifier: ViewModifier {
    let isEnabled: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .transition(
                reduceMotion || !isEnabled
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity
                    )
            )
            .animation(
                reduceMotion || !isEnabled
                    ? WorkbenchStyle.motionFast
                    : WorkbenchStyle.motionStandard.delay(Double(index) * 0.035),
                value: isEnabled
            )
    }
}
```

Add this method to the existing `extension View`:

```swift
func commandCenterTransition(isEnabled: Bool = true, index: Int = 0) -> some View {
    modifier(CommandCenterTransitionModifier(isEnabled: isEnabled, index: index))
}
```

- [ ] **Step 5: Route existing status helpers through the new tokens**

In `WorkbenchStyle.statusColor(_:)`, return the new semantic aliases:

```swift
static func statusColor(_ kind: PlatformEvidenceStatusKind) -> Color {
    switch kind {
    case .ready:
        return routeGreen
    case .unavailable:
        return amberAlert
    case .loginRequired, .captchaRequired:
        return amberAlert
    case .parseFailed:
        return criticalRed
    case .waitingForEvidence:
        return muted
    }
}
```

- [ ] **Step 6: Run focused style tests**

Run:

```bash
swift test --filter WorkbenchStyle
```

Expected: all `WorkbenchStyle` tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/CarRentalOptimizer/WorkbenchStyle.swift Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift
git commit -m "Add command center design system"
```

## Task 2: Main Workbench Shell And Top Task Bar

**Files:**
- Modify: `Sources/CarRentalOptimizer/MainView.swift`
- Create: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `WorkbenchBackground`, `StatusLightRail`, `TaskStatusTile`, `WorkbenchStyle.commandBlue`, `WorkbenchStyle.signalTeal`, `WorkbenchStyle.routeGreen`, `WorkbenchStyle.amberAlert`.
- Produces: the main shell using the shared command-center background and a status rail driven by `viewModel.isSearching`.

- [ ] **Step 1: Add source-contract tests for the main shell**

Create `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`:

```swift
import Foundation
import Testing

@Suite("UI effects source contracts")
struct UIEffectsSourceTests {
    @Test("Main view uses command center shell components")
    func mainViewUsesCommandCenterShellComponents() throws {
        let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/MainView.swift", encoding: .utf8)

        #expect(source.contains("WorkbenchBackground()"))
        #expect(source.contains("StatusLightRail(isActive: viewModel.isSearching"))
        #expect(source.contains("TaskStatusTile("))
        #expect(source.contains("tone: .active"))
        #expect(source.contains("tone: .success"))
        #expect(source.contains("tone: .warning"))
    }
}
```

- [ ] **Step 2: Run the main shell test and verify it fails**

Run:

```bash
swift test --filter "Main view uses command center shell components"
```

Expected: failure because `MainView.swift` has not adopted these components.

- [ ] **Step 3: Add the command background to `MainView`**

Replace the outer `VStack` body in `MainView.body` with this structure:

```swift
ZStack {
    WorkbenchBackground()

    VStack(spacing: 0) {
        WorkbenchHeader {
            showingMonitorCenter = true
        }

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
```

Keep the existing `.sheet` and `.onReceive` modifiers attached to this `ZStack`.

- [ ] **Step 4: Upgrade `WorkbenchHeader` to a task status bar**

Inside `WorkbenchHeader.body`, wrap the header in a `VStack(spacing: 0)` and replace the three `HeaderMetric` calls with `TaskStatusTile`:

```swift
VStack(spacing: 0) {
    HStack(alignment: .center, spacing: 18) {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [WorkbenchStyle.commandBlue, WorkbenchStyle.signalTeal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "car.side.front.open")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppInfo.appName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WorkbenchStyle.ink)
                Text("Car rental optimizer · v\(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(WorkbenchStyle.muted)
            }
        }

        Spacer(minLength: 18)

        TaskStatusTile(
            title: "上次搜索",
            value: lastSuccessfulSearch,
            icon: "clock.badge.checkmark",
            tone: viewModel.lastSuccessfulSearchAt == nil ? .idle : .success
        )

        TaskStatusTile(
            title: "当前推荐",
            value: selectedTotal,
            icon: "yensign.circle",
            tone: viewModel.selected == nil ? .idle : .active
        )

        TaskStatusTile(
            title: "监控状态",
            value: monitorHealthValue,
            icon: "bell.badge",
            tone: monitorViewModel.healthSummary.needsAttentionCount > 0 ? .warning : .success
        )

        Button {
            onOpenMonitorCenter()
        } label: {
            Label("监控中心", systemImage: "bell.badge")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        StatusPill(
            text: viewModel.isSearching ? "查询中" : "真实 API",
            color: viewModel.isSearching ? WorkbenchStyle.amberAlert : WorkbenchStyle.commandBlue,
            systemImage: viewModel.isSearching ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle.fill"
        )

        StatusPill(
            text: monitorViewModel.backgroundMonitoringEnabled ? "后台巡查" : "手动巡查",
            color: monitorViewModel.backgroundMonitoringEnabled ? WorkbenchStyle.routeGreen : WorkbenchStyle.muted,
            systemImage: monitorViewModel.backgroundMonitoringEnabled ? "checkmark.circle.fill" : "pause.circle"
        )
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 14)

    StatusLightRail(isActive: viewModel.isSearching, tone: viewModel.isSearching ? .active : .idle)
}
.background(WorkbenchStyle.panelSurface)
```

- [ ] **Step 5: Remove the old `HeaderMetric` struct**

Delete the private `HeaderMetric` struct from `MainView.swift`; `TaskStatusTile` now owns that role.

- [ ] **Step 6: Run the main shell test**

Run:

```bash
swift test --filter "Main view uses command center shell components"
```

Expected: PASS.

- [ ] **Step 7: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add Sources/CarRentalOptimizer/MainView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "Upgrade main workbench shell"
```

## Task 3: Query Console Upgrade

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `WorkbenchCard`, `StatusLightRail`, `ActionStatusRow`, `WorkbenchStyle.commandBlue`, `WorkbenchStyle.signalTeal`, `WorkbenchStyle.amberAlert`, `WorkbenchStyle.routeGreen`, `View.commandCenterTransition(isEnabled:index:)`.
- Produces:
  - `private struct QueryConsoleSection<Content: View>`
  - `private struct PlatformSignalToggleButton`
  - `private struct CompareCommandButton`
  - upgraded preflight issue and suggestion surfaces.

- [ ] **Step 1: Add source-contract tests for the query console**

Append this test to `UIEffectsSourceTests`:

```swift
@Test("Search panel uses command console components")
func searchPanelUsesCommandConsoleComponents() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/SearchPanelView.swift", encoding: .utf8)

    #expect(source.contains("QueryConsoleSection"))
    #expect(source.contains("PlatformSignalToggleButton"))
    #expect(source.contains("CompareCommandButton"))
    #expect(source.contains("ActionStatusRow("))
    #expect(source.contains("StatusLightRail(isActive: viewModel.isSearching"))
    #expect(source.contains("WorkbenchCard("))
}
```

- [ ] **Step 2: Run the query console test and verify it fails**

Run:

```bash
swift test --filter "Search panel uses command console components"
```

Expected: failure because the new query console component names are not present.

- [ ] **Step 3: Use the status rail above the compare button**

In `SearchPanelView.body`, inside the bottom area above `compareButton`, insert:

```swift
StatusLightRail(
    isActive: viewModel.isSearching,
    tone: viewModel.hasBlockingPreflightIssues ? .warning : .active
)
.padding(.horizontal, 16)
.padding(.top, 12)
```

Then keep `compareButton.padding(16).background(WorkbenchStyle.panelSurface)`.

- [ ] **Step 4: Replace query section chrome**

Rename `QuerySection` to `QueryConsoleSection` and update its body to use `WorkbenchCard`:

```swift
private struct QueryConsoleSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: WorkbenchStyle.hairline, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(WorkbenchStyle.signalTeal)
                        .frame(width: 18)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchStyle.ink)
                    Spacer()
                }

                content
            }
        }
    }
}
```

Replace every `QuerySection(` call with `QueryConsoleSection(`.

- [ ] **Step 5: Upgrade preflight issue rows**

Replace the row content inside `PreflightIssueList` with `ActionStatusRow`:

```swift
ForEach(issues) { issue in
    ActionStatusRow(
        icon: issue.severity == .blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
        title: issue.title,
        message: issue.message,
        tone: issue.severity == .blocking ? .critical : .warning
    )
}
```

- [ ] **Step 6: Rename and upgrade the compare button component**

Rename `private var compareButton` to `private var compareButton: some View { CompareCommandButton(...) }` and add this component:

```swift
private struct CompareCommandButton: View {
    let isSearching: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Spacer()
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                    Text("查询中...")
                } else {
                    Image(systemName: "magnifyingglass")
                    Text("开始比较")
                }
                Spacer()
            }
            .font(.headline.weight(.semibold))
            .frame(minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(WorkbenchStyle.commandBlue)
        .disabled(isDisabled)
        .animation(WorkbenchStyle.motionFast, value: isSearching)
    }
}
```

Use it from `compareButton`:

```swift
private var compareButton: some View {
    CompareCommandButton(
        isSearching: viewModel.isSearching,
        isDisabled: viewModel.isSearching || viewModel.hasBlockingPreflightIssues
    ) {
        dismissOriginInput()
        Task { await viewModel.runSearch() }
    }
}
```

- [ ] **Step 7: Upgrade platform toggles with signal chrome**

Rename `PlatformToggleButton` to `PlatformSignalToggleButton`. Keep the same initializer and action behavior, then make the selected background use `WorkbenchCard` semantics:

```swift
.background(
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isSelected ? WorkbenchStyle.commandBlue.opacity(0.12) : WorkbenchStyle.quietFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? WorkbenchStyle.commandBlue.opacity(0.46) : WorkbenchStyle.hairline, lineWidth: 1)
        )
)
```

Replace every `PlatformToggleButton(` call with `PlatformSignalToggleButton(`.

- [ ] **Step 8: Upgrade the address suggestion dropdown surface**

In `OriginSuggestionDropdown.body`, replace the manual rounded background, overlay, and shadow with:

```swift
.background(
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(WorkbenchStyle.elevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WorkbenchStyle.commandBlue.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: WorkbenchStyle.cardShadow.opacity(0.62), radius: 14, x: 0, y: 8)
)
```

- [ ] **Step 9: Run the query console test**

Run:

```bash
swift test --filter "Search panel uses command console components"
```

Expected: PASS.

- [ ] **Step 10: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 11: Commit**

```bash
git add Sources/CarRentalOptimizer/SearchPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "Upgrade query console styling"
```

## Task 4: Candidate Results And Search States

**Files:**
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `WorkbenchCard`, `StatusLightRail`, `ActionStatusRow`, `View.commandCenterTransition(isEnabled:index:)`, existing `SearchProgressPhase`, existing `QuoteCredibility`.
- Produces:
  - `private struct StagedSearchLoadingCard`
  - `private struct ResultSignalCard`
  - upgraded recovery and filter surfaces using shared cards.

- [ ] **Step 1: Add source-contract tests for candidate results**

Append this test to `UIEffectsSourceTests`:

```swift
@Test("Result panel uses signal cards and staged loading")
func resultPanelUsesSignalCardsAndStagedLoading() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/ResultPanelView.swift", encoding: .utf8)

    #expect(source.contains("StagedSearchLoadingCard"))
    #expect(source.contains("ResultSignalCard"))
    #expect(source.contains("commandCenterTransition(isEnabled: true, index: index)"))
    #expect(source.contains("StatusLightRail(isActive: true"))
    #expect(source.contains("ActionStatusRow("))
    #expect(source.contains("WorkbenchCard("))
}
```

- [ ] **Step 2: Run the candidate result test and verify it fails**

Run:

```bash
swift test --filter "Result panel uses signal cards and staged loading"
```

Expected: failure because the new component names are not present.

- [ ] **Step 3: Replace the loading view with a staged loading card**

Rename `LoadingResultsView` to `StagedSearchLoadingCard` and use this body:

```swift
var body: some View {
    VStack(spacing: 16) {
        Spacer()
        WorkbenchCard(fill: WorkbenchStyle.panelSurface, stroke: WorkbenchStyle.commandBlue.opacity(0.24), padding: 18) {
            VStack(spacing: 12) {
                StatusLightRail(isActive: true, tone: .active)
                    .frame(width: 240)
                ProgressView()
                    .controlSize(.large)
                Text(phase.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.ink)
                Text(phase.message)
                    .font(.callout)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 320)
        }
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
}
```

Update the call site from `LoadingResultsView(phase:)` to `StagedSearchLoadingCard(phase:)`.

- [ ] **Step 4: Upgrade recovery suggestions to shared status rows**

In `RecoverySuggestionList`, replace each manual recovery row with:

```swift
ActionStatusRow(
    icon: action.systemImage,
    title: action.title,
    message: action.message,
    tone: .active
)
```

- [ ] **Step 5: Rename result rows to signal cards**

Rename `ResultRowView` to `ResultSignalCard`. Update the call site:

```swift
ResultSignalCard(
    rank: index + 1,
    recommendation: result,
    isSelected: viewModel.selected?.id == result.id
) {
    viewModel.selectResult(result.id)
    pendingMonitorRecommendation = result
}
.contentShape(Rectangle())
.commandCenterTransition(isEnabled: true, index: index)
.onTapGesture {
    viewModel.selectResult(result.id)
}
```

- [ ] **Step 6: Upgrade the result card surface**

In `ResultSignalCard.body`, replace the outer `SurfaceBox` with:

```swift
WorkbenchCard(
    fill: isSelected ? WorkbenchStyle.commandBlue.opacity(0.11) : WorkbenchStyle.elevatedSurface,
    stroke: isSelected ? WorkbenchStyle.commandBlue.opacity(0.48) : WorkbenchStyle.hairline,
    isHighlighted: isSelected,
    padding: 0
) {
    VStack(alignment: .leading, spacing: 12) {
        cardHeader
        cardMetrics
        Text(rankingReason)
            .font(.caption2)
            .foregroundStyle(WorkbenchStyle.muted)
            .lineLimit(1)
        QuoteCredibilityBadge(credibility: QuoteCredibility.make(for: recommendation))
    }
    .padding(14)
}
.scaleEffect(isSelected ? 1.006 : 1.0)
.animation(WorkbenchStyle.motionFast, value: isSelected)
.accessibilityLabel(accessibilitySummary)
```

Extract the existing first `HStack` into `private var cardHeader: some View` and the metrics `HStack` into `private var cardMetrics: some View`. The extracted code must preserve the existing labels and button action.

- [ ] **Step 7: Upgrade rank badge color**

In `rankBadge`, change the fill and text colors:

```swift
.foregroundStyle(isSelected ? .white : WorkbenchStyle.commandBlue)
```

and:

```swift
.fill(isSelected ? WorkbenchStyle.commandBlue : WorkbenchStyle.commandBlue.opacity(0.13))
```

- [ ] **Step 8: Run the candidate result test**

Run:

```bash
swift test --filter "Result panel uses signal cards and staged loading"
```

Expected: PASS.

- [ ] **Step 9: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 10: Commit**

```bash
git add Sources/CarRentalOptimizer/ResultPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "Upgrade candidate result signal cards"
```

## Task 5: Decision Receipt Detail Panel

**Files:**
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `WorkbenchCard`, `TaskStatusTile`, `ActionStatusRow`, `WorkbenchStyle.commandBlue`, `WorkbenchStyle.signalTeal`, `WorkbenchStyle.routeGreen`, existing `Recommendation` and `RouteEstimate`.
- Produces:
  - `private struct DecisionReceiptHeader`
  - `private struct RouteDecisionCard`
  - `private struct ReceiptActionBar`

- [ ] **Step 1: Add source-contract tests for the decision receipt**

Append this test to `UIEffectsSourceTests`:

```swift
@Test("Detail panel uses decision receipt components")
func detailPanelUsesDecisionReceiptComponents() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/DetailPanelView.swift", encoding: .utf8)

    #expect(source.contains("DecisionReceiptHeader"))
    #expect(source.contains("RouteDecisionCard"))
    #expect(source.contains("ReceiptActionBar"))
    #expect(source.contains("TaskStatusTile("))
    #expect(source.contains("WorkbenchCard("))
    #expect(source.contains("ActionStatusRow("))
}
```

- [ ] **Step 2: Run the decision receipt test and verify it fails**

Run:

```bash
swift test --filter "Detail panel uses decision receipt components"
```

Expected: failure because the new component names are not present.

- [ ] **Step 3: Rename the total header**

Rename `TotalReceiptHeader` to `DecisionReceiptHeader` and update its call site.

Inside the header, replace `SurfaceBox` with:

```swift
WorkbenchCard(
    fill: WorkbenchStyle.commandBlue.opacity(0.12),
    stroke: WorkbenchStyle.commandBlue.opacity(0.28),
    isHighlighted: true,
    padding: 16
) {
    VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center) {
            StatusPill(
                text: recommendation.listing.platform.label,
                color: recommendation.listing.platform == .ehi ? WorkbenchStyle.signalTeal : WorkbenchStyle.commandBlue,
                systemImage: "building.2.fill"
            )
            Spacer()
            StatusPill(
                text: recommendation.bestRouteMode.label,
                color: WorkbenchStyle.routeGreen,
                systemImage: recommendation.bestRouteMode == .taxi ? "car.fill" : "bus.fill"
            )
        }

        VStack(alignment: .leading, spacing: 3) {
            Text("推荐总成本")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.muted)
            Text(formatMoney(recommendation.bestTotal))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(WorkbenchStyle.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("租车 \(formatMoney(recommendation.rentalTotal)) + 到店 \(formatMoney(bestRouteCost))")
                .font(.caption)
                .foregroundStyle(WorkbenchStyle.muted)
                .lineLimit(1)
        }
    }
}
```

- [ ] **Step 4: Use status tiles for the receipt facts**

Under `DecisionReceiptHeader`, add a compact tile row:

```swift
HStack(spacing: 8) {
    TaskStatusTile(title: "租车小计", value: formatMoney(recommendation.rentalTotal), icon: "car.fill", tone: .active)
    TaskStatusTile(title: "到店成本", value: formatMoney(bestRouteCost), icon: recommendation.bestRouteMode == .taxi ? "car.side" : "bus.fill", tone: .success)
}
```

Add this `bestRouteCost` helper to `RecommendationDetailView`:

```swift
private var bestRouteCost: Double {
    recommendation.bestRouteMode == .taxi ? recommendation.taxiRoute.cost : recommendation.transitRoute.cost
}
```

- [ ] **Step 5: Rename route boxes**

Rename `RouteBoxView` to `RouteDecisionCard` and update both call sites. Replace its outer `SurfaceBox` with:

```swift
WorkbenchCard(
    fill: isBest ? WorkbenchStyle.routeGreen.opacity(0.10) : WorkbenchStyle.elevatedSurface,
    stroke: isBest ? WorkbenchStyle.routeGreen.opacity(0.34) : WorkbenchStyle.hairline,
    isHighlighted: isBest,
    padding: 11
) {
    VStack(alignment: .leading, spacing: 7) {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchStyle.ink)
            Spacer()
            if isBest {
                Text("推荐")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkbenchStyle.routeGreen)
            }
        }

        Text(formatMoney(total))
            .font(.headline.weight(.bold))
            .foregroundStyle(WorkbenchStyle.ink)
            .monospacedDigit()

        VStack(alignment: .leading, spacing: 3) {
            Text(route.summary)
            Text("\(Int(route.durationMinutes.rounded())) 分钟 · \(route.distanceKm, specifier: "%.1f") km")
        }
        .font(.caption2)
        .foregroundStyle(WorkbenchStyle.muted)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

- [ ] **Step 6: Convert warnings to shared status rows**

In `WarningBox.body`, replace the manual icon/text row with:

```swift
ActionStatusRow(
    icon: "exclamationmark.triangle.fill",
    title: "提醒",
    message: renderWarnings(warnings),
    tone: .warning
)
```

- [ ] **Step 7: Extract receipt actions**

Replace the monitor and source link buttons in `RecommendationDetailView` with:

```swift
ReceiptActionBar(
    sourceURL: URL(string: recommendation.listing.sourceUrl),
    onMonitor: onMonitor
)
```

Add this component near the bottom of `DetailPanelView.swift`:

```swift
private struct ReceiptActionBar: View {
    let sourceURL: URL?
    let onMonitor: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button {
                onMonitor()
            } label: {
                HStack(spacing: 6) {
                    Spacer()
                    Text("监控这个方案")
                    Image(systemName: "bell.badge")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(WorkbenchStyle.commandBlue)

            if let sourceURL {
                Link(destination: sourceURL) {
                    HStack(spacing: 6) {
                        Spacer()
                        Text("打开原始平台")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
```

- [ ] **Step 8: Run the decision receipt test**

Run:

```bash
swift test --filter "Detail panel uses decision receipt components"
```

Expected: PASS.

- [ ] **Step 9: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 10: Commit**

```bash
git add Sources/CarRentalOptimizer/DetailPanelView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "Upgrade recommendation decision receipt"
```

## Task 6: Monitor Center Command Styling

**Files:**
- Modify: `Sources/CarRentalOptimizer/MonitorCenterView.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `WorkbenchBackground`, `WorkbenchCard`, `ActionStatusRow`, `TaskStatusTile`, existing `MonitorHealthSummary`, `PriceMonitor`, `PriceSnapshot`, `PriceMonitorEvent`.
- Produces:
  - `private struct MonitorCommandSurface<Content: View>`
  - `private struct MonitorEventPulseRow`
  - upgraded health strip, trend chart container, event list, and snapshot table.

- [ ] **Step 1: Add source-contract tests for monitor center**

Append this test to `UIEffectsSourceTests`:

```swift
@Test("Monitor center uses command surfaces")
func monitorCenterUsesCommandSurfaces() throws {
    let source = try String(contentsOfFile: "Sources/CarRentalOptimizer/MonitorCenterView.swift", encoding: .utf8)

    #expect(source.contains("MonitorCommandSurface"))
    #expect(source.contains("MonitorEventPulseRow"))
    #expect(source.contains("TaskStatusTile("))
    #expect(source.contains("ActionStatusRow("))
    #expect(source.contains("WorkbenchCard("))
}
```

- [ ] **Step 2: Run the monitor center test and verify it fails**

Run:

```bash
swift test --filter "Monitor center uses command surfaces"
```

Expected: failure because monitor center still uses the older surface composition.

- [ ] **Step 3: Add monitor command surface wrapper**

Add this component near the other private monitor components:

```swift
private struct MonitorCommandSurface<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder let content: Content

    var body: some View {
        WorkbenchCard(fill: WorkbenchStyle.elevatedSurface, stroke: WorkbenchStyle.hairline, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                MonitorSectionTitleRow(icon: icon, title: title)
                content
            }
        }
    }
}
```

- [ ] **Step 4: Upgrade the health strip to status tiles**

In `MonitorHealthStrip.body`, replace `SurfaceBox` with `WorkbenchCard` and use `TaskStatusTile`:

```swift
WorkbenchCard(fill: WorkbenchStyle.panelSurface, padding: 10) {
    HStack(spacing: 8) {
        TaskStatusTile(title: "总数", value: "\(summary.totalCount)", icon: "number", tone: .idle)
        TaskStatusTile(title: "需处理", value: "\(summary.needsAttentionCount)", icon: "exclamationmark.triangle.fill", tone: summary.needsAttentionCount > 0 ? .warning : .idle)
        TaskStatusTile(title: "降价", value: "\(summary.recentPriceDropCount)", icon: "arrow.down.circle.fill", tone: summary.recentPriceDropCount > 0 ? .success : .idle)
        TaskStatusTile(title: "今日", value: "\(summary.dueTodayCount)", icon: "calendar.badge.clock", tone: .active)
    }
}
```

- [ ] **Step 5: Upgrade monitor summary box**

In `MonitorSummaryBox.body`, replace `SurfaceBox(fill: WorkbenchStyle.accentSoft)` with:

```swift
WorkbenchCard(fill: WorkbenchStyle.commandBlue.opacity(0.10), stroke: WorkbenchStyle.commandBlue.opacity(0.22), padding: 12) {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
        MetricPill(title: "最近租车价", value: trend.latestPlatformRentalPrice.map(formatMoney) ?? "--")
        MetricPill(
            title: "相比上次",
            value: formatSignedMoney(trend.platformRentalDelta),
            color: (trend.platformRentalDelta ?? 0) < 0 ? WorkbenchStyle.routeGreen : WorkbenchStyle.muted
        )
        MetricPill(
            title: "下次巡查",
            value: monitor.nextCheckAt.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "--"
        )
        MetricPill(title: "历史低点", value: trend.lowestPlatformRentalPrice.map(formatMoney) ?? "--", color: WorkbenchStyle.routeGreen)
        MetricPill(title: "历史高点", value: trend.highestPlatformRentalPrice.map(formatMoney) ?? "--")
        MetricPill(
            title: "首次至今",
            value: formatSignedMoney(trend.platformRentalDeltaFromFirst),
            color: (trend.platformRentalDeltaFromFirst ?? 0) < 0 ? WorkbenchStyle.routeGreen : WorkbenchStyle.muted
        )
    }
}
```

- [ ] **Step 6: Wrap chart, events, and snapshots in command surfaces**

In `MonitorTrendChart.body`, replace the outer `SurfaceBox` with:

```swift
MonitorCommandSurface(title: "价格趋势", icon: "chart.xyaxis.line") {
    Chart {
        ForEach(points) { snapshot in
            if let price = snapshot.platformRentalPrice {
                LineMark(x: .value("时间", snapshot.checkedAt), y: .value("价格", price))
                    .foregroundStyle(by: .value("口径", "平台租车价"))
            }
            if let total = snapshot.recommendationTotalCost {
                LineMark(x: .value("时间", snapshot.checkedAt), y: .value("价格", total))
                    .foregroundStyle(by: .value("口径", "推荐总成本"))
            }
        }
    }
    .chartLegend(position: .bottom)
}
```

In `MonitorEventList.body`, replace the outer `SurfaceBox` with `MonitorCommandSurface(title: "事件", icon: "bell.badge")`.

In `MonitorSnapshotTable.body`, replace the outer `SurfaceBox` with `MonitorCommandSurface(title: "历史快照", icon: "chart.line.uptrend.xyaxis")`.

- [ ] **Step 7: Add event pulse rows**

Replace the event row body in `MonitorEventList` with:

```swift
MonitorEventPulseRow(event: event)
```

Add this component:

```swift
private struct MonitorEventPulseRow: View {
    let event: PriceMonitorEvent

    var body: some View {
        ActionStatusRow(
            icon: event.kind == .priceDrop ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill",
            title: event.kind == .priceDrop ? "价格下降" : "监控异常",
            message: event.message,
            tone: event.kind == .priceDrop ? .success : .warning
        )
        .commandCenterTransition(isEnabled: true, index: 0)
    }
}
```

- [ ] **Step 8: Run the monitor center test**

Run:

```bash
swift test --filter "Monitor center uses command surfaces"
```

Expected: PASS.

- [ ] **Step 9: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 10: Commit**

```bash
git add Sources/CarRentalOptimizer/MonitorCenterView.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "Upgrade monitor center command styling"
```

## Task 7: Sheet And Login Chrome

**Files:**
- Modify: `Sources/CarRentalOptimizer/CreateMonitorSheet.swift`
- Modify: `Sources/CarRentalOptimizer/EhiLoginSheet.swift`
- Modify: `Sources/CarRentalOptimizer/PlatformLoginSheet.swift`
- Modify: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `WorkbenchSheetShell`, `WorkbenchCard`, `ActionStatusRow`, `WorkbenchStyle.commandBlue`, `WorkbenchStyle.amberAlert`.
- Produces: consistent sheet headers and status rows across create-monitor, one-hi login, and platform login flows.

- [ ] **Step 1: Add source-contract tests for sheets**

Append this test to `UIEffectsSourceTests`:

```swift
@Test("Sheets use shared workbench chrome")
func sheetsUseSharedWorkbenchChrome() throws {
    let createMonitor = try String(contentsOfFile: "Sources/CarRentalOptimizer/CreateMonitorSheet.swift", encoding: .utf8)
    let ehi = try String(contentsOfFile: "Sources/CarRentalOptimizer/EhiLoginSheet.swift", encoding: .utf8)
    let platform = try String(contentsOfFile: "Sources/CarRentalOptimizer/PlatformLoginSheet.swift", encoding: .utf8)

    #expect(createMonitor.contains("WorkbenchSheetShell("))
    #expect(createMonitor.contains("WorkbenchCard("))
    #expect(createMonitor.contains("ActionStatusRow("))
    #expect(ehi.contains("WorkbenchSheetShell("))
    #expect(ehi.contains("ActionStatusRow("))
    #expect(platform.contains("WorkbenchSheetShell("))
    #expect(platform.contains("ActionStatusRow("))
}
```

- [ ] **Step 2: Run the sheet chrome test and verify it fails**

Run:

```bash
swift test --filter "Sheets use shared workbench chrome"
```

Expected: failure because sheets still use local header chrome.

- [ ] **Step 3: Wrap create-monitor content in shared shell**

Replace `CreateMonitorSheet.body` with:

```swift
WorkbenchSheetShell(
    title: recommendation == nil ? "新建价格监控" : "监控这个方案",
    subtitle: recommendation == nil ? "手动配置巡查条件" : "保存当前报价并持续巡查",
    icon: "bell.badge",
    tone: .active
) {
    VStack(alignment: .leading, spacing: 16) {
        summary
        controls

        if let errorMessage {
            ActionStatusRow(
                icon: "xmark.octagon.fill",
                title: "保存失败",
                message: errorMessage,
                tone: .critical
            )
        }

        HStack {
            Spacer()
            Button("取消") { dismiss() }
            Button("保存监控") {
                Task { await save() }
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkbenchStyle.commandBlue)
        }
    }
    .padding(20)
}
.frame(width: 460)
.onAppear {
    name = recommendation.map { "\($0.listing.vehicleName) \(request.pickupAt)" } ?? "租车价格监控"
    vehicleQuery = recommendation?.listing.vehicleName ?? request.vehicleQuery
}
```

- [ ] **Step 4: Upgrade create-monitor summary**

In `CreateMonitorSheet.summary`, replace `SurfaceBox` with:

```swift
WorkbenchCard(fill: WorkbenchStyle.elevatedSurface, padding: 12) {
    VStack(alignment: .leading, spacing: 8) {
        MonitorSheetFactLine(icon: "calendar", text: "\(request.pickupAt) 至 \(request.returnAt)")
        MonitorSheetFactLine(icon: "mappin.circle.fill", text: request.originLabel)
        MonitorSheetFactLine(icon: "car.fill", text: vehicleQuery.isEmpty ? "未指定车型" : vehicleQuery)
        if let recommendation {
            MonitorSheetFactLine(icon: "yensign.circle", text: "租车价 \(formatMoney(recommendation.rentalTotal)) · 总成本 \(formatMoney(recommendation.bestTotal))")
            MonitorSheetFactLine(icon: "building.2.fill", text: "\(recommendation.listing.platform.label) · \(recommendation.listing.store.name)")
        }
    }
}
```

- [ ] **Step 5: Wrap one-hi login in shared shell**

In `EhiLoginSheet.body`, replace the top header `HStack` block with:

```swift
WorkbenchSheetShell(
    title: pageTitle.isEmpty ? "一嗨登录" : pageTitle,
    subtitle: currentURL,
    icon: "person.badge.key.fill",
    tone: .active
) {
    VStack(spacing: 0) {
        HStack {
            Spacer()
            Button {
                captchaWarning = nil
                reloadToken += 1
            } label: {
                Label("刷新登录页", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button("取消") {
                dismiss()
            }
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
            .tint(WorkbenchStyle.commandBlue)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(WorkbenchStyle.panelSurface)
        .subtleDividerOverlay()

        captchaWarningView

        EhiLoginWebView(
            pageTitle: $pageTitle,
            currentURL: $currentURL,
            captchaWarning: $captchaWarning,
            reloadToken: reloadToken,
            resetToken: resetToken
        )
        .frame(minWidth: 760, minHeight: 620)
    }
}
.frame(minWidth: 760, minHeight: 680)
```

Extract the existing captcha warning block into:

```swift
@ViewBuilder
private var captchaWarningView: some View {
    if let captchaWarning {
        HStack(alignment: .top, spacing: 10) {
            ActionStatusRow(
                icon: "exclamationmark.triangle.fill",
                title: captchaWarning,
                message: "已停止自动刷新登录页，避免打断验证码输入。先点「刷新登录页」重新获取验证码，仍异常再重置验证状态。",
                tone: .warning
            )
            Button("重置验证状态") {
                self.captchaWarning = nil
                resetToken += 1
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(WorkbenchStyle.amberAlert.opacity(0.10))
        .subtleDividerOverlay()
    }
}
```

- [ ] **Step 6: Wrap platform login in shared shell**

In `PlatformLoginSheet.body`, replace the top header `HStack` block with a `WorkbenchSheetShell` and retain the platform-specific segmented picker in the action row:

```swift
WorkbenchSheetShell(
    title: pageTitle.isEmpty ? "\(platform.label)登录" : pageTitle,
    subtitle: currentURL,
    icon: "person.badge.key.fill",
    tone: .active
) {
    VStack(spacing: 0) {
        HStack {
            if platform == .carInc {
                Picker("神州登录方式", selection: $zucheLoginMode) {
                    ForEach(ZucheLoginMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 226)
                .help("默认使用神州官网登录；如果官网登录异常，可切换到移动端短信或密码登录页。")
            }

            Spacer()

            Button {
                reloadToken += 1
            } label: {
                Label("刷新登录页", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button("取消") {
                dismiss()
            }
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
            .tint(WorkbenchStyle.commandBlue)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(WorkbenchStyle.panelSurface)
        .subtleDividerOverlay()

        ActionStatusRow(
            icon: "yensign.circle.fill",
            title: "费用补全",
            message: "神州基础服务费来自官方确认页费用接口；登录后点击完成，程序会重新比较并补全这部分费用。",
            tone: .active
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(WorkbenchStyle.commandBlue.opacity(0.08))
        .subtleDividerOverlay()

        PlatformLoginWebView(
            platform: platform,
            pageTitle: $pageTitle,
            currentURL: $currentURL,
            zucheLoginMode: zucheLoginMode,
            reloadToken: reloadToken
        )
        .frame(minWidth: 760, minHeight: 620)
    }
}
.frame(minWidth: 760, minHeight: 680)
```

Keep the existing `.onChange(of: zucheLoginMode)` modifier attached to this shell.

- [ ] **Step 7: Run the sheet chrome test**

Run:

```bash
swift test --filter "Sheets use shared workbench chrome"
```

Expected: PASS.

- [ ] **Step 8: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 9: Commit**

```bash
git add Sources/CarRentalOptimizer/CreateMonitorSheet.swift Sources/CarRentalOptimizer/EhiLoginSheet.swift Sources/CarRentalOptimizer/PlatformLoginSheet.swift Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
git commit -m "Unify sheet command chrome"
```

## Task 8: Final Verification And Visual QA

**Files:**
- Modify only if a previous task introduced a compile or visual regression.

**Interfaces:**
- Consumes: all components and page updates from Tasks 1-7.
- Produces: verified UI-only upgrade with passing tests and launch smoke evidence when the local environment can build the app bundle.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Run the debug build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Build the app bundle**

Run:

```bash
scripts/build-app.sh
```

Expected: script completes and verifies `build/租车比价助手.app`.

- [ ] **Step 4: Launch smoke test**

Run:

```bash
scripts/verify-launch.sh build/租车比价助手.app
```

Expected: script completes without reporting a launch failure.

- [ ] **Step 5: Manual visual check**

Launch the app and check these states:

```text
Main workbench:
- Header task status bar shows app name, last search, selected total, monitor status, API status, and background monitoring status.
- Search panel groups remain readable at the minimum 1280 x 760 window size.
- Result loading state shows the status rail and current search phase.
- Result cards show rank, platform, vehicle, total cost, route costs, and credibility without overlap.
- Selecting a result highlights the card and keeps the decision receipt readable.

Monitor center:
- Health strip uses the same tile language as the main header.
- Trend chart remains readable and the legend is visible.
- Event and snapshot cards do not overlap at the 920 x 620 sheet minimum.

Sheets:
- Create monitor sheet uses the shared shell and shows errors as status rows.
- One-hi login sheet keeps web content visible and captcha warning is readable.
- Platform login sheet keeps the login-mode picker visible and the fee-completion status row readable.
```

Expected: every listed item is true.

- [ ] **Step 6: Check UI-only scope**

Run:

```bash
BASE_COMMIT=$(git log --format=%H --grep="Add UI effects upgrade implementation plan" -1)
git diff --name-only "${BASE_COMMIT}..HEAD"
```

Expected: changed files are limited to:

```text
Sources/CarRentalOptimizer/WorkbenchStyle.swift
Sources/CarRentalOptimizer/MainView.swift
Sources/CarRentalOptimizer/SearchPanelView.swift
Sources/CarRentalOptimizer/ResultPanelView.swift
Sources/CarRentalOptimizer/DetailPanelView.swift
Sources/CarRentalOptimizer/MonitorCenterView.swift
Sources/CarRentalOptimizer/CreateMonitorSheet.swift
Sources/CarRentalOptimizer/EhiLoginSheet.swift
Sources/CarRentalOptimizer/PlatformLoginSheet.swift
Tests/CarRentalOptimizerTests/WorkbenchStyleTests.swift
Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift
```

- [ ] **Step 7: Commit visual QA fixes if any were needed**

If Step 5 required UI corrections, commit those corrections:

```bash
git add Sources/CarRentalOptimizer Tests/CarRentalOptimizerTests
git commit -m "Polish UI effects upgrade"
```

If Step 5 required no corrections, do not create an empty commit.
