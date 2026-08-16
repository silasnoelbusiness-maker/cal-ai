class_name TrafficLight
extends Node3D
## One junction's signals.
##
## A single node owns the whole crossroads rather than four independent heads,
## which makes conflicting greens impossible by construction: there is one phase
## at a time and the two axes read it opposite ways.
##
## Cars ask `should_stop_for()`; they never read the phase directly, so adding
## turn arrows later changes this file and nothing else.

signal phase_changed(phase: Phase)

enum Phase { NS_GREEN, NS_YELLOW, EW_GREEN, EW_YELLOW }
enum Colour { RED, YELLOW, GREEN }

@export var green_seconds: float = 15.0
@export var yellow_seconds: float = 3.0
## Distance from the junction centre to the stop line on each approach.
@export var stop_line_distance: float = 8.0
## How far to one side of the carriageway the signal heads stand. Must clear the
## road half-width, or the posts end up planted in the traffic they direct.
@export var head_lateral_offset: float = 8.8
## Which axis goes first. Staggering the two junctions stops the whole district
## turning green at once.
@export var start_phase: Phase = Phase.NS_GREEN
@export var start_offset_seconds: float = 0.0

var phase: Phase = Phase.NS_GREEN

var _timer: float = 0.0
var _heads: Array[Dictionary] = []
var _materials: Dictionary = {}


func _ready() -> void:
	add_to_group(&"traffic_light")
	phase = start_phase
	_timer = _duration_of(phase) - start_offset_seconds
	_build_materials()
	_build_heads()
	_refresh_heads()


## Puts the signal back to its configured starting phase. The district calls
## nothing else; it exists so timings can be changed at runtime — by a test, or
## later by whatever wants rush-hour cycles — without waiting out the phase
## already in progress.
func restart_cycle() -> void:
	phase = start_phase
	_timer = _duration_of(phase) - start_offset_seconds
	_refresh_heads()
	phase_changed.emit(phase)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_advance()


# --- Queries -------------------------------------------------------------

func colour_for(axis_is_east_west: bool) -> Colour:
	match phase:
		Phase.NS_GREEN:
			return Colour.RED if axis_is_east_west else Colour.GREEN
		Phase.NS_YELLOW:
			return Colour.RED if axis_is_east_west else Colour.YELLOW
		Phase.EW_GREEN:
			return Colour.GREEN if axis_is_east_west else Colour.RED
		_:
			return Colour.YELLOW if axis_is_east_west else Colour.RED


func is_green_for(axis_is_east_west: bool) -> bool:
	return colour_for(axis_is_east_west) == Colour.GREEN


## Yellow counts as stop. A prototype has no dilemma zone to reason about, and
## "yellow means go faster" is not the behaviour to model first.
func should_stop_for(axis_is_east_west: bool) -> bool:
	return colour_for(axis_is_east_west) != Colour.GREEN


## Where a car on this approach should wait. `approach_direction` is the way the
## car is travelling.
func stop_line_for(approach_direction: Vector3) -> Vector3:
	var flat := Vector3(approach_direction.x, 0.0, approach_direction.z)
	if flat.length_squared() < 0.01:
		return global_position
	return global_position - flat.normalized() * stop_line_distance


# --- Cycle ---------------------------------------------------------------

func _advance() -> void:
	match phase:
		Phase.NS_GREEN:
			phase = Phase.NS_YELLOW
		Phase.NS_YELLOW:
			phase = Phase.EW_GREEN
		Phase.EW_GREEN:
			phase = Phase.EW_YELLOW
		Phase.EW_YELLOW:
			phase = Phase.NS_GREEN
	_timer = _duration_of(phase)
	_refresh_heads()
	phase_changed.emit(phase)


func _duration_of(which: Phase) -> float:
	return yellow_seconds if which in [Phase.NS_YELLOW, Phase.EW_YELLOW] else green_seconds


# --- Visuals -------------------------------------------------------------

## One shared material per lamp colour per state, so switching a signal is an
## assignment rather than a new material.
func _build_materials() -> void:
	_materials = {
		"red_on": CityKit.make_emissive_material(Color(0.45, 0.08, 0.08), 3.4, Color(1.0, 0.18, 0.15)),
		"red_off": CityKit.make_material(Color(0.16, 0.06, 0.06), 0.7),
		"yellow_on": CityKit.make_emissive_material(Color(0.45, 0.36, 0.09), 3.4, Color(1.0, 0.75, 0.2)),
		"yellow_off": CityKit.make_material(Color(0.16, 0.14, 0.06), 0.7),
		"green_on": CityKit.make_emissive_material(Color(0.09, 0.42, 0.16), 3.4, Color(0.25, 1.0, 0.35)),
		"green_off": CityKit.make_material(Color(0.06, 0.15, 0.08), 0.7),
		"post": CityKit.make_material(Color(0.180, 0.192, 0.216), 0.6, 0.4),
	}


## Four heads, one per approach, each showing that approach's own colour. Lamps
## face upward as well as outward so they read from the top-down camera.
func _build_heads() -> void:
	var approaches := [
		{"offset": Vector3(0.0, 0.0, -stop_line_distance), "ew": false},
		{"offset": Vector3(0.0, 0.0, stop_line_distance), "ew": false},
		{"offset": Vector3(-stop_line_distance, 0.0, 0.0), "ew": true},
		{"offset": Vector3(stop_line_distance, 0.0, 0.0), "ew": true},
	]

	for i in approaches.size():
		var data: Dictionary = approaches[i]
		var offset: Vector3 = data["offset"]
		# Set out onto the kerb corner rather than standing in the road: the
		# approach's own axis keeps the stop-line distance, the other axis is
		# pushed clear of the carriageway.
		# On the approaching driver's right, which for right-hand traffic is the
		# side they actually look at.
		var corner := offset
		if data["ew"]:
			corner.z = -signf(offset.x) * head_lateral_offset
		else:
			corner.x = signf(offset.z) * head_lateral_offset

		var holder := Node3D.new()
		holder.name = "Head%d" % i
		holder.position = corner
		add_child(holder)

		CityKit.add_cylinder(
			holder, "Post", Vector3(0.0, 1.6, 0.0), 0.11, 3.2, _materials["post"]
		)
		CityKit.add_box(
			holder, "Case", Vector3(0.0, 3.55, 0.0), Vector3(0.5, 1.3, 0.5), _materials["post"], false
		)

		var lamps := {}
		var lamp_names := ["red", "yellow", "green"]
		for lamp_index in lamp_names.size():
			var lamp := CityKit.add_box(
				holder,
				"Lamp_%s" % lamp_names[lamp_index],
				Vector3(0.0, 4.02 - float(lamp_index) * 0.4, 0.0),
				Vector3(0.56, 0.3, 0.56),
				_materials["%s_off" % lamp_names[lamp_index]],
				false,
				false
			)
			lamps[lamp_names[lamp_index]] = lamp

		_heads.append({"east_west": data["ew"], "lamps": lamps})


func _refresh_heads() -> void:
	for head in _heads:
		var colour := colour_for(head["east_west"])
		var lamps: Dictionary = head["lamps"]
		_set_lamp(lamps["red"], "red", colour == Colour.RED)
		_set_lamp(lamps["yellow"], "yellow", colour == Colour.YELLOW)
		_set_lamp(lamps["green"], "green", colour == Colour.GREEN)


func _set_lamp(lamp: Node3D, colour_name: String, lit: bool) -> void:
	var mesh := lamp as MeshInstance3D
	if mesh == null:
		return
	mesh.material_override = _materials["%s_%s" % [colour_name, "on" if lit else "off"]]
