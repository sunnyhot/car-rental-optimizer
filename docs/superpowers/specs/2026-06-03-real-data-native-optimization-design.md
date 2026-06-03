# Real Data Native Optimization Design

## Goal

Turn the native macOS app from a runnable mock demo into a trustworthy rental comparison tool. The app must never fabricate platform inventory, especially when a platform such as CAR Inc. has not opened rentals for the selected date range.

## Product Positioning

The app is a decision tool for choosing the lowest practical rental option after including the cost and inconvenience of reaching the pickup store. It should compare official platform evidence, route estimates, vehicle match quality, and platform availability states. When evidence is missing, the app should say so plainly instead of ranking guessed data.

The app name will be `租车比价助手`. The icon direction is a macOS rounded-square mark with a car, map pin, and yuan symbol to communicate rental, location, and total cost.

## Data Approach

The production Swift app will stop calling mock rental adapters. It will use a real platform evidence workflow:

- Users can open official one-click platform links.
- Users paste official page text or HTML from each platform after searching on the platform.
- The app parses pasted evidence into listings only when prices, vehicles, and stores can be identified.
- Platform text containing no-availability, not-open, login, or captcha signals becomes an explicit platform status and does not create listings.

Route cost remains a transparent local estimate, not a fake platform value. It is renamed and presented as an estimate so users can distinguish official rental evidence from route calculation.

## Platform States

Each selected platform has one of these states:

- `waiting-for-evidence`: no official page content has been provided.
- `ready`: one or more listings were parsed from official evidence.
- `unavailable`: the platform page says the selected period is not open, unavailable, or has no cars.
- `login-required`: the platform page requires login before results are visible.
- `captcha-required`: the platform page requires verification.
- `parse-failed`: official content was present but no listing could be extracted.

Only `ready` listings enter the ranked candidate list.

## Date Rules

The native UI uses date-only selection:

- Pickup date cannot be earlier than today.
- Return date cannot be earlier than pickup date.
- Requests use `yyyy-MM-dd`.
- Billing days use whole calendar-day differences and always return at least one day.

## UI Design

The three-panel layout stays, but copy and states change:

- Header says `租车比价助手` and `真实数据工作流`.
- Search panel includes official platform links and a compact evidence input area for selected platforms.
- Empty results explain which platform evidence is missing or unavailable.
- Results show parsed official rental listings and estimated route totals.
- Detail panel keeps total cost breakdown and labels partial platform prices clearly.

The visual tone is a quiet utility app: dense, scan-friendly, no marketing hero, no decorative cards within cards.

## Testing

Swift tests cover:

- Date-only formatting, clamping, and day-count calculation.
- Platform evidence parser states for no evidence, unavailable CAR Inc. periods, login/captcha, parse failure, and parsed listings.
- SearchViewModel does not return mock listings by default.
- SearchViewModel ranks pasted real evidence and preserves unavailable platform diagnostics.
- AppInfo uses the new app name.

## Non-Goals

This change does not promise a private platform API, bypass login, bypass captcha, or silently scrape pages against platform controls. Those require explicit platform support or user-controlled official pages.
