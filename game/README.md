# Street Capital — V0.1 Prototype

An original 3D open-world life, business & crime simulator, viewed from an
elevated top-down camera. This directory holds a self-contained **Godot 4.3**
project; it is unrelated to the Next.js app in the repository root.

**Art direction:** stylized, clean and readable — low-to-mid poly urban
simulation, strong silhouettes, clear colour separation and a night look worth
looking at. Not photorealism, and not a graybox either. Everything is still
generated from primitives at load; what changed in the visual pass is that the
primitives are now assembled into people, cars, facades and rooms rather than
standing in for them.

**V0.1 phases A–N are complete** — eleven milestones, because two of them were
called G (the art pass and the crime expansion) and the naming is kept here as
it happened. The full life/economy loop is playable end to end — wake up in your
flat, sleep off the night, walk to the warehouse for a paid shift, buy food at
the convenience store, eat it, head home — and the city around it now moves:
civilian traffic on every street, signals at five junctions, a crowd that gets
out of the way of cars, and police who chase you through all of it.

The city is now two districts. **Harbour Row** is where you start: low brick and
timber, a park, a warehouse, room to park. **Central District** is north up the
boulevard: twenty-metre towers, three streets each way, service roads round the
back, a pedestrian plaza with a monument in it, and rents to match. They share
one coordinate space, one pedestrian graph and one lane network, so a route, a
delivery, a car or a police chase crosses the district line without anything
happening at it.

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

Open `game/project.godot` in Godot 4.3 (or newer 4.x) and press Play. The game
boots to its title screen (`res://ui/menu/main_menu.tscn`); the world itself is
`res://main.tscn`, which is what the headless tests load directly so the front
end never stands between a test and the game.

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
| `B` | Open the business dashboard, or the company view outside a shop |
| `M` | Open the city map |
| `K` | Open the company: brands, locations, staff, operations, finance |
| `P` | Open your profile: net worth, vehicles, home, lifestyle |
| `H` | Open the property portfolio: holdings, mortgages, income |
| `L` | Open logistics: the depot, its stock, shipments, rounds and vans |
| `U` | Open the underworld: reputation, contacts, jobs and illegal earnings |
| Left mouse | Attack with whatever is in your hand · place equipment · place furniture |
| `R` | Rotate the equipment or furniture being placed |

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
| `F5` | Quick save to slot 1 |
| `F8` | Unstick the current vehicle |
| `F6` / `F7` | Set wanted level 1 / 2 |
| `F9` | Clear the wanted level |
| `F3` | Show / hide the crime overlay (points, response, statistics) |
| `F4` | Put a steel pipe in the bag, for testing melee |
| `F10` | Show / hide the business overlay |
| `1`–`0`, `Q`–`I` | Business debug commands, only while that overlay is up |
| `F11` | Show / hide the world overlay (district, populations, graphs, FPS) |
| `1`–`6`, `0` | World debug view layers, only while that overlay is up |
| `F12` | Show / hide the audio overlay (voices, ambience, buses, surface) |
| `O` | Show / hide the ownership overlay (fleet, home, garages, lifestyle) |
| `1`–`0`, `Q`–`T` | Ownership debug commands, only while that overlay is up |
| `Y` `U` `I` `J` `K` | Property debug commands, only while that overlay is up |

Every overlay is hidden by default and draws nothing until it is switched on, so
none of them intrudes on ordinary play or on a screenshot.

`F9` was quick-load in Phase D and is now clear-wanted. Quick-load has been
retired altogether: loading is a considered choice made from the pause menu
against a named slot, rather than a keystroke that silently discards everything
since the last save. `F12` is now the audio overlay, and the ownership
overlay is on `O` rather than a function key because F1 to F12 were already
spent.

## Running a business

Four vacant retail units are advertised along Main Street, and they are not
alike: a small one at 18 Main Street, a cheap back-street pitch at 40 Quayside,
a medium unit at 42 Harbour Avenue and a premium one at 7 Central Plaza. Rent
buys floor space, the number of customers who fit inside, and how much passing
trade the address itself brings. Standing at the door of one offers the letting
details; signing takes the deposit and the first rent out of your own pocket and
hands you the keys.

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
Press `B` outside a shop and you get the company instead.

## Building an empire

There is a second business type — a **coffee shop** — and it is a different
business rather than a repainted one. A shop sells what is on its shelves; a
kitchen holds beans, milk and cups in the back and makes a drink when somebody
orders one. Both go through the same queue, the same till and the same books;
what stands between them is a recipe.

| Role | Wage | What they do |
| --- | --- | --- |
| Cashier | $18/h | Works the queue |
| Stocker | $19/h | Carries stock from the back room to the shelves |
| Barista | $20/h | Takes the order and makes the drink |
| Manager | $30/h | Opens up, keeps the shelves full and reorders — without you |

A manager is the point at which a business stops needing you. They work to
permissions you set — open and close to the published hours, restock the
shelves, reorder stock up to a budget you choose — and nothing is on until you
turn it on. They are also dear enough to notice on the profit line.

Stock now takes two to six in-game hours to arrive from the supplier, so running
out is a mistake with consequences. Advertising buys attention and never money:
a campaign brings more people through the door, and if the shelves are bare they
leave again as lost sales. Upgrades are bought per business — better signage,
faster tills, more storage — and belong to that shop alone.

The bank lends to businesses, not to people: three loans, each with its own
rate and its own weekly payment. Miss one and it costs a little more and is
remembered. Pay it off early and it stops.

Every business is valued from what it holds, what it earns and what it owes, and
the company view adds them up beside your cash, your cars and your debt to give
a net worth. A business can be closed — it stops trading and the rent carries on
— or sold, which asks twice and cannot be undone.

    one shop  ->  a manager  ->  a second unit  ->  a coffee shop  ->  a loan
    ->  two shops running while you are across the city committing a crime

## The city

### Harbour Row

Roughly 176m square: two east–west streets (Main Street, North Avenue) crossed
by Center Boulevard, giving two junctions with crosswalks. It holds 12 buildings
— pitched roofs on the low ones, parapets and pilasters on the tall ones — a
park with a fountain, a paved plaza, hedges and benches, kerbside parking bays
and an off-street lot, 44 street lights, tree-lined verges, overhead cable runs
on timber poles, patched asphalt, driveway aprons, and a set of signals at each
junction. It is deliberately the older, looser half of the city: lower, wider
apart, more brick and timber, more open ground — and the flat roofs carry plant,
ducting, a water tank and an aerial, because from this camera a roof is a facade. Its perimeter wall now has a gap in it where Center Boulevard leaves
to the north.

### Central District

