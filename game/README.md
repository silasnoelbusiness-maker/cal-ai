# Meridian City — V0.1 Prototype

An original 3D open-world life & crime simulator, viewed from an elevated
top-down camera. This directory holds a self-contained **Godot 4.3** project; it
is unrelated to the Next.js app in the repository root.

**V0.1 phases A–I are complete** (two of them were called G — the art pass and
the crime expansion; the naming is kept here as it happened, so the business
phase is the ninth milestone and the eighth letter). The full life/economy loop is playable end to
end — wake up in your flat, sleep off the night, walk to the warehouse for a
paid shift, buy food at the convenience store, eat it, head home — and the city
around it now moves: civilian traffic on both streets, signals at the two
junctions, a crowd that gets out of the way of cars, and police who chase you
through all of it.

    sleep at home  ->  4h shift, +$120  ->  buy a meal, -$15  ->  eat  ->  home

Sleeping restores energy but hunger keeps draining across the night, work costs
hours and energy, and food costs money — so the loop has to keep turning.

Eight cars are parked around the district. One is yours; the other seven are
not, and taking one files a vehicle theft. Whether that costs you anything
depends on who was looking:

    steal unseen        ->  nothing happens
    civilian sees it    ->  they stare, then call it in  ->  ★☆☆☆☆
    an officer sees it  ->  reported on the spot         ->  ★☆☆☆☆

Once you are wanted, police respond to where the crime was reported and chase
you on foot and in marked patrol cars. Break line of sight and an escape
countdown starts while they search your last known position; stay hidden and
the heat clears. Get caught and you are fined and released outside the
precinct.

The streets are no longer empty while that happens. Eleven or so civilian cars
— sedans, hatchbacks and vans — drive the lane network at about 40 km/h,
queue behind each other, stop at the two sets of lights and pick a different
way at each junction. Pedestrians watch for cars and jump clear; one that does
not make it is knocked down, gets up shaken and hurries off. Driving away
after hitting somebody is recorded as a hit-and-run — as an incident on your
record, not yet as something the police come for.

The crime expansion turns the single theft into a set of things you can do, all
priced against one another. Behind the stars is a points meter: every crime is
worth points, points add up, and the stars are a reading of the total — so a
theft and then a robbery is worse than either alone.

| Crime | Points | How you commit it |
| --- | --- | --- |
| Trespassing | 5 | Stay in a staff-only area after the warning |
| Shoplifting | 10 | Walk out of a shop with goods you have not paid for |
| Vehicle theft | 20 | Take a parked car that is not yours |
| Assault | 25 | Hit somebody (left mouse) |
| Carjacking | 35 | Take a car with somebody still in it |
| Store robbery | 40 | Hold up a till (`G` at the counter) |

Stars light at 20, 40 and 70 points, and the response scales with them: one star
sends up to two units, two stars three, three stars five, and the police drive
and run faster at each step. An arrest costs $100, $250 or $500 by level, never
more than you are carrying, and anything in your bag flagged as stolen is
confiscated.

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
| `F` | Enter / exit a vehicle · carjack an occupied one |
| `G` | Rob the till you are stood at |
| `B` | Open the business dashboard |
| Left mouse | Attack with whatever is in your hand · place equipment |
| `R` | Rotate the equipment being placed |

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
| `F1` | Show / hide the traffic overlay |
| `F2` | Cycle traffic density (low / medium / high) |
| `F5` / `F12` | Quick save / quick load (until the pause menu lands) |
| `F8` | Unstick the current vehicle |
| `F6` / `F7` | Set wanted level 1 / 2 |
| `F9` | Clear the wanted level |
| `F3` | Show / hide the crime overlay (points, response, statistics) |
| `F4` | Put a steel pipe in the bag, for testing melee |
| `F10` | Show / hide the business overlay |
| `1`–`0` | Business debug commands, only while that overlay is up |

`F9` was quick-load in Phase D; it is now clear-wanted, and quick-load moved to
`F12`.

## Running a business

