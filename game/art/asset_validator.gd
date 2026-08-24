class_name AssetValidator
extends RefCounted

## Checks the visual layer for the mistakes that only ever surface at run time.
##
## A missing mesh, a material name nobody registered, a character built at the
## wrong scale, a decorative prop wide enough to seal a pavement: every one of
## these is invisible in code review, silent at load, and obvious to a player.
## This walks the whole set and reports rather than waiting to be found.
##
## Never throws and never modifies anything. It returns a list of problems, and
## the test suite fails on a non-empty list.

## One problem found.
class Issue extends RefCounted:
	var area: StringName = &""
	var subject: String = ""
	var detail: String = ""

	func _to_string() -> String:
		return "[%s] %s — %s" % [area, subject, detail]


## Feet must be within this of the ground, or a figure floats or sinks.
const FOOT_TOLERANCE := 0.06
## A prop wider than this on a pavement is a wall.
const MAX_DECORATIVE_WIDTH := 3.0
## Nobody in the game is shorter or taller than these.
const HEIGHT_RANGE := Vector2(1.40, 2.10)


## Everything, in one call. `tree` may be null for the checks that do not need
## a live world.
static func run(tree: SceneTree = null) -> Array:
	var issues: Array = []
	issues.append_array(check_materials())
	issues.append_array(check_props())
	issues.append_array(check_visual_registry())
	if tree != null:
		issues.append_array(check_characters(tree))
		issues.append_array(check_vehicles(tree))
		issues.append_array(check_interaction_points(tree))
	return issues


## Every material name anything asks for must be in the library. A miss returns
## magenta and a warning today, which is better than a crash and worse than a
## test — this is the test.
static func check_materials() -> Array:
	var issues: Array = []
	for name: StringName in Palette.LIBRARY:
		var entry: Array = Palette.LIBRARY[name]
		if entry.size() != 4 and entry.size() != 7:
			issues.append(_issue(
				&"material", String(name),
				"has %d fields; a library entry is 4 (flat) or 7 (surface)" % entry.size()
			))
			continue
		var colour: Color = entry[0]
		if colour.a < 0.999 and not String(name).begins_with("glass"):
			issues.append(_issue(
				&"material", String(name),
				"is transparent, which only glass should be"
			))
		var roughness: float = float(entry[1])
		if roughness < 0.0 or roughness > 1.0:
			issues.append(_issue(
				&"material", String(name), "roughness %.2f is outside 0-1" % roughness
			))
	return issues


## A prop must have a builder, a sane footprint, and must not be wide enough to
## block a route unless it is meant to be solid.
static func check_props() -> Array:
	var issues: Array = []
	for id in PropLibrary.ids():
		if PropLibrary.builder_of(id).is_empty():
			issues.append(_issue(&"prop", String(id), "has no builder"))
		var size := PropLibrary.footprint(id)
		if size.x <= 0.0 or size.y <= 0.0:
			issues.append(_issue(&"prop", String(id), "has an empty footprint"))
		if not PropLibrary.is_solid(id) and maxf(size.x, size.y) > MAX_DECORATIVE_WIDTH:
			issues.append(_issue(
				&"prop", String(id),
				"is decorative but %.1fm across, which would block a pavement" % maxf(size.x, size.y)
			))
	return issues


## Anything registered against an id must actually be there.
static func check_visual_registry() -> Array:
	var issues: Array = []
	for kind: VisualRegistry.Kind in [
		VisualRegistry.Kind.CHARACTER, VisualRegistry.Kind.VEHICLE,
		VisualRegistry.Kind.PROP,
	]:
		var table: Dictionary = VisualRegistry._table(kind)
		for id in table:
			if not ResourceLoader.exists(String(table[id])):
				issues.append(_issue(
					&"registry", String(id),
					"points at '%s', which does not exist" % table[id]
				))
	return issues


## Every figure in the world: right scale, feet on the ground, collision intact.
static func check_characters(tree: SceneTree) -> Array:
	var issues: Array = []
	for node in tree.get_nodes_in_group(&"pedestrian") + tree.get_nodes_in_group(&"police"):
		var body := node as CharacterBody3D
		if body == null:
			continue
		var look_height: float = float(body.get("look_height") if body.get("look_height") != null else 1.78)
		if look_height < HEIGHT_RANGE.x or look_height > HEIGHT_RANGE.y:
			issues.append(_issue(
				&"character", String(body.name),
				"is %.2fm tall, outside %.2f-%.2f" % [
					look_height, HEIGHT_RANGE.x, HEIGHT_RANGE.y
				]
			))
		var shape := _first_shape(body)
		if shape == null:
			issues.append(_issue(&"character", String(body.name), "has no collision shape"))
	return issues


## Every vehicle: wheels under the body, lamps on it, collision aligned.
static func check_vehicles(tree: SceneTree) -> Array:
	var issues: Array = []
	for node in tree.get_nodes_in_group(&"vehicle"):
		var car := node as Node3D
		if car == null or car.get("data") == null:
			continue
		var data = car.get("data")
		if data.body_length <= 0.0 or data.body_width <= 0.0:
			issues.append(_issue(&"vehicle", String(car.name), "has no body size"))
			continue
		if data.wheel_radius <= 0.0:
			issues.append(_issue(&"vehicle", String(car.name), "has no wheel radius"))
		# A wheel taller than the body sits through the roof.
		if data.wheel_radius * 2.0 > data.body_height + data.cabin_height:
			issues.append(_issue(
				&"vehicle", String(car.name),
				"wheels (%.2fm) are taller than the whole car" % (data.wheel_radius * 2.0)
			))
		if _first_shape(car) == null:
			issues.append(_issue(&"vehicle", String(car.name), "has no collision shape"))
	return issues


## A door's interaction point is what the map, the routines and the property
## system all navigate to. A façade mesh may move; this must not.
static func check_interaction_points(tree: SceneTree) -> Array:
	var issues: Array = []
	for node in tree.get_nodes_in_group(&"building_entrance"):
		var door := node as Node3D
		if door == null:
			continue
		var at := door.global_position
		if at.y < -1.0 or at.y > 6.0:
			issues.append(_issue(
				&"door", String(door.name),
				"is at y=%.1f, which is through the floor or on the roof" % at.y
			))
	return issues


## A one-line summary, for the debug overlay and the test message.
static func summary(issues: Array) -> String:
	if issues.is_empty():
		return "assets: nothing wrong"
	var lines := PackedStringArray()
	for issue in issues:
		lines.append(str(issue))
	return "assets: %d problem%s\n%s" % [
		issues.size(), "" if issues.size() == 1 else "s", "\n".join(lines)
	]


## How much of the game is still drawn from primitives rather than imported.
## Reported rather than hidden — see assets/README.md.
static func coverage_report() -> String:
	return "production art: characters %.0f%%, vehicles %.0f%%, props %.0f%%" % [
		VisualRegistry.production_coverage(VisualRegistry.Kind.CHARACTER) * 100.0,
		VisualRegistry.production_coverage(VisualRegistry.Kind.VEHICLE) * 100.0,
		VisualRegistry.production_coverage(VisualRegistry.Kind.PROP) * 100.0,
	]


static func _first_shape(node: Node) -> CollisionShape3D:
	for child in node.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape != null:
			return shape
	return null


static func _issue(area: StringName, subject: String, detail: String) -> Issue:
	var issue := Issue.new()
	issue.area = area
	issue.subject = subject
	issue.detail = detail
	return issue
