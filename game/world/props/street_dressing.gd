class_name StreetDressing
extends RefCounted

## Fills a pavement with the things pavements have on them.
##
## The single loudest thing wrong with the city at the Phase T2 camera was not
## the buildings or the cars — it was that half of every frame was blank light
## grey. A real pavement has a planting line, bins, meters, cycle stands, cafe
## tables outside the cafe, utility boxes, signposts and a bus shelter, and the
## eye reads all of that as "city" before it reads any individual object.
##
## Everything here is decorative and non-solid unless it is large enough that
## walking through it would be obvious. §169's rule from Phase T still holds: a
## crowd wedged against a litter bin is a bug the player can see, and one they
## clip through is not something anybody notices from twenty metres up.

## Metres between items along a run. Not a fixed step — see `_stride`.
const BASE_SPACING := 7.5
## How far from the kerb the planting line sits.
const KERB_SETBACK := 1.35
## How far from the building line the frontage zone sits.
const FRONTAGE_SETBACK := 1.15
## How far anything decorative stays from a door, a job station or a shop sign.
const CLEARANCE := 4.5


## Dresses one straight run of pavement.
##
## `from` and `to` are the ends of the kerb line; `inward` points away from the
## road toward the buildings; `depth` is how wide the pavement is. The caller
## owns the geometry, so a district that knows its own street widths gets this
## right without this file knowing anything about the city.
static func dress_run(
	parent: Node3D,
	run_name: String,
	from: Vector3,
	to: Vector3,
	inward: Vector3,
	depth: float,
	rng: RandomNumberGenerator,
	kit: Dictionary,
	keep_clear: Array = []
) -> void:
	var span := from.distance_to(to)
	if span < 6.0 or depth < 1.6:
		return
	var along := (to - from).normalized()
	var holder := Node3D.new()
	holder.name = run_name
	parent.add_child(holder)

	# The planting line: trees and lamps alternate down the kerb, with the gaps
	# between them taking the smaller furniture. Alternating rather than
	# clustering is what stops a street looking like a shop display.
	var at := rng.randf_range(3.0, 6.0)
	var index := 0
	while at < span - 3.0:
		var kerb_point := from + along * at + inward * KERB_SETBACK
		# Seven slots rather than five, and only two of them trees: a planting
		# line where every other item is a tree reads as an avenue, and Central
		# is a commercial street.
		match index % 7:
			0, 3:
				_tree(holder, "%sTree%d" % [run_name, index], kerb_point, rng, kit)
			1, 5:
				_meter(holder, "%sMeter%d" % [run_name, index], kerb_point, along, rng, kit)
			2:
				_bin(holder, "%sBin%d" % [run_name, index], kerb_point, along, rng, kit)
			4:
				_planter(holder, "%sPlanter%d" % [run_name, index], kerb_point, along, rng, kit)
			6:
				_bollards(holder, "%sBollard%d" % [run_name, index], kerb_point, along, rng, kit)
		# A varied stride, so nothing is at mathematically identical spacing.
		at += _stride(rng)
		index += 1

	# The frontage zone against the buildings: benches, cycle stands, utility
	# boxes and signposts. Sparser than the kerb line, because this is the strip
	# people actually walk down.
	if depth > 3.4:
		var back := rng.randf_range(9.0, 15.0)
		var back_index := 0
		while back < span - 6.0:
			var wall_point := from + along * back + inward * (depth - FRONTAGE_SETBACK)
			# Never in front of a door. The frontage zone runs along the
			# building line, which is exactly where every entrance is, and a
			# bench across a shop door is worse than an empty pavement.
			if _blocked(wall_point, keep_clear):
				back += rng.randf_range(6.0, 10.0)
				back_index += 1
				continue
			match back_index % 4:
				0:
					_bench(holder, "%sBench%d" % [run_name, back_index], wall_point, along, rng, kit)
				1:
					_utility(holder, "%sUtility%d" % [run_name, back_index], wall_point, along, rng, kit)
				2:
					_cycles(holder, "%sCycles%d" % [run_name, back_index], wall_point, along, rng, kit)
				3:
					_signpost(holder, "%sSign%d" % [run_name, back_index], wall_point, rng, kit)
			back += rng.randf_range(16.0, 26.0)
			back_index += 1