Two vacant retail units are advertised on Main Street and at Quayside. Standing
at the door of one offers the letting details; signing takes the deposit and the
first rent out of your own pocket and hands you the keys.

    save up  ->  rent a unit  ->  found a business  ->  fund it  ->  fit it out
    ->  order stock  ->  fill the shelves  ->  set prices  ->  open  ->  serve
    ->  hire a cashier  ->  walk away and it keeps trading

The business account is separate from your wallet, and nothing moves between
them except by your own deposit or withdrawal. A shop cannot open without a
till, a shelf and something on it. Customers walk in off the street, browse the
shelf holding what they came for, queue at the counter and pay — and only if
somebody is on the till, which is what makes hiring worth the wages.

| Startup cost | |
| --- | --- |
| Deposit and first rent (Main Street) | $1,150 |
| Checkout counter | $300 |
| Two shelves | $240 |
| Storage rack | $150 |
| Opening stock | $150–$400 |
| **Total** | **about $2,000–$2,250** |

Rent falls due every seven days and comes out of the business account. A shop
that is priced sensibly, kept in stock and staffed clears roughly $150–$300 a
day against the warehouse job's $120 a shift — better, but only after the
capital and only if it is managed. Charge double and nobody buys; run out of
stock and the visits become lost sales; overstaff a quiet shop and the wages
eat the margin. None of that is prevented.

Everything is one screen, on `B`: an overview with the cash on both sides of the
boundary, the stock and the supplier, the prices, the equipment (buying, placing,
moving), the staff and their shifts, the day's finances, and the opening hours.

## The district

"Harbour Row" is roughly 176m square: two east–west streets (Main Street, North
Avenue) crossed by Center Boulevard, giving two junctions with crosswalks. It
holds 12 buildings — pitched roofs on the low ones, parapets and pilasters on the
tall ones — a park with a fountain, a paved plaza, hedges and benches, kerbside
parking bays and an off-street lot, 44 street lights, tree-lined verges, overhead
cable runs on timber poles, patched asphalt, driveway aprons, a set of signals at
each junction, and a perimeter wall marking where the next district will
connect.

Everything is generated from the layout tables in `world/district_01.gd` rather
than hand-placed, so the grid can be retuned by editing data. Geometry is still
primitives — boxes, cylinders, spheres, one hip-roof mesh — sharing a small
palette of procedurally textured materials. There are no imported art assets and
no image files in the repository: every surface, canopy and cable is generated at
load. Gameplay does not depend on any of it, so modelled meshes can replace the
primitives later without touching a system.

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
npc/          nav_graph, npc_walker, pedestrian, police_officer, police_driver
traffic/      road_network, traffic_light, traffic_driver, traffic_manager,
              traffic_debug
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
* **Navigation** is two `AStar3D` graphs — pavements and road centre lines —
  sampled from the same street lines the district draws itself from. Baking a
  navmesh from procedurally built geometry at runtime would be slower, harder
  to verify headlessly, and more machinery than a grid of streets needs.
* **The crime loop is four separate systems.** `CrimeManager` records what
  happened; `WitnessSystem` decides whether anyone saw it; `WantedManager` owns
  the heat, the escape countdown and the arrest; the police AI owns individual
  officers and cars. None of them reach into another's job.
* **Police are never told where the player is.** They navigate to
  `WantedManager.last_known_position`, which only changes when a unit actually
  *sees* the player. That single rule is what makes hiding work.
* **Traffic runs on its own graph, not the pedestrian one.** `RoadNetwork` is a
  *directed* lane graph built from one polyline per lane. Turns at junctions are
  never authored: a node links to any node ahead of it, within reach, that is
  not a U-turn, which at a crossroads produces straight-on plus a left and a
  right for free. A new road is a new strand and nothing else.
* **Routes are chosen a junction at a time**, at random from the successors,
  rather than solved end to end. Pedestrians want the shortest path; traffic
  wants a plausible one, and cars that all solved the same route would all drive
  the same loop.
