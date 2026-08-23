extends Node

## Why the streets look the way they do at a given hour.
##
## Autoload `RoutineManager`. §4 asks for a lightweight architecture and warns
## against giving every civilian a life simulation ticking every frame, so this
## does not own any people. It owns the *shape* of the population: which mix of
## archetypes belongs in which district at this hour, and how many of them
## should be visible.
##
## The people themselves are the pedestrians the districts already build. Each
## one is handed a RoutineSchedule and asks this, when it needs somewhere to go,
## where somebody like them would be. That is the whole integration: no second
## population (§15), no parallel crowd fighting the existing one.
##
## §12's far simulation falls out of the same design. A pedestrian nobody is
## near stops moving — Pedestrian already does that — and when the player comes
## back it asks for its current activity and walks to wherever that is now. The
## city was never simulating those walks; it just knows where people ought to be.

signal density_changed(district_id: StringName, target: int)

## Visible pedestrians a district aims for, by hour band. §145 — a budget, not
## an unlimited spawn. The peaks are lunch and the evening in Central and the
## early shift in Harbour Row, which is §16-§19 expressed as numbers.
const DENSITY_BY_HOUR := {
	&"harbour_row": [
		# 0  1  2  3  4  5  6  7  8  9 10 11
		 3, 2, 2, 2, 3, 7,11,14,14,12,11,11,
		# 12 13 14 15 16 17 18 19 20 21 22 23
		 14,13,11,11,13,14,11, 9, 7, 6, 5, 4,
	],
	&"central": [
		 6, 5, 4, 3, 3, 5, 9,15,22,24,24,25,
		 30,28,24,24,26,30,28,26,24,26,28,20,
	],
}

## How the mix shifts through the day. Each entry is a weight per archetype;
## which archetypes are plausible at all is what makes 08:00 and 23:00 different
## streets rather than the same street with different lighting.
const MIX_BY_BAND := {
	&"morning": {
		RoutineProfile.Archetype.OFFICE_WORKER: 4,
		RoutineProfile.Archetype.HARBOUR_WORKER: 4,
		RoutineProfile.Archetype.RETAIL_WORKER: 3,
		RoutineProfile.Archetype.FITNESS_REGULAR: 2,
		RoutineProfile.Archetype.RESIDENT: 2,
		RoutineProfile.Archetype.SHOPPER: 1,
	},
	&"midday": {
		RoutineProfile.Archetype.OFFICE_WORKER: 4,
		RoutineProfile.Archetype.SHOPPER: 4,
		RoutineProfile.Archetype.RETAIL_WORKER: 3,
		RoutineProfile.Archetype.HARBOUR_WORKER: 3,
		RoutineProfile.Archetype.YOUNG_ADULT: 2,
		RoutineProfile.Archetype.RESIDENT: 2,
	},
	&"evening": {
		RoutineProfile.Archetype.OFFICE_WORKER: 3,
		RoutineProfile.Archetype.FITNESS_REGULAR: 4,
		RoutineProfile.Archetype.SHOPPER: 3,
		RoutineProfile.Archetype.YOUNG_ADULT: 3,
		RoutineProfile.Archetype.RESIDENT: 3,
		RoutineProfile.Archetype.NIGHTLIFE_VISITOR: 2,
	},
	&"night": {
		RoutineProfile.Archetype.NIGHTLIFE_VISITOR: 6,
		RoutineProfile.Archetype.YOUNG_ADULT: 4,
		RoutineProfile.Archetype.RESIDENT: 2,
		RoutineProfile.Archetype.HARBOUR_WORKER: 1,
	},
}

var save_id: StringName = &"routines"
var reset_on_missing_save: bool = true

## Everybody who has ever been given a schedule, by the id of their node. Kept
## so a person is the same person across a session — and across a save, since
## §165 asks for enough state to reconstruct the world rather than thousands of
## serialised NPCs.
var _schedules: Dictionary = {}
var _next_person: int = 1
var _last_band: StringName = &""


func _ready() -> void:
	add_to_group(&"saveable")
	TimeManager.hour_passed.connect(_on_hour_passed)


# --- The shape of the day -------------------------------------------------

## Which of the four times of day it is. §16-§19.
static func band_at(hour: int) -> StringName:
	if hour >= 5 and hour < 11:
		return &"morning"
	if hour >= 11 and hour < 17:
		return &"midday"
	if hour >= 17 and hour < 22:
		return &"evening"
	return &"night"


func band() -> StringName:
	return band_at(TimeManager.hour)


