# Changelog

The top section is the next TestFlight build's "What to Test" note (`node scripts/testflight.mjs <build>`).

## Unreleased

Autopilot, step 1: the LiDAR maps the room. Menu (the gear) › Autopilot › Scan the room: walk slowly around the room
with the phone up until the walls are outlined, then Done; RoomPlan shows its 3D model, Save keeps it. Room plan
then draws the room from above (walls, doors, windows, furniture with their names, the size in metres). The camera
permission is asked for the scan.

## 1.0 builds 8 and 9 — 31 October 2026

HOLD 360 works again: it stopped 11 ms after it started since build 4. One menu, the gear, with Bluetooth inside; one
layout.

## 1.0 builds 3 to 7 — 31 October 2026

Between the sticks, only what is real, in three columns: the PEDALS box with the brake (red) and the throttle (green)
as vertical bars; the car's battery (when it reports it) and the Bluetooth signal; then BOOST (the turbo, purple as in
the 2026 F1 game, no battery limit), LIGHTS and HOLD 360. All in the isometric game's look: its fonts, its glossy
tiles with a colour bar under each. The speed and the gear are gone: the car reports neither.

## 1.0 build 2 — 31 October 2026

New controls, as in the isometric game: put your left thumb anywhere on the left half to steer (a ring appears under
it: push left or right past the dashed circle), and your right thumb anywhere on the right for gas (push up) and
reverse (pull down). DRS (the turbo) and Lights stay on until tapped again; hold 360 to spin.

Below the sticks, an F1 TV style read-out: speed, gear, shift lights, throttle (green) and brake (red) bars, the DRS
tag and a g-force dot. It is simulated from your commands: the car reports nothing.

Settings › Layout brings back the big pads of build 1. New icon: a checkered flag.

## 1.0 build 1 — 31 October 2026

First build. Switch the car on, then tap "Choose your car" at the top and pick it (its name probably starts with
"SL-"). Left pad steers, right pad drives forward and reverse (swap sides in Settings); Turbo and Lights stay on until
tapped again; hold "360" to spin. The car stops whenever you lift your fingers or leave the app.

If the car does not move: the wrench → your car → "Share the services report", and send it to Claude. The wrench
also shows every Bluetooth device nearby and can send raw bytes.