* **One node owns each whole junction.** A `TrafficLight` has a single phase and
  the two axes read it opposite ways, so conflicting greens are impossible by
  construction rather than by careful configuration.
* **Vehicles do not collide with people.** A crowd that physically blocked
  traffic would jam the roads solid, so pedestrians sit on a layer cars ignore
  and contact is resolved by an area poll instead: over walking pace it is a
  knockdown, under it a shove. That is what stops cars passing through people
  without stopping the city dead.
* **Every stuck car eventually gets recycled.** The graduated recovery — try
  another turning, back off and re-join the lane, give up — cannot break a
  deadlock, because in a deadlock every car is correctly waiting for the one in
  front and none of them believes it is stuck. So there is a second, blunter
  watchdog on top: no real movement for several seconds and the car is taken out
  of circulation, wherever it is and whatever it thinks it is waiting for.
* **Recycling, not spawning.** Cars that reach the edge of the district or give
  up are moved to a fresh lane node well away from the player rather than freed
  and re-instanced, so a much bigger city later still costs a fixed pool of
  vehicles.
* **Surfaces are textured by world position, not by UV.** Everything here is a
  scaled unit box, so a UV-mapped texture would stretch one tile across a 170m
  road and squash another onto a bench. World *triplanar* mapping projects from
  world coordinates instead, which is what makes texturing a kit of scaled
  primitives possible at all — every surface gets the same grain at the same
  size, and new geometry needs no UV work.
* **The relief matters more than the tint.** A flat colour under a directional
  light reads as plastic however carefully it is chosen; the same colour with a
  few millimetres of normal-mapped relief reads as asphalt, grass or shingle.
  Water is the one deliberate exception and is left smooth — noise on it looks
  like television static.
* **Pitched roofs are a mesh, not a stack of boxes.** There is no primitive for a
  hipped roof, so one unit roof is built with a SurfaceTool and scaled per
  instance like everything else. Its faces are wound from a supplied outward
  normal rather than by hand, because getting that wrong is how a roof ends up
  with two black slopes. Buildings low enough to look down onto get one; the
  office slabs keep a flat parapet and get cornices and pilasters instead, so
  they still have more than one silhouette.
* **Scenery is not solid.** Bins, hydrants, post boxes, hedges, poles, wires and
  street trees carry no collision at all. Every one of them sits within a metre
  or two of a pedestrian route, and a crowd wedged against a litter bin is a bug
  the player can see, where a bin they clip through is one nobody notices from
  this camera. Planting *solid* street trees is what broke the walk to the
  market — which is the argument for the rule, and for having a test that walks
  it.

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
round trip. Finally it plays the crime loop: a theft nobody sees costs nothing,
a civilian witness reports it after a delay, an officer reports it instantly,
breaking line of sight starts the escape countdown, being spotted again cancels
it, and getting caught fines the player and releases them — including at
night, and including a player too poor to pay the fine.

Phase F adds the living city: that the park is reachable and nothing routes
through the fountain, that the lane graph never links onto an oncoming lane and
does offer both a straight on and a turning at each junction, that routes
diverge, that the signals cycle and never show conflicting greens, that the
spawned population is the right size and every car of it is on a carriageway,
under AI control and impossible to hijack, that traffic keeps moving inside its
speed band without leaving the road, that a car queues behind the one in front
and slows for somebody standing in the lane, that red means stop and green means
go, that a wedged car tries another way out and is recycled when that fails,
that a pedestrian jumps clear of an approaching car, and that one who does not
is knocked down, logged as an incident rather than a crime, gets back up and
runs:

The crime expansion is tested the same way, in two halves. The table — what each
crime is worth, where the stars light, what an arrest costs — is checked
directly, because a table either says the right thing or it does not. Everything
else is played: the player walks into the shop, takes something off a shelf,
carries it out and the crime lands; stands behind the counter until the warning
runs out; robs the till, walks out of one mid-way and finds the same till empty
for days afterwards; pulls a driver out of a stopped car and drives it away
while they run off; punches somebody, then does it with a pipe until they stop
getting up. Three crimes stack to three stars, five units answer, and the
arrest at the end costs $500. Afterwards the shop still serves them, which is
the check that the city carries on.

