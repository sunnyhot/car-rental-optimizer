# Remaining Optimizations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Finish the remaining roadmap enhancements across price monitoring productization and desktop workflow integration before the local commit history is consolidated.

**Architecture:** Keep monitor filtering, sorting, repeated-failure detection, recovery detection, trend summary, and monitored-recommendation explanation in deterministic `CarRentalDomain` helpers. Expose derived monitor state, filters, and batch actions from `MonitorCenterViewModel`; render them with the existing three-column workbench components and compact macOS controls.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, XCTest, Swift Package Manager.

---

## File Structure

- Modify `Sources/CarRentalDomain/PriceMonitoring.swift`
  - Add monitor center filters, attention sorting, health summary, expanded trend summary, and monitor event derivation helpers.
- Modify `Sources/CarRentalDomain/PriceMonitorMatching.swift`
  - Add monitored recommendation selection explanations while preserving the existing selection API.
- Modify `Sources/CarRentalOptimizer/MonitorCenterViewModel.swift`
  - Load per-monitor snapshots/events, expose displayed monitors, health summary, filter counts, feedback text, and batch pause/resume/run actions.
- Modify `Sources/CarRentalOptimizer/MonitorCenterView.swift`
  - Add filters, health summary, attention-first list, richer trend summary, batch actions, recovery feedback, and accessibility labels.
- Modify `Sources/CarRentalOptimizer/MainView.swift`
  - Surface monitoring health and latest successful search state in the compact header.
- Modify `Sources/CarRentalOptimizer/App.swift` and `Sources/CarRentalOptimizer/AppPresentation.swift`
  - Add stable notification names and keyboard command wiring for retry search and run due monitor checks.
- Modify `Tests/CarRentalDomainTests/PriceMonitoringTests.swift`
  - Cover monitor filters, sorting, health summary, trend summary, repeated failures, and recovery event derivation.
- Modify `Tests/CarRentalDomainTests/PriceMonitorMatchingTests.swift`
  - Cover matching explanation priority.
- Modify `Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift`
  - Cover filter state, batch pause/resume, and run-now feedback.
- Modify `Tests/CarRentalOptimizerTests/MonitorSchedulerTests.swift`
  - Cover repeated failure and recovery events emitted by scheduled checks.
- Modify `Tests/CarRentalOptimizerTests/MonitorPresentationTests.swift`
  - Cover new notification names and presentation labels.
- Modify `README.md` and `CHANGELOG.md`
  - Document the user-facing monitor and workflow improvements.

## Task 1: Monitor Domain Operations

- [x] **Step 1: Write failing tests**

Add tests to `Tests/CarRentalDomainTests/PriceMonitoringTests.swift` for:

- `MonitorCenterFilter.needsAttention` returning only attention monitors.
- `sortedForMonitorCenter` putting needs-attention monitors, recent price drops, urgent pickups, and overdue checks before ordinary active monitors.
- `MonitorHealthSummary.make` counting attention monitors, recent price drops, due-today monitors, and active monitors.
- `PriceTrendSummary` exposing latest, lowest, highest, first-to-latest delta, previous delta, and latest successful check time.
- `makeMonitorLifecycleEvents` emitting `repeatedFailure` on the third equivalent failure and `recovered` after a successful check follows failures.

Run:

```bash
swift test --filter PriceMonitoringTests
```

Expected: compile failures because the new helper types and fields do not exist.

- [x] **Step 2: Implement deterministic helpers**

Add the smallest public domain types/functions needed by the tests:

- `MonitorCenterFilter`
- `MonitorHealthSummary`
- `MonitorEventEvaluation`
- `filterMonitorsForCenter`
- `sortMonitorsForCenter`
- `makeMonitorLifecycleEvents`

Run:

```bash
swift test --filter PriceMonitoringTests
```

Expected: `PriceMonitoringTests` pass.

## Task 2: Matching Explanation

- [x] **Step 1: Write failing tests**

Add tests to `Tests/CarRentalDomainTests/PriceMonitorMatchingTests.swift` asserting that exact signature, same-platform vehicle, same vehicle, target-platform query, and fallback selections expose stable explanation codes and human-readable summaries.

Run:

```bash
swift test --filter PriceMonitorMatchingTests
```

Expected: compile failure because selection explanation types do not exist.

- [x] **Step 2: Implement selection explanations**

Add `MonitoredRecommendationSelection`, `MonitorMatchStrategy`, and `selectMonitoredRecommendationWithExplanation`, then make `selectMonitoredRecommendation` delegate to it.

Run:

```bash
swift test --filter PriceMonitorMatchingTests
```

Expected: matching tests pass.

## Task 3: Scheduler Lifecycle Events

- [x] **Step 1: Write failing scheduler tests**

Add tests to `Tests/CarRentalOptimizerTests/MonitorSchedulerTests.swift` for repeated failure event emission and recovery event emission.

Run:

```bash
swift test --filter MonitorScheduler
```

Expected: failure because scheduler does not append lifecycle events.

- [x] **Step 2: Emit lifecycle events from scheduled checks**

After appending each snapshot, have `MonitorScheduler` evaluate repeated failure and recovery events using previous snapshots. Preserve existing price-drop notification behavior.

Run:

```bash
swift test --filter MonitorScheduler
```

Expected: scheduler tests pass.

## Task 4: Monitor Center ViewModel Productization

- [x] **Step 1: Write failing ViewModel tests**

Add tests to `Tests/CarRentalOptimizerTests/MonitorCenterViewModelTests.swift` for:

- filter counts and displayed monitor order after reload,
- health summary counts,
- batch pause and resume over displayed monitor IDs,
- run-now feedback after scheduler execution.

Run:

```bash
swift test --filter MonitorCenterViewModel
```

Expected: compile failures or assertion failures because the ViewModel surface does not exist.

- [x] **Step 2: Implement ViewModel derived state and actions**

Load snapshots/events for every monitor during reload, expose `filter`, `displayedMonitors`, `healthSummary`, `filterCount(for:)`, `pauseMonitors(ids:)`, `resumeMonitors(ids:)`, and `runShownChecks()`.

Run:

```bash
swift test --filter MonitorCenterViewModel
```

Expected: ViewModel tests pass.

## Task 5: Desktop UI Integration

- [x] **Step 1: Write failing presentation tests**

Add presentation tests for new notification names and labels in `Tests/CarRentalOptimizerTests/MonitorPresentationTests.swift`.

Run:

```bash
swift test --filter MonitorPresentation
```

Expected: compile failure for missing notification names or labels.

- [x] **Step 2: Implement compact UI enhancements**

Update `MonitorCenterView`, `MainView`, `App.swift`, and `AppPresentation.swift` to expose monitor filters, health summary, trend summary, batch actions, retry/run keyboard commands, and concise feedback text.

Run:

```bash
swift test --filter MonitorPresentation
swift build
```

Expected: presentation tests and build pass.

## Task 6: Documentation And Final Verification

- [x] **Step 1: Update docs**

Update `README.md` and `CHANGELOG.md` with short user-facing notes for monitor filters, attention sorting, repeated failure/recovery events, and keyboard commands.

- [x] **Step 2: Full verification**

Run:

```bash
swift package clean
swift test
swift build
```

Expected: full test suite and build pass. The known `LocationServices.swift` Swift 6 isolation warning may remain unless separately fixed.

