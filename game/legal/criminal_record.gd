class_name CriminalRecord
extends RefCounted

## What the game remembers about the player, for good.
##
## §2 is the whole point of Phase R: the difference between one bad decision and
## a career. That difference is `pressure()` — a running weight built from the
## arrests, in which serious history keeps its value for a long time and petty
## history fades (§12, §13). The tier the rest of the game reads is a band of
## that number.
##
## §3 governs everything downstream: a record creates friction, never
## demolition. Nothing here, and nothing reading it, deletes a business, a
## property or a vehicle.

enum Tier { CLEAN, MINOR, KNOWN, SERIOUS, REPEAT, HIGH_RISK }

const TIER_NAMES := {
	Tier.CLEAN: "Clean",
	Tier.MINOR: "Minor record",
	Tier.KNOWN: "Known offender",
	Tier.SERIOUS: "Serious record",
	Tier.REPEAT: "Repeat offender",
	Tier.HIGH_RISK: "High-risk record",
}

## Pressure at which each tier begins. Deliberately far apart at the bottom: a
## first shoplifting is worth 1 and a first robbery 14, so one silly evening
## cannot reach "known offender" and one serious night can.
const TIER_THRESHOLDS := [0, 3, 12, 30, 60, 100]

## How much of an old incident's weight survives once it is past its full-value
## window. Never zero — §13 says history fades, not that it is erased.
const RESIDUAL_FRACTION := 0.3

## Extra weight per repeat within a band. §35 — moderate on purpose; a second
## shoplifting must not be catastrophic.
const REPEAT_STEP := 0.35
const REPEAT_CAP := 2.0

## What ignoring a hearing adds. Big enough to notice, small enough that it is
## not a tier on its own.
const MISSED_COURT_WEIGHT := 6.0

var arrests: Array[ArrestRecord] = []
var cases: Array[LegalCase] = []
var total_fines_paid: int = 0
var total_legal_costs: int = 0
var missed_court_events: int = 0


func arrest_count() -> int:
	return arrests.size()


func highest_severity() -> CrimeData.Severity:
	var worst := CrimeData.Severity.MINOR
	for record in arrests:
		if record.severity > worst:
			worst = record.severity
	return worst


func case_by_id(id: StringName) -> LegalCase:
	for case in cases:
		if case.case_id == id:
			return case
	return null


func arrest_by_id(id: StringName) -> ArrestRecord:
	for record in arrests:
		if record.arrest_id == id:
			return record
	return null


func open_cases() -> Array[LegalCase]:
	var found: Array[LegalCase] = []
	for case in cases:
		if case.is_open():
			found.append(case)
	return found


## Cases the player let the date pass on. §26 — an outstanding legal matter is a
## thing other systems are allowed to notice.
func overdue_cases(today: int) -> Array[LegalCase]:
	var found: Array[LegalCase] = []
	for case in cases:
		if case.is_overdue(today):
			found.append(case)
	return found


func has_outstanding_matter(today: int) -> bool:
	return not overdue_cases(today).is_empty()


## The next hearing, or null. The HUD, the map and the legal screen all read
## this, so all three agree about what "next" means.
func next_case(today: int) -> LegalCase:
	var soonest: LegalCase = null
	for case in cases:
		if not case.is_open() or case.court_day < today:
			continue
		if soonest == null or case.court_day < soonest.court_day:
			soonest = case
		elif case.court_day == soonest.court_day and case.court_hour < soonest.court_hour:
			soonest = case
	return soonest


## The running weight of everything on the record, as of today.
##
## Each arrest contributes its severity weight, aged: full value inside its
## window, a residual fraction after it. Repeats within a band add a little on
## top of each later incident, which is how §35 gets "doing it again matters"
## without a second table of rules.
func pressure(today: int) -> float:
	var total := 0.0
	var seen_in_band := {}
	for record in arrests:
		var weight := float(LegalSeverity.weight_of(record.severity))
		var age := maxi(today - record.day, 0)
		if age > LegalSeverity.full_days(record.severity):
			weight *= RESIDUAL_FRACTION
		var band := int(record.severity)
		var repeats := int(seen_in_band.get(band, 0))
		weight *= minf(1.0 + REPEAT_STEP * float(repeats), REPEAT_CAP)
		seen_in_band[band] = repeats + 1
		total += weight
	total += float(missed_court_events) * MISSED_COURT_WEIGHT
	return total


func tier(today: int) -> Tier:
	var value := pressure(today)
	var reached := Tier.CLEAN
	for candidate in range(TIER_THRESHOLDS.size()):
		if value >= float(TIER_THRESHOLDS[candidate]):
			reached = candidate as Tier
	return reached


static func tier_name(value: Tier) -> String:
	return String(TIER_NAMES.get(value, "Clean"))


## How many arrests in this band, ever. What "repeat offence" means to the
## screens and to the tests.
func count_of_severity(band: CrimeData.Severity) -> int:
	var found := 0
	for record in arrests:
		if record.severity == band:
			found += 1
	return found


## Arrests in the last `days` days. The "recent" half of §12 — somebody who went
## straight a year ago is not the same as somebody taken in yesterday, even at
## the same lifetime total.
func recent_arrests(today: int, days: int = 30) -> int:
	var found := 0
	for record in arrests:
		if today - record.day <= days:
			found += 1
	return found


func to_dict() -> Dictionary:
	var arrest_states: Array = []
	for record in arrests:
		arrest_states.append(record.to_dict())
	var case_states: Array = []
	for case in cases:
		case_states.append(case.to_dict())
	return {
		"arrests": arrest_states,
		"cases": case_states,
		"fines": total_fines_paid,
		"costs": total_legal_costs,
		"missed": missed_court_events,
	}


static func from_dict(state: Dictionary) -> CriminalRecord:
	var record := CriminalRecord.new()
	for entry in state.get("arrests", []):
		if entry is Dictionary:
			record.arrests.append(ArrestRecord.from_dict(entry))
	for entry in state.get("cases", []):
		if entry is Dictionary:
			record.cases.append(LegalCase.from_dict(entry))
	record.total_fines_paid = int(state.get("fines", 0))
	record.total_legal_costs = int(state.get("costs", 0))
	record.missed_court_events = int(state.get("missed", 0))
	return record
