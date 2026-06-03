# Real Data Native Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native macOS app trustworthy by removing production mock listings, adding real platform evidence states, enforcing date-only future selection, and refreshing name/icon assets.

**Architecture:** Keep the existing Swift Package split between `CarRentalDomain` and `CarRentalOptimizer`. Add a small domain parser for platform evidence and a focused app view model workflow that ranks only parsed official evidence. Route costs stay as local estimates and are labeled as estimates.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, XCTest, macOS `.app` bundling scripts.

---

### Task 1: Date-Only Domain Behavior

**Files:**
- Modify: `Sources/CarRentalDomain/SearchSummary.swift`
- Test: `Tests/CarRentalDomainTests/SearchSummaryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import CarRentalDomain

final class SearchSummaryTests: XCTestCase {
    func testDateOnlyRentalDaysUseCalendarDifference() {
        XCTAssertEqual(calculateRentalDays(pickupAt: "2026-09-01", returnAt: "2026-10-11"), 40)
    }

    func testSameDateRentalIsAtLeastOneDay() {
        XCTAssertEqual(calculateRentalDays(pickupAt: "2026-09-01", returnAt: "2026-09-01"), 1)
    }

    func testDateOnlyStatusDoesNotShowTimes() {
        let request = SearchRequest(
            origin: GeoPoint(lat: 39.9169, lng: 116.6462),
            originLabel: "北京通州",
            pickupAt: "2026-09-01",
            returnAt: "2026-10-11",
            returnMode: .sameStore,
            radiusKm: 100,
            vehicleQuery: "瑞虎8",
            platforms: [.ehi, .carInc]
        )

        XCTAssertEqual(formatSearchCompletionStatus(request: request, resultCount: 0), "已按 2026/09/01 - 2026/10/11 查询，按 40 天计费，没有找到候选车辆。")
    }
}
```

- [ ] **Step 2: Run `swift test --filter SearchSummaryTests` and verify the new tests fail.**
- [ ] **Step 3: Add date-only parsing and formatting in `SearchSummary.swift`.**
- [ ] **Step 4: Run `swift test --filter SearchSummaryTests` and verify the tests pass.**

### Task 2: Platform Evidence Parser

**Files:**
- Create: `Sources/CarRentalDomain/PlatformEvidence.swift`
- Test: `Tests/CarRentalDomainTests/PlatformEvidenceTests.swift`

- [ ] **Step 1: Write tests for `waitingForEvidence`, `unavailable`, `loginRequired`, `captchaRequired`, `parseFailed`, and parsed listing evidence.**
- [ ] **Step 2: Run `swift test --filter PlatformEvidenceTests` and verify the tests fail because the type is missing.**
- [ ] **Step 3: Implement `PlatformEvidenceInput`, `PlatformEvidenceStatus`, `PlatformEvidenceResult`, and `parsePlatformEvidence`.**
- [ ] **Step 4: Run `swift test --filter PlatformEvidenceTests` and verify the tests pass.**

### Task 3: SearchViewModel Real-Data Workflow

**Files:**
- Modify: `Sources/CarRentalOptimizer/SearchViewModel.swift`
- Modify: `Sources/CarRentalOptimizer/EstimatedMapService.swift`
- Test: `Tests/CarRentalOptimizerTests/SearchViewModelTests.swift`

- [ ] **Step 1: Replace the existing default-result test with tests asserting default search returns no mock listings and pasted official evidence ranks real listings.**
- [ ] **Step 2: Run `swift test --filter SearchViewModel` and verify the new tests fail against the mock workflow.**
- [ ] **Step 3: Add evidence state to `SearchViewModel`, parse evidence, rank only parsed listings, and change status text.**
- [ ] **Step 4: Run `swift test --filter SearchViewModel` and verify the tests pass.**

### Task 4: Native UI, Name, and Date Rules

**Files:**
- Modify: `Sources/CarRentalOptimizer/AppInfo.swift`
- Modify: `Sources/CarRentalOptimizer/App.swift`
- Modify: `Sources/CarRentalOptimizer/AppPresentation.swift`
- Modify: `Sources/CarRentalOptimizer/MainView.swift`
- Modify: `Sources/CarRentalOptimizer/SearchPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/ResultPanelView.swift`
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`
- Modify: `native/Info.plist`
- Test: `Tests/CarRentalOptimizerTests/AppInfoTests.swift`

- [ ] **Step 1: Update AppInfo test to expect `租车比价助手`.**
- [ ] **Step 2: Run `swift test --filter AppInfo` and verify the name test fails.**
- [ ] **Step 3: Update app constants, menus, bundle display name, header, empty states, and search form copy.**
- [ ] **Step 4: Change SwiftUI `DatePicker` to `.date`, with pickup range from today and return range from pickup.**
- [ ] **Step 5: Run `swift test --filter AppInfo` and verify it passes.**

### Task 5: Icon Asset and Bundle Integration

**Files:**
- Create: `native/AppIcon.iconset/*`
- Create: `native/AppIcon.icns`
- Modify: `scripts/build-app.sh`
- Modify: `native/Info.plist`

- [ ] **Step 1: Generate a macOS icon from a vector source: car, map pin, and yuan mark.**
- [ ] **Step 2: Convert icon sizes into `native/AppIcon.icns`.**
- [ ] **Step 3: Copy the icon into `Contents/Resources` during app build and set `CFBundleIconFile`.**
- [ ] **Step 4: Run `scripts/build-app.sh` and verify bundle validation passes.**

### Task 6: Full Verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README to describe the real evidence workflow and remove production mock claims.**
- [ ] **Step 2: Add a changelog entry for the native real-data optimization.**
- [ ] **Step 3: Run `swift test`.**
- [ ] **Step 4: Run `scripts/build-app.sh`.**
- [ ] **Step 5: Run `scripts/verify-app-bundle.sh build/租车比价助手.app`.**
