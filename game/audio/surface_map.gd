class_name SurfaceMap
extends RefCounted
## What the ground under somebody is made of.
##
## Footsteps need a surface, and the naive way to get one is a table of
## coordinates — "if x is between these, it is wood" — which is wrong the first
## time a room moves. Instead, anything that owns a floor puts itself in a
## group naming its surface, and this walks up from whatever the foot is
## standing on to find the nearest answer.
##
## Groups beat metadata here because a district builds hundreds of slabs from
## CityKit and adding one `add_to_group` at the call site is cheaper than
## threading a property through every primitive helper.

enum Surface { CONCRETE, ASPHALT, WOOD, TILE, CARPET, GRASS }

## The group a piece of geometry joins to declare its surface.
const GROUPS := {
	&"surface_concrete": Surface.CONCRETE,
	&"surface_asphalt": Surface.ASPHALT,
	&"surface_wood": Surface.WOOD,
	&"surface_tile": Surface.TILE,
	&"surface_carpet": Surface.CARPET,
	&"surface_grass": Surface.GRASS,
}

const STEP_SOUNDS := {
	Surface.CONCRETE: &"step_concrete",
	Surface.ASPHALT: &"step_asphalt",
	Surface.WOOD: &"step_wood",
	Surface.TILE: &"step_tile",
	Surface.CARPET: &"step_carpet",
	Surface.GRASS: &"step_grass",
}


## Layer the surface probes live on.
##
## Road markings and carriageways are decorative slabs with no collision, so a
## ray straight down from a walking figure passes through them and hits the
## ground underneath. Rather than making roads solid — which would change how
## everything in the game drives and walks — each surface gets a probe body on a
## layer nothing else collides with. The footstep ray is the only thing that
## looks at it.
const PROBE_LAYER := 1 << 6

## Tags a node — and therefore whatever is standing on it — with a surface.
static func tag(node: Node, surface: Surface) -> void:
	for group in GROUPS:
		if GROUPS[group] == surface:
			node.add_to_group(group)
			return


## The surface of a collider, or of the nearest ancestor that declares one.
## Concrete is the fallback because the city is mostly pavement.
## Adds an invisible probe over a decorative slab, so a ray can find out what
## the player is standing on without the slab itself becoming solid.
static func probe(parent: Node3D, rect: Rect2, top_y: float, surface: Surface) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "SurfaceProbe"
	body.collision_layer = PROBE_LAYER
	body.collision_mask = 0
	body.position = Vector3(rect.position.x + rect.size.x * 0.5, top_y, rect.position.y + rect.size.y * 0.5)
	parent.add_child(body)

	var shape := BoxShape3D.new()
	# Thin, and sitting just under the surface it describes.
	shape.size = Vector3(rect.size.x, 0.08, rect.size.y)
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)

	tag(body, surface)
	return body


static func of_collider(collider: Node) -> Surface:
	var node := collider
	var hops := 0
	while node != null and hops < 6:
		for group in GROUPS:
			if node.is_in_group(group):
				return GROUPS[group]
		node = node.get_parent()
		hops += 1
	return Surface.CONCRETE


## What the given body is standing on, by looking straight down.
##
## Uses the body's own last collision when it has one — a CharacterBody3D that
## just moved already knows what it hit — and falls back to a short ray, which
## covers standing still.
static func under(body: CharacterBody3D) -> Surface:

	# The probe layer first: a road or a floor that describes itself wins over
	# whatever solid geometry happens to be under it.
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * 0.5
	var probe_query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.8)
	probe_query.collision_mask = PROBE_LAYER
	probe_query.exclude = [body.get_rid()]
	var probe_hit := space.intersect_ray(probe_query)
	if not probe_hit.is_empty():
		return of_collider(probe_hit.get("collider"))

	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.8)
	query.exclude = [body.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Surface.CONCRETE
	return of_collider(hit.get("collider"))


static func sound_for(surface: Surface) -> StringName:
	return STEP_SOUNDS.get(surface, &"step_concrete")


static func display_name(surface: Surface) -> String:
	return Surface.keys()[surface].capitalize()