220m by 200m of city centre, up the boulevard. Three east–west streets (Market
Street, Kingston Road, Riverside Drive) crossed by three north–south ones (Plaza
Street, Center Boulevard, Exchange Street), with a pair of narrow service roads
behind the outer blocks. Thirteen blocks run to twenty-two metres with the
setbacks halved, so the streets read as canyons from the elevated camera rather
than as open ground with boxes on it. Facades carry punched window grids that
light up together at dusk; the ground floors are parades of shopfronts —
glazing, mullions, a stall riser, a sign band with the shop's name on it and an
awning over the pavement — so a Central street reads as a high street rather
than as glazing with nothing behind it. Kerbs carry benches, bins, planters,
meters, bike racks, hydrants and street-name signs; there is a shelter on the
boulevard and outdoor tables along the plaza edge.

Central Plaza sits in the middle of it — paving, benches, planters, a monument,
and bollards that keep cars out of it while pedestrians walk straight through.
Two surface car parks sit behind the service roads, which is where a car goes in
a district whose kerbs are all double-yellow. Three more signalled junctions run
out of phase with Harbour Row's, and the top of the boulevard is barriered with
a `NORTHGATE — ROAD CLOSED` sign on it: the seam a third district opens along.

Central holds four commercial units (a small one on Market Street, two medium
ones on Central Boulevard and Central Plaza, a food-service unit on Kingston
Road), a one-bedroom flat at 5 Kingston Road, a grocer, a coffee counter, a
courier depot and a police post.

### One world

Everything is generated from the layout tables in `world/district_01.gd` and
`world/district_02.gd` rather than hand-placed, so either grid can be retuned by
editing data. Geometry is still
primitives — boxes, cylinders, spheres, one hip-roof mesh — sharing a small
palette of procedurally textured materials. There are no imported art assets and
no image files in the repository: every surface, canopy and cable is generated at
load. Gameplay does not depend on any of it, so modelled meshes can replace the
primitives later without touching a system.

`WorldManager` is the register: each district builds itself and hands over a
`DistrictData` — bounds, centre, traffic and pedestrian density, commercial and
residential rent modifiers, demand modifier, police presence — and everything
that used to assume one square of map asks it instead. There is one nav graph
and one lane network for the whole city; districts `extend()` them rather than
building their own, which is why a walking route from a Harbour Row pavement to
Central Plaza is 54 hops of one graph and not two graphs stitched together.

Crossing the line is not an event. There is no loading screen, no prompt, and
nothing is unloaded — the only thing that happens at the boundary is a name
appearing once, the first time you arrive. Traffic density follows the player's
district, and which cars turn up follows it too: vans and saloons down in
Harbour Row, compacts and the odd coupe in Central. So does the police response:
the same wanted level sends more units in Central than in Harbour Row, which is
the risk half of a district that charges more rent.

What a second district must not do is cost twice as much to run all the time.
Traffic is one pool that follows the player and recycles rather than growing,
businesses were already split near/far, and pedestrians now do the same: a
civilian more than 140m from the player stops thinking and stops walking, at the
cost of one distance check each per quarter second. That is wider than a
district is across, so nobody freezes anywhere you can see them — you are always
in a full crowd, and the other district costs almost nothing until you drive
into it.

## How it is drawn

Four small libraries carry the look, and every district, interior and screen is
assembled from them:

* **`art/palette.gd`** — the material library and the colour language. One
  cached `StandardMaterial3D` per name, so a street of a hundred benches binds
  one material; and one set of meanings (`MONEY`, `LOSS`, `DANGER`, `POLICE_BLUE`)
  shared by the world, the HUD, the map and the dashboards.
* **`art/character_kit.gd`** — one humanoid builder for everybody in the game.
  A `CharacterLook` (skin, hair, build, height, clothing, category) goes in; a
  rig of hips, chest, head, two arms and two legs comes out. `character_animator.gd`
  then drives those joints from a phase counter — walk, run, idle, work, carry —
  which is what a crowd of forty can afford and an imported skeleton per
  pedestrian is not.
* **`art/building_kit.gd`** — punched window grids, shopfronts (glazing,
  mullions, stall riser, sign band, awning) and roof kits (plant, ducts, tank,
  mast). A district still lays out rectangles; the kit turns them into
  buildings.
* **`art/prop_kit.gd`** — the reusable things: benches, bins, planters,
  bollards, hydrants, signs, meters, bike racks, a shelter; chillers, goods
  rows, crate stacks, cafe tables, espresso machines, menu boards; sofas, lamps,
  kitchen runs, dressers, rugs, plants and framed art.

`ui/theme/ui_theme.gd` does the same job for the interface: one `Theme` built in
code and applied at the window root, so every panel, button, tab and bar in the
game inherits one look instead of styling itself.

Detail has to be paid for. The city builds about 4,600 mesh instances, and the
single biggest saving is that every window on a building goes into two
`MultiMesh`es rather than into two nodes each — a facade of eight bays and four
floors on four sides is 256 windows, and twenty-five buildings of them would
otherwise be six thousand draw calls for geometry that never moves and shares
one material. Everything else follows the same rule: shared cached materials, no
shadow casting on crowd figures or window panes, emissive panels instead of
lights wherever a light would only be seen and not needed, and props chosen to
be many and cheap rather than few and expensive.

## The map

`M` opens the city map. It draws the district rectangles, the real lane network
(node to successor, so what you see is what traffic drives), your position and
facing, and a marker for everything worth going to: your home, your businesses,
vacant units, jobs, the precinct, shops and the landmark. Categories can be
switched off. Selecting a marker offers `SET DESTINATION` — and, for a business
you own, `VIEW BUSINESS` — after which the route is drawn on the map, the
distance sits under the HUD clock and counts down as you travel, and arriving
clears it.

The route follows the road graph while you are driving and the pavement graph
while you are on foot, so a car is never routed through a building or a plaza.

## Courier work

The map paying for itself: the depot in Central hands out deliveries. A run
picks a destination at least 120m away from the pool of real addresses, sets it
as your map destination, and pays a base fee plus distance, with a bonus for
getting there promptly. Each run costs eight minutes of the day whether or not
you hurry, so it cannot be farmed by driving in circles.

## Somewhere to live

The starter studio at Larkspur Apartments is now a property like any other, and
5 Kingston Road in Central is the one to move up to — dearer, bigger, a
bedroom and a kitchen rather than a bedsit. Renting takes a deposit and the
first week's rent; residential rent then falls due on the same calendar as
commercial rent, out of your own pocket rather than a business account.

Whichever place is set as `CURRENT HOME` is the one you sleep in. The other
bed says `NOT YOUR HOME` and will not let you, and ending a lease does not
happen by itself when you take on another.

## How it sounds

There are no audio files in this repository, for the same reason there are no
image files: the project generates what it needs at load. Every sound is
synthesised by `audio/tone_bank.gd` — filtered noise bursts for footsteps and
impacts, sine blips and sweeps for the interface, whole-cycle saw loops for
engines, a two-note loop for the siren, cross-faded noise for the ambience beds.
Nothing is sampled from anything, so there is no provenance to document and no
licence to honour.

