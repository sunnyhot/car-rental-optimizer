# Roadmap Enhancements Design

## Goal

Enhance the current SwiftUI macOS car rental optimizer across functionality, logic, and experience through a phased roadmap. The work should improve trust in official search results, make price monitoring more operational, and polish the desktop workflow without changing the product direction.

The product rule remains unchanged: production recommendations only come from official platform evidence and route estimates. The app must not invent listings or prices when platforms fail, require login, return captcha, or provide incomplete data.

## Current Context

The app is a Swift Package with a SwiftUI executable target and a dependency-free `CarRentalDomain` library. The current mainline already includes:

- Native three-column search workbench.
- Official-platform search for Ehi and CarInc through `LiveRentalSearchService`.
- Search progress phases, retry, platform statuses, result sorting, and partial price warnings.
- Recommendation detail views with route and cost breakdowns.
- Price monitoring with snapshots, trends, events, notifications, scheduler, and a monitor center.
- Ehi login sheet and persistent cookie handling.

This roadmap builds on those capabilities rather than replacing them.

## Phasing

Implement in three release-sized phases:

1. Phase 1: trustworthy search mainline.
2. Phase 2: price monitoring productization.
3. Phase 3: desktop experience integration.

Each phase should be independently shippable and verified with `swift test`. Later phases may depend on domain types introduced earlier, but each phase should avoid broad UI rewrites unless required by the specific user workflow.

## Phase 1: Trustworthy Search Mainline

### Scope

Phase 1 makes the search flow more explainable and resilient. It focuses on what was searched, what was trusted, what failed, and what the user can do next.

### Features

- Add lightweight preflight validation for address, date range, selected platforms, radius, and vehicle query.
- Generate a structured search diagnostic summary after every search.
- Map platform failure states to explicit recovery suggestions.
- Consolidate quote credibility into a single presentation model.
- Preserve the last successful result set when a later search fails.

### Design Details

Preflight validation should warn without blocking reasonable searches. Examples include blank address, abnormal date range, no selected platform, broad radius with a narrow vehicle query, or an empty vehicle query that changes matching behavior. Hard blocking should be reserved for impossible input such as no selected platform.

Search diagnostics should be a value model owned by `SearchViewModel` or a small app-layer presentation type. It should include queried platforms, successful platforms, failed platforms, listing counts, visible result counts, route estimate status, and filtering or matching notes. It should reuse existing `PlatformEvidenceStatus` values rather than introducing another platform status source of truth.

Recovery suggestions should be deterministic mappings from platform status kinds:

- `loginRequired`: open Ehi login when applicable, then retry the same request.
- `captchaRequired`: open or refresh the platform login flow, then retry.
- `parseFailed`: retry later or open the original platform for verification.
- `unavailable`: adjust platform or route conditions, or retry later.
- no listings with ready status: broaden radius, relax vehicle query, or verify availability on platform.

Quote credibility should combine `dataCompleteness` and `ResultWarning` into one display model. Suggested labels are complete quote, partial price requires review, route estimate missing, cross-city or one-way risk, and login/captcha blocked. Result rows, detail views, and monitor snapshots should use the same vocabulary.

When a new search fails after a previous success, the UI should keep the previous successful recommendations visible with a stale-state banner. The banner should say the latest search did not complete and the visible results come from the last successful search. This preserves user context during transient platform or login failures.

### Data Flow

1. `SearchPanelView` updates `SearchViewModel.request`.
2. `SearchViewModel` runs preflight validation before search.
3. `SearchViewModel.runSearch()` records phases and platform evidence as it does today.
4. After platform calls and ranking, the ViewModel builds a diagnostic summary and quote credibility models.
5. If the search succeeds, current results replace any prior results and become the latest successful set.
6. If the search fails or returns no actionable listings, the ViewModel shows failure diagnostics while optionally retaining the latest successful set as stale results.

### Error Handling

Address failures should remain terminal for that search and should clearly say no platform was called. Platform failures should continue to be represented by `PlatformEvidenceStatusKind`. Retained stale results must never be presented as current; they need an explicit stale marker and the last successful search time.

### Testing

- Domain or app-layer tests for credibility label mapping.
- ViewModel tests for diagnostic summary creation.
- ViewModel tests for success followed by failed search retaining previous results as stale.
- ViewModel tests for recovery suggestion mapping from platform statuses.
- Existing search progress and sorting tests remain in place.

## Phase 2: Price Monitoring Productization

### Scope

Phase 2 turns the monitor center into a task-focused price operations view. Users should quickly see which monitors need attention, why they need attention, and what action is available.

### Features

- Add monitor filters for all, active, needs attention, paused, and expired.
- Sort the monitor list by attention priority, recent price drops, pickup urgency, and next check time.
- Add a monitor health summary at the top of the monitor center.
- Detect repeated failures and recovery events.
- Add batch pause, resume, and run-now actions.
- Add more readable trend summaries.
- Explain which listing match strategy selected each monitored recommendation.

### Design Details

The monitor list should default to an attention-first order. `needsAttention` monitors appear before active monitors. Monitors with recent price-drop events, upcoming pickup dates, or overdue checks should also be elevated.

