# Vehicle Suggestions Design

## Context

The search panel currently exposes vehicle input as a plain text field. Users can mistype model names, and exact-model searches are sensitive to spelling. The app already receives real vehicle names from successful live searches, especially when the vehicle field is empty, so those results can become a local suggestion source.

## Goal

Add lightweight vehicle suggestions that reduce typo-driven misses without changing the search contract. Suggestions should help users fill `request.vehicleQuery`; selecting a suggestion should not automatically start a search.

## User Experience

- The vehicle field keeps the existing placeholder and remains optional.
- When the user focuses or types in the vehicle field, show up to six suggestions below it.
- Suggestions come from three sources, in priority order:
  1. Recently selected suggestions.
  2. Vehicle names learned from successful search results.
  3. Built-in common options.
- Empty input should show recent selections first, then learned vehicles, then built-ins.
- Non-empty input should match against Chinese text, ASCII fragments, and simple aliases such as `h5`, `suv`, `mpv`, `ruihu`, and `haval`.
- Each suggestion row shows the vehicle name and a short source label: `最近使用`, `搜索结果`, or `常用`.
- Clicking a suggestion fills the vehicle field, records it as a recent selection, hides the suggestion dropdown, and leaves search execution to the existing compare button.

## Data Model

Introduce a small local vehicle suggestion model:

- `VehicleSuggestion`: stable `id`, display `name`, source, optional aliases, and timestamps/counters for learned or selected entries.
- `VehicleSuggestionStore`: loads and saves learned vehicles and recent selections in Application Support as JSON.
- Built-in suggestions are static defaults in code and are never persisted.

Successful search handling will record visible recommendation vehicle names after ranking. This includes blank-vehicle searches, which are the best source for discovering real available models. Placeholder names such as `未指定车型` are ignored.

The store should keep bounded history:

- Recent selections: newest 20.
- Learned search-result vehicles: newest or most frequent 100.

## Matching And Ranking

Normalize strings by lowercasing, removing spaces, hyphens, middle dots, and common punctuation. Add simple aliases for common models and classes.

Ranking:

1. Exact normalized name or alias prefix.
2. Contains match in name or alias.
3. Source priority: recent, learned, built-in.
4. Recency and count.
5. Localized name order as a stable tie-breaker.

Duplicate names collapse to one row, using the strongest available source label.

## UI Integration

Create a `VehicleSuggestionField` next to the existing `OriginLocationField` style:

- It owns focus/editing state and asks `SearchViewModel` for suggestions.
- It uses the existing workbench surfaces, spacing, captions, and subdued borders.
- It dismisses suggestions when the user picks a suggestion, starts a search, changes date controls, or moves focus away.
- It should not introduce a modal, popover dependency, or new framework.

The dropdown should be compact enough for the left console and reuse the command-console look rather than becoming a large card.

## SearchViewModel Changes

Add published vehicle suggestion state:

- `vehicleSuggestions: [VehicleSuggestion]`
- `isVehicleSuggestionPanelVisible: Bool`

Add actions:

- `refreshVehicleSuggestions(for:)`
- `selectVehicleSuggestion(_:)`
- `dismissVehicleSuggestions()`
- `recordVehicleSuggestions(from recommendations:)`

`recordVehicleSuggestions(from:)` runs after successful search results are ranked and stored. It should not run for failed searches or retained stale results.

## Error Handling

Suggestion persistence is best-effort. If the JSON store cannot be read, start with built-ins and overwrite on next successful save. If save fails, keep in-memory suggestions for the current session and do not block search.

## Testing

Add focused tests for:

- Matching by Chinese text and aliases such as `h5`.
- Source priority and deduplication across recent, learned, and built-in suggestions.
- Recording vehicle names from successful blank-vehicle searches while ignoring placeholders.
- Selecting a suggestion updates `request.vehicleQuery` and hides the panel.
- Source-contract UI test that the search panel uses `VehicleSuggestionField`.

Run:

- `swift test --filter VehicleSuggestion`
- `swift test --filter SearchViewModelTests`
- `swift test`
