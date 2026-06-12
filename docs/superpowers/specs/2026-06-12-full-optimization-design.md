# Full Optimization Design

## Goal

Optimize the project in the requested order: A steady the SwiftUI mainline, B remove the retired Electron/Node line, then C improve the existing macOS workbench experience without changing the product direction.

## Scope

### A. Mainline Health

- Make the Swift test suite stable on any calendar date.
- Preserve the product rule that pickup dates cannot be earlier than today.
- Add release/version consistency checks so `AppInfo.swift` and `native/Info.plist` cannot drift silently.
- Keep all production search results based on official platform evidence.

### B. Electron Cleanup

- Remove the retired Electron/Vite/React implementation and Node package files from the active repository.
- Update README and release docs so SwiftUI is the only documented runtime.
- Remove Node audit exposure by eliminating the active Node dependency graph rather than upgrading an obsolete path.
- Preserve historical context in changelog/docs where useful, but do not keep runnable legacy app entry points.

### C. Workbench UX Enhancements

- Add staged search progress so users can see whether the app is resolving address, querying platforms, or ranking routes.
- Add a retry path after a search without making users edit fields unnecessarily.
- Improve quote credibility display by distinguishing incomplete platform quote data from complete totals.
- Add lightweight sorting controls for current results: best total, rental subtotal, distance, and data completeness.
- Improve accessibility labels on platform toggles, result rows, and retry actions.

## Architecture

`Sources/CarRentalDomain` remains pure and dependency-free. Sorting options and quote confidence can live in the domain if they are deterministic value behavior. UI state and staged progress belong in `SearchViewModel`.

`Sources/CarRentalOptimizer` continues to own SwiftUI views, platform integrations, update checks, and app-level date rules. Date normalization gets an injectable clock only for deterministic testing; production defaults still use the real current date in Asia/Shanghai.

Electron cleanup is a repository-level removal. No Swift code should depend on the old TypeScript implementation after this change.

## Data Flow

1. Search starts from `SearchPanelView`.
2. `SearchViewModel` updates a typed progress phase while it resolves location, requests platform evidence, ranks listings, and completes.
3. Platform clients still return `PlatformEvidenceResult`.
4. Domain ranking produces recommendations.
5. Result UI applies the selected sort mode to already computed recommendations.

## Error Handling

- Address failures still stop the search and show platform statuses that explain no platform was called.
- Platform failures remain typed as ready, unavailable, login required, captcha required, parse failed, or waiting.
- Retry reuses the last current request and calls the same search flow.
- Incomplete quote data is surfaced as a warning/credibility note, not hidden in totals.

## Testing

- Add a regression test that proves date normalization can be tested with a fixed `today`.
- Keep the existing calendar rule tests.
- Add tests for version consistency between `AppInfo` and `Info.plist`.
- Add tests for result sorting behavior where practical in pure domain or ViewModel code.
- Run `swift test` as the primary verification.
- `npm test` and `npm audit` are removed from required verification once Node package files are deleted.

## Non-Goals

- No new rental platforms.
- No invented or mock production listings.
- No large visual redesign, landing page, or decorative UI treatment.
- No Developer ID signing or notarization setup in this pass.
- No Sparkle reintroduction.
