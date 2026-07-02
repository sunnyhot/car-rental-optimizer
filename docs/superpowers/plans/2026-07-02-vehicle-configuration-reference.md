# Vehicle Configuration Reference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make vehicle detail show richer common configuration items with clear source status: platform confirmed, model-library reference, or unconfirmed.

**Architecture:** Keep the existing `VehicleInsight` pipeline. Add computed configuration facts derived from `VehicleFeature` and display them in `DetailPanelView`; keep platform-returned features as highest priority and allow series/model-library reference features to fill lower-confidence states.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing/XCTest, existing `swift test` verification.

## Global Constraints

- Do not claim rental-platform certainty unless the feature comes from `VehicleSpecScope.platformListing`.
- Do not scrape unstable automotive pages in this task; leave the network source pluggable and make UI/source states ready.
- Keep release artifacts untouched.

---

### Task 1: Configuration Fact Model

**Files:**
- Modify: `Sources/CarRentalOptimizer/VehicleInsights.swift`
- Test: `Tests/CarRentalOptimizerTests/VehicleInsightTests.swift`

**Interfaces:**
- Produces: `VehicleInsight.formattedConfigurationFacts` as `[VehicleInsightFact]`.

- [x] Write a failing test that a listing without returned feature text still exposes common feature rows such as `倒车影像：未确认`.
- [x] Run `swift test --filter VehicleInsightTests` and confirm the new test fails.
- [x] Add `formattedConfigurationFacts`.
- [x] Preserve existing `platformFeatures` behavior for confirmed feature tags.
- [x] Run `swift test --filter VehicleInsightTests` and confirm it passes.

### Task 2: UI Display

**Files:**
- Modify: `Sources/CarRentalOptimizer/DetailPanelView.swift`
- Test: `Tests/CarRentalOptimizerTests/UIEffectsSourceTests.swift`

**Interfaces:**
- Consumes: `VehicleInsight.formattedConfigurationFacts`.
- Replaces empty fallback copy under the configuration section with a compact grid of source-labeled facts.

- [x] Write a failing source-level UI test that `DetailPanelView` references `formattedConfigurationFacts` and uses the copy `配置参考`.
- [x] Run `swift test --filter UIEffectsSourceTests` and confirm the new assertion fails.
- [x] Update `VehicleInsightSection` to render `VehicleInsightFactGrid(title: "配置参考", facts: insight.formattedConfigurationFacts)`.
- [x] Keep the caution copy `下单前以平台确认页为准`.
- [x] Run `swift test --filter UIEffectsSourceTests` and confirm it passes.

### Task 3: Verification and Commit

**Files:**
- Modify: task files only.

- [x] Run `swift test --filter VehicleInsightTests`.
- [x] Run `swift test --filter UIEffectsSourceTests`.
- [x] Run `swift test`.
- [x] Commit code and plan with message `feat: show vehicle configuration reference`.
