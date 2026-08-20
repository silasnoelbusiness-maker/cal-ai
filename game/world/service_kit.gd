class_name ServiceKit
extends RefCounted
## Builds the two things a car owner needs that are not a dealership: somewhere
## to keep it and somewhere to get it fixed.
##
## Both districts get one of each, and both are the same construction with
## different numbers, so this is one builder rather than two nearly-identical
## passes through the district scripts. Both are open-fronted structures on the
## ground rather than interiors: the player drives up to them, which is the
## whole point of them being places at all.


## An open-fronted garage: three walls, no roof, and one marked bay per space.
##
## `front_z` is the open side, `bay_yaw` the way a car in a bay faces. Returns
## the GarageProperty, with its bay transforms already filled in, for the
## district to add to its interactables.
static func build_garage(
	geometry: Node3D, props: Node3D, garage_name: String, rect: Rect2, front_z: float,
	capacity: int, bay_yaw: float, materials: Dictionary
) -> GarageProperty:
	var holder := Node3D.new()
	holder.name = garage_name
	props.add_child(holder)

	var wall: StandardMaterial3D = materials.get("wall", CityKit.make_material(Color(0.478, 0.482, 0.494)))
	var trim: StandardMaterial3D = materials.get("trim", CityKit.make_material(Color(0.243, 0.259, 0.290)))
	var deck: StandardMaterial3D = materials.get("deck", CityKit.make_material(Color(0.243, 0.247, 0.259)))

	var height := 4.0
	var depth_sign := signf(front_z - rect.get_center().y)
	var back_z := rect.end.y if depth_sign < 0.0 else rect.position.y

	# The apron in front, so a car is standing on tarmac rather than on grass.
	var apron := CityKit.rect_from_bounds(
		rect.position.x - 1.0, minf(front_z, front_z + depth_sign * 9.0) ,
		rect.end.x + 1.0, maxf(front_z, front_z + depth_sign * 9.0)
	)
	CityKit.add_slab(geometry, "%sApron" % garage_name, apron, 0.005, 0.02, deck, false, false)

	# Three walls. The front is left open, which is what makes the bays visible
	# from the street with nothing to open or walk through.
	var t := 0.35
	CityKit.add_slab(
		holder, "Back", CityKit.rect_from_bounds(rect.position.x, back_z - t * 0.5, rect.end.x, back_z + t * 0.5),
		0.0, height, wall
	)
	for side: float in [-1.0, 1.0]:
		var x := rect.position.x if side < 0.0 else rect.end.x
		CityKit.add_slab(
			holder, "Side%d" % int(side),
			CityKit.rect_from_bounds(x - t * 0.5, rect.position.y, x + t * 0.5, rect.end.y),
			0.0, height, wall
		)
	# Deliberately no roof, only a parapet round the top of the walls. Every
	# interior in this game is open to the sky for the same reason: the camera
	# looks down, and a garage you cannot see into is a garage that might as
	# well be a menu.
	for edge: Rect2 in [
		CityKit.rect_from_bounds(rect.position.x - 0.4, rect.position.y - 0.4, rect.end.x + 0.4, rect.position.y),
		CityKit.rect_from_bounds(rect.position.x - 0.4, rect.end.y, rect.end.x + 0.4, rect.end.y + 0.4),
		CityKit.rect_from_bounds(rect.position.x - 0.4, rect.position.y, rect.position.x, rect.end.y),
		CityKit.rect_from_bounds(rect.end.x, rect.position.y, rect.end.x + 0.4, rect.end.y),
	]:
		CityKit.add_slab(holder, "Parapet%d_%d" % [int(edge.position.x), int(edge.position.y)],
			edge, height, 0.35, trim, false)
	# A lit fascia over the opening, so it reads at night.
	CityKit.add_box(
		holder, "Fascia",
		Vector3(rect.get_center().x, height - 0.55, front_z),
		Vector3(rect.size.x, 0.7, 0.18),
		CityKit.make_emissive_material(Color(0.898, 0.867, 0.729), 0.5), false, false
	)

	var garage := GarageProperty.new()
	garage.name = garage_name

	# One bay per space, evenly across the opening, each with its lines painted.
	var bays: Array[Transform3D] = []
	for i in capacity:
		var x := rect.position.x + rect.size.x * (float(i) + 0.5) / float(capacity)
		var z := front_z - depth_sign * 3.4
		var bay_rect := CityKit.rect_from_bounds(x - 1.5, minf(z, back_z) + 0.4, x + 1.5, maxf(z, back_z) - 0.4)
		CityKit.add_slab(
			geometry, "%sBayMark%d" % [garage_name, i], bay_rect, 0.026, 0.012,
			CityKit.make_material(Color(0.847, 0.847, 0.831)), false, false
		)
		var spot := Transform3D(Basis(Vector3.UP, deg_to_rad(bay_yaw)), Vector3(x, 0.4, z))
		bays.append(spot)
	garage.bay_transforms = bays
	return garage


