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

## State

- 2026-10-31: v1 build 1 in TestFlight ("Box Box RC"), CI green on the first run (CarKit's 11 tests, archive,
  upload). It drives Julien's SF-25 (Julien: "It work"), so the SF-25 speaks the SL protocol of the 2023-2025
  Ferrari cars (README.md). Next build carries the new icon (checkered flag, committed with [skip ci]).

- 2026-10-31, builds 2 to 9: the isometric game's floating sticks and tiles (README.md), BOOST, one menu, one layout;
  HOLD 360 fixed with a UI test (app/UITests). Next: the autopilot, starting with the LiDAR room scan (Julien's pick).

## v2 later: autopilot in the app

A RoomPlan (LiDAR) room scan gives a floor plan with obstacles; the phone, propped up, looks at the floor; Vision or
Core ML tracks the car; closed-loop control drives it to a tapped point or along a drawn track, with an AR overlay of
the path.

## Builds: GitHub Actions → TestFlight

Repository `JulienMalige/rc-car` (public); `.github/workflows/ios.yml` builds and uploads on every push that touches
`app/`, `CarKit/` or the workflow. The app is "Box Box RC" in App Store Connect (app id `6829202941`), its TestFlight
group "Internal" gets every build. README.md, "Build and release", has the Apple side (bundle id, profile, secrets).
- Copied from `~/isometric-racing/.github/workflows/ios.yml` and TV Scores' `docs/release.md` (the App Store Connect
  key and the distribution certificate live in `~/.config/tvscores/`, this app's profile in `~/.config/rccar/`).
  Never print or commit a key, certificate or profile.
- Public repository since 2026-10-31: the account's free macOS minutes for private repositories ran out on build 3,
  and Julien's rule was to make it public then (public repositories build free). Keep anything personal out of it
  (where Julien is, his plans): the travel line was removed from the whole history before it went public. Secrets live
  only in the repository's GitHub secrets and in `~/.config/`.
- No Mac and no Swift toolchain on the VPS: the CI run is the compiler. CarKit (the packet formats) has XCTest tests
  that run first in CI (`swift test --package-path CarKit`).

## Rules

- Ask Julien before anything that costs money (Apple or App Store items, sniffer hardware).
- When v1 is ready, send Julien the TestFlight link and a phone notification.

## This session

`rc-car` on the VPS (Zellij session, Remote Control name and title), unit `claude-rc-car.service`. It runs Opus 5.5
at effort max through the unit's flags (`--model claude-opus-5-5 --effort max`), for this session only: the global
settings stay as they are.
