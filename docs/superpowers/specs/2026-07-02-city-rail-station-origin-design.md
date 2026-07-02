# City Rail Station Origin Design

## Goal

Improve the left-side trip input so a user can enter a destination city, at least at city level, and choose a railway or high-speed rail station as the search origin before comparing rental options.

The feature should support cross-city rental planning. A user often knows the city they will arrive in by train, but not the exact rental pickup area. The app should help them resolve that city into a rail station origin, then reuse the existing official-platform search, radius filtering, and route-cost ranking.

## Current Context

The app already has a single left-side origin field labeled `当前位置`. It supports debounced address suggestions through `AddressSuggestionProviding`, selection of a candidate, current-location refresh, and stale lookup protection in `SearchViewModel`.

The search request already stores a single source of truth for the origin:

- `SearchRequest.originLabel`
- `SearchRequest.origin`

Platform search and ranking already consume this origin. `LiveRentalSearchService` also has station-store heuristics for cross-city candidate stores, but those heuristics operate after the origin has already been chosen. This design adds an earlier city-to-station resolution step so the origin itself is more intentional.

## Product Behavior

The origin field remains one compact entry point. Its user-facing meaning expands from current address only to current location, address, city, or rail station.

When the user types a city name such as `德州`, `济南市`, or `苏州`, the suggestion dropdown should prioritize rail-station candidates, for example `德州东站`, `德州站`, or `苏州北站`. The recommended station appears first, but the user confirms the exact station by selecting it. The app must not silently use a city center coordinate when the user supplied only a city.

When the user selects a station candidate, the app updates `originLabel` and `origin` to the selected station name and coordinate. The existing search button, platform calls, radius slider, route estimates, and ranking continue to work from that station origin.

If no station can be found inside the city, the app may show the nearest plausible railway station as a fallback. The fallback must be explicit in the status text so the user understands the station is nearby rather than definitely inside the requested city.

## Scope

### Included

- City-level input recognition in the existing origin field.
- Rail-station suggestion results mixed into or prioritized above general address suggestions.
- A dedicated app-layer resolver protocol for city and rail-station suggestions.
- User confirmation through the existing dropdown selection pattern.
- Status text for station selection, empty station results, and nearest-station fallback.
- ViewModel tests for suggestion, selection, stale lookup, and failure paths.

### Excluded

- A separate second origin field.
- A full train schedule or railway timetable integration.
- A new rental platform.
- Changing recommendation ranking, pricing, monitoring, or platform evidence rules.
- Inventing rental listings or prices when official platform APIs return no data.
- Automatic search launch immediately after city text input.

## User Stories

As a cross-city renter, I want to type the city I will arrive in, so I can quickly choose a high-speed rail or train station as my rental search origin.

As a user comparing total trip cost, I want the app to use a rail station coordinate rather than a broad city center, so the distance and route-cost ranking reflect my real arrival point.

As a cautious user, I want to confirm which station is used, so I do not accidentally compare rental stores from the wrong side of a city.

## Requirements

1. WHEN the user enters at least two non-whitespace characters in the origin field THEN the system SHALL request location suggestions using the current debounced input flow.

2. WHEN the rail station resolver finds station candidates for the current origin input THEN the system SHALL include those rail-station suggestions in the dropdown.

3. WHEN both rail-station suggestions and general address suggestions are available THEN the system SHALL present rail-station suggestions before general address suggestions.

4. WHEN multiple rail-station suggestions are available for a city THEN the system SHALL place the recommended station first while still allowing the user to select a different station.

5. WHEN the user selects a rail-station suggestion THEN the system SHALL update `SearchRequest.originLabel` and `SearchRequest.origin` with the selected station display name and coordinate.

6. WHEN the user searches after selecting a station suggestion THEN the system SHALL run the existing official-platform search using the selected station coordinate.

7. IF the current origin text is marked as a city-level unresolved origin and the user has not selected a station or address suggestion THEN the system SHALL not silently replace the origin with the city center.

8. IF the current origin text is marked as a city-level unresolved origin and the user starts a search before selecting a station or address suggestion THEN the system SHALL guide the user to select the recommended station or a more specific address before continuing.

