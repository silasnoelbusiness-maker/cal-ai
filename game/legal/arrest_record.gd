class_name ArrestRecord
extends RefCounted

## One arrest, as the record remembers it.
##
## §6 asks for a record per arrest and §7 that a single pursuit not become fifty
## of them. So this is the *incident*: everything the player was taken in for at
## once, aggregated to one entry with one overall severity — the worst thing in
## it — with the offences kept alongside for the record screen to read out.

var arrest_id: StringName = &""
var day: int = 0
var minute_of_day: int = 0
## Star level at the moment of the arrest.
var wanted_level: int = 0
## Display names of the offences rolled into this incident, worst first.
var offences: PackedStringArray = PackedStringArray()
## The worst band in `offences`, which is what everything legal keys off.
var severity: CrimeData.Severity = CrimeData.Severity.MINOR
## What was actually taken at the roadside.
var fine_charged: int = 0
var fine_paid: int = 0
var release_cost: int = 0
var goods_confiscated: int = 0
## Whether the player was driving something that was not theirs.
var stolen_vehicle_recovered: bool = false
## Set when this arrest opened a case, so the record can link the two.
var case_id: StringName = &""
## Whether anybody could put a name to the person arrested. §45 — a company only
## suffers for an incident the city can pin on its owner.
var publicly_identified: bool = false


static func make(
	id: StringName, day_index: int, minute: int, level: int,
	names: PackedStringArray, band: CrimeData.Severity
) -> ArrestRecord:
	var record := ArrestRecord.new()
	record.arrest_id = id
	record.day = day_index
	record.minute_of_day = minute
	record.wanted_level = level
	record.offences = names
	record.severity = band
	return record


func severity_name() -> String:
	return LegalSeverity.name_of(severity)


func has_case() -> bool:
	return case_id != &""


## One line for the record screen: what it was, in the player's words.
func headline() -> String:
	if offences.is_empty():
		return "Arrest"
	if offences.size() == 1:
		return offences[0]
	return "%s and %d more" % [offences[0], offences.size() - 1]


func stars() -> String:
	return "★".repeat(wanted_level)


func to_dict() -> Dictionary:
	return {
		"id": String(arrest_id),
		"day": day,
		"minute": minute_of_day,
		"level": wanted_level,
		"offences": offences,
		"severity": int(severity),
		"fine_charged": fine_charged,
		"fine_paid": fine_paid,
		"release_cost": release_cost,
		"goods": goods_confiscated,
		"vehicle": stolen_vehicle_recovered,
		"case": String(case_id),
		"identified": publicly_identified,
	}


static func from_dict(state: Dictionary) -> ArrestRecord:
	var record := ArrestRecord.new()
	record.arrest_id = StringName(state.get("id", ""))
	record.day = int(state.get("day", 0))
	record.minute_of_day = int(state.get("minute", 0))
	record.wanted_level = int(state.get("level", 0))
	var names: Array = state.get("offences", [])
	record.offences = PackedStringArray(names)
	record.severity = int(state.get("severity", 0)) as CrimeData.Severity
	record.fine_charged = int(state.get("fine_charged", 0))
	record.fine_paid = int(state.get("fine_paid", 0))
	record.release_cost = int(state.get("release_cost", 0))
	record.goods_confiscated = int(state.get("goods", 0))
	record.stolen_vehicle_recovered = bool(state.get("vehicle", false))
	record.case_id = StringName(state.get("case", ""))
	record.publicly_identified = bool(state.get("identified", false))
	return record
