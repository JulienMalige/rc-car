# rc-car

A native iPhone app (SwiftUI + CoreBluetooth) to drive Julien's Bluetooth RC car. Started on 2026-10-31 at Julien's
request (relayed by the Pi's root session, `pi-root`).

## The car

Shell V-Power promo car: Bburago Ferrari SF-25, 1/41 scale (Leclerc's #16, "75" livery), driven over Bluetooth.
Julien got it on 2026-10-30 at a Shell station.

## Julien's side

- iPhone 16 Pro Max (iPhone17,2, with LiDAR). No computer: iPad and iPhone only, so no Xcode and no Mac.
- The app must work standalone on the phone.

## v1 first: aim for a TestFlight build within a few hours

- Manual control: throttle/brake, steering, turbo, and lights if the car supports them.
- A BLE discovery/debug screen: scan, list services and characteristics, log notifications and send raw bytes, so
  Julien can screenshot what his car exposes.

Starting points for the protocol: others have already reverse-engineered the Shell/Bburago BLE cars (UUIDs can differ
per model). Read their code for the packet format:
- https://pypi.org/project/shell-motorsport/
- https://github.com/jenkings/BLE-RC-Car-ESP32 (has a Bburago mode)
- https://github.com/ariasbruno/rc-commander

## v2 later: autopilot in the app

A RoomPlan (LiDAR) room scan gives a floor plan with obstacles; the phone, propped up, looks at the floor; Vision or
Core ML tracks the car; closed-loop control drives it to a tapped point or along a drawn track, with an AR overlay of
the path.

## Builds: GitHub Actions → TestFlight

Same Apple developer team and pipeline as Julien's other apps (the Voice app, Ultimate Motorsports). No GitHub
repository yet. What to copy:
- `~/isometric-racing/.github/workflows/ios.yml` (Ultimate Motorsports' native iOS app: XcodeGen, manual signing,
  upload to App Store Connect) and its `native/ios/README.md`, section "Apple side".
- `~/tvscores/docs/release.md`: the App Store Connect API key and the distribution certificate (both in
  `~/.config/tvscores/`, files 600), and how to mint a profile without a Mac.
- Bundle ids are `com.julienmalige.<app>`, registered by API; each app's App Store profile is kept in
  `~/.config/<app>/` (700, files 600). Never print or commit a key, certificate or profile.
- The app's record in App Store Connect is made by hand (the API cannot create apps): ask Julien early.

## Rules

- Ask Julien before anything that costs money (Apple or App Store items, sniffer hardware).
- When v1 is ready, send Julien the TestFlight link and a phone notification.

## This session

`rc-car` on the VPS (Zellij session, Remote Control name and title), unit `claude-rc-car.service`. It runs Opus 5.5
at effort max through the unit's flags (`--model claude-opus-5-5 --effort max`), for this session only: the global
settings stay as they are.
