# Show All Vehicle Matches Design

## Context

When a user enters a concrete vehicle model, the app should stay focused on that model. The default result should remain the cheapest matching recommendation so the main answer is fast to read. Sometimes the user still needs to inspect every matching quote across stores and platforms, especially when validating that mobile app inventory exists but the desktop view only shows one candidate.

## Goal

Add a result-panel control that lets users switch between the cheapest matching vehicle result and all matching quotes for the requested vehicle.

## User Experience

- With a concrete vehicle query, the result list defaults to the cheapest matching result.
- If the same query has more than one matching recommendation, show a compact control in the result filter area.
- The control has two states:
  - `只看最低价`: default, displays the lowest-total recommendation for the requested vehicle.
  - `显示全部匹配`: displays all recommendations that match the requested vehicle, sorted by the current result sort mode.
- The control should not show when the vehicle query is blank, generic class-only, or when there is only one matching result.
- The existing filters still apply after the match expansion state. A user can expand all matches and then filter by platform, budget, distance, or fee completeness.
- Starting a normal new search resets the control to the default cheapest-only state.
- Retrying failed platforms keeps the current state, matching the existing retry behavior for result filters.

## Data Flow

The domain ranking layer should keep enough exact-match recommendations for the UI to decide whether to collapse or expand. The ViewModel owns display state:

- `showsAllVehicleMatches`: whether the user wants all matches for a concrete vehicle query.
- `hasExpandableVehicleMatches`: whether the current result set contains multiple matches for the concrete query.
- `displayedResults`: applies the cheapest-only collapse when `showsAllVehicleMatches` is false, then applies the existing recommendation filters and sort mode.

The cheapest-only collapse uses the current total-cost ranking rule and should be deterministic on ties.

## UI Integration

Place the control in `RecommendationFilterBar`, near the existing count and clear-filter command. Use a compact button or segmented-style toggle with SF Symbols, consistent with the current workbench style. It should read as a result-display control, not as another platform API search condition.

The panel subtitle should reflect the collapsed state, for example `1/N 个匹配，显示最低价`, while the expanded state can continue to show the filtered count.

## Testing

Add focused tests for:

- A concrete vehicle query defaults to one cheapest displayed result when multiple exact matches exist.
- Toggling `showsAllVehicleMatches` displays all exact matches.
- Blank or generic vehicle queries do not use the concrete-model collapse.
- Starting a normal new search resets `showsAllVehicleMatches`; retrying failed platforms keeps it.

Run:

- `swift test --filter SearchOrchestratorTests`
- `swift test --filter SearchViewModelTests`
- `swift test`
