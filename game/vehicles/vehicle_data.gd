class_name VehicleData
extends Resource
## Everything that varies between one *model* of vehicle and another: how it
## drives, how tough it is, and how big the placeholder body is.
##
## A van, a sports car, a truck, a taxi or a police car is a new .tres file,
## not a new script. Note that ownership is deliberately NOT here — that is
## per-instance state (see Vehicle.owner_type), because every sedan in the city
## shares this resource and they do not share an owner.

@export var id: StringName = &""
@export var display_name: String = "Car"
@export_multiline var description: String = ""

@export_group("Performance")
## Top forward speed in metres per second. 24 m/s is about 86 km/h.
@export var max_speed: float = 23.0
@export var max_reverse_speed: float = 8.0
## Metres per second squared under throttle.
@export var acceleration: float = 12.0
## Deceleration when braking against the direction of travel.
@export var brake_deceleration: float = 22.0
## Deceleration when coasting with no input.
@export var engine_braking: float = 5.5
@export var handbrake_deceleration: float = 16.0

@export_group("Steering")
## Turn rate in radians/second at a standstill-ish crawl.
@export var steer_rate_low: float = 2.5
## Turn rate in radians/second at max_speed. Lower than steer_rate_low so the
## car cannot pull a hairpin at full pelt.
@export var steer_rate_high: float = 0.95
## How fast steering input ramps in and out. Higher is twitchier.
@export var steer_response: float = 7.0
## Steering multiplier while the handbrake is down, for tighter parking turns.
@export var handbrake_steer_bonus: float = 1.35
## Below this speed (m/s) the car cannot turn at all, so it never pivots on the
## spot like a tank.
@export var min_speed_to_steer: float = 0.6
## Speed (m/s) at which steering authority is fully available.
@export var full_steer_speed: float = 3.0

@export_group("Value")
## What a clean, low-mileage example of this model fetches on the used market.
## Every valuation in the game starts here and is modified by that particular
## car's mileage and condition, so this is the model's worth, never an
## individual's. Only the player's own vehicles count toward their net worth; a
## stolen one is not theirs to sell.
@export var resale_value: int = 4500
## List price at the dealership for a brand new one. Deliberately independent of
## `resale_value` rather than derived from it: the gap between the two is what
## makes buying used the sensible early move.
@export var price_new: int = 12000

@export_group("Showroom")
## The marque. Model names are already distinct, so this is who builds them —
## what the dealership groups its floor by and what the player learns to
## recognise.
@export var manufacturer: String = "Kestrel"
## What kind of thing it is, in the words the showroom uses.
@export var vehicle_class: String = "Saloon"
## 0-100. What owning one says about you, which is deliberately not what it
## cost: a panel van is dear and says nothing, and lifestyle reads this rather
## than the price tag.
@export var prestige: int = 20
## Whether the dealership will sell you one. Police cars exist and are not for
## sale, which is why this is off by default.
@export var purchasable: bool = false
## Cargo volume in arbitrary units, for the deliveries and equipment-moving a
## van is obviously for. Nothing reads it yet; it is here so the roster does not
## have to be revisited when something does.
@export var cargo_capacity: int = 0

@export_group("Durability")
@export var max_health: float = 100.0
## Impact speed (m/s) below which a collision does no damage at all.
@export var damage_speed_threshold: float = 7.0
## Health lost per m/s of impact speed above the threshold.
@export var damage_per_impact_speed: float = 3.2
## Fraction of speed kept after a head-on impact. Low values feel like a crash,
## high values feel like a bumper car.
@export var impact_speed_retention: float = 0.15

## Body silhouettes. Each is a different arrangement of bonnet, cabin and boot;
## the dimensions still come from the numbers above.
enum Profile { HATCHBACK, SALOON, VAN, SUV, COUPE, CRUISER }

## Paint schemes that mean something. A livery is not a colour — it is the
## panels that tell the player at a glance what a car is for.
enum Livery { NONE, POLICE }

@export_group("Body")
@export var body_length: float = 4.3
@export var body_width: float = 1.9
## Height of the lower body box, above the ground clearance.
@export var body_height: float = 0.62
@export var cabin_height: float = 0.58
@export var ground_clearance: float = 0.22
@export var wheel_radius: float = 0.34
@export var wheel_width: float = 0.25
@export var body_color: Color = Color(0.541, 0.259, 0.243)
@export var trim_color: Color = Color(0.176, 0.184, 0.208)
@export var glass_color: Color = Color(0.122, 0.184, 0.216)
## Which silhouette the body builder draws. Two cars with the same numbers and
## different profiles are the difference between a roster and one car painted
## six colours.
@export var body_profile: Profile = Profile.SALOON
## How far the cabin sits back from the middle, as a fraction of the length.
## Positive is towards the boot, which is what a long bonnet looks like.
@export var cabin_offset: float = 0.06
@export var livery: Livery = Livery.NONE


func get_total_height() -> float:
	return ground_clearance + body_height + cabin_height


## Top speed as the HUD shows it.
func get_max_speed_kmh() -> float:
	return max_speed * 3.6


# --- Showroom ratings ----------------------------------------------------
#
# The numbers on the dealership wall are read off the physics rather than
# stored beside it. A car that is quicker in the driver's seat is quicker on
# the board by construction, and there is no second copy of the roster to drift
# out of step with the first.

## Maps a value in [from, to] onto 0-100, clamped at both ends.
static func _rate(value: float, from: float, to: float) -> int:
	return clampi(roundi((value - from) / maxf(to - from, 0.001) * 100.0), 0, 100)


func speed_rating() -> int:
	return _rate(max_speed, 15.0, 37.0)


func acceleration_rating() -> int:
	return _rate(acceleration, 7.0, 25.0)


## Cornering, from how much steering authority survives at speed and how
## quickly the car answers the wheel.
func handling_rating() -> int:
	return clampi(
		roundi(_rate(steer_rate_high, 0.7, 1.35) * 0.65 + _rate(steer_response, 6.0, 10.0) * 0.35),
		0, 100
	)


## How much of a shunt it will take: the health it carries, less how hard each
## impact hits it.
func durability_rating() -> int:
	return clampi(
		roundi(_rate(max_health, 55.0, 175.0) * 0.75 + (100 - _rate(damage_per_impact_speed, 2.0, 5.5)) * 0.25),
		0, 100
	)


## Every showroom figure in one dictionary, in the order the panels show them.
func showroom_ratings() -> Dictionary:
	return {
		"Top speed": speed_rating(),
		"Acceleration": acceleration_rating(),
		"Handling": handling_rating(),
		"Durability": durability_rating(),
		"Prestige": clampi(prestige, 0, 100),
	}
