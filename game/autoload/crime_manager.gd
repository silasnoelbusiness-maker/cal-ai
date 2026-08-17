extends Node
## The ledger of what the player has done.
##
## Deliberately only a ledger. It records what happened, where, when, to whom and
## how visibly — and emits a signal. It does not decide consequences: WitnessSystem
## decides whether anyone saw it and WantedManager decides what the police do
## about it. Keeping the three apart is what lets a new crime be added by filing a
## record from one place rather than by teaching every object about police.
##
## Everything a crime is *worth* — how serious, how much heat, how much evidence
## it leaves — lives in the PROFILES table below rather than in the objects that
## file crimes. Tuning the whole game's risk against its reward is editing one
## dictionary.

signal crime_reported(record: Dictionary)
## Emitted when a crime that was recorded unseen is later witnessed.
signal crime_witnessed(record: Dictionary)
## Emitted once a witnessed crime has actually been called in.
signal crime_reported_to_police(record: Dictionary)
## Filed but deliberately kept away from the witness system. See log_incident.
signal incident_logged(record: Dictionary)
signal statistics_changed()

enum CrimeType {
	VEHICLE_THEFT,
	SHOPLIFTING,
	ASSAULT,
	ROBBERY,
	BURGLARY,
	TRESPASSING,
	VEHICULAR_ASSAULT,
	HIT_AND_RUN,
	STORE_ROBBERY,
	CARJACKING,
}

## Why the player did it. Nothing distinguishes these yet — every crime the
## player commits is INTENTIONAL — but the field exists so that a later phase can
## tell a deliberate assault from a car accident without re-cutting the record
## format, and so nothing has to guess retrospectively.
enum Intent { INTENTIONAL, ACCIDENTAL, SELF_DEFENCE }

## One row per crime type.
##
##   severity  1 (petty) to 5 (severe). What the crime *is*.
##   points    what a reported one adds to the wanted meter. What it *costs*.
##   evidence  how identifiable the act is, 1-5. Reserved for CCTV, masks and
##             disguises later; witnesses currently identify the player outright.
##
## severity and points are separate on purpose: a crime can be serious to have on
## the record and cheap to be chased for, or the reverse.
const PROFILES: Dictionary = {
	CrimeType.TRESPASSING: {"severity": 1, "points": 5, "evidence": 1},
	CrimeType.SHOPLIFTING: {"severity": 1, "points": 10, "evidence": 1},
	CrimeType.VEHICLE_THEFT: {"severity": 2, "points": 20, "evidence": 2},
	CrimeType.ASSAULT: {"severity": 3, "points": 25, "evidence": 3},
	CrimeType.VEHICULAR_ASSAULT: {"severity": 3, "points": 25, "evidence": 3},
	CrimeType.BURGLARY: {"severity": 3, "points": 30, "evidence": 2},
	CrimeType.HIT_AND_RUN: {"severity": 3, "points": 30, "evidence": 2},
	CrimeType.CARJACKING: {"severity": 3, "points": 35, "evidence": 3},
	CrimeType.STORE_ROBBERY: {"severity": 4, "points": 40, "evidence": 4},
	CrimeType.ROBBERY: {"severity": 4, "points": 40, "evidence": 3},
}

## Records kept in memory, so a long session stays flat.
const MAX_HISTORY := 100

## Counters a future statistics screen will read. Kept as a flat dictionary so
## adding one is a key here plus a call to `_tally`, with no save migration.
const STATISTIC_KEYS: Array[StringName] = [
	&"vehicles_stolen",
	&"cars_carjacked",
	&"items_shoplifted",
	&"stores_robbed",
	&"assaults",
	&"times_busted",
	&"times_escaped",
	&"highest_wanted_level",
	&"illegal_income",
	&"fines_paid",
]

@export var save_id: StringName = &"crime_manager"

var _history: Array[Dictionary] = []
var _next_id: int = 1
var _statistics: Dictionary = {}


