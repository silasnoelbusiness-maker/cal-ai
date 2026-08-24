class_name VisualRegistry
extends RefCounted

## Where gameplay asks what something looks like.
##
## Every visual in the game is reached through a semantic id — a character
## category, a vehicle profile, a prop name — rather than through a path to a
## mesh. Nothing in the gameplay layer knows whether the answer came from an
## imported scene or from a builder that assembles boxes at run time, which is
## the whole point: replacing a car model must not touch physics, ownership,
## mileage, value, repair, police status or saving.
##
## Today every id falls back to a builder, because the project ships no imported
## art. `assets/README.md` says so plainly and lists what should replace what.
## Registering a scene against an id is the only change needed to swap one.

## Registered scenes, by kind and id. Empty until production art exists.
##
## A static dictionary rather than a resource file on purpose: a missing entry
## must be a silent fallback, not a load error, and a .tres full of null paths
## is a load error waiting to happen.
const CHARACTER_SCENES := {}
const VEHICLE_SCENES := {}
const PROP_SCENES := {}

enum Kind { CHARACTER, VEHICLE, PROP }


## The scene registered for an id, or null if the builder should be used.
##
## Never raises. A registered path that does not exist warns and falls back,
## because a half-finished art pass should leave the game playable with boxes
## rather than leave a hole in the world.
static func scene_for(kind: Kind, id: StringName) -> PackedScene:
	var table: Dictionary = _table(kind)
	if not table.has(id):
		return null
	var path := String(table[id])
	if not ResourceLoader.exists(path):
		push_warning(
			"VisualRegistry: %s '%s' points at '%s', which is not there. Using the fallback."
			% [_kind_name(kind), id, path]
		)
		return null
	return load(path) as PackedScene


## Whether an id has production art behind it. The debug overlay and the asset
## validator both read this to report how much of the game is still boxes.
static func has_production_art(kind: Kind, id: StringName) -> bool:
	return scene_for(kind, id) != null


## Every id the game will ask about, so the validator can check the whole set
## rather than only the ones that happen to be on screen.
static func known_ids(kind: Kind) -> Array[StringName]:
	var out: Array[StringName] = []
	match kind:
		Kind.CHARACTER:
			for value in CharacterLook.Category.values():
				out.append(StringName(str(value)))
		Kind.VEHICLE:
			for id in VehicleCatalogue.ids():
				out.append(StringName(id))
		Kind.PROP:
			out.assign(PropLibrary.ids())
	return out


## How much of the game is still drawn from primitives, as a fraction. Reported
## by the validator, so "we have art now" is a measurement rather than a claim.
static func production_coverage(kind: Kind) -> float:
	var ids := known_ids(kind)
	if ids.is_empty():
		return 1.0
	var covered := 0
	for id in ids:
		if has_production_art(kind, id):
			covered += 1
	return float(covered) / float(ids.size())


static func _table(kind: Kind) -> Dictionary:
	match kind:
		Kind.CHARACTER:
			return CHARACTER_SCENES
		Kind.VEHICLE:
			return VEHICLE_SCENES
	return PROP_SCENES


static func _kind_name(kind: Kind) -> String:
	match kind:
		Kind.CHARACTER:
			return "character"
		Kind.VEHICLE:
			return "vehicle"
	return "prop"
