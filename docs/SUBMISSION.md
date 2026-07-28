# Submission checklist

Everything needed to get Shifty onto TestFlight and, later, the App Store.

## Blocking: toolchain

Shifty is currently built against **beta Xcode 27 / iOS 26**. The App Store only accepts builds made with the released (GM) Xcode and SDK, so **App Store submission must wait until iOS 26 ships publicly**. TestFlight accepts beta-SDK builds during the beta period, so internal testing can start now.

When the GM arrives: open the project in release Xcode, rebuild, re-run the tests, and archive. No code changes are expected.

Also decide before launch: the deployment target is **iOS 26.0**, so only devices already updated can install. Lowering it means giving up Foundation Models, the newer widget families, and `.sidebarAdaptable`.

## Before the first upload

- [ ] Confirm a paid **Apple Developer Program** membership.
- [ ] Create the app record in App Store Connect (Platform: iOS, Bundle ID `kseabury.Shifty`).
  - The public name must be unique — "Shifty" alone is likely taken. Something like _Shifty: Shift & Pay Tracker_ keeps the on-device name "Shifty".
- [ ] Bump **Build** (target → General) before every archive; version stays 1.0 until content changes.
- [ ] **Deploy the CloudKit schema to production** at [icloud.developer.apple.com](https://icloud.developer.apple.com) → container `iCloud.kseabury.Shifty` → Deploy Schema Changes. TestFlight and App Store builds use the production environment; without this, sync silently does nothing.

## Archive and upload

1. Destination: **Any iOS Device (arm64)** → Product → Archive.
2. Organizer → Distribute App → TestFlight (Internal Only) → Upload.
3. The watch app and both extensions are embedded in the archive automatically.
4. `ITSAppUsesNonExemptEncryption` is already declared, so no export-compliance prompt appears.

## App Store Connect content

- [ ] **Privacy policy URL** — required even though nothing is collected. Host `docs/PRIVACY.md` (GitHub Pages, a gist, or any static page) and fill in a contact email first.
- [ ] **Privacy nutrition label** — answer **Data Not Collected**. No tracking, no third-party SDKs.
- [ ] **Screenshots** — 6.9" iPhone and 13" iPad required. Use the launch arguments to populate a clean device:
  ```sh
  xcrun simctl launch <device> kseabury.Shifty -seedDemoData YES -startSection pay
  ```
  `-startSection` accepts `home`, `shifts`, `calendar`, `pay`, `settings`.
- [ ] **Category** — Productivity (Business is a reasonable secondary).
- [ ] **Age rating** — 4+.

## Reviewer notes (paste into App Review Information)

> Shifty is an offline shift-and-pay tracker. No account or login is required — launch the app and use it immediately.
>
> A few notes that may help testing:
>
> • **iCloud sync** keeps shifts in the user's own private CloudKit database so they appear on their other devices. It cannot be observed on a single device, and the app is fully functional without an iCloud account.
>
> • **Apple Intelligence features** ("Describe Shift" in the new-shift form and "Import from Text" in the Shifts tab) only appear on devices that support Apple Intelligence and have it enabled. On other devices they are hidden and the app works normally.
>
> • **Notifications** (shift reminders, tip prompts, weekly summary) are opt-in from Settings and are scheduled locally.
>
> • **Calendar access** is requested only when the user taps "Export Month to Calendar" in the Calendar tab, and is write-only.
>
> • The app never requests location. Workplace pins are places the user searches for; the device's own location is never used.

## Known limitations (not blockers)

- Settings (week start, pay cycle, goals, overtime) live in per-device storage, so the Apple Watch app uses defaults until settings sync is added.
- The UI walkthrough test targets iPhone; on iPad it stalls on the onboarding sheet.
- The app is English-only; all strings are localization-ready but no translations exist yet.
- No VoiceOver end-to-end audit has been done, though accessibility labels are in place throughout.
