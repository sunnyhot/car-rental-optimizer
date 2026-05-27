# Car Rental Optimizer Design

## Goal

Build a macOS desktop app that automatically compares eHi and CAR Inc. rental options around the user's current location, including rental price, same-store or different-store return rules, and the cost of traveling to the pickup store by taxi and public transit.

## Product Scope

The first version opens directly to the comparison tool. The user grants location access or enters a manual starting point, chooses pickup and return dates, chooses same-store or different-store return, enters a desired model such as "瑞虎8", sets a search radius that defaults to 100 km and can be expanded to 500 km or more, then runs a search across eHi and CAR Inc.

The app ranks every candidate by total cost. Each candidate shows rental cost, platform fees, one-way return fees when available, taxi cost to the pickup store, public transit cost to the pickup store, travel time, store details, vehicle match confidence, and links back to the source platform page.

The app does not place orders or pay for rentals in the first version.

## Platform Automation

The recommended technical path is local browser automation. The app maintains local browser sessions for eHi and CAR Inc. The user logs in inside platform-owned pages, handles SMS or captcha prompts manually when required, and the app reuses the local session to search future prices.

Each rental provider is implemented behind a platform adapter interface:

- `EhiAdapter` for eHi.
- `CarIncAdapter` for CAR Inc.
- `MockRentalAdapter` for local development and tests.

Adapters return normalized search results instead of leaking page selectors or platform-specific fee names into the UI.

The real site adapters are expected to be maintained separately from the ranking and UI logic because rental platform pages may change without notice. If an adapter cannot complete a query, it returns a typed status such as login required, captcha required, no inventory, selector mismatch, or partial result.

Official platform entry points used by the design:

- eHi official site: https://www.1hai.cn/
- CAR Inc. official site: https://www.zuche.com/
- CAR Inc. store service site: https://service.zuche.com/

## Traffic Cost Model

Traffic cost is calculated through a map service adapter. The first implementation supports mocked route data and is structured for a future Gaode, Tencent Maps, or Baidu Maps integration.

For every pickup store, the app requests two route families:

- Taxi route: estimated fare, distance, and duration.
- Public transit route: fare, distance, duration, and route summary.

Cross-city pickup is valid when the store is inside the configured radius. For example, if the user is in Beijing Tongzhou and sets the radius to 500 km, Dezhou East Station can be included and can win if rental price plus pickup travel cost is lower.

## Vehicle Matching

Vehicle matching is explicit and conservative:

- Exact model match: the listing name or normalized aliases match the requested model, such as "瑞虎8".
- Similar class match: the requested model and listing are in the same class, such as mid-size SUV.
- Low-confidence substitute: the adapter has incomplete model metadata.

The app never presents a substitute as the exact requested car. Every result carries a match label and confidence score.

## Recommendation Model

The app calculates:

- `rentalTotal`: base rental price plus platform fees, insurance/service fees, and known one-way return fees.
- `taxiTotal`: `rentalTotal + taxiPickupCost`.
- `transitTotal`: `rentalTotal + publicTransitPickupCost`.
- `bestTotal`: the lower of taxi and transit totals.
- `timePenaltyMinutes`: shown separately in the first version, not converted into money by default.

Default sorting is by `bestTotal`, then exact vehicle match, then shorter travel time, then higher data completeness.

## UI Structure

The UI follows a mainstream macOS desktop utility layout:

- Left search panel: current location, pickup and return dates, return mode, radius, vehicle query, platform toggles, and search action.
- Center ranked result list: platform, store, model, total prices, route summaries, and match confidence.
- Right detail panel: recommendation summary, full cost breakdown, route details, store metadata, warnings, source links, and recheck action.

The first screen is the working tool, not a marketing landing page.

## Data Storage And Privacy

Search history, preferences, and platform session state stay on the local Mac. The app should not upload platform credentials or travel history to any custom backend.

The app stores only normalized comparison data needed for history and debugging. Sensitive session data should remain inside the automation browser profile where possible.

## Error Handling

The UI exposes actionable states:

- Location permission denied: allow manual starting point.
- Login expired: open platform login window.
- Captcha or SMS required: pause search and let the user complete the challenge.
- Platform selector mismatch: mark that platform as unavailable and keep other platform results.
- No inventory: show the store/platform as searched with no matching cars.
- Partial price: include the result but lower data completeness.
- Map API unavailable: show rental-only ranking and mark traffic cost missing.

## Testing Strategy

Core ranking and matching logic are tested with Vitest before implementation. Tests cover exact model preference, similar model fallback, total-cost ranking, taxi/transit split, and cross-city low-rental-price recommendations.

UI tests are kept lightweight in the first version. The build must pass TypeScript and Vite production compilation.

