extends Node
## Lifetime counters for the ordinary business of living: shifts worked, meals
## eaten, nights slept, kilometres driven.
##
## Every other counter in the game already has an owner — crimes belong to
## CrimeManager, tills to BusinessManager, money to EconomyManager. This one
## exists for the things that belonged to nobody, and it deliberately does not
## duplicate those: the statistics screen reads all four and adds nothing of
## its own. Adding a counter here is a key in COUNTERS plus a call to `add`.

signal counter_changed(key: StringName, value: int)

## This file deliberately names no other system. Counters are pushed in from
## the place the thing happens, never pulled: an item is a Resource, and a
## Resource script that reaches for an autoload which in turn reaches back
## toward items is a compile cycle. When that cycle formed, every .tres in the
## project loaded with default values and two hundred checks failed a long way
## from the cause. Keep this file a leaf.
##
## Grouped only so the statistics screen can print them under headings; the
## store underneath is flat.
const COUNTERS := {
	&"work": [
		[&"shifts_worked", "Shifts worked"],
		[&"shift_income", "Earned in wages"],
		[&"deliveries_made", "Deliveries made"],
	],
	&"living": [
		[&"meals_eaten", "Meals eaten"],
		[&"coffees_drunk", "Coffees drunk"],
		[&"nights_slept", "Nights slept"],
		[&"gym_sessions", "Gym sessions"],
		[&"days_lived", "Days lived"],
	],
	&"travel": [
		[&"kilometres_driven", "Kilometres driven"],
		[&"vehicles_bought", "Vehicles bought"],
	],
}

const GROUP_NAMES := {
	&"work": "Work",
	&"living": "Living",
	&"travel": "Getting about",
}

@export var save_id: StringName = &"life_stats"
## A fresh game starts these at nothing, so a save without them is a clean one.
@export var reset_on_missing_save: bool = true

var _counters: Dictionary = {}
## Fractions of a kilometre not yet worth counting, kept apart so a hundred
## short trips still add up to something.
var _part_km: float = 0.0


func _ready() -> void:
	add_to_group(&"saveable")
	_reset()
	TimeManager.day_passed.connect(_on_day_changed)


func _on_day_changed(_day: int) -> void:
	add(&"days_lived")


## Every key that exists, in the order the screen shows them.
static func keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for group in COUNTERS:
		for entry in COUNTERS[group]:
			out.append(entry[0])
	return out


static func label_for(key: StringName) -> String:
	for group in COUNTERS:
		for entry in COUNTERS[group]:
			if entry[0] == key:
				return String(entry[1])
	return String(key)


func get_counter(key: StringName) -> int:
	return int(_counters.get(key, 0))


func all_counters() -> Dictionary:
	return _counters.duplicate()


## Unknown keys are ignored rather than created, so a typo at a call site
## cannot quietly invent a statistic nothing displays.
func add(key: StringName, amount: int = 1) -> void:
	if not _counters.has(key) or amount == 0:
		return
	_counters[key] = int(_counters[key]) + amount
	counter_changed.emit(key, int(_counters[key]))


## Distance arrives in metres from the vehicle, which is why the remainder is
## carried: rounding each trip down would lose most of a city's driving.
func add_distance(metres: float) -> void:
	if metres <= 0.0:
		return
	_part_km += metres / 1000.0
	var whole := int(floor(_part_km))
	if whole > 0:
		_part_km -= float(whole)
		add(&"kilometres_driven", whole)


func _reset() -> void:
	_counters = {}
	for key in keys():
		_counters[key] = 0
	_part_km = 0.0


func clear() -> void:
	_reset()


func save_state() -> Dictionary:
	return {"counters": _counters.duplicate(), "part_km": _part_km}


func load_state(state: Dictionary) -> void:
	_reset()
	var stored: Dictionary = state.get("counters", {})
	for key in stored:
		# Read through StringName so a save written as plain strings by an
		# older build still lands on the right counter.
		var name := StringName(key)
		if _counters.has(name):
			_counters[name] = int(stored[key])
	_part_km = float(state.get("part_km", 0.0))