Six buses sit under the master — Music, SFX, Ambience, Interface, Vehicles,
Voice — each with its own slider, and a limiter on the master so a chase with
sirens, engines, traffic, a collision and music at once compresses instead of
clipping. Settings live in `user://settings.cfg`, entirely separate from save
games: changing the music volume needs no save slot, and loading an old save
cannot reset your resolution.

Everything plays through one pooled manager, which is what makes concurrency
enforceable: a fixed pool of flat and positional players, a per-sound cooldown
so a shower of tiny collisions is one thump, and voice stealing that takes from
whatever is furthest away. A cashier in Harbour Row is inaudible from Central
because the falloff says so, not because anything special-cases it.

Footsteps are driven by the walk cycle rather than a timer — the animator counts
strides, so cadence follows the animation for free and standing still is silent.
What you are standing on comes from groups the geometry joins when it is built,
so moving a street moves the sound of walking on it: asphalt in the road,
concrete on the pavement, grass on the verges, tile in a shop, boards in a cafe
or a flat. Nearby pedestrians get footsteps too, capped at six voices city-wide.

Cars carry their own audio: one pitched engine loop whose loudness follows
throttle and speed, tyres that only scrub under the handbrake or a hard corner,
graded impacts, and — on a patrol car — a siren that follows the light bar
exactly, so what you hear and what you see can never disagree. A parked car with
nobody in it is silent, and so is any car more than 55m away, which is what
keeps a city of traffic down to the handful of engines actually near you.

The music system is architecture with silence in it. Shipping invented music
for a game meant to be played for hours would be worse than shipping none, so
the state machine — menu, day, night, wanted — is wired to the real events and
crossfades between states, and every track slot is empty. The day one exists it
is one line in a table.

## The front end

`ui/menu/main_menu.tscn` is what the game boots to: title, CONTINUE, NEW GAME,
LOAD GAME, SETTINGS, QUIT. CONTINUE is disabled rather than hidden when there is
nothing to continue, so the menu does not change shape. LOAD GAME lists every
readable slot with the day, the time, the money and the district, read from a
summary written into the save rather than by restoring it — and a slot that
cannot be parsed is left out of the list rather than offered and then failing.

There are three manual slots plus an autosave slot the player cannot write to,
so the game saving itself can never overwrite a save you made. Autosaves happen
at natural breaks — waking up, signing a lease, founding a business — with a
cooldown, and show a quiet SAVING… toast rather than anything modal.

Settings are four tabs: audio (a slider per bus), graphics (three presets,
display mode, vsync), gameplay (camera and zoom sensitivity, camera shake,
prompts) and controls (every major binding, click to rebind, conflicts named
rather than silently allowed, reset to defaults). The pause menu is the same
screens again with RESUME, SAVE, LOAD, SETTINGS, MAIN MENU and QUIT.

The gameplay sliders are wired to the camera rather than stored and ignored:
sensitivity scales both the keyboard orbit and the mouse drag, zoom sensitivity
scales the step per notch, and the shake slider scales a knock the camera takes
when the car the player is driving hits something — all the way down to nothing
at zero, which is the setting that matters most for anybody who cannot tolerate
it.

## What the money buys

Until this pass, earning was a number going up. Now it buys things that exist in
the world, and the two measures of how the player is doing are deliberately
allowed to disagree: net worth is what the books say, lifestyle is what the life
looks like, and a player with a fortune in the bank and a studio flat is
correctly described as rich and living modestly.

### Vehicles

Ten models across five invented marques — Kestrel at the everyday end,
Northline for the van and the SUV, Ardent for the quick ones, Crown for the
luxury pair and Mira for the one nobody can afford yet. The showroom figures for
speed, acceleration, handling and durability are read off the physics rather
than stored beside it, so a car that is quicker in the driver's seat is quicker
on the board by construction. Prestige is deliberately not price: the panel van
is dear and impresses nobody, and lifestyle reads prestige.

A car the player owns is a record, not a node. That is what makes the rest
possible: two sedans are two records with their own mileage and their own dents,
a car left across the city stays exactly where it was left without being
simulated there, and a car in a garage has no node at all and is still an asset.
Nodes come and go within about 120 metres of the player; the record is the
truth.

Mileage is measured from how far the car actually moves, so a parked one never
gains any and a car being pushed downhill does. Health and condition are
separate on purpose — health is what this crash did, condition is what the car
has been through — and value falls with both, plus a slow drift for age. The
mechanic prices the two jobs separately: putting the damage right is cheap and
takes an hour, putting the years right is dear, takes three, and never quite
gets a car back to new.

Northline Motors on Riverside Drive sells them. The showroom floor holds six
real models with their physics switched off, each on a lit plinth with a stand
beside it; the desk at the back does the paperwork, including part exchange and
selling, which can only be done there because a car has to be brought in. Four
used cars sit on the lot at any time with somebody else's mileage on them, and
one of them is always something a new player could afford.

### Garages and homes

Two garages, three bays and six, rented rather than bought — so neither is an
asset, but what is inside them is. A stored car is drawn in its bay when the
player is near enough to see it and is not simulated otherwise. Nothing stolen
goes in: the registry only ever holds vehicles that were paid for, which is the
whole difference between owning a car and having taken one.

Three places to live now, and the rent, the room and what living there says
about you all climb together: the Larkspur studio, Meridian Heights, and Central
Heights on Riverside Drive with a private bay outside it. Furniture is bought at
Kingston Furnishings and delivered — nobody carries a wardrobe — and then placed
by hand in the same mode, with the same keys, that puts shop equipment on a shop
floor. A flat remembers exactly where its sofa is, because the sofa is a record
too.

Only the best two things in each category count towards lifestyle. That is the
whole answer to buying twenty identical plants, and it is a rule rather than a
fudge: a second sofa does not make a flat twice as nice.

## The property ladder

Renting a shop unit and owning the building it is in are different
relationships with the same address, and the game now models both. The door in
the street is still a `CommercialProperty` or a `ResidenceProperty` doing its
own leasing; ownership is a separate layer keyed to the same `property_id`, so a
player can rent a flat, live in it for a month and then buy it without anything
about the flat changing.

Twelve addresses are on the market: the three flats, the eight shop units and
one small block. Nothing appears on the market screen until the player has stood
in front of its board — the city is meant to be driven around rather than
browsed from a menu — and the boards are drawn from the listings, so an address
coming on or off the market puts up or takes down its own sign.

### What a building is worth

