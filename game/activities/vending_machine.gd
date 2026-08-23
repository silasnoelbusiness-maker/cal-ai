class_name VendingMachine
extends Shop
## A drinks machine on the pavement.
##
## The corner shop shuts. The machine does not, which is the whole reason it
## exists: at four in the morning, halfway through a delivery run, there is
## somewhere to get a coffee. It charges for the privilege.
##
## A Shop rather than a new kind of thing, because everything a machine needs —
## stock, prices, the buying screen — a shop already had. What it does not have
## is a till worth robbing, so it is not robbable and never will be.

const MARKUP := 1.4
const MESH_SIZE := Vector3(0.9, 1.9, 0.6)


func _init() -> void:
	super()
	shop_name = "Vending machine"
	prompt_action = "Use machine"
	opens_hour = 0
	closes_hour = 24
	price_multiplier = MARKUP
	robbable = false


## Builds the box, its glass front and its light. Placed by the district at a
## point on the pavement; everything about how it looks is here so a second
## machine is one line in the district table.
func build_body(colour: Color) -> void:
	var box := MeshInstance3D.new()
	box.name = "Body"
	var mesh := BoxMesh.new()
	mesh.size = MESH_SIZE
	box.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.55
	box.material_override = material
	box.position = Vector3(0.0, MESH_SIZE.y * 0.5, 0.0)
	add_child(box)

	var glass := MeshInstance3D.new()
	glass.name = "Front"
	var pane := BoxMesh.new()
	pane.size = Vector3(MESH_SIZE.x * 0.72, MESH_SIZE.y * 0.6, 0.06)
	glass.mesh = pane
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.86, 0.92, 0.78)
	lit.emission_enabled = true
	lit.emission = Color(0.86, 0.92, 0.78)
	# Bright enough to be a landmark on an empty street at night, dim enough
	# not to light the pavement like a streetlamp.
	lit.emission_energy_multiplier = 1.6
	glass.material_override = lit
	glass.position = Vector3(0.0, MESH_SIZE.y * 0.58, MESH_SIZE.z * 0.5 + 0.03)
	add_child(glass)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(2.4, 2.2, 2.4)
	shape.shape = box_shape
	shape.position = Vector3(0.0, 1.1, 0.0)
	add_child(shape)

	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(0.88, 0.94, 0.8)
	glow.light_energy = 0.8
	glow.omni_range = 5.0
	glow.position = Vector3(0.0, 1.6, 0.6)
	add_child(glow)