## How many people a district should have on its pavements right now.
func density_for(district_id: StringName, hour: int = -1) -> int:
	var when: int = TimeManager.hour if hour < 0 else hour
	var table: Variant = DENSITY_BY_HOUR.get(district_id, [])
	if not (table is Array) or (table as Array).is_empty():
		return 8
	var hours: Array = table
	var target := int(hours[clampi(when, 0, hours.size() - 1)])
	# §20 — leisure is stronger on a weekend-like day, and work is not. Reuses
	# the weekday the clock already keeps rather than building a calendar.
	if TimeManager.weekday >= 5:
		var leisure := band_at(when) in [&"evening", &"night", &"midday"]
		target = roundi(float(target) * (1.15 if leisure else 0.8))
	return maxi(target, 2)


## Picks an archetype appropriate to the hour and the district.
##
## Seeded on the person rather than on the clock, so somebody keeps being the
## same kind of person all day instead of becoming a nightclub visitor at eight
## in the evening and an office worker again at nine.
func archetype_for(district_id: StringName, person_seed: int) -> RoutineProfile.Archetype:
	var mix: Dictionary = MIX_BY_BAND.get(band(), MIX_BY_BAND[&"midday"])
	var pool: Array = []
	for kind: RoutineProfile.Archetype in mix:
		var profile := RoutineProfile.by_archetype(kind)
		# §23 and §26 — an archetype tied to one district does not turn up in
		# the other one. A harbour worker on the Central plaza at seven in the
		# morning is exactly the sort of thing that makes a city feel generated.
		if profile.work_district != &"" and profile.work_district != district_id:
			if profile.home_district != district_id:
				continue
		for i in int(mix[kind]):
			pool.append(kind)
	if pool.is_empty():
		return RoutineProfile.Archetype.RESIDENT
	var rng := RandomNumberGenerator.new()
	rng.seed = person_seed
	return pool[rng.randi_range(0, pool.size() - 1)]


# --- People ---------------------------------------------------------------

## The schedule for one pedestrian, made the first time it is asked for.
func schedule_for(person_id: StringName, district_id: StringName) -> RoutineSchedule:
	if _schedules.has(person_id):
		return _schedules[person_id]
	var person_seed := hash(person_id) + _next_person
	_next_person += 1
	var schedule := RoutineSchedule.make(
		archetype_for(district_id, person_seed), person_seed
	)
	_schedules[person_id] = schedule
	return schedule


func schedule_count() -> int:
	return _schedules.size()


## Where somebody on this schedule should be heading, now.
##
## Returns Vector3.INF when their activity has nowhere to happen, which the
## pedestrian reads as "wander as before" — a district with no gym should not
## freeze everybody who wanted one (§13's other half).
func destination_for(
	schedule: RoutineSchedule, from: Vector3
) -> Vector3:
	if schedule == null:
		return Vector3.INF
	var hour := float(TimeManager.hour) + float(int(TimeManager.total_minutes) % 60) / 60.0
	var activity := schedule.activity_at(hour)
	var rng := schedule.rng_for(TimeManager.hour)
	return RoutineActivity.venue_for(get_tree(), activity, from, rng)


func activity_for(schedule: RoutineSchedule) -> RoutineActivity.Kind:
	if schedule == null:
		return RoutineActivity.Kind.HOME
	var hour := float(TimeManager.hour) + float(int(TimeManager.total_minutes) % 60) / 60.0
	return schedule.activity_at(hour)


## How many of the people currently carrying a schedule are doing a given thing.
## What the tests and the debug overlay read to check that eight in the morning
## does not look like eleven at night.
func counting(kind: RoutineActivity.Kind) -> int:
	var found := 0
	for id: StringName in _schedules:
		if activity_for(_schedules[id]) == kind:
			found += 1
	return found


func archetype_tally() -> Dictionary:
	var tally := {}
	for id: StringName in _schedules:
		var kind := (_schedules[id] as RoutineSchedule).archetype()
		tally[kind] = int(tally.get(kind, 0)) + 1
	return tally


func _on_hour_passed(hour: int) -> void:
	var now := band_at(hour)
	if now == _last_band:
		return
	_last_band = now
	for district in DENSITY_BY_HOUR:
		density_changed.emit(district, density_for(district, hour))


# --- Save -----------------------------------------------------------------

## §165 — the routine population is reconstructed rather than serialised. All a
## save needs is the counter that keeps people distinct; every schedule is a
## pure function of that and the person's node name.
func clear() -> void:
	_schedules.clear()
	_next_person = 1
	_last_band = &""


func save_state() -> Dictionary:
	return {"next_person": _next_person}


func load_state(state: Dictionary) -> void:
	clear()
	_next_person = int(state.get("next_person", 1))