The health summary should show counts for monitors needing attention, recent price drops, checks due today, and whether background monitoring is enabled. This summary should be computed in `MonitorCenterViewModel` from existing monitors, events, and snapshots.

Repeated failure detection should live in monitor scheduling or a domain helper. Consecutive snapshots with equivalent failure categories should emit a `repeatedFailure` event after a small threshold, and should avoid creating duplicate events on every loop. A successful snapshot after one or more failure snapshots should emit a `recovered` event.

Batch operations should be ViewModel methods that accept monitor IDs. UI selection can be multi-select if SwiftUI list behavior remains stable; otherwise a lighter first pass can use per-filter bulk actions such as pause all shown or run all shown.

Trend summaries should sit near the chart and include latest price, historical low, historical high, change from first successful snapshot, change from previous successful snapshot, and latest successful check time.

Monitor matching should expose a human-readable explanation for the selected recommendation. The priority should match the current matching logic: exact original signature, same platform and vehicle, same vehicle, query match within target platform, then fallback to best ranked platform result.

### Data Flow

1. `MonitorCenterViewModel.reload()` loads monitors, selected snapshots, and selected events.
2. ViewModel derives filter counts, list ordering, health summary, and trend summary.
3. `MonitorScheduler.runDueChecks()` appends snapshots and events.
4. Scheduler or domain helpers produce repeated failure, recovery, price drop, and paused-after-pickup events.
5. Monitor detail displays snapshots, events, trend summary, and matching explanation.

### Error Handling

Batch operations should report partial failures without losing selection. Scheduler failures should continue to set `storageErrorMessage`. Repeated failure events should compress noise, not hide the latest snapshot message.

### Testing

- Domain tests for monitor attention sorting and filters.
- Domain or scheduler tests for repeated failure thresholds and recovery events.
- Tests for matching explanation order.
- ViewModel tests for health summary counts and batch pause or resume.
- Existing scheduler and store tests remain in place.

## Phase 3: Desktop Experience Integration

### Scope

Phase 3 makes the app feel more coherent as a macOS tool. It should improve navigation, status visibility, keyboard access, empty states, and layout resilience without introducing a new app shell.

### Features

- Unify top-level status language across search and monitoring.
- Add common quick actions for retry, compare, open monitor center, run checks, login, and open original platform.
- Normalize empty and error states into a common structure.
- Add keyboard shortcuts for frequent actions.
- Improve accessibility labels for status, sorting, platform rows, result rows, and chart summaries.
- Harden layout under narrower windows.
- Add clear feedback after save, batch action, login retry, and scheduler actions.

### Design Details

The main header should keep the current compact workbench style but include more useful state: latest successful search time, current platform health, and background monitoring state. It should not become a marketing hero or take vertical space away from the workbench.

Quick actions should use system icons and short labels. The app should prefer existing SwiftUI controls and `WorkbenchStyle` components. Actions should appear where the user already looks: retry in result empty/error states, login on relevant platform rows, run checks in monitor center, and original platform links in detail.

Empty and error states should follow the same structure: what happened, why it happened, and the next action. Existing `EmptyStateBlock`, `SurfaceBox`, and status rows can be extended rather than replaced.

Keyboard shortcuts should cover start compare, retry latest search, open monitor center, run due checks, and move selection through results. The implementation should preserve mouse-driven workflows and not require new dependencies.

Layout resilience should be incremental. Keep `HSplitView`, but tighten text wrapping, button compression, row line limits, minimum widths, and detail panel priorities so the app remains usable near the current minimum window width.

### Data Flow

Phase 3 should mostly consume state created by Phase 1 and Phase 2. It should not introduce another business logic layer. Shared presentation helpers are acceptable when they reduce duplicated status wording between search and monitor views.

### Error Handling

User-triggered operations should give immediate feedback. Successful monitor creation, batch pause or resume, run-now completion, failed login retry, and failed platform search should each update visible state. Feedback should be text-first and consistent with existing panels.

### Testing

- Tests for keyboard shortcut command wiring where practical.
- Presentation tests for shared empty/error-state text.
- App-window layout tests for minimum and ideal widths.
- Manual local visual check after implementation.
- `swift test` remains the required automated verification.

## Architecture Principles

- Keep deterministic value behavior in `CarRentalDomain`.
- Keep SwiftUI state orchestration in `CarRentalOptimizer`.
- Reuse `PlatformEvidenceStatus`, `ResultWarning`, `PriceSnapshotStatus`, and monitor event types where possible.
- Add new domain types only when they encode reusable deterministic logic, such as monitor sorting, matching explanations, or credibility classification.
- Avoid broad visual rewrites, new dependencies, or a new navigation framework.
- Preserve the official-data-only product rule.

## Non-Goals

- No new rental platforms in this roadmap.
- No invented prices, mock production listings, or fallback recommendations from static data.
- No Developer ID signing or notarization work.
- No replacement of SwiftUI with another UI framework.
- No large visual redesign or marketing-style landing page.
- No cloud sync for monitors.

## Verification

Each implementation phase should end with:

- Focused tests for the changed domain or ViewModel behavior.
- Full `swift test`.
- Manual run of the app for workflows that are visual or interaction-heavy.
- Documentation or changelog updates when the user-facing behavior changes.
