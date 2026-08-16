# Meridian City — V0.1 Prototype

An original 3D open-world life & crime simulator, viewed from an elevated
top-down camera. This directory holds a self-contained **Godot 4.3** project; it
is unrelated to the Next.js app in the repository root.

**V0.1 phases A–D are complete.** The full life/economy loop is playable end to
end — wake up in your flat, sleep off the night, walk to the warehouse for a
paid shift, buy food at the convenience store, eat it, head home — and the city
now has cars in it.

    sleep at home  ->  4h shift, +$120  ->  buy a meal, -$15  ->  eat  ->  home

Sleeping restores energy but hunger keeps draining across the night, work costs
hours and energy, and food costs money — so the loop has to keep turning.

Eight cars are parked around the district. One is yours; the other seven are
not, and taking one files a vehicle theft. Nothing chases you for it yet — the
crime ledger is in place so Phase E can hang witnesses and police off it.

## Running

Open `game/project.godot` in Godot 4.3 (or newer 4.x) and press Play. The main
scene is `res://main.tscn`.

## Controls

| Input | Action |
| --- | --- |
| `W` `A` `S` `D` | Move (relative to the camera) |
| `Shift` | Sprint (drains energy) |
| `E` | Interact with the highlighted object |
| `Tab` / `I` | Open and close the inventory |
| `Q` / `←` / `→` | Orbit the camera |
| Right-mouse drag | Orbit the camera |
| Mouse wheel | Zoom in / out |
| `Esc` | Close an open screen, else pause / resume |
| `R` | Reset the camera orientation |
| `F` | Enter / exit a vehicle |

Driving:

| Input | Action |
| --- | --- |
| `W` / `S` | Accelerate / brake and reverse |
| `A` / `D` | Steer |
| `Space` | Handbrake |
| `F` | Get out (only below ~22 km/h) |

Development keys, to be removed before release:

| Input | Action |
| --- | --- |
| `F5` / `F9` | Quick save / quick load (until the Phase F pause menu) |
| `F8` | Unstick the current vehicle |

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
inventory/    inventory.gd, inventory_slot.gd
items/        item_data.gd + definitions/*.tres
jobs/         job_data.gd, job_station.gd + definitions/*.tres
shops/        shop.gd
player/       player.tscn, player.gd, player_stats.gd
ui/           hud, inventory_panel, shop_panel
vehicles/     vehicle_base, vehicle_data, vehicle_door + cars/*.tres
world/        district_01, city_kit, day_night_cycle, portal, interiors/
tests/        smoke_test, screenshot
main.tscn     entry scene
```

## How the loop is put together

* **Items** are `ItemData` resources (`items/definitions/*.tres`), so the shop's
  stock list and the inventory both take resource references — no product is
  named in code.
* **Shops** take a stock list and opening hours. A second shop is a second list.
* **Jobs** are `JobData` resources describing hours, pay, requirements and a
  per-day shift cap; a `JobStation` is the place you work one from.
* **Interiors** live off to one side of the world. A `Portal` teleports the
  player between a street door and an interior marker, found by group so
  neither side needs to know where the other sits in the tree, and carries the
  camera framing that interior needs.
* **Needs** are charged by *elapsed in-game minutes*, not per signal, so an
  eight-hour sleep and a four-hour shift cost exactly what they should.
* **Vehicles** are `CharacterBody3D`, not Godot's `VehicleBody3D`. The brief
  wanted arcade handling that never flips, spins or bounces, and a kinematic
  body gives that by construction rather than by tuning a rigid body until it
  behaves. Speed along the car's own forward axis is the only state variable.
  Model stats live in `VehicleData` resources; *ownership* is per-instance,
  because every sedan shares one `VehicleData` but not one owner.
* **Kerbs** sit on their own physics layer. Pedestrians collide with it and step
  up; vehicles do not, so a car mounts a kerb instead of being stopped dead by a
  12cm lip.
* **Saving** is a group: any node that joins `saveable`, exposes a `save_id` and
  implements `save_state()` / `load_state()` is persisted. Adding a system to
  the save is two methods on that system and no change to `SaveManager`.

## Tests

A headless smoke test drives the real main scene with simulated input and
checks spawn placement, gravity, camera framing, walking, sprinting, braking,
building collision, curb climbing, interaction focus, pausing, the day/night
cycle and the economy ledger. It then plays the whole life loop — enter the
flat, sleep, leave, walk to work, complete a shift, walk to the shop, buy a meal
through the real shop screen, eat it and go home — plus the rules that keep it
honest (closed shops, shift caps, too tired to work, a full bag never taking
your money). Finally it drives: entering and exiting, throttle, braking,
reverse, the handbrake, steering falling off with speed, crashing into a
building, stealing an NPC car, the camera widening with speed, and a save/load
round trip:

```sh
godot --headless --path game res://tests/smoke_test.tscn
```

It exits non-zero if any check fails.

A screenshot tool renders the game to a PNG without a desktop, for eyeballing
the district:

```sh
xvfb-run -a godot --rendering-driver opengl3 --path game \
    res://tests/screenshot.tscn ++ out=shot.png hour=22.5 scenario=apartment
```

Args after `++` are `key=value` pairs, all optional: `out`, `hour`, `scenario`
(`street`, `apartment`, `shop`, `inventory`, `warehouse`, `car`, `driving`,
`theft`) and camera `distance`
/ `yaw` / `pitch` for overview shots. Scenarios drive the real interactables
rather than faking their results. It runs under the Compatibility renderer, so
lighting is close to but not identical to the Forward+ game.

## What is next

Phase E: pedestrians, then the witness and wanted systems on top of the crime
ledger, then police. Phase F: a real pause menu over the existing save system.
The diner and precinct doors are real interaction points holding those places;
only what happens behind the prompt is still to come.