Value is floor area times a rate for its kind, adjusted for the pitch it stands
on, the district, its condition and a market trend that wanders slowly around
1.0 and is pulled back the further it drifts. Rent follows value, but not at a
flat percentage: a fringe address yields more than a prime one, which is what
makes the cheap flat in Harbour Row and the unit on Central Plaza different
investments rather than the same investment at two sizes.

| Address | Kind | Asking | Gross yield |
| --- | --- | --- | --- |
| Larkspur Apartments | Residential | ~$40,000 | ~40% |
| 40 Quayside | Commercial | ~$129,000 | ~45% |
| 18 Main Street | Commercial | ~$154,000 | ~42% |
| Dockside Court | Four flats | ~$183,000 | ~39% |
| 1 Riverside Drive | Residential | ~$212,000 | ~30% |
| 3 Central Plaza | Commercial | ~$405,000 | ~37% |

### Mortgages

Fixed rate, level payment, interest first. A lender wants 20% down on a flat,
25% on a shop unit and 30% on the block, will not deal with anybody worth less
than $12,000, and charges 6% a year over 200 weekly payments. Early payments are
mostly interest and later ones mostly principal, which is what makes paying
extra early worth doing; an overpayment comes straight off the balance and the
next period's interest is smaller for it.

A payment that cannot be met is missed rather than forgiven — the balance is
simply owed again next period, and three misses flag the mortgage AT RISK, which
stops any further borrowing. **Nothing is ever repossessed.** That system does
not exist yet, and quietly deleting a property to imply it does would be worse
than not having it.

### Tenants

A tenant is a name, a budget, a reliability and a payment schedule — data, and
deliberately so. There is no tenant walking about a flat across the city, and
there should not be: a portfolio of nine units would otherwise be nine more
people to simulate for no gameplay at all. What the player interacts with is the
decision, and it is a real one: this applicant pays more but is less reliable,
that one is dull and always pays.

Asking rent is the lever. Ask under the going rate and applicants arrive
quickly; ask half again and almost nobody does, and the flat sits empty while
the upkeep and the mortgage carry on. Leases run 28 days and renew if the tenant
is happy, the place is decent and the rent is not more than 15% over the market.
Every tenant puts a little wear on the building, a careless one slightly more.

Dockside Court is four flats under one roof, and it is there for the arithmetic
the single properties cannot teach: one flat is let or it is not, four flats are
three-quarters let, and the difference between a good week and a bad one is one
tenant leaving. Its windows light one per let flat, so an empty block is dark
from the street.

### Owning what you already use

Buying the unit your own shop trades from does not create a rent you pay
yourself. The unit's landlord becomes nobody, rent day skips it entirely rather
than moving money between the player's pockets, and the business keeps its
equipment, staff and signage exactly as they were. The same goes for buying the
flat you live in: the lease ends, the furniture and the home marker stay, and
nothing is charged. A building with your own business in it cannot be sold —
there is no relocation system, so the sale is refused rather than allowed to
destroy the shop.

### The books

`H` opens the portfolio: what is owned, what is owed, and what it earned.
Selling is at market value less a 4% fee, with whatever is still owed cleared
out of the proceeds before the player sees a penny, so a sold building never
leaves a mortgage behind it. Property equity — market value less mortgage debt —
is counted in net worth alongside cash, vehicles, furniture and business value,
and the profile screen shows the value and the debt as separate lines so the two
together are legibly the equity.

## The company

Phase O is where one shop becomes a company. Three new kinds of business arrive,
and none of them is a shop with a different sign.

### How a business type works

`BusinessTypeData` is still one `.tres` per kind of business, and it now carries
everything that used to be implicit: which staff roles it needs, what a property
has to be zoned for, how many people fit inside, a twenty-four-hour demand curve,
what a weekend is worth to it, which district suits it, who walks through the
door and whether the place gets dirty.

The one field the rest of the game switches on is `service_model`, and it picks
an `OperatingModel` — a strategy object with no state of its own, shared by every
branch of that kind:

| Model | Business | What it is |
| --- | --- | --- |
| `RETAIL` | Convenience store | Goods off a shelf, paid for at a till |
| `COUNTER_SERVICE` | Coffee shop | Made to order, handed over at a counter |
| `TABLE_SERVICE` | Restaurant | Seated, ordered, cooked, carried, paid |
| `MEMBERSHIP` | Gym | The customer buys access to the room |
| `VENUE` | Nightclub | Entry, then drinks, with the night doing the work |

Capacity, throughput, what a visit is worth, why somebody walked out, what is
holding the place up and which way a customer walks through the building all
come from the model. `BusinessManager` never asks what kind of business it is
looking at, and the visible customers on the floor run the same `serve_one` the
far simulation does — which is what stops a business earning differently
depending on whether anybody is watching it.

### The restaurant

Six dishes, seven ingredients, and two separate bottlenecks. A cover is seated
before it is anything else: no free table and they wait a little, then leave, and
`NO SEATING` is counted against the day. Sitting down puts a ticket in the
kitchen; a cook takes the oldest one, the ingredients come out of the larder
*then*, and the plate is only paid for when a server carries it to the table. A
cook with no server has meals nobody carries. A server with no cook has orders
nobody makes. Which of the two is short is the thing the dashboard names, and
buying another table when the kitchen is the problem is the mistake the
bottleneck report exists to prevent.

Food quality is the cook's skill and the tier of the stove, and nothing else.

### The gym

Machines are the capacity: a treadmill holds one person, a weight rack holds two,
and the room holds no more than what is in it. Revenue is a membership rather
than a purchase — walk-ins either sign up or buy a day pass, members pay a
seventh of the weekly fee every day whether they come in or not, and a dirty or
overcrowded gym loses them. That is the whole of the recurring-revenue trade: the
equipment is dear, the income is steady, and the cleaner is the reason it stays
steady.

### The nightclub

The same room is worthless at three in the afternoon and rammed at midnight, and
nothing in the code knows that — the type's demand curve does. Security is an
operating role rather than a fight: without somebody on the door the venue runs
at 55% of its capacity and the dashboard says why. A DJ is a number that moves
reputation, satisfaction and how many people are prepared to queue.

### Brands, branches and the company

A `BrandData` is a name several shops trade under. It holds no stock, employs
nobody and has no till: every one of those stays with the branch, because two
shops with the same sign still have different people in them. What a brand owns
is the name, the colour above the door, and a reputation that drifts slowly
towards the average of its branches — one bad day at one shop does not cost the
name.

Opening a business in a unit that suits it now offers a choice: a new brand, or
another branch of one you already run. A branch takes the brand's name and its
street as its identifier — `SILAS MARKET — CENTRAL` — and keeps its own
inventory, staff, cash flow, hours and local reputation.

`CompanyManager` sits above `BusinessManager` and owns everything that is true of
several shops at once. It aggregates, compares and moves people, and it holds no
money of its own — every figure on the company screen is derived from the
branches, so there is exactly one place each number lives.

