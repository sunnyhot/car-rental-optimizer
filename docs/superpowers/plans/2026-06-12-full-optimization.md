# Full Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore SwiftUI mainline health, remove the retired Electron/Node implementation, and improve the macOS workbench search experience.

**Architecture:** Keep deterministic behavior in `CarRentalDomain` and app coordination in `CarRentalOptimizer`. Date normalization gets injectable time for tests. Retired Electron files are removed from the active project. UX additions reuse the existing three-column workbench components.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing/XCTest, Swift Package Manager.

---

### Task 1: Stabilize Date Rules

**Files:**
- Modify: `Sources/CarRentalOptimizer/AppPresentation.swift`
- Modify: `Tests/CarRentalOptimizerTests/AppDateRulesTests.swift`

- [ ] **Step 1: Write the failing test**

Add a test that calls `AppDateRules.normalizedRange(pickup:returnDate:today:)` with a fixed `today` after the return date and before the pickup date.

- [ ] **Step 2: Run focused test to verify it fails**

Run: `swift test --filter AppDateRules`

Expected: compile failure because `normalizedRange(pickup:returnDate:today:)` does not exist yet.

- [ ] **Step 3: Implement minimal code**

Add an overload/default parameter so production still calls `normalizedRange(pickup:returnDate:)`, while tests can pass a fixed `today`.

- [ ] **Step 4: Run focused test**

Run: `swift test --filter AppDateRules`

Expected: all AppDateRules tests pass.

### Task 2: Add Version Consistency Coverage

**Files:**
- Modify: `Tests/CarRentalOptimizerTests/AppInfoTests.swift`

- [ ] **Step 1: Write the failing test**

Add a test that loads `native/Info.plist` from the package root and asserts `CFBundleShortVersionString == AppInfo.version` and `CFBundleVersion == AppInfo.build`.

- [ ] **Step 2: Run focused test**

Run: `swift test --filter AppInfo`

Expected: the new test fails if path lookup or plist parsing is missing.

- [ ] **Step 3: Implement minimal test helper**

Add a package-root lookup helper inside the test file only.

- [ ] **Step 4: Run focused test**

Run: `swift test --filter AppInfo`

Expected: AppInfo tests pass.

### Task 3: Remove Electron/Node Active Line

**Files:**
- Delete: `package.json`
- Delete: `package-lock.json`
- Delete: `tsconfig.json`
- Delete: `tsconfig.node.json`
- Delete: `vite.config.ts`
- Delete: `index.html`
- Delete: `src/`
- Delete: `electron/`
- Modify: `README.md`
- Modify: `docs/release-guide.md`
- Modify: `.gitignore`

- [ ] **Step 1: Update docs first**

Remove Electron run/build instructions and describe the project as SwiftUI-only.

- [ ] **Step 2: Delete retired files**

Remove Node/Electron project files and source directories.

- [ ] **Step 3: Verify no active references remain**

Run: `rg -n "Electron|Vite|React|npm|package.json|src/|electron/" README.md docs .github scripts Sources Tests`

Expected: only historical changelog/spec/plan references, if any.

### Task 4: Add Search Progress and Retry State

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Modify: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`
- Modify: `Sources/CarRentalOptimizer/SearchPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`

- [ ] **Step 1: Write failing ViewModel test**

Test that a search with listings finishes with `.completed`, and an address failure finishes with `.failed`.

- [ ] **Step 2: Run focused test**

Run: `swift test --filter SearchViewModel`

Expected: compile failure because `SearchProgressPhase` does not exist yet.

- [ ] **Step 3: Implement progress phase**

Add `SearchProgressPhase` and update `runSearch()` through resolving location, querying platforms, ranking, completed, and failed.

- [ ] **Step 4: Add retry helper**

Add `retrySearch()` that calls `runSearch()` and leaves UI code simple.

- [ ] **Step 5: Update UI**

Show staged progress in the result panel loading state and show a retry button in empty/error states.

- [ ] **Step 6: Run focused test**

Run: `swift test --filter SearchViewModel`

Expected: SearchViewModel tests pass.

### Task 5: Add Result Sort Modes and Credibility Labels

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Modify: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`

- [ ] **Step 1: Write failing sort test**

Test that changing sort mode reorders existing results by rental subtotal, store distance, and data completeness.

- [ ] **Step 2: Run focused test**

Run: `swift test --filter SearchViewModel`

Expected: compile failure because sort mode support does not exist yet.

- [ ] **Step 3: Implement sort mode**

Add `RecommendationSortMode` and expose `displayedResults` from the ViewModel.

- [ ] **Step 4: Update result list**

Use a segmented picker in the candidate panel header and render `displayedResults`.

- [ ] **Step 5: Improve credibility messaging**

Show an explicit "部分价格需复核" note for `.partialPrice` recommendations in list/detail views.

- [ ] **Step 6: Run focused test**

Run: `swift test --filter SearchViewModel`

Expected: SearchViewModel tests pass.

### Task 6: Verification

**Files:**
- All changed files

- [ ] **Step 1: Run Swift tests**

Run: `swift test`

Expected: all Swift tests pass.

- [ ] **Step 2: Build app bundle**

Run: `scripts/build-app.sh`

Expected: app bundle verification passes.

- [ ] **Step 3: Confirm Node removal**

Run: `test ! -f package.json && test ! -d src && test ! -d electron`

Expected: exit 0.

- [ ] **Step 4: Inspect git diff**

Run: `git status --short` and `git diff --stat`

Expected: only intentional optimization files changed.
