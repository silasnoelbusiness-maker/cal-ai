class_name LegalCase
extends RefCounted

## A case opened by a serious arrest, and the court date that settles it.
##
## §19 and §23. This is a game object, not a legal one: a date, a band of
## expected consequence, and exactly one outcome. §104 is the reason the outcome
## is a stored field rather than something recomputed — a case must resolve at
## most once, whatever the player does with saves.

enum Status { OPEN, RESOLVED, MISSED, DISMISSED }
enum Outcome { NONE, DISMISSED, REDUCED, FINE, HEAVY_FINE }

const STATUS_NAMES := {
	Status.OPEN: "Awaiting court",
	Status.RESOLVED: "Resolved",
	Status.MISSED: "Court missed",
	Status.DISMISSED: "Dismissed",
}

const OUTCOME_NAMES := {
	Outcome.NONE: "Not yet heard",
	Outcome.DISMISSED: "Dismissed",
	Outcome.REDUCED: "Reduced",
	Outcome.FINE: "Fine and record",
	Outcome.HEAVY_FINE: "Heavy fine and record",
}

var case_id: StringName = &""
var arrest_id: StringName = &""
var title: String = "Case"
var severity: CrimeData.Severity = CrimeData.Severity.SERIOUS
## Day index the hearing falls on, and the hour it is listed for.
var court_day: int = 0
var court_hour: int = 12
var status: Status = Status.OPEN
var outcome: Outcome = Outcome.NONE
## What the hearing actually cost, once heard.
var fine_applied: int = 0
var costs_applied: int = 0
## Whether the player turned up. §24 — one of the things that decides how the
## hearing goes.
var attended: bool = false
## Which legal service was retained when the case was heard.
var counsel_id: StringName = &"public_counsel"
## Set once the reminder has been shown, so §130 happens once rather than every
## minute. Same for the missed-court notice.
var reminder_shown: bool = false
var missed_notice_shown: bool = false


static func make(
	id: StringName, arrest: StringName, name: String,
	band: CrimeData.Severity, day: int, hour: int
) -> LegalCase:
	var case := LegalCase.new()
	case.case_id = id
	case.arrest_id = arrest
	case.title = name
	case.severity = band
	case.court_day = day
	case.court_hour = hour
	return case


func is_open() -> bool:
	return status == Status.OPEN


## Whether the hearing has already happened, however it went. The guard that
## makes §104 true: nothing may apply an outcome to a case this returns true for.
func is_settled() -> bool:
	return status == Status.RESOLVED or status == Status.DISMISSED


func status_name() -> String:
	return String(STATUS_NAMES.get(status, "Awaiting court"))


func outcome_name() -> String:
	return String(OUTCOME_NAMES.get(outcome, "Not yet heard"))


func severity_name() -> String:
	return LegalSeverity.name_of(severity)


func days_until(today: int) -> int:
	return court_day - today


## Whether the hearing is due — today, at or past the listed hour.
func is_due(today: int, hour: int) -> bool:
	if not is_open():
		return false
	if today > court_day:
		return true
	return today == court_day and hour >= court_hour


## Whether the player has let the date pass entirely.
func is_overdue(today: int) -> bool:
	return is_open() and today > court_day


func court_time_label() -> String:
	return "%02d:00" % court_hour


func to_dict() -> Dictionary:
	return {
		"id": String(case_id),
		"arrest": String(arrest_id),
		"title": title,
		"severity": int(severity),
		"day": court_day,
		"hour": court_hour,
		"status": int(status),
		"outcome": int(outcome),
		"fine": fine_applied,
		"costs": costs_applied,
		"attended": attended,
		"counsel": String(counsel_id),
		"reminded": reminder_shown,
		"missed_notice": missed_notice_shown,
	}


static func from_dict(state: Dictionary) -> LegalCase:
	var case := LegalCase.new()
	case.case_id = StringName(state.get("id", ""))
	case.arrest_id = StringName(state.get("arrest", ""))
	case.title = String(state.get("title", "Case"))
	case.severity = int(state.get("severity", 2)) as CrimeData.Severity
	case.court_day = int(state.get("day", 0))
	case.court_hour = int(state.get("hour", 12))
	case.status = int(state.get("status", 0)) as Status
	case.outcome = int(state.get("outcome", 0)) as Outcome
	case.fine_applied = int(state.get("fine", 0))
	case.costs_applied = int(state.get("costs", 0))
	case.attended = bool(state.get("attended", false))
	case.counsel_id = StringName(state.get("counsel", "public_counsel"))
	case.reminder_shown = bool(state.get("reminded", false))
	case.missed_notice_shown = bool(state.get("missed_notice", false))
	return case