**Company value is not net worth.** Company value is the operating business: the
branches, plus a premium a chain with a name earns on top of them. Net worth is
that plus the property, the cars, the furniture and the cash, less what is owed.
Both are shown, on different screens, and the profile says so in as many words.

### Staff

Eleven roles now — cashier, stocker, barista, manager, cook, server,
receptionist, cleaner, security, bartender, DJ — and eight skills, of which each
role is paid for exactly one. A week is a list of `ShiftSlot`s: a day (or every
day), a pair of clock hours, the job being done and the branch it is done at. A
shift that runs past midnight belongs to the day it started on, which is how a
nightclub is staffed.

Overlaps are refused before anything is written, including the same hour at two
different branches. Transfers move the person rather than copying them: same id,
same skills, same history, and the old branch stops having them.

### Managers

A manager may open up, restock, reorder, keep the place clean, and nothing else
unless told. Pricing is on the list and off by default — a manager quietly
changing what you charge is not automation. Everything they spend comes out of
one daily allowance, and they never spend past what the branch actually holds,
whichever of the two is smaller.

## Getting the goods there

Phase P is the plumbing under the company: where stock actually lives, how it
gets from one place to another, and what happens when a business runs out of
money.

### One depot, and where stock is allowed to be

A warehouse is an ordinary commercial unit with `LogisticsManager` holding a
`WarehouseInstance` against it. Capacity is racking the player buys, and the
racks are a number rather than a hundred placed pallets — the stock they hold
is a line on a screen, and a placement puzzle nobody asked for is not a
warehouse.

The rule the whole system is built on is that a unit of stock is in exactly one
of three places: a warehouse, a branch, or a shipment that owns it. Every
transition is one move. Goods leave the source at dispatch and arrive at the
destination on completion, and there is no moment in between when they are in
both places or neither. Reservation covers the gap between "the player asked
for it" and "a van is free": stock is spoken for at the source, so it cannot be
sold out from under a shipment that is already promised.

Money works the same way. There is no company treasury. The warehouse's rent
and its stock are paid by a branch the player nominates, through the same
`debit` every other cost goes through.

### Shipments

`TransferOrder` is one record for the whole journey — REQUESTED to DELIVERED,
with FAILED and CANCELLED as the ways out. It deliberately is not split into an
order and a separate shipment: two records for one journey is two places for
the cargo to be, which is the bug this design exists to make impossible.

A shipment can be cancelled while the cargo is still on the shelf and not once
the van has gone. Cancelling mid-journey would mean deciding where the cargo
lands, and there is no honest answer to that.

### Vans you can see, and vans you cannot

A shipment in transit has an arrival time from the distance between its two
ends. If the player is near either end, `DeliveryTraffic` puts a real van on
the road, driven by a `DeliveryDriver` — a `TrafficDriver` that walks an A\*
route from `RoadNetwork.path_between` instead of turning at random. Reaching
the kerb is what finishes that shipment. Drive away and the van is despawned
and the clock finishes it instead.

Both paths call the same `complete_transfer`. The van is a view of the
shipment, never a second copy of it, which is why watching a delivery and
ignoring one produce the same stock in the same place.

The player can also take a run themselves. It uses no van, no driver and no
delivery budget, it is marked on the map, and it arrives when they get there —
time passing will not do it for them. Turning back puts every unit back where
it came from.

### Cover

`BackupPool` is the people who are not on shift right now. A manager with the
`call_backup` permission will pull somebody in when a branch is short-handed,
at a wage premium, after however long it takes them to travel across the city.
Anybody can cover their own role; covering somebody else's takes skill.

### Running out of money

`Obligation` is a view, never a ledger. It is built on demand from the systems
that already take money — payroll, the landlord, the lenders — so the forecast
cannot drift out of step with what actually gets charged, because there is
nothing to drift.

`DistressState` reads arrears, missed payments, cash and what is due, and puts
a business in one of HEALTHY, WARNING, DISTRESSED, CRITICAL, CLOSED or
LIQUIDATING. Nothing about it is sudden. Wages go into arrears before anybody
walks out; three missed pay runs is when somebody stops turning up. A branch
sits at CRITICAL for four days before the doors shut, and closing is not
deletion — the lease, the stock and the fittings are all still there, and it
can be reopened. Liquidation is the separate, explicit act of winding it up,
and it pays out at eighty per cent for stock and half for second-hand fittings.

A mortgage warns at three missed payments and a notice arrives at six, with ten
days to find the arrears. Curing it costs the arrears and not the whole debt.
Losing the property never leaves the player with nowhere to sleep.

## Crime, and the police

Phase Q is the crime side grown up. The legal simulation underneath it does not
pause for any of it: a player being chased across Central still has shops
trading, vans delivering and rent falling due.

### What the police know

The most important idea in the whole phase is that what is true and what the
police have been told are two different things, and the gap between them is
where escaping happens. `PoliceMemory` holds only what somebody could
plausibly have observed — where the player was when last seen, when that was,
roughly which way they were going, and what they were driving if anybody got a
look at it. It does not hold the player's position and nothing in it reads it.

Knowing the *player* and knowing the *car* are kept apart. A witness who
watched somebody get into a car knows both; the moment the player gets out,
those come apart, and that is what makes abandoning a vehicle worth doing.
Police no longer recognise anybody they merely look at — they need a
description or a car they are looking for.

### Wanted, in points

Stars are presentation. Underneath is one meter, and every crime adds to it, so
a theft then a robbery is worse than either alone. Each star changes what
happens: more units, further out, searching longer, and above three, units that
try to cut the player off rather than queue behind them. What it never changes
is how fast police drive. A harder level is more police behaving better, not
the same police cheating.

### The pursuit state machine

CLEAR, REPORTED, RESPONDING, PURSUIT, ESCAPING, SEARCHING, COOLDOWN, CLEARED,
BUSTED. `PoliceResponseManager` owns them and everything else reads them:
`SearchManager` runs the area, `PursuitCoordinator` hands out roles,
`RoadblockManager` decides whether it may block a road, the HUD picks a word.

Heat only drains once line of sight is broken. A player standing in front of an
officer is not escaping, however long they stand there.

### Searching

When the police lose the player they search a circle around where they were
last seen, which widens as they work outwards and never becomes the whole city.
The map draws that circle and nothing else — no officer positions, because the
search is meant to leave that uncertain.

`PursuitCoordinator` gives each unit a corner of it rather than sending
everybody to the same kerb, and during a chase makes one car PRIMARY, the rest
SECONDARY on their own approaches, and some INTERCEPT.

### Hiding

World visibility, not invisibility. A room the player walked into is a room the
street cannot see into, and that is the whole mechanic — no stealth meter, no
crouch. Ducking into a shop while an officer watches does not lose them;
ducking in unseen does. Owning the building makes no difference, and a car the
police are looking for parked outside undoes most of it.

