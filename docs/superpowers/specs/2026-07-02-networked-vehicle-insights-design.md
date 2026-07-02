# Networked Vehicle Insights Design

## Context

Result cards currently show the vehicle name and platform-provided class text, but they do not explain whether the vehicle is suitable for the user's trip. Rental platform data often includes useful fragments such as energy type, body style, battery or displacement, and seat count. A richer introduction should help users quickly understand the model without affecting search reliability.

## Goal

Add vehicle introductions with two layers:

- A short practical rental suggestion on each result card.
- A longer vehicle introduction in the detail panel, enriched from network sources when available.

The feature must never block or degrade rental search. If network lookup fails, the app should still show a local inferred introduction.

## User Experience

- Result card:
  - Show one concise line below the vehicle name.
  - Example: `纯电三厢 5 座，适合 1-4 人轻行李出行；长途注意补能。`
  - The line should fit the compact card layout and truncate gracefully.
- Detail panel:
  - Add a `车型介绍` section.
  - Show a longer introduction, source label, and source freshness.
  - Distinguish `联网简介` from `本地推断` so users know whether the text came from a network source.
  - Distinguish `车系介绍` from `平台配置`. Network text explains the model family; platform-returned fields explain the rentable vehicle's visible configuration.
  - If the model year cannot be confirmed, show `年款未确认` rather than guessing.
- If the user changes selection, the detail panel may show local inference immediately, then update to network-enriched text when lookup completes.
- Failed or missing network results should not show an error banner. Keep the local fallback and optional muted status text.

## Data Sources

Use stable public encyclopedia-style sources first:

1. Wikipedia REST summary API for page summaries.
2. Wikidata search/SPARQL for model/entity discovery.

Brand official pages may be used only as optional source links in a later enhancement. Do not scrape automotive media sites or app pages in the first version.

## Data Model

Introduce a vehicle insight model:

- `VehicleInsight`
  - `vehicleName: String`
  - `seriesName: String`
  - `configurationSummary: String?`
  - `modelYear: String?`
  - `modelYearConfidence: VehicleInsightConfidence`
  - `trimConfidence: VehicleInsightConfidence`
  - `shortSummary: String`
  - `longSummary: String`
  - `sourceName: String`
  - `sourceURL: String?`
  - `fetchedAt: Date?`
  - `confidence: VehicleInsightConfidence`
  - `origin: VehicleInsightOrigin`
- `VehicleInsightOrigin`
  - `.localInference`
  - `.network`
- `VehicleInsightConfidence`
  - `.high`
  - `.medium`
  - `.low`

Local inference consumes `RentalListing.vehicleName` and `RentalListing.vehicleClass`. It should extract signals such as pure electric, plug-in hybrid, SUV, sedan, MPV, seat count, battery size, and displacement when present.

## Model Year And Trim Confidence

Vehicle introductions must avoid overstating precision. Treat vehicle identity as three layers:

1. `seriesName`: the model family or车系, such as `小鹏 MONA` or `大众朗逸`.
2. `modelYear`: the year款, only set when platform text or network source explicitly includes a year-like signal such as `2024款`, `2025款`, or a platform vehicle-age signal narrow enough to infer a recent year range.
3. `configurationSummary`: visible rentable-vehicle configuration, such as `51kWh`, `三厢`, `5座`, `360影像`, `天窗`, or `1.5T`.

Rules:

- Platform fields have priority for configuration because they describe the rentable listing.
- Network sources explain the model family and must not overwrite platform-returned configuration.
- A model-family network hit is not enough to claim a specific year款 or trim.
- Vehicle-age labels such as `车龄1年内` may produce copy like `近年款车辆`, but must not become a specific model year unless a year is present.
- When confidence is below medium, the detail panel should say `年款未确认` or `配置以平台为准`.
- The short card line should prefer platform signals: `平台标注：纯电三厢 5座，51kWh，车龄1年内；适合市内/短途出行。`
- The detail copy should separate concerns: `车系介绍：... 当前租赁车辆配置以平台返回为准：51kWh、5座、360影像。`

## Service Design

Create `VehicleInsightService` with:

- `localInsight(for listing: RentalListing) -> VehicleInsight`
- `insight(for listing: RentalListing) async -> VehicleInsight`

`insight(for:)` returns cached network insight when fresh, otherwise attempts a network lookup and falls back to local inference.

Cache:

- Store insights in Application Support as JSON.
- Cache key is normalized vehicle name.
- Cache TTL is 30 days.
- Cache writes are best-effort and must not block UI.

Network lookup:

- Normalize model names by stripping rental suffixes such as `自动`, `新能源`, `1.5T`, seat text, and platform marketing fragments.
- Try Chinese and English title/search variants when possible.
- Only accept network summaries when the matched title/entity contains strong model-name overlap.
- Treat network summaries as `seriesName` evidence unless the source explicitly names a year款 or trim.
- If confidence is low, keep local inference rather than showing an unrelated encyclopedia result.

## UI Integration

Result card:

- Add a small `VehicleInsightLine` under the vehicle name row.
- Use existing muted caption style.
- Keep copy short and practical.

Detail panel:

- Add `VehicleInsightSection` near the vehicle/store facts.
- Show title, long summary, source badge, and source link if available.
- Use existing workbench cards and status styling. Do not introduce a modal.

State ownership:

- `SearchViewModel` or a lightweight detail-facing view model owns selected-vehicle insight state.
- On selection change, emit local inference immediately and start async network enrichment.
- Avoid one network request per row during list rendering; only selected/detail insight should fetch network data in the first version.

## Error Handling And Privacy

- Do not send pickup location, rental dates, or user identity to the vehicle insight service.
- Only send normalized vehicle model query text to public sources.
- Network failures, timeouts, and irrelevant matches silently fall back to local inference.
- Surface source metadata when network data is used.

## Testing

Add tests for:

- Local inference from `纯电 51kWh | 三厢 5座`.
- Year and trim confidence from platform text such as `车龄1年内`, `2024款`, `360影像`, and `天窗`.
- Network model-family hits not claiming a concrete year款 or trim.
- Local inference from SUV, MPV, plug-in hybrid, and fuel/displacement strings.
- Cache hit, stale cache miss, and best-effort save behavior.
- Network response mapping with a stub HTTP client.
- Irrelevant network matches falling back to local inference.
- Result panel source contract includes `VehicleInsightLine`.
- Detail panel source contract includes `VehicleInsightSection`.

Run:

- `swift test --filter VehicleInsight`
- `swift test --filter SearchViewModelTests`
- `swift test --filter UIEffectsSourceTests`
- `swift test`
