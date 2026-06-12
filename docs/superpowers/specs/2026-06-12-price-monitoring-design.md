# Price Monitoring And History Design

## Goal

Add a complete local price monitoring loop to the SwiftUI macOS car rental optimizer.

The user can monitor a rental plan for a selected pickup/return time, vehicle, location, return mode, and existing platform set. The app periodically rechecks official eHi and CAR Inc results, compares the new platform rental price with the previous valid snapshot, records historical price trends, and alerts the user when prices fall.

## Product Decisions

- Do not add new rental platforms in this phase.
- Store monitoring data locally on the Mac. No account system, cloud sync, or remote service is introduced.
- Preserve old quote values as historical snapshots. They can be used for trend comparison, but the UI must mark them as historical and possibly stale.
- Default monitoring runs while the app is open.
- A background monitoring switch is available. In the first implementation, background mode keeps a lightweight app/menu-bar process active when the main window is closed. If the user explicitly quits the app or macOS terminates it, due monitors catch up on the next launch.
- Track both platform rental price and recommendation total cost.
- Price-drop alerts default to platform rental price so route estimate changes do not create noisy alerts.
- Support both result-driven monitor creation and manual monitor creation.
- Keep in-app events for every alert-worthy change. System notifications are optional and require user permission.

## Scope

### In Scope

- Monitor center UI.
- Create a monitor from a current recommendation.
- Manually create and edit a monitor.
- Local persistence for monitors, snapshots, and events.
- Foreground scheduler with smart and fixed frequency options.
- Optional background mode for monitoring while the main window is closed.
- Price-drop rules:
  - any decrease,
  - decrease by at least a fixed amount,
  - decrease by at least a configured percentage.
- Historical trend display for:
  - platform rental price,
  - recommendation total cost.
- In-app price-drop event log.
- Optional macOS notifications for price drops.
- Failure snapshots for login required, captcha required, unavailable, no car, parse failed, and network/search failures.
- Automatic monitor pause after pickup time has passed.

### Out Of Scope

- New rental platforms.
- Server-side monitoring.
- Multi-device sync.
- Payment, booking, or checkout automation.
- Guaranteed monitoring after the user explicitly quits the app.
- Developer ID signing, notarization, or Sparkle changes.
- Replacing JSON storage with SQLite in the first implementation.

## User Stories

1. As a renter, I want to monitor a car plan I found, so I can know when the platform price drops before I book.
2. As a renter, I want to create a monitor manually before searching, so I can watch a planned trip in advance.
3. As a renter, I want to see price history, so I can judge whether the current price is unusually high or low.
4. As a renter, I want clear alerts when prices fall, so I can act quickly without repeatedly checking manually.
5. As a renter, I want old quotes kept but marked as historical, so I do not confuse stale prices with live bookable prices.

## Requirements

1. WHEN the user creates a monitor from a recommendation THEN the system SHALL save the monitor request and append the current recommendation as the first price snapshot.
2. WHEN the user creates a monitor manually THEN the system SHALL save the monitor request and mark it as waiting for the first check.
3. WHEN a monitor reaches its next check time THEN the system SHALL query eHi and CAR Inc through the existing official data flow.
4. WHEN a monitor check returns recommendations THEN the system SHALL select the closest matching recommendation for the monitored vehicle and request.
5. WHEN a successful recommendation is selected THEN the system SHALL append a snapshot containing platform rental price, recommendation total cost, platform, store, vehicle, data completeness, warnings, and source status.
6. WHEN a new platform rental price is lower than the previous valid snapshot THEN the system SHALL create a price-drop event if at least one enabled alert rule is satisfied.
7. IF system notifications are enabled and notification permission is granted THEN the system SHALL send a macOS notification for a price-drop event.
8. WHEN the user opens a monitor detail THEN the system SHALL show both platform rental price and recommendation total cost history.
9. WHEN historical quote values are shown THEN the system SHALL label them as historical snapshots that may no longer be available.
10. IF a platform check requires login, requires captcha, returns no car, fails parsing, or fails with an error THEN the system SHALL append a failure snapshot and SHALL NOT create a price-drop event.
11. WHEN a monitor has repeated failures THEN the system SHALL show the monitor as needing attention and record an event.
12. WHEN a previously failing monitor succeeds again THEN the system SHALL record a recovery event.
13. WHEN the pickup time has passed THEN the system SHALL pause the monitor automatically.
14. IF the user selects smart frequency THEN the system SHALL calculate the next check interval from the pickup time.
15. IF the user selects a fixed frequency THEN the system SHALL use the selected interval of 30 minutes, 1 hour, 3 hours, or 1 day.

