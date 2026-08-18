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
## What the car is worth second hand. Only the player's own vehicles count
## toward their net worth; a stolen one is not theirs to sell.
@export var resale_value: int = 4500

@export_group("Durability")
@export var max_health: float = 100.0
## Impact speed (m/s) below which a collision does no damage at all.
@export var damage_speed_threshold: float = 7.0
## Health lost per m/s of impact speed above the threshold.
@export var damage_per_impact_speed: float = 3.2
## Fraction of speed kept after a head-on impact. Low values feel like a crash,
## high values feel like a bumper car.
@export var impact_speed_retention: float = 0.15

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


func get_total_height() -> float:
	return ground_clearance + body_height + cabin_height


## Top speed as the HUD shows it.
func get_max_speed_kmh() -> float:
	return max_speed * 3.6