func _ready() -> void:
	_reset_statistics()
	add_to_group(&"saveable")


# --- Filing --------------------------------------------------------------

## Files a crime and puts it in front of the witness system.
##
## `witnessed` stays false here: whether anyone saw it is WitnessSystem's job,
## and a crime nobody saw stays unreported forever, which is what makes an unseen
## theft free.
func report_crime(
	type: CrimeType,
	position: Vector3,
	perpetrator: Node = null,
	target: Node = null,
	witnessed: bool = false,
	extras: Dictionary = {}
) -> Dictionary:
	var record := _make_record(type, position, perpetrator, target, witnessed, extras)
	_remember(record)
	_tally_crime(record)

	crime_reported.emit(record)
	# Deliberately not "CRIME REPORTED": at this point the crime has happened,
	# but nobody has necessarily seen it.
	GameManager.notify(_describe(record), GameManager.Tone.BAD)
	return record


## Files something that happened without putting it in front of the witness
## system. Hit-and-runs need to be on the record — for the statistics, and so a
## later phase can escalate them — but must not yet summon a police response, and
## `crime_reported` is exactly the signal WitnessSystem listens to. Same ledger,
## quieter door.
func log_incident(
	type: CrimeType,
	position: Vector3,
	perpetrator: Node = null,
	target: Node = null,
	extras: Dictionary = {}
) -> Dictionary:
	var record := _make_record(type, position, perpetrator, target, false, extras)
	record["incident_only"] = true
	_remember(record)
	_tally_crime(record)
	incident_logged.emit(record)
	return record


## Called by WitnessSystem when somebody has actually seen a crime. Seeing is not
## the same as reporting: a civilian stares first, and only then calls it in.
func mark_witnessed(record: Dictionary, witness: Node = null) -> void:
	if record.is_empty() or record.get("witnessed", false):
		return
	record["witnessed"] = true
	record["reporting_witness"] = witness
	# A witness who saw the act saw who did it. Masks and distance will make this
	# a real decision later; for now seeing is identifying.
	record["suspect_identified"] = true
	crime_witnessed.emit(record)


## The crime has been called in. This is the point the wanted system reacts to.
func mark_reported(record: Dictionary) -> void:
	if record.is_empty() or record.get("reported", false):
		return
	record["reported"] = true
	crime_reported_to_police.emit(record)
	GameManager.notify("CRIME REPORTED\n%s" % record.get("type_name", "CRIME"), GameManager.Tone.BAD)


# --- Queries -------------------------------------------------------------

func get_history() -> Array[Dictionary]:
	return _history.duplicate()


func get_last_crime() -> Dictionary:
	return _history.back() if not _history.is_empty() else {}


func count_of(type: CrimeType) -> int:
	var total := 0
	for record in _history:
		if record["type"] == type:
			total += 1
	return total


func get_incidents_of(type: CrimeType) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for record in _history:
		if record["type"] == type and record.get("incident_only", false):
			found.append(record)
	return found


func get_crimes_of(type: CrimeType) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for record in _history:
		if record["type"] == type and not record.get("incident_only", false):
			found.append(record)
	return found


func clear_history() -> void:
	_history.clear()


static func get_type_name(type: CrimeType) -> String:
	return String(CrimeType.keys()[type]).replace("_", " ")


static func severity_of(type: CrimeType) -> int:
	return int(_profile(type).get("severity", 1))


static func points_for(type: CrimeType) -> int:
	return int(_profile(type).get("points", 10))


static func evidence_for(type: CrimeType) -> int:
	return int(_profile(type).get("evidence", 1))


# --- Statistics ----------------------------------------------------------

func get_statistics() -> Dictionary:
	return _statistics.duplicate()


func get_statistic(key: StringName) -> int:
	return int(_statistics.get(key, 0))


