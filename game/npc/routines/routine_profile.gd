class_name RoutineProfile
extends RefCounted

## An archetype's day, as a list of blocks.
##
## §5 asks for several archetypes and §7 warns off requiring identical
## schedules. So a profile is the *shape* of a day — leave around eight, work
## until midday, eat, work again, maybe the gym, home — and the individual
## offsets that make one office worker unlike the next live in RoutineSchedule.
##
## Everything here is a movement and demand pattern. §5 is explicit that these
## are not demographic identities and nothing below models one.

enum Archetype {
	OFFICE_WORKER, HARBOUR_WORKER, RETAIL_WORKER, YOUNG_ADULT,
	FITNESS_REGULAR, NIGHTLIFE_VISITOR, SHOPPER, RESIDENT,
}

const NAMES := {
	Archetype.OFFICE_WORKER: "Office worker",
	Archetype.HARBOUR_WORKER: "Harbour worker",
	Archetype.RETAIL_WORKER: "Retail worker",
	Archetype.YOUNG_ADULT: "Young adult",
	Archetype.FITNESS_REGULAR: "Fitness regular",
	Archetype.NIGHTLIFE_VISITOR: "Nightlife visitor",
	Archetype.SHOPPER: "Shopper",
	Archetype.RESIDENT: "Resident",
}

var archetype: Archetype = Archetype.RESIDENT
## Blocks as [start_hour, activity]. Read in order; the activity runs until the
## next block begins. Hours are floats so half past is expressible.
var blocks: Array = []
## Which district this archetype mostly belongs to, for §23 and §26's mixes.
## Empty means either.
var home_district: StringName = &""
var work_district: StringName = &""


static func make(
	kind: Archetype, day: Array, home: StringName = &"", work: StringName = &""
) -> RoutineProfile:
	var profile := RoutineProfile.new()
	profile.archetype = kind
	profile.blocks = day
	profile.home_district = home
	profile.work_district = work
	return profile


static func name_of(kind: Archetype) -> String:
	return String(NAMES.get(kind, "Resident"))


## What this archetype is doing at a given hour, before personal variance.
func activity_at(hour: float) -> RoutineActivity.Kind:
	var current: RoutineActivity.Kind = RoutineActivity.Kind.HOME
	for block in blocks:
		if hour >= float(block[0]):
			current = block[1]
	return current


## Every archetype in the game.
##
## §7 and §8 give the office and harbour shapes; the rest follow the same idea.
## §9's nightlife visitor is barely present in daylight, which is what makes the
## evening city read differently from the morning one.
static func catalogue() -> Array[RoutineProfile]:
	var A := RoutineActivity.Kind
	return [
		# §7 — the example, with the gym-or-shop evening left as one block
		# because which of them happens is the individual's business.
		make(Archetype.OFFICE_WORKER, [
			[0.0, A.HOME], [7.5, A.COMMUTE], [9.0, A.WORK], [12.0, A.LUNCH],
			[13.0, A.WORK], [17.0, A.SHOP], [19.0, A.RETURN_HOME], [20.0, A.HOME],
		], &"", &"central"),
		# §8 — earlier hours, and the shop before work rather than after.
		make(Archetype.HARBOUR_WORKER, [
			[0.0, A.HOME], [5.5, A.CAFE], [6.5, A.COMMUTE], [7.0, A.WORK],
			[12.0, A.LUNCH], [12.75, A.WORK], [16.0, A.RETURN_HOME],
			[17.0, A.SHOP], [19.0, A.HOME],
		], &"harbour_row", &"harbour_row"),
		make(Archetype.RETAIL_WORKER, [
			[0.0, A.HOME], [8.0, A.COMMUTE], [9.0, A.WORK], [13.0, A.LUNCH],
			[14.0, A.WORK], [18.0, A.RETURN_HOME], [19.0, A.HOME],
		]),
		make(Archetype.YOUNG_ADULT, [
			[0.0, A.HOME], [10.0, A.CAFE], [12.0, A.SHOP], [15.0, A.PARK],
			[18.0, A.HOME], [21.0, A.NIGHTLIFE], [26.0, A.RETURN_HOME],
		], &"", &"central"),
		make(Archetype.FITNESS_REGULAR, [
			[0.0, A.HOME], [6.5, A.GYM], [8.0, A.COMMUTE], [9.0, A.WORK],
			[17.0, A.GYM], [19.5, A.RETURN_HOME], [20.5, A.HOME],
		]),
		# §9 — almost nothing in the day, then Central after dark.
		make(Archetype.NIGHTLIFE_VISITOR, [
			[0.0, A.NIGHTLIFE], [2.5, A.RETURN_HOME], [3.5, A.HOME],
			[19.0, A.SHOP], [21.0, A.NIGHTLIFE],
		], &"", &"central"),
		make(Archetype.SHOPPER, [
			[0.0, A.HOME], [10.0, A.SHOP], [12.5, A.LUNCH], [13.5, A.SHOP],
			[17.0, A.CAFE], [18.5, A.RETURN_HOME], [19.5, A.HOME],
		]),
		# Somebody who is simply about: the filler that stops a street emptying
		# between shifts.
		make(Archetype.RESIDENT, [
			[0.0, A.HOME], [9.0, A.PARK], [11.0, A.SHOP], [14.0, A.PARK],
			[17.0, A.SHOP], [19.0, A.HOME],
		]),
	]


static func by_archetype(kind: Archetype) -> RoutineProfile:
	for profile in catalogue():
		if profile.archetype == kind:
			return profile
	return catalogue()[catalogue().size() - 1]
