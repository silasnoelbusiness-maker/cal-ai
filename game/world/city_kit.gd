class_name CityKit
extends RefCounted
## Static helpers for assembling prototype city geometry out of primitives.
##
## Everything shares one unit BoxMesh and one unit CylinderMesh scaled per
## instance, so a district of a few hundred pieces still only holds a handful of
## mesh resources. Materials are looked up from a palette dictionary built once
## per district. When real art arrives, only this file and the district data
## need to change.

## Sidewalk slabs sit this high above the road surface. Kept low enough that the
## player capsule steps up onto a curb instead of being blocked by it.
const CURB_HEIGHT := 0.12
const ROAD_HEIGHT := 0.02
const MARKING_HEIGHT := 0.045

static var _unit_box: BoxMesh
static var _unit_cylinder: CylinderMesh
static var _unit_sphere: SphereMesh
static var _unit_gable: PrismMesh
## Hip roofs keyed by ridge ratio; there are only ever two or three in use.
static var _hip_roofs: Dictionary = {}
## Noise images are shared by every material that asks for the same settings, so
## a district of several hundred pieces still holds a handful of textures.
static var _noise_cache: Dictionary = {}


static func unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box


static func unit_cylinder() -> CylinderMesh:
	if _unit_cylinder == null:
		_unit_cylinder = CylinderMesh.new()
		_unit_cylinder.top_radius = 0.5
		_unit_cylinder.bottom_radius = 0.5
		_unit_cylinder.height = 1.0
		_unit_cylinder.radial_segments = 12
		_unit_cylinder.rings = 1
	return _unit_cylinder


static func unit_sphere() -> SphereMesh:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 0.5
		_unit_sphere.height = 1.0
		_unit_sphere.radial_segments = 12
		_unit_sphere.rings = 6
	return _unit_sphere


static func make_material(
	color: Color, roughness: float = 0.92, metallic: float = 0.0
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


## A material with real surface relief on it.
##
## Two things make this work on a city built out of scaled unit boxes. The first
## is *world triplanar* mapping: the texture is projected from world coordinates
## rather than read from UVs, so a 170m road slab and a 2m bench get the same
## grain instead of one noise tile stretched across each of them. Without it,
## texturing a kit of scaled primitives is not worth attempting. The second is
## that the noise drives a normal map, not just a tint — a flat colour under a
## directional light reads as plastic however carefully it is chosen, and the
## same colour with a few millimetres of relief reads as asphalt, grass or
## shingle.
##
## `detail_scale` is in metres per noise tile. `bump` is relief strength; `mottle`
## is how much the albedo varies. Either may be zero.
static func make_surface(
	color: Color,
	roughness: float = 0.92,
	detail_scale: float = 2.0,
	bump: float = 0.6,
	mottle: float = 0.12,
	metallic: float = 0.0,
	noise_seed: int = 1
) -> StandardMaterial3D:
	var material := make_material(color, roughness, metallic)
	if bump <= 0.0 and mottle <= 0.0:
		return material

	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / maxf(detail_scale, 0.01)

	if bump > 0.0:
		material.normal_enabled = true
		material.normal_scale = bump
		material.normal_texture = _noise(noise_seed, true, mottle)

	if mottle > 0.0:
		# The ramp only ever darkens, so this reads as patchiness and wear on the
		# authored colour. Scaling the colour back up to compensate was tried
		# and made every surface pale and chalky — a mottled surface wants to
		# sit slightly *below* its flat colour, not above it.
		material.albedo_texture = _noise(noise_seed, false, mottle)
	return material


## Shared noise texture. As a normal map it is the relief; as an albedo texture
## it is a near-white ramp that only darkens, so multiplying by it tints rather
## than washes out.
static func _noise(noise_seed: int, as_normal: bool, mottle: float) -> NoiseTexture2D:
	var key := "%d_%s_%.3f" % [noise_seed, as_normal, mottle]
	if _noise_cache.has(key):
		return _noise_cache[key]

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.55

	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.as_normal_map = as_normal
	texture.bump_strength = 6.0
	if not as_normal:
		var ramp := Gradient.new()
		var floor_value := clampf(1.0 - mottle, 0.0, 1.0)
		ramp.set_color(0, Color(floor_value, floor_value, floor_value))
		ramp.set_color(1, Color.WHITE)
		texture.color_ramp = ramp

	_noise_cache[key] = texture
	return texture


## `color` is the surface albedo; `emission_color` defaults to it. Keeping the
## two separate lets a window read as dark glass by day and glow after dark by
## animating only the energy.
static func make_emissive_material(
	color: Color, energy: float = 1.6, emission_color: Color = Color(0, 0, 0, 0)
) -> StandardMaterial3D:
	var material := make_material(color, 0.4)
	material.emission_enabled = true
	material.emission = color if emission_color.a == 0.0 else emission_color
	material.emission_energy_multiplier = energy
	return material


## Adds a box. `size` is the full extent; `center` is the centre of the box.
## Returns the created node (a StaticBody3D when solid, a MeshInstance3D when
## purely decorative) so callers can parent extra props to it.
##
## `layer` is the physics layer the solid body occupies. It exists so kerbs can
## sit on a layer vehicles ignore while pedestrians still step up them.
static func add_box(
	parent: Node3D,
	node_name: String,
	center: Vector3,
	size: Vector3,
	material: StandardMaterial3D,
	solid: bool = true,
	cast_shadow: bool = true,
	layer: int = 1
) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = unit_box()
	mesh_instance.scale = size
	mesh_instance.material_override = material
	if not cast_shadow:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if not solid:
		mesh_instance.name = node_name
		mesh_instance.position = center
		parent.add_child(mesh_instance)
		return mesh_instance

	var body := StaticBody3D.new()
	body.name = node_name
	body.position = center
	body.collision_layer = layer
	body.collision_mask = 0
	parent.add_child(body)

	body.add_child(mesh_instance)
	mesh_instance.name = "Mesh"

	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)
	return body