9. IF no station is found inside the requested city but a nearby rail station is found THEN the system SHALL show the nearby station as a fallback and explain that it is outside or nearest to the requested city.

10. IF station lookup fails because the provider returns an error THEN the system SHALL preserve the current request origin and show a recoverable error message.

11. WHILE a newer origin lookup has started THEN the system SHALL prevent older city or station lookup results from replacing the current suggestions.

12. WHEN the origin input is blank or shorter than two non-whitespace characters THEN the system SHALL clear suggestions and keep the existing guidance text behavior.

## Architecture

Add an app-layer rail station resolver beside the existing location services:

```swift
protocol RailStationSuggestionProviding {
    func stationSuggestions(for query: String, near origin: GeoPoint?) async throws -> [RailStationSuggestion]
}
```

`RailStationSuggestion` should carry the display text, coordinate, city or area subtitle, and a flag or note describing whether the result is a direct city match, recommended station, or nearest-station fallback.

The first implementation can use MapKit searches for combinations such as city plus `高铁站`, `火车站`, `站`, and the raw query. It should filter out airports and unrelated points of interest, deduplicate station names, and sort by station relevance before distance. This keeps the first version dependency-free and consistent with the current Apple location stack.

`SearchViewModel` should depend on both the existing `AddressSuggestionProviding` and the new `RailStationSuggestionProviding`. It should introduce a small unified origin suggestion presentation type so rail-station candidates and address candidates share one dropdown path while preserving their kind, display text, subtitle, coordinate, and fallback note. The UI should stay visually close to the current dropdown, with an icon or compact label that distinguishes station candidates from normal address candidates.

The ViewModel should also track whether the current text is an unresolved city-level origin. Selecting any concrete station or address candidate clears that state. Manual edits after selection make the origin unresolved again until a new candidate is selected or current location is refreshed.

## Data Flow

1. `OriginLocationField` updates `viewModel.request.originLabel` as the user types.
2. The existing debounce calls `SearchViewModel.updateOriginInput(_:)`.
3. `SearchViewModel` starts a new suggestion request ID and clears stale suggestions.
4. The ViewModel asks the rail station resolver and address suggestion provider for candidates.
5. The ViewModel merges, deduplicates, and sorts suggestions with rail stations first.
6. The dropdown displays candidates while preserving loading and stale-result handling.
7. On selection, the ViewModel writes the selected label and coordinate into the search request.
8. `runSearch()` uses the resolved station coordinate through the existing search flow.

## Error Handling

Station lookup errors should not block general address lookup when general address suggestions still succeed. If both station and address lookup fail, the status text should say the suggestion lookup failed and ask the user to enter a more specific station or address.

City-center fallback is intentionally disallowed for a city-only search. If the app cannot confidently resolve a station and the user has not selected a concrete candidate, the search should stop before platform calls and explain what needs confirmation.

Nearest-station fallback is allowed only as a visible candidate. It becomes the origin only after user selection.

## Testing

Add or extend app-layer tests around the existing location input coverage:

- City input returns station suggestions before address suggestions.
- Selecting a station suggestion updates `originLabel`, `origin`, and resolved-origin state.
- A city-only origin without station selection blocks search with a clear preflight issue.
- A nearest-station fallback candidate is displayed with fallback text and only applied after selection.
- Failed station lookup preserves usable address suggestions when address lookup succeeds.
- Stale station lookup results are ignored after the input changes or suggestions are dismissed.
- Blank or one-character input clears suggestions without calling providers.

Existing tests for current location refresh, address suggestion selection, stale lookup dismissal, and search failure handling should remain valid.

## Non-Functional Requirements

- The feature should remain dependency-free beyond the existing Apple location frameworks.
- Suggestion results should appear through the existing debounced path, not through a new always-on background loop.
- The UI should preserve the compact left-panel workflow and avoid adding another required setup step.
- The resolver should be protocol-driven so tests can use deterministic stub data.

## Open Decisions Resolved

- The user should confirm a station from suggestions instead of the app silently starting from a guessed station.
- The recommended station should be first in the dropdown.
- City-center coordinates should not be used as a silent fallback for station-oriented searches.
- A nearby station fallback is acceptable only when it is visible and selected by the user.