## Monitoring Frequency

`MonitoringFrequency` supports:

- `smart`
- `fixed30Minutes`
- `fixed1Hour`
- `fixed3Hours`
- `fixed1Day`

Smart frequency:

- More than 7 days before pickup: check daily.
- Within 7 days before pickup: check every 3 hours.
- Within 2 days before pickup: check every 1 hour.
- Within 12 hours before pickup: check every 30 minutes.
- After pickup time: pause automatically.

The scheduler should apply small jitter to due checks so multiple monitors do not hit platform APIs at exactly the same time.

## Alert Rules

Each monitor has an alert configuration:

- `notifyOnAnyDecrease`
- `minimumDropAmount`
- `minimumDropPercent`

The default is `notifyOnAnyDecrease = true`, with no amount or percentage threshold. If the user configures multiple rules, a price-drop event is created when any enabled rule passes.

Alert comparison uses platform rental price. Recommendation total cost is stored and displayed for context.

## Domain Model

Add pure domain types under `Sources/CarRentalDomain`:

- `PriceMonitor`
- `PriceMonitorStatus`
- `MonitoringFrequency`
- `PriceDropRule`
- `PriceSnapshot`
- `PriceSnapshotStatus`
- `PriceMonitorEvent`
- `PriceMonitorEventKind`
- `PriceTrendSummary`

`PriceMonitor` should contain:

- stable id,
- display name,
- `SearchRequest`,
- target vehicle query,
- optional target platform,
- optional target listing signature from the original recommendation,
- frequency,
- alert rules,
- notification setting,
- status,
- created time,
- updated time,
- last checked time,
- next check time.

`PriceSnapshot` should contain:

- stable id,
- monitor id,
- checked time,
- status,
- platform rental price when available,
- recommendation total cost when available,
- platform and store metadata when available,
- vehicle metadata when available,
- data completeness,
- warnings,
- source URL,
- user-facing status message.

`PriceMonitorEvent` should contain:

- stable id,
- monitor id,
- event time,
- kind,
- previous snapshot id when relevant,
- current snapshot id when relevant,
- platform rental price delta when relevant,
- total cost delta when relevant,
- message.

## Persistence

Add a `MonitorStore` abstraction in the app layer:

- `listMonitors()`
- `saveMonitor(_:)`
- `deleteMonitor(id:)`
- `appendSnapshot(_:)`
- `snapshots(for:)`
- `appendEvent(_:)`
- `events(for:)`
- `markMonitorStatus(id:status:)`

The first implementation should use versioned JSON files under Application Support:

- `monitors.json`
- `price-snapshots.json`
- `monitor-events.json`

The store writes atomically by saving to a temporary file and replacing the previous file. Corrupt files are not silently discarded; the UI should surface a storage error and preserve the unreadable file for manual recovery.

## Scheduler

`MonitorScheduler` lives in the app layer and coordinates:

- due monitor selection,
- platform querying through the existing `RentalSearchProviding`,
- recommendation ranking through existing domain ranking,
- snapshot creation,
- event creation,
- notification dispatch,
- next check calculation.

The scheduler should:

- start on app launch,
- run due checks while the app is open,
- catch up due monitors after app launch or resume,
- limit concurrent checks,
- skip paused monitors,
- avoid starting duplicate checks for the same monitor,
- update monitor status during checking,
- back off after repeated failures.

Background mode should be implemented conservatively. When enabled, closing the main window should keep the scheduler alive in a lightweight background/menu-bar state. Explicit app quit stops monitoring until the next launch.

## Recommendation Matching

For a monitor created from a recommendation, store a listing signature made from:

- platform,
- store id or normalized store name/address,
- normalized vehicle name,
- vehicle class when available.