### Roadblocks

Four stars and up, on validated road nodes: never inside a junction, never
overlapping a building, never in front of the player, never so many that the
city is sealed. They expire on their own and come down with the wanted level. A
roadblock is meant to create a decision, not a capture.

### Being caught

The fine is the level's fine surcharged by the worst thing actually done, so
three stars for a string of thefts is not three stars for armed robbery. An
arrest also costs hours that the city runs through — a day's trading lost is a
consequence a business owner feels. Legal vehicles and businesses are never
touched; stolen goods and stolen vehicles are.

### The underworld

Entirely apart from the company. Committing a crime does not make the player's
shops criminal and nothing in `crime/` touches a business.

Criminal reputation is its own number in five tiers, and it unlocks work rather
than weapons. A fence buys what the player should not have at thirty to sixty
per cent depending on standing. A vehicle buyer takes cars that are genuinely
stolen and refuses ones the player owns — that is what the dealership is for —
with a cooldown and a falloff so one street cannot be farmed. A broker offers
four kinds of work, each reusing gameplay the game already has.

Illegal money lands in the player's pocket like any other income and is tagged
by source. That is exactly as far as Phase Q goes: the ledger is preparation
for laundering, not laundering.

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
traffic/      road_network, traffic_light, traffic_driver, delivery_driver,
              traffic_manager, traffic_debug
art/          palette, character_look, character_kit, character_animator,
              building_kit, prop_kit
ui/theme/     ui_theme
audio/        audio_buses, tone_bank, audio_manager, surface_map, footsteps,
              vehicle_audio, ambience_director, music_director, game_audio,
              audio_debug
