# UI Workbench Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the macOS app into a polished professional car-rental comparison workbench.

**Architecture:** Keep existing search/data logic unchanged. Add a focused SwiftUI design system file for colors, typography helpers, status styling, and panel surfaces, then refactor the three main panels around clearer hierarchy: query controls, ranked options, and cost detail.

**Tech Stack:** SwiftUI, AppKit colors, SF Symbols, existing `CarRentalDomain` recommendation models.

---

### Task 1: Shared Design System

**Files:**
- Create: `Sources/CarRentalOptimizer/WorkbenchStyle.swift`

- [x] **Step 1: Add shared color tokens, reusable surface modifiers, status pills, and empty/loading blocks**

Create a compact design system with neutral macOS surfaces, blue/teal accent colors, orange warning, red failure, green ready state, 8px radius surfaces, and tabular number formatting for prices.

- [x] **Step 2: Build to confirm the design system compiles**

Run: `swift test --filter AppInfo`

Expected: app target compiles and selected tests pass.

### Task 2: Main Workbench Shell

**Files:**
- Modify: `Sources/CarRentalOptimizer/MainView.swift`
- Modify: `Sources/CarRentalOptimizer/ContentView.swift`

- [x] **Step 1: Replace the flat header with a workbench title bar**

Add a title group, live data indicator, current result count, selected recommendation total, and restrained toolbar styling.

- [x] **Step 2: Rebalance column widths**

Use a more deliberate three-column shell: query console, ranked options, decision detail. Preserve existing minimum app size and native split behavior.

### Task 3: Query Console

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchPanelView.swift`

- [x] **Step 1: Refactor the search form into grouped control sections**

Use labeled rows, compact date fields, platform toggles with status chips, a prominent compare button, and clearer helper text for radius behavior.

- [x] **Step 2: Keep all existing bindings and behavior**

Do not change `SearchViewModel` APIs or platform toggling behavior.

### Task 4: Ranked Results

**Files:**
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`

- [x] **Step 1: Replace rows with scan-friendly recommendation cards**

Show rank, total cost, platform badge, vehicle/match, store distance, and taxi/transit totals. Keep selection behavior.

- [x] **Step 2: Improve empty and loading states**

Use platform status summaries that explain whether data is waiting, unavailable, login required, or failed.

### Task 5: Decision Detail

**Files:**
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`

- [x] **Step 1: Convert detail into a receipt-style decision panel**

Emphasize total cost, selected route, store facts, fee breakdown, route comparison, warnings, and source link.

- [x] **Step 2: Keep labels concise and avoid instructional filler**

The detail panel should read like a decision receipt, not documentation.

### Task 6: Verification and Release

**Files:**
- Modify: `Sources/CarRentalOptimizer/AppInfo.swift`
- Modify: `native/Info.plist`
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `scripts/install-release.sh`
- Modify: `docs/release-guide.md`

- [x] **Step 1: Run full tests**

Run: `swift test` and `npm test`.

- [x] **Step 2: Build and visually inspect the app**

Run: `scripts/build-app.sh`, `scripts/verify-launch.sh build/租车比价助手.app`, and capture a screenshot of the launched app.

- [ ] **Step 3: Bump to v0.6.3 and publish**

Create `build/CarRentalOptimizer-v0.6.3.zip`, verify it, install it locally, commit, tag, push, and upload the GitHub Release.
