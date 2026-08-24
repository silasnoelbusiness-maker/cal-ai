class_name PropLibrary
extends RefCounted

## The street furniture the city knows about, by name.
##
## `PropKit` builds each one out of primitives; this is the list of what those
## names are, and what gameplay needs to know about each without knowing how it
## is drawn. A bench is somewhere a routine can send somebody and something the
## player walks round; whether it is four boxes or an imported mesh is the
## visual layer's business.
##
## Kept flat and static so the asset validator can walk the whole set, and so
## `VisualRegistry` has something to check production coverage against.

## Each entry: [builder name, solid, group it joins, footprint metres].
##
## `solid` is whether the player collides with it. Most street furniture is
## deliberately not solid — a bin the crowd wedges against is a bug the player
## can see, and one they clip through is not something anybody notices from
## this camera.
const PROPS := {
	&"bench_01": ["bench", false, &"bench", Vector2(2.2, 0.7)],
	&"bin_01": ["bin", false, &"", Vector2(0.6, 0.6)],
	&"planter_01": ["planter", false, &"", Vector2(1.4, 1.4)],
	&"bollard_01": ["bollard", false, &"", Vector2(0.3, 0.3)],
	&"hydrant_01": ["hydrant", false, &"", Vector2(0.4, 0.4)],
	&"sign_01": ["street_sign", false, &"", Vector2(0.3, 0.3)],
	&"meter_01": ["parking_meter", false, &"", Vector2(0.3, 0.3)],
	&"bike_rack_01": ["bike_rack", false, &"", Vector2(1.8, 0.4)],
	&"shelter_01": ["shelter", false, &"", Vector2(4.0, 1.6)],
	&"crate_stack_01": ["crate_stack", true, &"", Vector2(1.6, 1.6)],
	&"vending_01": ["vending_machine", true, &"", Vector2(0.9, 0.6)],
	&"park_spot_01": ["park_spot", false, &"park_spot", Vector2(0.5, 0.5)],
}


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in PROPS:
		out.append(id)
	return out


static func exists(id: StringName) -> bool:
	return PROPS.has(id)


## Whether the player collides with this prop.
static func is_solid(id: StringName) -> bool:
	var entry: Array = PROPS.get(id, [])
	return entry.size() > 1 and bool(entry[1])


## The group this prop joins, or an empty name. This is what makes a bench
## somewhere a routine can be sent and a bin merely scenery.
static func group_of(id: StringName) -> StringName:
	var entry: Array = PROPS.get(id, [])
	return entry[2] if entry.size() > 2 else &""


## Ground footprint in metres, for the validator's route check: a decorative
## prop must not be wide enough to block a pavement.
static func footprint(id: StringName) -> Vector2:
	var entry: Array = PROPS.get(id, [])
	return entry[3] if entry.size() > 3 else Vector2.ONE


static func builder_of(id: StringName) -> String:
	var entry: Array = PROPS.get(id, [])
	return String(entry[0]) if not entry.is_empty() else ""