ui/menu/      main_menu, settings_screen, pause_menu, menu_kit
vehicles/     vehicle_base, vehicle_data, vehicle_door, vehicle_catalogue
              + cars/*.tres  (compact, sedan, hatchback, van, suv, coupe)
world/        world_manager, district_data, district_01, district_02,
              world_debug, city_kit, day_night_cycle, portal, interiors/
world/map/    map_manager, map_marker
ui/map/       city_map
property/     property_manager, commercial_property, residence_property,
              garage_property, home_manager, owned_furniture,
              real_estate, property_record, property_listing, mortgage_data,
              tenant_data, multi_unit_building, property_sign
ui/property/  property_sale_panel, real_estate_panel
business/     business_manager, business_instance, business_type_data,
              business_catalogue, supplier_data, purchase_order, loan,
              marketing_campaign, upgrade_data, brand_data, company_manager,
              company_debug, company_terminal, kitchen_order
business/models/  operating_model, counter_service_model, table_service_model,
              membership_model, venue_model, operating_models, service_result,
              lost_reason
logistics/    logistics_manager, warehouse_data, warehouse_instance,
              transfer_order, delivery_route, warehouse_terminal,
              delivery_traffic, dropoff_point
crime/        crime_manager, crime_data, crime_profile, crime_event,
              criminal_reputation, criminal_contact, criminal_contact_point,
              illegal_job, illegal_job_factory, underworld_manager,
              restricted_area, crime_debug, underworld_debug
police/       police_response_manager, police_memory, search_manager,
              pursuit_coordinator, roadblock_manager, hiding
finance/      finance_manager, obligation, distress_state, liquidation
staff/        backup_pool
vehicles/company/  company_fleet
employees/    employee_data, employee_ai, shift_slot
customers/    customer_ai, customer_spawner, customer_demand,
              customer_archetype, service_queue
ui/company/   company_dashboard, staff_schedule_panel, manager_panel,
              branch_finance_panel
ui/logistics/ logistics_panel
ui/underworld/  underworld_panel, contact_panel
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

The empire phase is tested the same way, and mostly for *independence*: two
businesses that quietly shared a store room, a payroll or a set of books would
look fine from inside either one of them. A second unit is leased, a coffee shop
is founded in it, fitted with a machine and a counter, stocked with ingredients
and staffed with a barista who walks in and makes a drink somebody ordered. Both
shops then trade at once with separate customers, separate takings and separate
stock; a stocker moves goods without inventing any; a manager opens up, fills
the shelves and reorders inside a budget without ordering the same thing twice;
a delivery goes PLACED to IN TRANSIT to DELIVERED and arrives exactly once; a
campaign raises footfall and expires; an upgrade helps only the shop that bought
it; a loan is drawn, paid, missed and settled early; eight hours are slept
through and both shops trade through them; a crime and an arrest happen around
it all; and the whole empire goes through a save file and back without
duplicating anything. A Phase H save loads into it unchanged.

The city expansion is tested for the thing that is easy to get wrong when a
world grows: that it is still one world. Both districts register with their own
bounds, densities and rent modifiers, and the modifiers actually differ in the
direction the design says they do — Central is dearer, busier and better
policed, and the dearest unit in it beats the dearest unit in Harbour Row.
A point in either district resolves to it, a point on the road between them
resolves to something rather than nothing, and walking into Central names it
once and not twice. A walking route and a driving route both cross the boundary
with no gap in them, and the ground holds all the way along the connecting
stretch — the check that caught a building laid across a street and, later, a
second one laid across a service road.

The map is checked for what is on it: every category represented, every marker
labelled and inside the city, nothing stray, and Central represented. A
destination is set, its distance measured, its route drawn, and arriving fires
the arrival and clears it. The better flat is rented — refused without the
money, charged a deposit and a first rent with it, refused twice — set as home,
and slept in, with the studio's bed refusing to be slept in once it is not home
any more. A courier run is taken, the destination proved to be far enough away
to be worth paying for, driven to and paid; a run that is dropped pays nothing.
Central's units are proved to differ from each other physically rather than only
in price, every property in the city is proved to have its own id, and one is
leased and given up. A robbery in Harbour Row is committed and the wanted level
carried into Central, where the police still answer. Then the whole enlarged
world goes through a save file — lease, home, delivery record and all — and a
save written before the second district existed still loads into it.

Last, the edges: the closed road at the top of Central stops the player without
dropping them out of the world, the gateway is walled along its verges, there is
ground under both car parks, and every layer of the world debug view draws and
clears without taking the game with it.

The visual pass is tested for the things a swap of art can quietly break. The
player is checked to be a built figure with hips, chest, head, arms and legs, to
have a head and shoes on it, to have no placeholder capsule left anywhere under
it, and to swing its legs when it walks and not when it stands. The crowd is
checked to be built figures with a range of skin tones, hair colours, clothing
and heights — a crowd of clones passes a count and fails the eye. An officer is
checked to be built as police, in a cap with a badge and a stab vest, in a dark
uniform, and the patrol car to carry a livery and a light bar. Every car in the
roster is instanced and checked for a chassis, bonnet, boot, cabin, roof, grille,
headlights, taillights, mirrors, wheel hubs and arches, and the roster as a whole
for at least four distinct silhouettes. The shop is checked to have glazing, a
stall riser, racking in the store room and lighting; both flats for the furniture
that makes them lived-in. And the interface is checked to be themed once, at the
window root, with money and losses reading the same colour there as everywhere
else.

The audio and front end are tested for the things a headless machine can
actually know, which is not whether anything sounds good. The mixer is checked
to exist, to route every bus through a limited master, and to mute rather than
whisper at zero. Every sound in the bank is built and checked to be non-empty,
with loops marked as loops and one-shots as one-shots, and a sound asked for
twice proved to be the same cached stream rather than a waveform synthesised per
footstep. Standing in the road reports asphalt and stepping onto the pavement
reports concrete; every surface has a footstep and no two share one. A parked
car is proved not to be running, getting in starts it and getting out stops it;
a patrol car has a siren and a civilian car does not, and the siren is proved to
agree with the light bar. Ambience is checked to differ between day and night,
between a shop and a cafe, and between inside and out. The music states are
checked to be wired, and the track table to be deliberately empty rather than
missing.

Settings are checked to start where the mix says, to survive being wiped and
read back — which is what restarting the game does — and to fall back to
defaults rather than failing when the file is corrupt. The three graphics
presets are checked to differ in the direction they claim to, and applying one
is proved to reach the sun's shadows. Bindings are read, rebound, clashed
against another action and reset. Save slots are checked empty, written,
described without being loaded, listed, and — for a deliberately corrupted slot
— skipped rather than offered; the autosave is proved to have a slot the player
cannot write to, to fire once and refuse to fire twice in a row. Finally the
front end is checked to exist, to be what the game boots to, and to leave the
test harness loading the world directly.

The property pass is tested as arithmetic and as decisions. The arithmetic is
checked directly, because a formula is either right or it is not: value scales
with floor area, pitch, district and condition; a fringe address yields more
than a prime one; the level payment is the level payment for the term; interest
plus principal is exactly what was paid; the selling fee is 4% and the proceeds
are the price less the fee less what is owed. The decisions are driven through
the same calls the screens make — buying for cash takes the money exactly once
and takes the board down, buying on a mortgage takes only the deposit, an
overpayment comes off the principal and shrinks the next period's interest, a
payment that cannot be met is missed and three misses stop any further
borrowing, and a payoff leaves the property owned outright with no debt behind
it.

Letting is played rather than asserted: a flat is listed, applicants are waited
for at the going rate, one is signed, the rent arrives week after week, the
tenancy is ended and the money stops. Asking rent is checked to move demand in
both directions. The block of flats is let one unit at a time and checked to
read as three-quarters full, and one tenant leaving is checked to empty exactly
one flat. Buying the unit the player's own shop trades from is checked to charge
no rent to anybody on rent day and to refuse the sale while the shop is still in
it; buying the flat they live in is checked to keep them living there. Property
equity is checked to reach net worth, the map to tell FOR SALE from OWNED in
different colours, and a portfolio to survive a save and a load with its
mortgage, its condition and its tenant intact — as is a save written before any
of this existed. One test exists for a bug: every door in the city with a board
outside it is checked to answer for itself rather than for the board.

```sh
godot --headless --path game res://tests/smoke_test.tscn
```

It exits non-zero if any check fails. As of the property pass it runs 1,756
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
`player_away`, `driving_business`, `commercial_properties`, `portfolio`,
`market_operating`, `coffee_empty`, `coffee_placement`, `ingredient_order`,
`coffee_customers`, `barista`, `stocker`, `manager_running`, `order_in_transit`,
`delivery_received`, `marketing`, `upgrades`, `two_businesses`,
`empire_finance`, `business_value`, `loans`, `net_worth`, `player_away_empire`,
`city_overview`, `harbour_row`, `central_district`, `central_night`,
`district_road`, `central_street`, `central_plaza`, `traffic_crossing`,
`central_pedestrians`, `city_map`, `map_filters`, `map_route`,
`central_property`, `large_interior`, `better_apartment`, `courier_delivery`,
`vehicle_roster`, `harbour_business`, `central_business`, `city_empire`,
`cross_district_chase`, `characters`, `police_officer`, `police_close`,
`business_exterior`, `hero`, `pause_menu`, `loaded_game`, `dealer_exterior`,
`showroom`, `vehicle_detail`, `vehicle_compare`, `used_listing`,
`purchase_confirm`, `player_vehicle`, `my_vehicles`, `repair_shop`,
`repair_screen`, `garage_exterior`, `garage_stored`, `premium_apartment`,
`furniture_store`, `furniture_buying`, `furniture_placing`,
`furnished_apartment`, `profile`, `night_premium`, `for_sale_board`,
`property_sale_screen`, `mortgage_offer`, `property_purchase_confirm`,
`dockside_court`, `dockside_court_let`, `property_portfolio`,
`property_detail`, `letting_screen`, `tenant_applicants`, `tenant_signed`,
`mortgage_tab`, `income_tab`, `renovation_screen`, `property_sale_confirm`,
`property_map`, `property_profile`, `owned_shop_unit`, `multi_unit_detail`,
`property_empire`) and camera `distance` /
`yaw` / `pitch` for overview shots. Scenarios drive the real interactables
rather than faking their results. It runs under the Compatibility renderer, so
lighting is close to but not identical to the Forward+ game.

The menus are their own scene, so they have their own small harness:

```sh
xvfb-run -a godot --rendering-driver opengl3 --path game \
    res://tests/menu_shot.tscn ++ out=shot.png screen=settings tab=1
```

`screen` is `menu`, `settings` or `load`, `tab` picks a settings tab, and
`saves=1` plays the world briefly first so the load screen has real slots to
list rather than photographing an empty one.

Phase O tests the company. That the five business types are five genuinely
different things and each resolves to its own operating model; that a restaurant
cannot open without seats, a stove and something in the larder, and can with all
three; that a cover really is seated, ordered, cooked out of real ingredients,
carried and paid for — watched, with the cook at the stove and the server at the
pass, and again as numbers with nobody in the building; that an hour with no cook
earns nothing and says why; that a full dining room turns people away rather than
stacking them; that a gym's machines are its ceiling, that its memberships pay
again the next day without anybody visiting, and that it gets dirty without a
cleaner and comes back with one; that the same venue takes more at eleven at
night than at three in the afternoon and that the curve rather than a spawn cheat
is why; that sending security home shrinks the room and raises a warning; that a
second shop under one name shares the brand and nothing else; that transferring
somebody moves them rather than copying them; that a rota clashing with itself or
with another branch is refused; that two shifts in a day are two shifts and a
Friday night one runs into Saturday; that a manager stays inside their
permissions and their allowance; that a deliberate kitchen backlog is named as a
kitchen backlog; that district and time-of-day demand tilt without deciding; that
a business left alone keeps trading and that staffing, stock and capacity still
matter when nobody is watching; that a unit the player owns charges the business
no rent; that the company's figures are the sum of the branches and that company
value is not net worth; that a company of five businesses, three brands, weekly
rotas, manager permissions, cleanliness and milestones survives a save and a load
exactly once; and that a Phase N save with no company in it loads, keeps every
business, employee, wage and skill it had, and quietly grows a brand for each.

The logistics and failure checks are the largest single block. Goods
conservation is the thing most of them are really testing: a depot holds what
it is given and no more, a bulk order is discounted once and delivered once, a
reservation cannot be sold out from under a shipment, a shipment cancelled on
the dock releases exactly what it held, a shipment that fails mid-journey puts
its cargo back, a delivery the player watches and one they do not both land
the same units in the same place, and a run the player gives up on halfway
loses nothing. Then the failure side: wages going into arrears, staff who stop
turning up after three missed pay runs, a manager calling cover for a shop
that requires no staff at all, the distress states in order, a loan called in
after four misses and brought back into good standing by paying it, closing a
branch without losing its lease or its stock, winding one up and getting
eighty per cent for the stock and half for the fittings, a brand surviving the
loss of a branch, a mortgage warning, its notice, curing it, and losing the
property without losing the roof over the player's head. And migration: a
Phase O save loads with no logistics in it and does not inherit a depot, a
fleet or a shipment from the session before.

The crime and police checks come next. Eviction from the first warning to the
landlord taking the unit back, including a business that keeps every last
thing it owns except the address. Then the crime table itself — every crime
banded, priced and answered for, a robbery worse than a shoplifting, a
carjacking worse than taking an empty car, and violence worth nothing on the
street. The wanted thresholds at every star; that each star sends more units
further and searches longer without any police car becoming faster; the
pursuit states and the transitions between them; that the police know where
the player *was* and that walking away does not update it; the search area,
its growth, and that units are spread around it rather than stacked;
reacquisition; a legally owned car becoming one the police look for without
becoming stolen; losing a description by switching cars unseen and failing to
by switching them watched; roadblocks that appear only at four stars, never in
a junction, never on top of the player and never so many that the city is
sealed; hiding that does not work in the middle of the street; a fine that
rises with what was actually done; a fence that pays under value and leaves
legitimate goods alone; a buyer that refuses the player's own car and takes a
stolen one exactly once; reputation tiers and what they unlock; a job that
pays once and cannot be completed twice; a job walked away from that pays
nothing; and the heat, the search, the reputation and the running job all
surviving a save without paying anybody twice or restoring a patrol fleet that
no longer exists.

And the two that matter most for what this game is: a Phase P save loads with
no crime in it and inherits none of it, and a company keeps trading —
deliveries landing, shops open, books balancing — while its owner is being
chased across the city.

## What is next

Nothing is started. The audio and front-end pass left the most obvious thread of
all: there is no music. The director, the states and the crossfades are wired to
the real events with silence in every slot, because inventing a soundtrack for a
game meant to be played for hours would be worse than shipping none — the day
tracks exist, they are a line each in one table.

The sound bank is synthesised, which has a ceiling of its own. Filtered noise
makes a convincing footstep and a passable engine; it does not make a convincing
crowd, and there is no voice work at all — the Voice bus exists and carries
nothing. Pedestrian reactions are architecture only for the same reason.
`Mute when unfocused` is not implemented. And loading is fast enough that a
loading screen would flash rather than inform, so the tips live on the title
screen instead; that changes the day a district takes real time to build.

The visual pass left its own threads. The characters and
cars are assembled primitives, which has a ceiling: going further — real
cloth, faces, curved bodywork, wheels that are not cylinders — means modelled
meshes rather than more code, and the kits are shaped so that swapping one part
for a mesh does not disturb the rest. Animation is procedural and has no upper
body work beyond a lean and an arm lift; a proper AnimationTree would buy
gestures, but only once there are rigs to drive. Interiors are roofless by
necessity and so cannot have ceiling fittings, which is why the light strips run
along the wall tops.

The city expansion left its own threads. Population is still
built at load rather than streamed: both districts spawn their pedestrians and
parked cars up front, and only traffic follows the player. That is affordable at
two districts and will not be at four, so the next world phase wants activation
ranges around the district the player is in. Business far simulation already
works that way and is the model to copy.

The vehicle roster grew to six models but nothing sells them: `resale_value` is
read by net worth and by nothing else, which is the hook a dealership would hang
off. Office space is zoned in Central and has no gameplay behind it. Street
names exist as constants and on the map but there is no address search. And the
north end of Central Boulevard is barriered rather than walled, which is a
promise about a third district that has not been kept yet.

The empire phase left its own threads: a third business type
(the architecture takes one as a `BusinessTypeData`, a stock list and — if it
cooks — a set of recipes), competitor businesses to compete for the same local
demand, and property that can be bought rather than rented.

Eviction is the oldest of those threads and is still not built. Phase P got
closer than any phase before it — rent arrears are counted, the stages are
named (RENT OVERDUE, DEFAULT NOTICE, LEASE AT RISK), and the card on the
company screen says so — but no landlord ever actually takes a unit back. The
foreclosure machinery is the shape it should copy: a notice, a deadline, a
stated amount to cure, and a completion that rehouses whatever was inside.

The crime expansion left threads of its own. Police response is reconstructed
from the wanted state on load rather than restored unit by unit, which is
honest but means a chase always resumes as a search — a saved pursuit can never
come back as a pursuit. Interception is a heading and a guess rather than a
route, so a unit told to cut somebody off sometimes arrives at a perfectly
sensible place the player was never going. Roadblocks pick their node by
distance and heading and know nothing about whether the route past them is
actually pleasant to drive. And hiding is binary: a room hides you completely
or not at all, with no notion of a window somebody could look through.

The underworld is three contacts and four job types, which is deliberately the
smallest thing that is a system rather than a feature. Nothing generates work
in the world — a job is a line of text and a target, not a marked van waiting
somewhere — and the robbery contract is the only one that puts a marker on the
map. Illegal income is tagged and goes straight into the same pocket as
everything else; there is nothing to launder and nothing that cares.

The logistics phase left threads of its own. There is one depot in the city
and the code takes a list, so a second is a table entry and a building rather
than new systems — but nothing balances two, and the bulk bands were tuned
against one. Routes run their stops in the order they were added, with no
notion of which order is shorter. A shipment carries whatever fits in one van
and a bigger one is refused rather than split across two. And the player can
drive only one run at a time, which is the honest limit of one player and one
van but means a chain of six branches is always going to be somebody else's
job.

The earlier phases left three more threads: a second
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
