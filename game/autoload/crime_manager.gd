extends Node
## Records crimes the player commits.
##
## Deliberately only a ledger for now. It records what happened, where, when and
## to whom, and emits a signal — it does not decide consequences. Phase E hangs
## witness checks off `crime_reported` and drives the wanted level from there;
## nothing in this file needs to change for that, because the record already
## carries the position, timestamp and `witnessed` flag the witness system will
## fill in.

signal crime_reported(record: Dictionary)
## Emitted when a crime that was recorded unseen is later witnessed. Phase E
## will call `mark_witnessed()`; nothing does yet.
signal crime_witnessed(record: Dictionary)
## Emitted once a witnessed crime has actually been called in.
signal crime_reported_to_police(record: Dictionary)

enum CrimeType { VEHICLE_THEFT, SHOPLIFTING, ASSAULT, ROBBERY, BURGLARY, TRESPASSING }

## How serious each crime is, 1 (petty) to 5 (severe). The wanted system will
## read these rather than re-deciding severity per crime site.
const SEVERITY: Dictionary = {
	CrimeType.VEHICLE_THEFT: 2,
	CrimeType.SHOPLIFTING: 1,
	CrimeType.TRESPASSING: 1,
	CrimeType.ASSAULT: 3,
	CrimeType.BURGLARY: 3,
	CrimeType.ROBBERY: 4,
}

## Wanted stars a *reported* crime is worth. Separate from severity so the two
## can be tuned independently — a crime can be serious to log and cheap to be
## chased for, or the reverse.
const WANTED_VALUE: Dictionary = {
	CrimeType.VEHICLE_THEFT: 1,
	CrimeType.SHOPLIFTING: 1,
	CrimeType.TRESPASSING: 1,
	CrimeType.ASSAULT: 2,
	CrimeType.BURGLARY: 2,
	CrimeType.ROBBERY: 3,
}

## Records kept in memory, so a long session stays flat.
const MAX_HISTORY := 100

var _history: Array[Dictionary] = []
var _next_id: int = 1


## Files a crime. `witnessed` stays false for now — Phase D has no witnesses,
## and the brief is explicit that this must not trigger a police response yet.
func report_crime(
	type: CrimeType,
	position: Vector3,
	perpetrator: Node = null,
	target: Node = null,
	witnessed: bool = false
) -> Dictionary:
	var record := {
		"id": _next_id,
		"type": type,
		"type_name": get_type_name(type),
		"severity": int(SEVERITY.get(type, 1)),
		"position": position,
		"day": TimeManager.day_index,
		"time": TimeManager.get_time_string(),
		"total_minutes": TimeManager.total_minutes,
		"perpetrator": perpetrator,
		"target": target,
		"witnessed": witnessed,
		# Filled in by WitnessSystem. A crime nobody saw stays unreported
		# forever, which is what makes an unseen theft free.
		"reporting_witness": null,
		"reported": false,
		"wanted_value": int(WANTED_VALUE.get(type, 1)),
	}
	_next_id += 1

	_history.append(record)
	if _history.size() > MAX_HISTORY:
		_history.remove_at(0)

	crime_reported.emit(record)
	# Deliberately not "CRIME REPORTED": at this point the crime has happened,
	# but nobody has necessarily seen it.
	GameManager.notify(_describe(record), GameManager.Tone.BAD)
	return record


## Called by WitnessSystem when somebody has actually seen a crime. Seeing is
## not the same as reporting: a civilian stares first, and only then calls it in.
func mark_witnessed(record: Dictionary, witness: Node = null) -> void:
	if record.is_empty() or record.get("witnessed", false):
		return
	record["witnessed"] = true
	record["reporting_witness"] = witness
	crime_witnessed.emit(record)


## The crime has been called in. This is the point the wanted system reacts to.
func mark_reported(record: Dictionary) -> void:
	if record.is_empty() or record.get("reported", false):
		return
	record["reported"] = true
	crime_reported_to_police.emit(record)
	GameManager.notify("CRIME REPORTED\n%s" % record.get("type_name", "CRIME"), GameManager.Tone.BAD)


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


func clear_history() -> void:
	_history.clear()


static func get_type_name(type: CrimeType) -> String:
	return String(CrimeType.keys()[type]).replace("_", " ")


func _describe(record: Dictionary) -> String:
	var headline: String = record["type_name"]
	if record["type"] == CrimeType.VEHICLE_THEFT:
		var target = record.get("target")
		if target != null and target.has_method("get_display_name"):
			return "VEHICLE THEFT\n%s" % target.call("get_display_name")
	return headline
