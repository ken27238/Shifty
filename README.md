# Shifty

A shift-work tracker for iPhone, iPad, and Apple Watch. Log shifts, see what your paycheck should say, and keep your schedule on your Home Screen, Lock Screen, and watch face.

Built with SwiftUI and SwiftData, synced across devices with CloudKit, and entirely on-device — no accounts, no servers, no tracking.

## Features

### Tracking
- **Home dashboard** — a job-tinted hero card for the current or next shift (live timer, countdown, estimated pay, and a map of the workplace with directions), weekly stats with goal progress, and compact upcoming/recent lists
- **Shifts list** — grouped by week with per-week hours and earnings, search, job filtering, jump-to-date, overtime and in-progress badges, swipe to duplicate, repeat today/tomorrow, and multi-select delete
- **Calendar** — month grid with job-colored dots (hollow for scheduled, filled for worked), a week timeline, a year heat map, drag a shift to another day, copy/paste whole days, and a rotation generator (e.g. 4 on, 4 off from a template)
- **Templates** — save common shifts and apply them in the form or generate weeks of them at once
- **Locations** — jobs and individual shifts can carry a place (Apple Maps search); repeat/duplicate/copy flows preserve it

### Pay
- **Pay cycles** — weekly, biweekly (anchored to your real period start), semimonthly, or monthly, with a payday countdown and expected pay
- **Overtime** — configurable threshold (per week or per day) and multiplier, applied consistently across totals, charts, exports, and the watch
- **Tips, mileage, and expenses** per shift; estimated take-home percentage; weekly earnings goal
- **Charts** — earnings by day (stacked by job) and a multi-period trend, plus a per-job breakdown that links into the filtered shift list
- **Exports** — CSV (full or per-period, re-importable) and a one-page PDF pay summary

### Beyond the app
- **Five iOS widgets** — Up Next (configurable per job, with Lock Screen families), This Week (with an interactive Repeat Last Shift button), Payday, Schedule, and a Month heat map — all deep-linking into the right tab
- **Apple Watch app** — Up Next with live timer, a This Week gauge, and an Upcoming list, plus watch-face complications in all four accessory families
- **Siri & Shortcuts** — "When's my next shift?", "How many hours this week?", "Log a shift"
- **Apple Intelligence** *(on supported devices)* — describe a shift in plain language to fill the form, or paste a schedule and review the extracted shifts before importing; both run fully on-device with guided generation
- **Notifications** — shift reminders with configurable lead time, tip-logging nudges when shifts end, and a weekly summary

## Requirements

- **Xcode 27 beta** — the project file uses a format (`objectVersion = 110`) that stable Xcode cannot open
- iOS / iPadOS 26.0+, watchOS 26.0+
- Apple Intelligence features require a supported device with it enabled; the app fully works without it
- CloudKit sync requires an iCloud account; the app falls back to local storage without one

## Project layout

| Target | What it is |
|---|---|
| `Shifty` | The iOS/iPadOS app |
| `ShiftyWidgets` | Home Screen / Lock Screen widget extension |
| `ShiftyWatch` | The watchOS app (own store, synced via CloudKit) |
| `ShiftyWatchWidgets` | Watch-face complications |
| `ShiftyTests` / `ShiftyUITests` | Unit tests for the pay math and a UI walkthrough that screenshots every screen |

Shared code lives in `Shared/` and compiles into every target: the SwiftData models (`Shift`, `Job`, `ShiftPreset`), the overtime-aware `PayCalculator`, pay-period math (`PayPeriods`), and settings plumbing. `Schema.shifty` is the single source of truth for the model schema — when adding a model, that is the only registration to update.

Settings live in app-group `UserDefaults` (shared with the widgets); shift data lives in a SwiftData store in the app group container, mirrored through CloudKit. Note that settings are per-device — the watch currently uses defaults until a settings-sync mechanism exists.

## Building

1. Open `Shifty.xcodeproj` in Xcode 27 beta.
2. Change the bundle identifiers, development team, App Group (`group.kseabury.Shifty`), and iCloud container (`iCloud.kseabury.Shifty`) to your own throughout the targets and `.entitlements` files.
3. Build and run the `Shifty` scheme. The watch app runs from the `ShiftyWatch` scheme on a watchOS simulator.

From the command line:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme Shifty -destination 'generic/platform=iOS Simulator' build
```

## Testing

```sh
# Pay math, pay periods, and model behavior
xcodebuild test -scheme Shifty -destination '<simulator>' -only-testing:ShiftyTests

# Full UI walkthrough: onboarding, first shift, every tab (attaches screenshots)
xcodebuild test -scheme Shifty -destination '<simulator>' -only-testing:ShiftyUITests
```

## Privacy

Everything stays on your devices and in your private iCloud database. The app collects nothing, tracks nothing, and ships privacy manifests for the app and each extension. Apple Intelligence features process text on-device. Location is only ever a workplace pin you chose — the app never requests your location.

Full text: [docs/PRIVACY.md](docs/PRIVACY.md).

## Shipping

[docs/SUBMISSION.md](docs/SUBMISSION.md) covers TestFlight and App Store prep — including the current blocker (the project builds against beta Xcode 27 / iOS 26, and the App Store requires a released SDK), the CloudKit production-schema step, and reviewer notes.

## License

No license has been chosen yet — all rights reserved until one is added.