## Adds to a counter. `raise_to` semantics for anything that is a high-water mark
## rather than a running total.
func add_statistic(key: StringName, amount: int = 1) -> void:
	if not _statistics.has(key):
		return
	_statistics[key] = int(_statistics[key]) + amount
	statistics_changed.emit()


func raise_statistic(key: StringName, value: int) -> void:
	if not _statistics.has(key):
		return
	if value <= int(_statistics[key]):
		return
	_statistics[key] = value
	statistics_changed.emit()


func reset_statistics() -> void:
	_reset_statistics()
	statistics_changed.emit()


# --- Internals -----------------------------------------------------------

func _reset_statistics() -> void:
	_statistics = {}
	for key in STATISTIC_KEYS:
		_statistics[key] = 0


## Every filed crime bumps its own counter. Kept here rather than at each call
## site so a crime can never be filed without being counted.
func _tally_crime(record: Dictionary) -> void:
	match int(record["type"]):
		CrimeType.VEHICLE_THEFT:
			add_statistic(&"vehicles_stolen")
		CrimeType.CARJACKING:
			add_statistic(&"cars_carjacked")
		CrimeType.SHOPLIFTING:
			add_statistic(&"items_shoplifted", maxi(int(record.get("quantity", 1)), 1))
		CrimeType.STORE_ROBBERY:
			add_statistic(&"stores_robbed")
		CrimeType.ASSAULT, CrimeType.VEHICULAR_ASSAULT:
			add_statistic(&"assaults")
	var reward := int(record.get("reward_value", 0))
	if reward > 0:
		add_statistic(&"illegal_income", reward)


func _remember(record: Dictionary) -> void:
	_history.append(record)
	if _history.size() > MAX_HISTORY:
		_history.remove_at(0)


func _make_record(
	type: CrimeType,
	position: Vector3,
	perpetrator: Node,
	target: Node,
	witnessed: bool,
	extras: Dictionary
) -> Dictionary:
	var record := {
		"id": _next_id,
		"type": type,
		"type_name": get_type_name(type),
		"severity": severity_of(type),
		"wanted_points": points_for(type),
		"evidence_level": evidence_for(type),
		"position": position,
		"day": TimeManager.day_index,
		"time": TimeManager.get_time_string(),
		"total_minutes": TimeManager.total_minutes,
		"perpetrator": perpetrator,
		"target": target,
		"victim": null,
		"intent": Intent.INTENTIONAL,
		"reward_value": 0,
		"witnessed": witnessed,
		# Filled in by WitnessSystem.
		"reporting_witness": null,
		"reported": false,
		"suspect_identified": false,
		"incident_only": false,
	}
	# Callers override the parts that are theirs to know: what it was worth, who
	# it was done to, how many. Overriding rather than adding keeps the record
	# shape fixed whatever files it.
	for key in extras:
		record[key] = extras[key]
	_next_id += 1
	return record


static func _profile(type: CrimeType) -> Dictionary:
	return PROFILES.get(type, {})


func _describe(record: Dictionary) -> String:
	var headline: String = record["type_name"]
	if record["type"] == CrimeType.VEHICLE_THEFT or record["type"] == CrimeType.CARJACKING:
		var target = record.get("target")
		if target != null and target.has_method("get_display_name"):
			return "%s\n%s" % [headline, target.call("get_display_name")]
	var reward := int(record.get("reward_value", 0))
	if reward > 0:
		return "%s\n+$%d" % [headline, reward]
	return headline


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	# Only the statistics persist. The history is a session log, and restoring a
	# list of past crimes would restore nothing the player can see.
	var stored := {}
	for key in _statistics:
		stored[String(key)] = _statistics[key]
	return {"statistics": stored}


func load_state(state: Dictionary) -> void:
	var stored: Dictionary = state.get("statistics", {})
	_reset_statistics()
	for key in STATISTIC_KEYS:
		if stored.has(String(key)):
			_statistics[key] = int(stored[String(key)])
	statistics_changed.emit()