## Whether this spot is too close to something that must stay reachable.
static func _blocked(at: Vector3, keep_clear: Array) -> bool:
	for point in keep_clear:
		var other: Vector3 = point
		if Vector2(at.x - other.x, at.z - other.z).length() < CLEARANCE:
			return true
	return false


## A varied gap. Real street furniture is placed to a rule and then moved for a
## doorway, a crossing or a drain, so a perfectly even rhythm is the one thing
## that never happens.
static func _stride(rng: RandomNumberGenerator) -> float:
	return BASE_SPACING * rng.randf_range(0.78, 1.34)


static func _yaw(node: Node3D, along: Vector3, rng: RandomNumberGenerator) -> void:
	node.rotation.y = atan2(along.x, along.z) + rng.randf_range(-0.09, 0.09)


static func _tree(
	parent: Node3D, name: String, at: Vector3, rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	# A pit with a kerb round it, then the tree. Street trees grow out of a hole
	# in the paving, and the hole is half of what makes one read as a street
	# tree rather than as a pot plant.
	var pit := CityKit.add_slab(
		parent, name + "Pit",
		CityKit.rect_from_bounds(at.x - 0.72, at.z - 0.72, at.x + 0.72, at.z + 0.72),
		at.y + 0.01, 0.03, kit["soil"], false, false
	)
	for side in [[-0.75, 0.0, 0.10, 1.60], [0.75, 0.0, 0.10, 1.60],
			[0.0, -0.75, 1.60, 0.10], [0.0, 0.75, 1.60, 0.10]]:
		CityKit.add_box(
			parent, "%sKerb%d_%d" % [name, int(side[0] * 10), int(side[1] * 10)],
			Vector3(at.x + float(side[0]), at.y + 0.06, at.z + float(side[1])),
			Vector3(float(side[2]), 0.12, float(side[3])), kit["kerb"], false, false
		)
	CityKit.add_tree(
		parent, name, Vector3(at.x, at.y, at.z), rng.randf_range(0.88, 1.10),
		kit["bark"], kit["foliage"], rng, false, CityKit.TreeKind.STREET
	)


static func _bin(
	parent: Node3D, name: String, at: Vector3, along: Vector3,
	rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	var holder := Node3D.new()
	holder.name = name
	holder.position = at
	_yaw(holder, along, rng)
	parent.add_child(holder)
	CityKit.add_cylinder(holder, "Body", Vector3(0.0, 0.44, 0.0), 0.26, 0.88, kit["metal_dark"], false)
	CityKit.add_cylinder(holder, "Rim", Vector3(0.0, 0.90, 0.0), 0.29, 0.08, kit["metal"], false)
	CityKit.add_cylinder(holder, "Lid", Vector3(0.0, 0.96, 0.0), 0.24, 0.06, kit["metal"], false)
	CityKit.add_box(
		holder, "Post", Vector3(0.0, 0.30, -0.30), Vector3(0.07, 0.60, 0.07),
		kit["metal_dark"], false, false
	)


static func _meter(
	parent: Node3D, name: String, at: Vector3, along: Vector3,
	rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	var holder := Node3D.new()
	holder.name = name
	holder.position = at
	_yaw(holder, along, rng)
	parent.add_child(holder)
	CityKit.add_cylinder(holder, "Post", Vector3(0.0, 0.55, 0.0), 0.055, 1.10, kit["metal_dark"], false)
	CityKit.add_box(
		holder, "Head", Vector3(0.0, 1.22, 0.0), Vector3(0.20, 0.30, 0.14),
		kit["metal"], false, false
	)
	CityKit.add_box(
		holder, "Face", Vector3(0.0, 1.26, -0.08), Vector3(0.13, 0.15, 0.02),
		kit["glass"], false, false
	)


static func _planter(
	parent: Node3D, name: String, at: Vector3, along: Vector3,
	rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	var holder := Node3D.new()
	holder.name = name
	holder.position = at
	_yaw(holder, along, rng)
	parent.add_child(holder)
	CityKit.add_box(
		holder, "Tub", Vector3(0.0, 0.26, 0.0), Vector3(1.20, 0.52, 0.62),
		kit["stone"], false, false
	)
	CityKit.add_box(
		holder, "Lip", Vector3(0.0, 0.54, 0.0), Vector3(1.28, 0.08, 0.70),
		kit["kerb"], false, false
	)
	# Planting: three or four squashed lobes rather than one ball of hedge.
	var lobes := rng.randi_range(3, 4)
	for i in lobes:
		var t := (float(i) / float(lobes - 1)) - 0.5
		CityKit.add_sphere(
			holder, "Shrub%d" % i,
			Vector3(t * 0.80, 0.62 + rng.randf_range(0.0, 0.10), rng.randf_range(-0.10, 0.10)),
			Vector3(0.44, 0.30, 0.40) * rng.randf_range(0.85, 1.20),
			kit["foliage"][rng.randi_range(0, kit["foliage"].size() - 1)]
		)


static func _bench(
	parent: Node3D, name: String, at: Vector3, along: Vector3,
	rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	var holder := DistrictProps.bench(name, at, 0.0, kit["wood"], kit["metal_dark"])
	parent.add_child(holder)
	_yaw(holder, along, rng)


static func _utility(
	parent: Node3D, name: String, at: Vector3, along: Vector3,
	rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	var holder := Node3D.new()
	holder.name = name
	holder.position = at
	_yaw(holder, along, rng)
	parent.add_child(holder)
	var height := rng.randf_range(0.95, 1.35)
	CityKit.add_box(
		holder, "Cabinet", Vector3(0.0, height * 0.5, 0.0),
		Vector3(0.78, height, 0.42), kit["metal"], false, false
	)
	CityKit.add_box(
		holder, "Cap", Vector3(0.0, height + 0.03, 0.0),
		Vector3(0.84, 0.06, 0.48), kit["metal_dark"], false, false
	)
	# A seam down the door, which is the only detail at this size that reads.
	CityKit.add_box(
		holder, "Seam", Vector3(0.0, height * 0.5, -0.22),
		Vector3(0.02, height * 0.86, 0.02), kit["metal_dark"], false, false
	)


static func _cycles(
	parent: Node3D, name: String, at: Vector3, along: Vector3,
	rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	var holder := Node3D.new()
	holder.name = name
	holder.position = at
	_yaw(holder, along, rng)
	parent.add_child(holder)
	for i in 3:
		var x := (float(i) - 1.0) * 0.78
		# An inverted-U stand: two uprights and a crossbar.
		CityKit.add_cylinder(
			holder, "LegA%d" % i, Vector3(x - 0.28, 0.36, 0.0), 0.035, 0.72,
			kit["metal"], false
		)
		CityKit.add_cylinder(
			holder, "LegB%d" % i, Vector3(x + 0.28, 0.36, 0.0), 0.035, 0.72,
			kit["metal"], false
		)
		var bar := CityKit.add_cylinder(
			holder, "Bar%d" % i, Vector3(x, 0.72, 0.0), 0.035, 0.60, kit["metal"], false
		)
		bar.rotation.z = PI * 0.5


## A short row of kerbside bollards. Cheap, and they do more than anything else
## here to describe where the pavement ends and the road begins.
static func _bollards(
	parent: Node3D, name: String, at: Vector3, along: Vector3,
	rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	var holder := Node3D.new()
	holder.name = name
	holder.position = at
	_yaw(holder, along, rng)
	parent.add_child(holder)
	for i in 3:
		var z := (float(i) - 1.0) * 1.45
		CityKit.add_cylinder(
			holder, "Post%d" % i, Vector3(0.0, 0.44, z), 0.075, 0.88,
			kit["metal_dark"], false
		)
		CityKit.add_cylinder(
			holder, "Cap%d" % i, Vector3(0.0, 0.90, z), 0.085, 0.06,
			kit["metal"], false
		)


static func _signpost(
	parent: Node3D, name: String, at: Vector3, rng: RandomNumberGenerator, kit: Dictionary
) -> void:
	var holder := Node3D.new()
	holder.name = name
	holder.position = at
	holder.rotation.y = rng.randf_range(0.0, TAU)
	parent.add_child(holder)
	CityKit.add_cylinder(holder, "Post", Vector3(0.0, 1.30, 0.0), 0.045, 2.60, kit["metal_dark"], false)
	var plates := rng.randi_range(1, 2)
	for i in plates:
		CityKit.add_box(
			holder, "Plate%d" % i,
			Vector3(0.30, 2.22 - float(i) * 0.26, 0.0), Vector3(0.62, 0.18, 0.03),
			kit["metal"], false, false
		)