## A repair shop: a workshop box, a service bay outside it and the sign over it.
## The player brings the car; the interaction is at the bay, not in an office.
static func build_repair_shop(
	geometry: Node3D, props: Node3D, shop_name: String, rect: Rect2, front_z: float,
	materials: Dictionary
) -> RepairShop:
	var holder := Node3D.new()
	holder.name = shop_name
	props.add_child(holder)

	var wall: StandardMaterial3D = materials.get("wall", CityKit.make_material(Color(0.514, 0.478, 0.435)))
	var trim: StandardMaterial3D = materials.get("trim", CityKit.make_material(Color(0.243, 0.259, 0.290)))
	var deck: StandardMaterial3D = materials.get("deck", CityKit.make_material(Color(0.243, 0.247, 0.259)))

	var height := 5.0
	var depth_sign := signf(front_z - rect.get_center().y)

	CityKit.add_slab(
		geometry, "%sApron" % shop_name,
		CityKit.rect_from_bounds(
			rect.position.x - 1.0, minf(front_z, front_z + depth_sign * 11.0),
			rect.end.x + 1.0, maxf(front_z, front_z + depth_sign * 11.0)
		),
		0.005, 0.02, deck, false, false
	)
	CityKit.add_slab(holder, "Workshop", rect, 0.0, height, wall)
	CityKit.add_slab(holder, "Parapet", rect.grow(0.3), height, 0.4, trim, false)

	# Two roller-shutter openings on the front face, which is what says workshop
	# rather than warehouse.
	for i in 2:
		var x := rect.position.x + rect.size.x * (float(i) + 0.5) / 2.0
		CityKit.add_box(
			holder, "Shutter%d" % i, Vector3(x, 1.9, front_z - depth_sign * 0.18),
			Vector3(rect.size.x * 0.34, 3.8, 0.22), trim, false, false
		)
		CityKit.add_box(
			holder, "ShutterSlats%d" % i, Vector3(x, 1.9, front_z - depth_sign * 0.30),
			Vector3(rect.size.x * 0.30, 3.5, 0.06),
			CityKit.make_material(Color(0.596, 0.612, 0.639), 0.6, 0.3), false, false
		)
	CityKit.add_box(
		holder, "Sign", Vector3(rect.get_center().x, height + 0.9, front_z),
		Vector3(rect.size.x * 0.7, 1.1, 0.2),
		CityKit.make_emissive_material(Color(0.918, 0.616, 0.286), 0.7), false, false
	)

	var bay_centre := Vector3(rect.get_center().x, 0.0, front_z - depth_sign * 4.6)
	CityKit.add_slab(
		geometry, "%sServiceBay" % shop_name,
		CityKit.rect_from_bounds(bay_centre.x - 2.8, bay_centre.z - 2.2, bay_centre.x + 2.8, bay_centre.z + 2.2),
		0.026, 0.012, CityKit.make_material(Color(0.878, 0.816, 0.510)), false, false
	)

	var shop := RepairShop.new()
	shop.name = shop_name
	shop.service_point = bay_centre
	return shop