## Adds a box from an axis-aligned footprint on the XZ plane. Far friendlier
## than centre+size for laying out streets and lots.
static func add_slab(
	parent: Node3D,
	node_name: String,
	rect: Rect2,
	base_y: float,
	height: float,
	material: StandardMaterial3D,
	solid: bool = true,
	cast_shadow: bool = true,
	layer: int = 1
) -> Node3D:
	var center := Vector3(
		rect.position.x + rect.size.x * 0.5,
		base_y + height * 0.5,
		rect.position.y + rect.size.y * 0.5
	)
	var size := Vector3(rect.size.x, height, rect.size.y)
	return add_box(parent, node_name, center, size, material, solid, cast_shadow, layer)


static func add_cylinder(
	parent: Node3D,
	node_name: String,
	center: Vector3,
	radius: float,
	height: float,
	material: StandardMaterial3D,
	solid: bool = true
) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = unit_cylinder()
	mesh_instance.scale = Vector3(radius * 2.0, height, radius * 2.0)
	mesh_instance.material_override = material

	if not solid:
		mesh_instance.name = node_name
		mesh_instance.position = center
		parent.add_child(mesh_instance)
		return mesh_instance

	var body := StaticBody3D.new()
	body.name = node_name
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	body.add_child(mesh_instance)
	mesh_instance.name = "Mesh"

	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)
	return body