On each check:

1. Prefer exact platform, store, and normalized vehicle match.
2. If the exact store is unavailable, prefer the same platform and normalized vehicle.
3. If the same platform is unavailable, use the best ranked recommendation for the same normalized vehicle across selected platforms.
4. If no acceptable match exists, append a no-match failure snapshot.

Manual monitors without an initial recommendation use the existing ranking result for the target vehicle query.

## UI Design

### Existing Result Flow

Add a monitor action to:

- result row,
- recommendation detail panel.

The action opens a confirmation sheet showing:

- trip time,
- origin,
- return mode,
- target vehicle,
- platform/store when known,
- current platform rental price,
- current recommendation total cost,
- frequency,
- alert rules,
- system notification toggle.

### Monitor Center

Add a monitor center entry from the app header and app menu.

The monitor center contains:

- monitor list,
- monitor detail,
- create/edit monitor sheet,
- historical trend chart,
- snapshot table,
- event log.

Monitor list rows show:

- vehicle and trip dates,
- current status,
- last platform rental price,
- change from previous valid snapshot,
- last check time,
- next check time,
- attention badge for login, captcha, repeated failure, or paused state.

Monitor detail shows:

- summary header,
- two-line trend chart for platform rental price and recommendation total cost,
- latest successful quote,
- price-drop events,
- failure/recovery events,
- snapshot table with historical/stale label,
- controls for frequency, alert rules, notifications, pause/resume, and delete.

## Error Handling

- Login required snapshots show an action to open the existing eHi login sheet when the failed platform is eHi.
- Captcha required snapshots do not retry aggressively; the monitor is marked as needing attention.
- No-car snapshots are kept as valid check results but do not trigger price-drop alerts.
- Parse failures and network failures are failure snapshots.
- Repeated failures create an attention event after a small threshold, such as 3 consecutive failures.
- Recovery after failure creates a recovery event.
- Storage errors are shown in monitor center and do not destroy existing in-memory results.

## Privacy And Safety

- All monitor data remains local.
- No external analytics or telemetry are added.
- The app should avoid excessive platform calls by respecting the configured interval, adding jitter, limiting concurrency, and backing off on repeated failures.
- Notification text should avoid exposing too much trip detail on the lock screen. It can say the monitored rental price dropped and show the delta; detailed trip data appears after opening the app.

## Testing

Domain tests:

- smart frequency intervals,
- fixed frequency intervals,
- automatic pause after pickup time,
- price-drop rule evaluation,
- trend summary generation,
- recommendation matching fallback order,
- stale historical label rules.

Store tests:

- JSON round trip for monitors, snapshots, and events,
- append-only snapshot behavior,
- atomic replacement behavior where practical,
- corrupt file handling.

Scheduler/ViewModel tests:

- create monitor from recommendation,
- create manual monitor,
- due monitor check success,
- due monitor check with no listings,
- login/captcha/failure snapshot behavior,
- price-drop event creation,
- no event when price is unchanged or higher,
- notification dispatch only when enabled,
- repeated failure attention event,
- recovery event,
- paused monitor skip.

UI-oriented tests where practical:

- monitor center state formatting,
- trend data preparation,
- stale snapshot copy,
- create-monitor sheet defaults.

Primary verification remains:

```bash
swift test
```

## Rollout

1. Add pure domain monitor models and tests.
2. Add local JSON store and tests.
3. Add scheduler with fake search provider tests.
4. Add monitor center view model.
5. Add result-to-monitor creation flow.
6. Add monitor center UI.
7. Add notification service.
8. Add background monitoring switch behavior.
9. Update README and changelog after implementation.

## Open Constraints Resolved For This Design

- Platform scope: eHi and CAR Inc only.
- Persistence: local Application Support JSON.
- Historical quote policy: preserve and clearly mark stale.
- Runtime policy: foreground by default, optional background/menu-bar mode.
- Frequency policy: smart default with fixed choices.
- Alert policy: any decrease by default, optional amount and percentage thresholds.
- Trend policy: track both platform rental price and recommendation total cost.
- Creation policy: from recommendation and manual monitor creation.
- Notification policy: in-app events always, macOS notifications optional.
