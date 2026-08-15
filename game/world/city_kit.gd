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
static func add_box(
	parent: Node3D,
	node_name: String,
	center: Vector3,
	size: Vector3,
	material: StandardMaterial3D,
	solid: bool = true,
	cast_shadow: bool = true
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
	body.collision_layer = 1
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
	cast_shadow: bool = true
) -> Node3D:
	var center := Vector3(
		rect.position.x + rect.size.x * 0.5,
		base_y + height * 0.5,
		rect.position.y + rect.size.y * 0.5
	)
	var size := Vector3(rect.size.x, height, rect.size.y)
	return add_box(parent, node_name, center, size, material, solid, cast_shadow)


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
