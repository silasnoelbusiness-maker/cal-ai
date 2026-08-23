class_name RoutineSchedule
extends RefCounted

## One person's version of an archetype's day.
##
## §10 is the whole reason this exists: a hundred people leaving work at exactly
## five o'clock is not a city, it is a fire drill. Every schedule carries a
## seeded offset, so two office workers built from the same profile leave at
## 16:47 and 17:12 and neither of them ever changes their mind about it.
##
## Seeded rather than random, per §10, so a run is reproducible and a failing
## test can be re-run.

## The most a person's day can slide from their archetype's, in hours.
const MAX_OFFSET := 0.75

var profile: RoutineProfile = null
## This person's fixed shift from the archetype's timetable.
var offset: float = 0.0
## Which of the plausible venues this person favours, so they go back to the
## same cafe rather than a new one every morning.
var venue_bias: int = 0
var seed_value: int = 0


static func make(kind: RoutineProfile.Archetype, person_seed: int) -> RoutineSchedule:
	var schedule := RoutineSchedule.new()
	schedule.profile = RoutineProfile.by_archetype(kind)
	schedule.seed_value = person_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = person_seed
	schedule.offset = rng.randf_range(-MAX_OFFSET, MAX_OFFSET)
	schedule.venue_bias = rng.randi_range(0, 3)
	return schedule


## What this person is doing now. The offset is applied to the clock rather than
## to the timetable, which comes to the same thing and keeps the profile
## immutable and shared.
func activity_at(hour: float) -> RoutineActivity.Kind:
	if profile == null:
		return RoutineActivity.Kind.HOME
	return profile.activity_at(wrapf(hour - offset, 0.0, 24.0))


func archetype() -> RoutineProfile.Archetype:
	return profile.archetype if profile != null else RoutineProfile.Archetype.RESIDENT


func archetype_name() -> String:
	return RoutineProfile.name_of(archetype())


## The seeded generator for this person's decisions, so where they choose to eat
## is stable across a session rather than flickering every time they are asked.
func rng_for(hour: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + hour
	return rng
