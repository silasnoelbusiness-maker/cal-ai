class_name DayNightCycle
extends DirectionalLight3D
## Drives the sun and sky from TimeManager.
##
## Sun elevation follows a sine over the day, so the light sweeps and the
## shadows rotate. At night the directional light is dimmed to a cool moonlight
## rather than switched off, so the city stays readable, and everything in the
## "street_light" group is toggled on.

## Emitted when the amount of daylight changes: 0.0 is full night, 1.0 is full
## day. The district uses it to fade its lit-window materials in and out.
signal daylight_changed(amount: float)

@export var environment_path: NodePath
@export_group("Sun")
## Pulled back in Phase T2. At 1.25 with the ambient fill behind it, every pale
## surface in the city — and the pavement is pale — clipped to flat white, and a
## white wall that shows no shape, shadow or material is the §100 test failing.
@export var day_energy: float = 1.02
@export var night_energy: float = 0.14
@export var day_color: Color = Color(1.0, 0.965, 0.898)
@export var golden_color: Color = Color(1.0, 0.72, 0.45)
@export var night_color: Color = Color(0.435, 0.541, 0.878)
@export_group("Sky")
@export var day_sky_energy: float = 1.0
@export var night_sky_energy: float = 0.16
## Dropping the daytime figure buys shadow contrast, but it was taken too far at
## first: 0.35 against a night value of 0.3 left almost no day/night difference
## in the fill light, and late afternoon — when the sun is low and the fill is
## doing most of the work — went nearly black. The two now sit clearly apart.
## Less fill, so shadows are shadows. Most of the washed-out look was here
## rather than in the sun: ambient light has no direction, so raising it flattens
## everything at once.
@export var day_ambient_energy: float = 0.38
## Enough that unlit tarmac is dark rather than absent. A road the player
## cannot see is not atmosphere, it is a hole in the picture.
@export var night_ambient_energy: float = 0.34
@export_group("Street Lights")
## Street lights switch on once the sun drops below this height (-1..1).
@export var street_light_threshold: float = 0.08

var _environment: Environment = null
## -1 = not yet applied, 0 = off, 1 = on. A plain bool cannot express "unknown",
## which meant a night start-up matched the default and skipped switching on.
var _street_lights_on: int = -1
var _initialised: bool = false
var _last_daylight: float = -1.0


func _ready() -> void:
	var world_environment := get_node_or_null(environment_path) as WorldEnvironment
	if world_environment != null:
		_environment = world_environment.environment
	# The street light group is populated by the district builder, which runs in
	# its own _ready; defer so the first update sees a complete group.
	call_deferred("_first_update")


func _first_update() -> void:
	_initialised = true
	_apply(TimeManager.day_fraction)


func _process(_delta: float) -> void:
	if _initialised:
		_apply(TimeManager.day_fraction)


func _apply(fraction: float) -> void:
	# -1 at midnight, 0 at 06:00 and 18:00, +1 at noon.
	var sun_height := sin((fraction - 0.25) * TAU)
	# Full brightness by the time the sun is ~17 degrees up, which is about 07:00,
	# and held until about 17:00. The original ramp reached full daylight only
	# near noon, so the city was dusk-dark by mid-afternoon — the sun is only
	# 7 degrees up at half past five, and that was enough to put the lights out.
	# Golden hour still reads, because the warm tint below is driven off
	# sun_height directly and peaks exactly where this saturates.
	var daylight := clampf(sun_height * 3.2 + 0.08, 0.0, 1.0)
	# Peaks when the sun is near the horizon, for sunrise/sunset warmth.
	var golden := clampf(1.0 - absf(sun_height) * 4.0, 0.0, 1.0) * clampf(sun_height * 8.0, 0.0, 1.0)

	# Elevation, plus an azimuth that swings east to west across the day.
	rotation_degrees.x = -clampf(rad_to_deg(asin(sun_height)), -12.0, 90.0)
	rotation_degrees.y = lerpf(-70.0, 110.0, clampf(fraction, 0.0, 1.0))

	light_energy = lerpf(night_energy, day_energy, daylight)
	var base_color := night_color.lerp(day_color, daylight)
	light_color = base_color.lerp(golden_color, golden)

	if _environment != null:
		_environment.background_energy_multiplier = lerpf(
			night_sky_energy, day_sky_energy, daylight
		)
		_environment.ambient_light_energy = lerpf(
			night_ambient_energy, day_ambient_energy, daylight
		)

	_set_street_lights(sun_height < street_light_threshold)

	# Coarse steps: window materials do not need a per-frame update.
	if absf(daylight - _last_daylight) > 0.02:
		_last_daylight = daylight
		daylight_changed.emit(daylight)


func _set_street_lights(should_be_on: bool) -> void:
	var wanted := 1 if should_be_on else 0
	if wanted == _street_lights_on:
		return
	_street_lights_on = wanted
	# Headlights are a separate group so the two can be counted and reasoned
	# about independently, even though they switch on together.
	for group in [&"street_light", &"vehicle_headlight"]:
		for light in get_tree().get_nodes_in_group(group):
			if light is Light3D:
				light.visible = should_be_on
