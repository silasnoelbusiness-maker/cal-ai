class_name ShiftSlot
extends RefCounted
## One block of somebody's week.
##
## A shift is a weekday, a pair of clock hours, the job being done and the
## branch it is done at. Phase H had one of these per employee and never said
## so; a company with a restaurant that opens for lunch and dinner needs
## several, at different places, doing different jobs.
##
## Deliberately not a Resource: shifts are made at runtime and saved as plain
## dictionaries, and there is nothing to author in the editor.

## A shift worked every day of the week rather than on one named day.
const EVERY_DAY := -1
const HOURS_PER_WEEK := 168

## 0 is Monday, matching TimeManager.
var weekday: int = EVERY_DAY
var start_hour: int = 9
var end_hour: int = 17
## EmployeeData.Role, held as a plain int so this class need not know about
## employees at all.
var role: int = 0
## Which branch. Empty means whichever business the employee belongs to, which
## is what every shift written before transfers existed meant.
var business_id: StringName = &""


static func make(
	start_hour: int, end_hour: int, role: int,
	weekday: int = EVERY_DAY, business_id: StringName = &""
) -> ShiftSlot:
	var slot := ShiftSlot.new()
	slot.start_hour = clampi(start_hour, 0, 23)
	slot.end_hour = clampi(end_hour, 0, 24)
	slot.role = role
	slot.weekday = weekday
	slot.business_id = business_id
	return slot


## Whether the times make any sense. A shift that starts and ends at the same
## hour is nobody working, not a full day.
func is_valid() -> bool:
	if start_hour < 0 or start_hour > 23:
		return false
	if end_hour < 0 or end_hour > 24:
		return false
	if weekday < EVERY_DAY or weekday > 6:
		return false
	return start_hour != end_hour


func length_hours() -> float:
	if end_hour == start_hour:
		return 0.0
	if end_hour > start_hour:
		return float(end_hour - start_hour)
	return float(24 - start_hour + end_hour)


## Whether this shift covers a given hour on a given weekday. Pass -1 as the
## weekday to ask "on any day", which is what the hourly simulation wants when
## it does not care which day it is.
func covers(hour: int, on_weekday: int = EVERY_DAY) -> bool:
	if not _covers_hour(hour):
		return false
	if weekday == EVERY_DAY or on_weekday == EVERY_DAY:
		return true
	# A shift that runs past midnight is still Friday's shift at one in the
	# morning on Saturday, which is exactly how a nightclub is staffed.
	if end_hour > start_hour or hour >= start_hour:
		return on_weekday == weekday
	return on_weekday == posmod(weekday + 1, 7)


func _covers_hour(hour: int) -> bool:
	if end_hour == start_hour:
		return false
	if end_hour > start_hour:
		return hour >= start_hour and hour < end_hour
	return hour >= start_hour or hour < end_hour


## Every hour of the week this shift occupies, as indices 0-167 with Monday
## midnight at zero. Overlap between two shifts is then just a shared index,
## which is far easier to get right than comparing clock arithmetic.
func week_hours() -> PackedInt32Array:
	var hours := PackedInt32Array()
	var days := range(7) if weekday == EVERY_DAY else [weekday]
	var length := int(ceilf(length_hours()))
	for day: int in days:
		for offset in length:
			var absolute := day * 24 + start_hour + offset
			hours.append(posmod(absolute, HOURS_PER_WEEK))
	return hours


## Two shifts clash when they want the same person in the same hour.
func overlaps(other: ShiftSlot) -> bool:
	if other == null:
		return false
	var mine := week_hours()
	var theirs := {}
	for value in other.week_hours():
		theirs[value] = true
	for value in mine:
		if theirs.has(value):
			return true
	return false


func day_name() -> String:
	if weekday == EVERY_DAY:
		return "EVERY DAY"
	return TimeManager.DAY_NAMES[clampi(weekday, 0, 6)]


func time_text() -> String:
	return "%02d:00-%02d:00" % [start_hour, end_hour]


func to_dict() -> Dictionary:
	return {
		"weekday": weekday, "start": start_hour, "end": end_hour,
		"role": role, "business": String(business_id),
	}


static func from_dict(state: Dictionary) -> ShiftSlot:
	var slot := ShiftSlot.new()
	slot.weekday = int(state.get("weekday", EVERY_DAY))
	slot.start_hour = int(state.get("start", 9))
	slot.end_hour = int(state.get("end", 17))
	slot.role = int(state.get("role", 0))
	slot.business_id = StringName(state.get("business", ""))
	return slot


func duplicate_slot() -> ShiftSlot:
	return from_dict(to_dict())
