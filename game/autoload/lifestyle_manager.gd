extends Node
## How well the player is visibly living, 0-100.
##
## Explicitly not net worth. Net worth is what the books say; lifestyle is what
## the life looks like. A player with $400,000 in the bank, a starter studio and
## the same compact they bought on day three is rich and lives modestly, and the
## game should say both — that gap is the whole reason this exists rather than
## being another read-out of the same number.
##
## Crime never raises it. Money earned any way spends the same, but the score
## measures possessions and where you live, not how you came by them, and
## wiring it to the crime statistics would turn it into a reward for offending.

signal score_changed(score: int)
signal milestone_reached(id: StringName, label: String)

## What each part is worth, out of 100. Configurable on purpose: the balance
## between "where you live" and "what you drive" is a design decision, and it is
## one line here rather than scattered through the sums.
const WEIGHTS := {
	&"home": 40.0,
	&"vehicle": 35.0,
	&"comfort": 20.0,
	&"business": 5.0,
}

## Score at or above which each tier applies, richest first.
const TIERS: Array = [
	[85, "ELITE"],
	[68, "WEALTHY"],
	[50, "SUCCESSFUL"],
	[32, "COMFORTABLE"],
	[15, "MODEST"],
	[0, "STRUGGLING"],
]

## Milestones worth a word when they happen. Each fires once per game.
const MILESTONES: Array = [
	[&"first_car", "FIRST VEHICLE"],
	[&"three_cars", "THREE VEHICLES OWNED"],
	[&"better_home", "MOVED UP IN THE WORLD"],
	[&"premium_vehicle", "PREMIUM VEHICLE OWNED"],
	[&"lifestyle_50", "LIFESTYLE 50"],
]

## Prestige at or above which a car counts as premium.
const PREMIUM_PRESTIGE := 60

var _score: int = 0
var _reached: Dictionary = {}
var _timer: float = 0.0


## What the save file calls this.
var save_id: StringName = &"lifestyle_manager"


func _ready() -> void:
	add_to_group(&"saveable")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	VehicleRegistry.fleet_changed.connect(_on_world_changed)
	HomeManager.furniture_changed.connect(_on_world_changed)


func _process(delta: float) -> void:
	# Recalculated on a slow tick as well as on the obvious signals, because
	# some of the inputs — which residence is home, how a business is doing —
	# change without anything shouting about it.
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 2.0
	refresh()


func _on_world_changed() -> void:
	refresh()


# --- The score -----------------------------------------------------------

func score() -> int:
	return _score


func tier_name() -> String:
	for entry in TIERS:
		if _score >= int(entry[0]):
			return String(entry[1])
	return "STRUGGLING"


## Each component as its own 0-100 figure, for the profile screen. The screen
## shows the parts as well as the total so the player can see what to spend on
## next, which is the only thing the score is really for.
func breakdown() -> Dictionary:
	return {
		"home": home_score(),
		"vehicle": vehicle_score(),
		"comfort": comfort_score(),
		"business": business_score(),
	}


func refresh() -> void:
	var parts := breakdown()
	var total := 0.0
	for key: StringName in WEIGHTS:
		total += float(parts.get(key, 0)) / 100.0 * float(WEIGHTS[key])
	var rounded := clampi(roundi(total), 0, 100)
	if rounded != _score:
		_score = rounded
		score_changed.emit(_score)
	_check_milestones()


## Where the player lives, from the residence's own lifestyle rating.
func home_score() -> int:
	var home := PropertyManager.current_home()
	if home == null:
		return 0
	return clampi(home.lifestyle_value, 0, 100)


## What is on the drive. The best car counts most — nobody is impressed twice by
## the same garage — with a small credit for having more than one.
func vehicle_score() -> int:
	var fleet := VehicleRegistry.get_fleet()
	if fleet.is_empty():
		return 0
	var best := 0
	for record in fleet:
		best = maxi(best, VehicleCatalogue.prestige(record.model_id))
	var collection := mini(fleet.size() - 1, 3) * 5
	return clampi(best + collection, 0, 100)


## How the home is furnished, capped per category so buying the same thing over
## and over cannot carry it.
func comfort_score() -> int:
	var home := PropertyManager.current_home()
	if home == null:
		return 0
	var furniture := HomeManager.furniture_lifestyle(home.residence_id)
	# Sixty points of well-chosen furniture is a fully furnished flat.
	return clampi(roundi(float(furniture) / 60.0 * 100.0), 0, 100)


## A small nod to the businesses, deliberately the smallest weight there is.
## Running a company is its own reward on the finance screen; this is about the
## life it pays for.
func business_score() -> int:
	var value := BusinessManager.total_business_value()
	return clampi(roundi(float(value) / 150000.0 * 100.0), 0, 100)


# --- Milestones ----------------------------------------------------------

func has_reached(id: StringName) -> bool:
	return bool(_reached.get(id, false))


func _check_milestones() -> void:
	var fleet := VehicleRegistry.get_fleet()
	_maybe(&"first_car", fleet.size() >= 1)
	_maybe(&"three_cars", fleet.size() >= 3)
	_maybe(&"premium_vehicle", VehicleRegistry.best_prestige() >= PREMIUM_PRESTIGE)
	_maybe(&"lifestyle_50", _score >= 50)
	var home := PropertyManager.current_home()
	_maybe(&"better_home", home != null and home.lifestyle_value >= 45)


func _maybe(id: StringName, reached: bool) -> void:
	if not reached or has_reached(id):
		return
	_reached[id] = true
	var label := String(id).to_upper()
	for entry in MILESTONES:
		if entry[0] == id:
			label = String(entry[1])
	GameManager.notify("MILESTONE\n%s" % label, GameManager.Tone.GOOD)
	milestone_reached.emit(id, label)


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var reached: Array = []
	for id: StringName in _reached:
		if _reached[id]:
			reached.append(String(id))
	return {"reached": reached}


func load_state(state: Dictionary) -> void:
	_reached.clear()
	for id in state.get("reached", []):
		_reached[StringName(id)] = true
	refresh()


func clear() -> void:
	_reached.clear()
	_score = 0
