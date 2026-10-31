# RC Car

An iPhone app (SwiftUI + CoreBluetooth) that drives Shell's promotional Bluetooth cars without the Shell app: Julien's
Bburago Ferrari SF-25 first. On TestFlight as **Box Box RC**; on the home screen it is "RC Car".

## The cars

Two families of Shell cars have been decoded by others. The app tells them apart by the characteristics a car has
once connected (`CarKit/Sources/CarKit/CarCatalog.swift`), and the settings can force one.

| | SL (Bburago Ferrari, 2023 onwards) | QCAR (Brandbase, 2020) |
|---|---|---|
| Advertised name | `SL-<model>` (`SL-SF-24`, `SL-499P`…) | `QCAR-<last 3 bytes of the MAC>` |
| Write to | `FFF1` in service `FFF0` | `D44BC439-ABFD-45A2-B575-925416129600` in `FFF0` |
| Frame | 8 bytes in clear: `01 fwd back left right lights turbo spin` | 16 bytes, AES-128-ECB: `00 'CTL' fwd back left right lightsOff speed 00…` |
| Battery | Battery service `180F`/`2A19` if present | notifications on `…9601`, `seq 'VBT' percent` |

Sources: [ariasbruno/rc-commander](https://github.com/ariasbruno/rc-commander) (`controllers/SLController.ts`, the
SL car list), [jenkings/BLE-RC-Car-ESP32](https://github.com/jenkings/BLE-RC-Car-ESP32) (both families), scrool's
[protocol notes](https://gist.github.com/scrool/e79d6a4cb50c26499746f4fe473b3768) (the QCAR key and battery
notifications). The QCAR clear layout comes from decrypting the frames those projects replay: the gist's table is one
byte off from offset 8. `CarKit/Tests` checks our encoder against every known frame.

Shell's 2026 Brazilian series (SF-25, SF90 XX, 488 Challenge, F80, 12Cilindri) speaks SL like the 2025 one: build 1
drove Julien's SF-25 on 2026-10-31.

## The app

- **Drive** (`app/Sources/Drive`): by default the isometric game's floating sticks (`TwinSticks.swift`, after
  `~/isometric-racing/game/src/platform/touch.js`): a steering ring jumps under the left thumb, a gas/reverse slider
  under the right; past 35 % of the travel a direction is on (the cars are digital). Between them, three columns in
  the game's look (`Tiles.swift`: Barlow Semi Condensed and Saira ExtraBold Italic, glossy panels with a colour bar
  under each), Julien's pick: one PEDALS box with the brake (red) and the throttle (green) as vertical bars, as on the
  2026 F1 TV graphic; the car's battery when it reports one and the Bluetooth signal; BOOST (the turbo, F1 2026's
  name, purple as in the F1 game), LIGHTS and HOLD 360. Only real values: the car reports no speed or gear. Settings ›
  Layout brings back build 1's big pads. The car stops when a finger lifts, a touch is cancelled, or the app leaves the
  screen (it disconnects in the background and reconnects on return). The last car is reconnected at launch.
- **Autopilot, step 1: the room** (`app/Sources/Autopilot`): Menu › Autopilot › Scan the room runs Apple's RoomPlan
  (LiDAR) full screen; the result (`CapturedRoom`, Codable) is kept in the app's documents as `room.json`, and Room
  plan draws it from above (`Plan2D`: walls, doors, windows, openings and furniture flattened onto the floor, in
  metres). It will be the autopilot's map.
- **Bluetooth debug** (the wrench): every device in range with its advertisement; tap one to connect, list its
  services and characteristics (every readable value is read, every notification subscribed and logged), write raw
  hex once or repeatedly while held (with a stop frame on release), and share a text report of the services or the
  whole log. That is how an unknown car gets worked out.
- **Sending** (`Drive/Driver.swift`): a changed command leaves at once; an unchanged one is resent every 100 ms by
  default (Settings: off, 50–500 ms); writes without response when the car offers them, never queued behind an
  unacknowledged one.

## Build and release

No Mac. `.github/workflows/ios.yml` runs on GitHub's macOS runner when `app/`, `CarKit/` or the workflow change (or by
hand: `gh workflow run ios.yml --repo JulienMalige/rc-car`): CarKit's tests (`swift test --package-path CarKit`),
XcodeGen, then archive, sign and upload. The build number is the run number. The repository is public since 2026-10-31 (public repositories build free;
the private allowance had run out), so nothing personal goes in it; the signing material is only in GitHub secrets.

The icon, a checkered flag in white lines on red in the style of TV Scores' court, is drawn by
`scripts/make-icon.py` (Pillow, numpy). The fonts in `app/Resources/Fonts` are the isometric game's, as TTF from Google
Fonts, under the SIL Open Font License (its text beside them).

### Apple side

| Item | Value |
|---|---|
| Bundle id | `com.julienmalige.rccar` (`36M9NL2Z3U`, registered by API 2026-10-31) |
| App Store Connect | "Box Box RC", app id `6829202941`, SKU `rccar`, made by hand by Julien |
| Profile | "RC Car iOS App Store" (`HQS58PC9RZ`), expires 2027-09-14, on the team's distribution certificate |
| TestFlight | internal group "Internal" (`703ac186-…`), all builds, Julien as tester |

The profile is kept on the VPS in `~/.config/rccar/` (700, files 600); the App Store Connect key and the certificate
are TV Scores' (`~/.config/tvscores/`, see its `docs/release.md` for renewal). Repository secrets: `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_TEAM_ID`, `ASC_KEY_P8`, `DIST_P12_BASE64`, `DIST_P12_PASSWORD`, `DIST_PROFILE_BASE64`.