The business phase is tested as one continuous story, because that is what it
is: the unit rented in the first test is the shop staffed in the ninth. The
player walks up to a vacant unit, signs for it, founds a business, moves capital
in, buys a counter and two shelves and puts them down — with the walls, the
doorway and the other equipment refusing the bad spots — orders stock at
wholesale, fills the shelves to their capacity and no further, sets prices,
opens, and serves a customer who walks in, browses, queues and pays. Then the
shelves are emptied to prove a lost sale is recorded rather than a phantom sale,
a cashier is hired and reaches the register, the player leaves and the shop
keeps trading, the staff are dismissed and it stops trading again, the books are
checked for double counting, rent is charged and missed, a crime and a police
chase happen around it, and the whole thing goes through a save file and comes
back.

```sh
godot --headless --path game res://tests/smoke_test.tscn
```

It exits non-zero if any check fails. As of the business phase it runs 610
checks.

A screenshot tool renders the game to a PNG without a desktop, for eyeballing
the district:

```sh
xvfb-run -a godot --rendering-driver opengl3 --path game \
    res://tests/screenshot.tscn ++ out=shot.png hour=22.5 scenario=apartment
```

Args after `++` are `key=value` pairs, all optional: `out`, `hour`, `scenario`
(`street`, `apartment`, `shop`, `inventory`, `warehouse`, `car`, `driving`,
`theft`, `crowd`, `unseen_theft`, `witness`, `wanted`, `pursuit`, `escaping`,
`cleared`, `busted`, `night_chase`, `traffic`, `vehicle_types`, `red_light`,
`green_light`, `crossing`, `pedestrian_reacts`, `driving_traffic`,
`traffic_crash`, `pursuit_traffic`, `police_lights`, `escaping_traffic`,
`night_traffic`, `store_interior`, `shoplifting`, `robbery`, `trespassing`,
`carjacking`, `carjack_victim`, `melee`, `weapon`, `incapacitated`,
`three_stars`, `police_response`, `fear_crowd`, `crime_overlay`,
`vacant_property`, `property_rental`, `empty_store`, `business_creation`,
`equipment_buy`, `equipment_place`, `business_storage`, `stocked_shelf`,
`pricing_screen`, `store_open`, `customers_browsing`, `checkout_queue`,
`player_register`, `employee_cashier`, `business_dashboard`, `daily_report`,
`player_away`, `driving_business`) and camera `distance` / `yaw` / `pitch` for overview shots. Scenarios drive the real interactables
rather than faking their results. It runs under the Compatibility renderer, so
lighting is close to but not identical to the Forward+ game.

## What is next

Nothing is started. The business phase left three obvious threads: a second
business type (the architecture takes one as a `BusinessTypeData` plus a stock
list, and nothing in the customer, employee or dashboard code knows what a
convenience store is), a stocker role for employees to refill shelves on their
own, and eviction for a lease that falls far enough into arrears — the arrears
are already counted, nothing acts on them.

The largest gap the crime expansion left is interiors: the
flat and the convenience store are the only two you can walk into, and the
diner, the small retail unit, the precinct lobby and the warehouse floor are
still doors with prompts on them. The store interior is built from five reusable
components — shelves, counter, restricted area, store zone, employee — so
another one is a stock list and a room rather than new systems.

The weapon side stops deliberately at the architecture: `WeaponData` carries a
`RANGED` kind that nothing fires yet. Adding a projectile is a new component
reading the same resource, not a change to how attacking works.

Other obvious candidates are a real pause menu with settings over the existing
save system, turning the hit-and-run incident into something the police actually
respond to, and the in-world UI layer — marker pins over objectives, a
phone-style app panel.

On the art, the procedural ceiling is roughly where it is now. Going further —
real window frames, porches, varied house types, foliage that is not spheres —
means modelled meshes rather than more code.
