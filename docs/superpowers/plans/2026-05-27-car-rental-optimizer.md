# Car Rental Optimizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable Electron + React macOS desktop app prototype for comparing eHi and CAR Inc. rental options by rental price plus pickup travel cost.

**Architecture:** The app separates UI, search orchestration, rental provider adapters, map route adapters, vehicle matching, and recommendation scoring. Real platform automation is represented by stable adapter interfaces and local mock adapters in the first runnable version.

**Tech Stack:** Electron, React, TypeScript, Vite, Vitest, CSS modules via plain CSS.

---

## File Structure

- `package.json`: project metadata, scripts, runtime and dev dependencies.
- `index.html`: Vite HTML entry.
- `electron/main.cjs`: Electron main process and production/dev window loading.
- `electron/preload.cjs`: isolated bridge reserved for future native APIs.
- `src/main.tsx`: React entry.
- `src/App.tsx`: app shell and UI state orchestration.
- `src/styles.css`: mainstream macOS-style desktop UI.
- `src/domain/types.ts`: normalized app types.
- `src/domain/vehicleMatcher.ts`: model matching and confidence logic.
- `src/domain/recommendation.ts`: cost totals and ranking logic.
- `src/services/mockRentalAdapters.ts`: eHi and CAR Inc. mock providers.
- `src/services/mockMapService.ts`: deterministic taxi/transit route estimates.
- `src/services/searchOrchestrator.ts`: coordinates providers, routes, matching, and ranking.
- `src/domain/vehicleMatcher.test.ts`: TDD tests for model matching.
- `src/domain/recommendation.test.ts`: TDD tests for ranking and cost totals.
- `src/services/searchOrchestrator.test.ts`: TDD tests for full mock search behavior.

### Task 1: Project Scaffold

**Files:**
- Create: `package.json`
- Create: `index.html`
- Create: `tsconfig.json`
- Create: `tsconfig.node.json`
- Create: `vite.config.ts`
- Create: `electron/main.cjs`
- Create: `electron/preload.cjs`
- Create: `src/main.tsx`
- Create: `src/vite-env.d.ts`

- [ ] **Step 1: Add project configuration and Electron shell**

Create the files listed above with scripts for `dev`, `test`, and `build`, then install dependencies.

- [ ] **Step 2: Run baseline install**

Run: `npm install`
Expected: dependencies installed and `package-lock.json` created.

### Task 2: Domain Logic With TDD

**Files:**
- Create: `src/domain/types.ts`
- Create: `src/domain/vehicleMatcher.test.ts`
- Create: `src/domain/vehicleMatcher.ts`
- Create: `src/domain/recommendation.test.ts`
- Create: `src/domain/recommendation.ts`

- [ ] **Step 1: Write failing tests for vehicle matching**

Tests must assert exact match for `瑞虎8`, same-class SUV fallback, and low-confidence fallback.

- [ ] **Step 2: Verify vehicle matching tests fail**

Run: `npm test -- src/domain/vehicleMatcher.test.ts`
Expected: FAIL because implementation files are missing or functions are undefined.

- [ ] **Step 3: Implement vehicle matching**

Implement normalized model matching and confidence scoring.

- [ ] **Step 4: Verify vehicle matching tests pass**

Run: `npm test -- src/domain/vehicleMatcher.test.ts`
Expected: PASS.

- [ ] **Step 5: Write failing tests for recommendation ranking**

Tests must assert rental plus taxi/transit totals, best total selection, exact-match tie-breaking, and a cross-city cheaper option winning by total cost.

- [ ] **Step 6: Verify recommendation tests fail**

Run: `npm test -- src/domain/recommendation.test.ts`
Expected: FAIL because ranking functions are missing.

- [ ] **Step 7: Implement recommendation ranking**

Implement total cost calculation and sorting.

- [ ] **Step 8: Verify recommendation tests pass**

Run: `npm test -- src/domain/recommendation.test.ts`
Expected: PASS.

### Task 3: Search Orchestration With Mock Adapters

**Files:**
- Create: `src/services/mockRentalAdapters.ts`
- Create: `src/services/mockMapService.ts`
- Create: `src/services/searchOrchestrator.test.ts`
- Create: `src/services/searchOrchestrator.ts`

- [ ] **Step 1: Write failing orchestration tests**

Tests must assert the orchestrator queries both platforms, includes Dezhou East Station when radius is 500 km, excludes it when radius is 100 km, and returns ranked cost breakdowns.

- [ ] **Step 2: Verify orchestration tests fail**

Run: `npm test -- src/services/searchOrchestrator.test.ts`
Expected: FAIL because orchestrator and adapters are missing.

- [ ] **Step 3: Implement mock adapters and orchestrator**

Implement deterministic rental and route data using normalized interfaces.

- [ ] **Step 4: Verify orchestration tests pass**

Run: `npm test -- src/services/searchOrchestrator.test.ts`
Expected: PASS.

### Task 4: Main UI

**Files:**
- Create: `src/App.tsx`
- Create: `src/styles.css`
- Modify: `src/main.tsx`

- [ ] **Step 1: Implement the three-column desktop tool UI**

Build search controls, ranked results, recommendation detail, warnings, and source link buttons.

- [ ] **Step 2: Wire UI to orchestrator**

Run searches locally through mock adapters and display ranked results.

- [ ] **Step 3: Verify production build**

Run: `npm run build`
Expected: TypeScript and Vite build exit 0.

### Task 5: Final Verification

**Files:**
- Modify as needed based on verification failures.

- [ ] **Step 1: Run full tests**

Run: `npm test`
Expected: all tests pass.

- [ ] **Step 2: Run production build**

Run: `npm run build`
Expected: build exits 0 and writes `dist/`.

- [ ] **Step 3: Start dev server**

Run: `npm run dev:web -- --host 127.0.0.1`
Expected: Vite serves the app locally.

## Self-Review

The plan covers the design spec requirements for local macOS app shape, normalized provider adapters, map-cost separation, vehicle matching, recommendation ranking, a usable desktop UI, and verification. Real platform selector automation is intentionally outside the first runnable implementation and is represented by adapter seams because it requires live login sessions and site-specific maintenance.