## Decorative sphere, used for tree canopies. Never solid — foliage the player
## bumps into is more annoying than it is convincing.
static func add_sphere(
	parent: Node3D,
	node_name: String,
	center: Vector3,
	size: Vector3,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = unit_sphere()
	mesh_instance.scale = size
	mesh_instance.position = center
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


# --- Roofs ---------------------------------------------------------------

## Unit gable roof: a triangular prism, ridge running along Z, base 1x1 in XZ,
## apex at y = 1. Godot's PrismMesh is exactly this shape already.
static func unit_gable() -> PrismMesh:
	if _unit_gable == null:
		_unit_gable = PrismMesh.new()
		_unit_gable.size = Vector3.ONE
		_unit_gable.left_to_right = 0.5
	return _unit_gable


## Unit hip roof: base 1x1 in XZ at y = 0, ridge along X at y = 1, `ridge_ratio`
## of the base long. Two trapezoid slopes and two triangular ends.
##
## A pitched roof is what makes a low building read as a house rather than a box,
## and there is no primitive for one — so it is built once here and scaled per
## instance like everything else in the kit. Pass 0 for a pyramid.
static func unit_hip_roof(ridge_ratio: float = 0.4) -> ArrayMesh:
	var key := snappedf(clampf(ridge_ratio, 0.0, 0.98), 0.01)
	if _hip_roofs.has(key):
		return _hip_roofs[key]

	var r: float = key * 0.5
	var bl := Vector3(-0.5, 0.0, 0.5)
	var br := Vector3(0.5, 0.0, 0.5)
	var tr := Vector3(0.5, 0.0, -0.5)
	var tl := Vector3(-0.5, 0.0, -0.5)
	var ridge_left := Vector3(-r, 1.0, 0.0)
	var ridge_right := Vector3(r, 1.0, 0.0)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# South and north slopes.
	_face(tool, [bl, br, ridge_right, ridge_left], Vector3(0.0, 1.0, 1.0))
	_face(tool, [tr, tl, ridge_left, ridge_right], Vector3(0.0, 1.0, -1.0))
	# East and west hips. With a zero ridge these collapse to the pyramid's
	# remaining two faces, which is the intended degenerate case.
	_face(tool, [br, tr, ridge_right], Vector3(1.0, 1.0, 0.0))
	_face(tool, [tl, bl, ridge_left], Vector3(-1.0, 1.0, 0.0))
	# Underside, so the roof is not see-through from below at a low camera angle.
	_face(tool, [bl, tl, tr, br], Vector3.DOWN)

	var mesh: ArrayMesh = tool.commit()
	_hip_roofs[key] = mesh
	return mesh


## Adds one polygon, wound so it faces `outward`.
##
## Godot takes clockwise winding as front-facing, and working that out by hand
## per face is how a roof ends up with two black slopes. Given the direction the
## face is meant to point, the winding follows from a cross product.
static func _face(tool: SurfaceTool, points: Array, outward: Vector3) -> void:
	var ordered := points.duplicate()
	var wound: Vector3 = (ordered[1] - ordered[0]).cross(ordered[2] - ordered[0])
	if wound.dot(outward) > 0.0:
		ordered.reverse()

	var normal := outward.normalized()
	for i in range(1, ordered.size() - 1):
		for vertex in [ordered[0], ordered[i], ordered[i + 1]]:
			tool.set_normal(normal)
			tool.add_vertex(vertex)


## A pitched roof over `rect`, sitting on top of a wall that reaches `base_y`.
## `overhang` is the eaves, which are most of what reads as "roof" from above.
static func add_roof(
	parent: Node3D,
	node_name: String,
	rect: Rect2,
	base_y: float,
	height: float,
	material: StandardMaterial3D,
	ridge_ratio: float = 0.4,
	overhang: float = 0.5
) -> MeshInstance3D:
	var footprint := rect.grow(overhang)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	# The ridge runs along the footprint's long axis, which is the only way a
	# pitched roof ever looks right.
	var along_x := footprint.size.x >= footprint.size.y
	mesh_instance.mesh = unit_hip_roof(ridge_ratio)
	mesh_instance.scale = (
		Vector3(footprint.size.x, height, footprint.size.y) if along_x
		else Vector3(footprint.size.y, height, footprint.size.x)
	)
	if not along_x:
		mesh_instance.rotation.y = PI * 0.5
	mesh_instance.position = Vector3(
		footprint.position.x + footprint.size.x * 0.5,
		base_y,
		footprint.position.y + footprint.size.y * 0.5
	)
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance


# --- Vegetation ----------------------------------------------------------

## A tree: trunk, and a canopy of overlapping blobs rather than one sphere.
##
## The single-sphere version read as a lollipop from every angle. Three to five
## offset, unevenly scaled blobs with a little colour drift between them break
## the silhouette, and from an elevated camera that difference is most of what
## makes a street look planted rather than decorated.
static func add_tree(
	parent: Node3D,
	node_name: String,
	spot: Vector3,
	scale_factor: float,
	trunk_material: StandardMaterial3D,
	foliage_materials: Array,
	rng: RandomNumberGenerator,
	solid_trunk: bool = true
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation.y = rng.randf_range(0.0, TAU)
	parent.add_child(holder)

	var trunk_height := 2.6 * scale_factor
	var trunk_radius := 0.19 * scale_factor
	add_cylinder(
		holder, "Trunk", Vector3(0.0, trunk_height * 0.5, 0.0),
		trunk_radius, trunk_height, trunk_material, solid_trunk
	)

	var blobs := rng.randi_range(3, 5)
	var canopy_base := trunk_height * 0.82
	var spread := 1.05 * scale_factor
	for i in blobs:
		# The first blob is the core; the rest hang off it.
		var offset := Vector3.ZERO
		var size := 2.5 * scale_factor
		if i > 0:
			var angle := TAU * (float(i) / float(blobs)) + rng.randf_range(-0.4, 0.4)
			offset = Vector3(
				cos(angle) * spread * rng.randf_range(0.5, 1.0),
				rng.randf_range(-0.35, 0.75) * scale_factor,
				sin(angle) * spread * rng.randf_range(0.5, 1.0)
			)
			size = rng.randf_range(1.5, 2.3) * scale_factor
		add_sphere(
			holder,
			"Canopy%d" % i,
			Vector3(offset.x, canopy_base + size * 0.42 + offset.y, offset.z),
			Vector3(size, size * rng.randf_range(0.78, 1.02), size),
			foliage_materials[rng.randi_range(0, foliage_materials.size() - 1)]
		)
	return holder


## A slack cable between two points, as a few straight segments following a
## parabola. Overhead wires are one of the strongest cues that a street is a
## real street rather than a diagram, and a dead-straight line between two poles
## does not read as a cable at all — the sag is the whole effect.
static func add_wire(
	parent: Node3D,
	node_name: String,
	from: Vector3,
	to: Vector3,
	sag: float,
	thickness: float,
	material: StandardMaterial3D,
	segments: int = 4
) -> void:
	var previous := from
	for step in range(1, segments + 1):
		var t := float(step) / float(segments)
		var point := from.lerp(to, t)
		# Parabola: zero at both ends, `sag` at the middle.
		point.y -= sag * 4.0 * t * (1.0 - t)
		var middle := (previous + point) * 0.5
		var span := point - previous

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "%s_%d" % [node_name, step]
		mesh_instance.mesh = unit_box()
		mesh_instance.scale = Vector3(thickness, thickness, span.length())
		mesh_instance.position = middle
		mesh_instance.look_at_from_position(middle, point, Vector3.UP)
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh_instance)
		previous = point


## A run of clipped hedge, as overlapping squashed blobs. Softens the hard edge
## of a lawn slab, which from above is otherwise a painted rectangle.
static func add_hedge(
	parent: Node3D,
	node_name: String,
	from: Vector2,
	to: Vector2,
	height: float,
	material: StandardMaterial3D,
	rng: RandomNumberGenerator
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	parent.add_child(holder)

	var length := from.distance_to(to)
	var steps := maxi(1, int(round(length / (height * 0.75))))
	for step in steps + 1:
		var flat := from.lerp(to, float(step) / float(steps))
		var size := height * rng.randf_range(0.92, 1.18)
		add_sphere(
			holder,
			"Bush%d" % step,
			Vector3(
				flat.x + rng.randf_range(-0.12, 0.12),
				size * 0.34,
				flat.y + rng.randf_range(-0.12, 0.12)
			),
			Vector3(size * 1.25, size, size * 1.25),
			material
		)
	return holder


## Builds a rectangle from min/max corners on the XZ plane.
static func rect_from_bounds(min_x: float, min_z: float, max_x: float, max_z: float) -> Rect2:
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


## Attaches a spherical interaction volume to `parent` at `local_position`.
## The caller supplies the already-configured Interactable so this stays free of
## any knowledge about what the interaction actually does.
static func attach_interactable(
	parent: Node3D, interactable: Interactable, local_position: Vector3, radius: float = 2.4
) -> Interactable:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var collider := CollisionShape3D.new()
	collider.name = "Volume"
	collider.shape = shape

	interactable.position = local_position
	parent.add_child(interactable)
	interactable.add_child(collider)
	return interactable
