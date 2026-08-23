class_name RoutineActivity
extends RefCounted

## What somebody is doing with their hour, and where that happens.
##
## §6 lists the activities a routine can contain. This is that list plus the one
## thing the world needs from it: given an activity and a district, where does a
## person doing it stand. Everything about routines that touches the map goes
## through `venue_for`, so a new kind of place is one entry here rather than a
## change in four files.
##
## §5 is worth restating because it shapes all of this: these are movement and
## demand archetypes, not people. Nothing here models who anybody is.

enum Kind {
	HOME, COMMUTE, WORK, LUNCH, SHOP, CAFE, GYM, PARK, NIGHTLIFE, RETURN_HOME,
}

const NAMES := {
	Kind.HOME: "at home",
	Kind.COMMUTE: "commuting",
	Kind.WORK: "at work",
	Kind.LUNCH: "at lunch",
	Kind.SHOP: "shopping",
	Kind.CAFE: "in a cafe",
	Kind.GYM: "at the gym",
	Kind.PARK: "in the park",
	Kind.NIGHTLIFE: "out for the night",
	Kind.RETURN_HOME: "heading home",
}

## Groups a routine looks in for somewhere to be. A venue is any node already in
## the world that means the right thing — §13 and §14 want people entering real
## entrances rather than vanishing on the pavement, so these are the doors and
## fronts the districts already build.
const VENUE_GROUPS := {
	Kind.HOME: [&"residence", &"building_entrance"],
	Kind.WORK: [&"job_station", &"warehouse_door", &"building_entrance"],
	Kind.LUNCH: [&"shop", &"building_entrance"],
	Kind.SHOP: [&"shop", &"retail_unit", &"building_entrance"],
	Kind.CAFE: [&"shop", &"building_entrance"],
	Kind.GYM: [&"building_entrance"],
	Kind.PARK: [&"bench", &"park_spot"],
	Kind.NIGHTLIFE: [&"building_entrance"],
}

## The last resort. Every façade door in both districts joins this, so an
## activity whose own group is empty still sends somebody to a doorway rather
## than to a random slab of pavement.
const FALLBACK_GROUP := &"building_entrance"


static func name_of(kind: Kind) -> String:
	return String(NAMES.get(kind, "about"))


## Whether this activity means being inside somewhere rather than on the street.
## Used to decide whether a person should disappear through a door.
static func is_indoors(kind: Kind) -> bool:
	return kind in [
		Kind.HOME, Kind.WORK, Kind.LUNCH, Kind.SHOP, Kind.CAFE, Kind.GYM,
		Kind.NIGHTLIFE,
	]


## Somewhere in the world a person doing this could plausibly be.
##
## Returns Vector3.INF when the city has nowhere for it, which the caller reads
## as "carry on walking" rather than as an error — a district with no gym should
## not strand everybody who wanted one.
static func venue_for(
	tree: SceneTree, kind: Kind, near: Vector3, rng: RandomNumberGenerator
) -> Vector3:
	if tree == null:
		return Vector3.INF
	var groups: Array = VENUE_GROUPS.get(kind, [])
	var found: Array[Vector3] = []
	for group: StringName in groups:
		for node in tree.get_nodes_in_group(group):
			var spot := node as Node3D
			if spot == null:
				continue
			found.append(spot.global_position)
		if not found.is_empty():
			break
	if found.is_empty():
		for node in tree.get_nodes_in_group(FALLBACK_GROUP):
			var door := node as Node3D
			if door != null:
				found.append(door.global_position)
	if found.is_empty():
		return Vector3.INF
	# Nearest few rather than the nearest one, so a street of people heading for
	# lunch does not become a queue of clones walking the same line.
	found.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			return a.distance_squared_to(near) < b.distance_squared_to(near)
	)
	var reach: int = mini(found.size(), 4)
	return found[rng.randi_range(0, reach - 1)]
