# Meridian City — V0.1 Prototype

An original 3D open-world life & crime simulator, viewed from an elevated
top-down camera. This directory holds a self-contained **Godot 4.3** project; it
is unrelated to the Next.js app in the repository root.

**V0.1 milestone 1 is complete:** spawn into a small city district, walk and
sprint with smooth acceleration, collide correctly with the world, orbit and
zoom an elevated top-down camera, and see contextual interaction prompts. The
clock, money, needs and a minimal HUD are wired up behind it.

## Running

Open `game/project.godot` in Godot 4.3 (or newer 4.x) and press Play. The main
scene is `res://main.tscn`.

## Controls

| Input | Action |
| --- | --- |
| `W` `A` `S` `D` | Move (relative to the camera) |
| `Shift` | Sprint (drains energy) |
| `E` | Interact with the highlighted object |
| `Q` / `←` / `→` | Orbit the camera |
| Right-mouse drag | Orbit the camera |
| Mouse wheel | Zoom in / out |
| `Esc` | Pause / resume |
| `F` | Reserved for enter/exit vehicle (Phase D) |

## The district

"Harbour Row" is roughly 176m square: two east–west streets (Main Street, North
Avenue) crossed by Center Boulevard, giving two junctions with crosswalks. It
holds 12 buildings, a park with a fountain and benches, kerbside parking bays
and an off-street lot, 32 street lights, and a perimeter wall marking where the
next district will connect.

Everything is generated from the layout tables in `world/district_01.gd` rather
than hand-placed, so the grid can be retuned by editing data. Geometry is
primitives sharing a small palette of materials — placeholder art that gameplay
does not depend on.

## Layout

```
autoload/     game_manager, time_manager, economy_manager  (singletons)
camera/       top_down_camera.gd + camera_rig.tscn
interaction/  interactable.gd, interaction_controller.gd, behaviours/
player/       player.tscn, player.gd, player_stats.gd
ui/           hud.tscn, hud.gd
world/        district_01.tscn/.gd, city_kit.gd, day_night_cycle.gd
tests/        smoke_test, screenshot
main.tscn     entry scene
```

## Tests

A headless smoke test drives the real main scene with simulated input and
checks spawn placement, gravity, camera framing, walking, sprinting, braking,
building collision, curb climbing, interaction focus, pausing, the day/night
cycle and the economy ledger:

```sh
godot --headless --path game res://tests/smoke_test.tscn
```

It exits non-zero if any check fails.

A screenshot tool renders the game to a PNG without a desktop, for eyeballing
the district:

```sh
xvfb-run -a godot --rendering-driver opengl3 --path game \
    res://tests/screenshot.tscn ++ shot.png 22.5
```

Args after `++`: output path, hour of day, then optional camera distance / yaw /
pitch for overview shots. It runs under the Compatibility renderer, so lighting
is close to but not identical to the Forward+ game.

## What is next

Phase B onward: the apartment interior and sleeping, the convenience store and
inventory, the warehouse job, then vehicles, pedestrians, and the crime,
witness, wanted and police systems. The venue doors already in the district
(apartment, market, diner, warehouse, precinct) are real interaction points
holding those places; only what happens behind the prompt is still to come.
