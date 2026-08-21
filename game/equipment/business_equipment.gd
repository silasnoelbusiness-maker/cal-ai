class_name BusinessEquipment
extends Node3D
## A piece of business equipment standing in a shop.
##
## The node is a view onto a PlacedEquipment record, not the thing itself — see
## that class for why. It builds itself from the EquipmentData, keeps its
## appearance in step with what is on it, and carries whatever interaction its
## role implies: a shelf is managed, a counter is worked, a rack opens the store
## room.

signal register_requested(equipment: BusinessEquipment)

const GROUP := &"business_equipment"

var business: BusinessInstance = null
var placed: PlacedEquipment = null
var unit: Node3D = null

var _definition: EquipmentData = null
var _interactable: Interactable = null
var _goods: Node3D = null
## Customers using this right now: people at a table, on a machine, on the
## floor. Kept on the node rather than in the record because it is a fact about
## the room the player is standing in, not about the business.
var occupants: int = 0


## Builds the whole object. Called once, straight after instancing.
func setup(
	owner_business: BusinessInstance, record: PlacedEquipment, owner_unit: Node3D = null
) -> void:
	business = owner_business
	placed = record
	unit = owner_unit
	_definition = record.data()
	if _definition == null:
		push_error("Placed equipment '%s' has no definition." % record.equipment_id)
		return

	add_to_group(GROUP)
	position = record.position
	rotation.y = record.rotation_y
	_build_body()
	_build_interactable()
	refresh()


## Places for customers this piece offers, from its definition.
func customer_slots() -> int:
	return _definition.customer_slots if _definition != null else 0


func free_slots() -> int:
	return maxi(customer_slots() - occupants, 0)


func has_room() -> bool:
	return free_slots() > 0


func take_slot() -> bool:
	if not has_room():
		return false
	occupants += 1
	return true


func release_slot() -> void:
	occupants = maxi(occupants - 1, 0)


func role() -> int:
	return int(_definition.role) if _definition != null else -1


func is_role(value: int) -> bool:
	return _definition != null and int(_definition.role) == value


func slot_id() -> int:
	return placed.slot_id if placed != null else -1


func is_checkout() -> bool:
	return placed != null and placed.is_checkout()


func is_shelf() -> bool:
	return placed != null and placed.is_shelf()


## Where a person stands to use this: a stride in front of it, on the side the
## equipment faces. Customers queue here and the cashier stands opposite.
func service_point() -> Vector3:
	var forward := -global_transform.basis.z
	return global_position + forward * (_definition.placement_size.y * 0.5 + 0.9)


func staff_point() -> Vector3:
	var forward := -global_transform.basis.z
	return global_position - forward * (_definition.placement_size.y * 0.5 + 0.8)


## Somewhere a person walking over from `origin` can actually stand next to this.
##
## Not simply "in front of it": the player can turn a shelf any way they like and
## push it against a wall, and walking at the far side of it wedges people
## against the thing they are trying to reach. Four sides are offered, the
## nearest one that is on open floor wins.
func approach_point_from(origin: Vector3) -> Vector3:
	var reach_x := _definition.placement_size.x * 0.5 + 0.85
	var reach_z := _definition.placement_size.y * 0.5 + 0.85
	var sides := [
		Vector3(0.0, 0.0, reach_z), Vector3(0.0, 0.0, -reach_z),
		Vector3(reach_x, 0.0, 0.0), Vector3(-reach_x, 0.0, 0.0),
	]
	return _best_side(origin, sides, service_point())


## The way in behind a counter: round one end rather than over the top of it.
## Which end depends on where the member of staff is coming from.
func staff_approach_from(origin: Vector3) -> Vector3:
	var along := global_transform.basis.x.normalized() * (_definition.placement_size.x * 0.5 + 0.95)
	var behind := staff_point()
	# Local offsets, because that is what _best_side puts back through the
	# transform. Passing a *difference* of two local points instead would land
	# both candidates on top of the counter, which is exactly where nobody can
	# stand.
	return _best_side(origin, [to_local(behind + along), to_local(behind - along)], behind)


## Picks a spot to stand from a set of offsets.
##
## Two things matter and in this order: the spot has to be on open floor, and
## there has to be a clear line to it. Nearest-first alone walks people into the
## very counter they are trying to get behind, because the near side of it is
## exactly the wrong side.
func _best_side(origin: Vector3, offsets: Array, fallback: Vector3) -> Vector3:
	var best := fallback
	var best_score := INF
	for offset in offsets:
		var point: Vector3 = global_transform * (offset as Vector3)
		if not _on_open_floor(point):
			continue
		var distance := origin.distance_to(point)
		# A blocked route is not disqualifying — it may be the only way in — but
		# it loses to any clear one.
		var score := distance + (0.0 if _has_clear_line(origin, point) else 100.0)
		if score < best_score:
			best_score = score
			best = point
	return best


func _on_open_floor(point: Vector3) -> bool:
	if unit == null or not unit.has_method("is_inside_floor"):
		return true
	return bool(unit.call("is_inside_floor", unit.to_local(point)))


## Whether somebody could walk straight there without meeting a wall or a
## counter. Waist height, on the world layer, which is what equipment and walls
## both collide on.
func _has_clear_line(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		from + Vector3.UP * 0.9, to + Vector3.UP * 0.9
	)
	query.collision_mask = 1
	return space.intersect_ray(query).is_empty()


# --- Appearance ----------------------------------------------------------

func _build_body() -> void:
	var size := _definition.placement_size
	var body := CityKit.make_material(_definition.body_color)
	var accent := CityKit.make_material(_definition.accent_color)

	match _definition.role:
		EquipmentData.Role.CHECKOUT:
			CityKit.add_box(
				self, "Desk", Vector3(0.0, _definition.height * 0.5, 0.0),
				Vector3(size.x, _definition.height, size.y), body
			)
			CityKit.add_box(
				self, "Worktop", Vector3(0.0, _definition.height + 0.03, 0.0),
				Vector3(size.x + 0.2, 0.08, size.y + 0.12), accent, false
			)
			CityKit.add_box(
				self, "Till", Vector3(-size.x * 0.28, _definition.height + 0.24, 0.0),
				Vector3(0.7, 0.35, 0.5),
				CityKit.make_material(Color(0.220, 0.235, 0.259), 0.5, 0.3), false
			)
		EquipmentData.Role.STORAGE:
			CityKit.add_box(
				self, "Frame", Vector3(0.0, _definition.height * 0.5, 0.0),
				Vector3(size.x, _definition.height, size.y), body
			)
			for level in 3:
				CityKit.add_box(
					self, "Shelf%d" % level,
					Vector3(0.0, 0.45 + float(level) * 0.6, 0.0),
					Vector3(size.x + 0.1, 0.06, size.y + 0.08), accent, false, false
				)
		EquipmentData.Role.SEATING:
			_build_seating(size, body, accent)
		EquipmentData.Role.MACHINE:
			_build_machine(size, body, accent)
		EquipmentData.Role.BAR, EquipmentData.Role.PASS, EquipmentData.Role.RECEPTION:
			_build_counter(size, body, accent)
		EquipmentData.Role.COOK_STATION:
			_build_cook_station(size, body, accent)
		EquipmentData.Role.DANCE_FLOOR:
			_build_dance_floor(size, body, accent)
		EquipmentData.Role.DJ_BOOTH, EquipmentData.Role.LIGHTING:
			_build_rig(size, body, accent)
		_:
			CityKit.add_box(
				self, "Unit", Vector3(0.0, _definition.height * 0.5, 0.0),
				Vector3(size.x, _definition.height, size.y), body
			)

	_goods = Node3D.new()
	_goods.name = "Goods"
	_goods.position = Vector3(0.0, _definition.height + 0.12, 0.0)
	add_child(_goods)


## A table: a top, four legs and a chair per seat.
##
## Phase K's rule is that a room should read from above without a label, and a
## single box does not read as anything. These are still primitives — the whole
## city is — but a table with legs and chairs round it is a table, and a box is
## a box.
func _build_seating(size: Vector2, body: StandardMaterial3D, accent: StandardMaterial3D) -> void:
	var top := _definition.height
	CityKit.add_box(
		self, "Top", Vector3(0.0, top - 0.04, 0.0),
		Vector3(size.x, 0.08, size.y), accent
	)
	var leg_x := size.x * 0.5 - 0.12
	var leg_z := size.y * 0.5 - 0.12
	var corners := [
		Vector3(-leg_x, 0.0, -leg_z), Vector3(leg_x, 0.0, -leg_z),
		Vector3(-leg_x, 0.0, leg_z), Vector3(leg_x, 0.0, leg_z),
	]
	for i in corners.size():
		var corner: Vector3 = corners[i]
		CityKit.add_box(
			self, "Leg%d" % i, Vector3(corner.x, (top - 0.08) * 0.5, corner.z),
			Vector3(0.09, top - 0.08, 0.09), body, false, false
		)
	# One chair per seat, round the edge, facing in.
	var seats := maxi(_definition.customer_slots, 1)
	var radius := maxf(size.x, size.y) * 0.5 + 0.34
	for i in seats:
		var angle := TAU * float(i) / float(seats)
		CityKit.add_box(
			self, "Chair%d" % i,
			Vector3(sin(angle) * radius, 0.22, cos(angle) * radius),
			Vector3(0.42, 0.44, 0.42), body, false, false
		)
		CityKit.add_box(
			self, "ChairBack%d" % i,
			Vector3(sin(angle) * (radius + 0.16), 0.52, cos(angle) * (radius + 0.16)),
			Vector3(0.42, 0.46, 0.10), accent, false, false
		)


## A gym machine: a footprint, an upright and something to hold.
func _build_machine(size: Vector2, body: StandardMaterial3D, accent: StandardMaterial3D) -> void:
	CityKit.add_box(
		self, "Base", Vector3(0.0, 0.09, 0.0), Vector3(size.x, 0.18, size.y), body
	)
	CityKit.add_box(
		self, "Upright", Vector3(0.0, _definition.height * 0.5, -size.y * 0.32),
		Vector3(size.x * 0.28, _definition.height, 0.16), body, false
	)
	CityKit.add_box(
		self, "Grip", Vector3(0.0, _definition.height - 0.08, -size.y * 0.14),
		Vector3(size.x * 0.7, 0.09, 0.09), accent, false, false
	)
	CityKit.add_box(
		self, "Pad", Vector3(0.0, 0.3, size.y * 0.14),
		Vector3(size.x * 0.5, 0.14, size.y * 0.45), accent, false, false
	)


## A counter people are served across: a body, a worktop and a back gantry.
func _build_counter(size: Vector2, body: StandardMaterial3D, accent: StandardMaterial3D) -> void:
	CityKit.add_box(
		self, "Body", Vector3(0.0, _definition.height * 0.5, 0.0),
		Vector3(size.x, _definition.height, size.y), body
	)
	CityKit.add_box(
		self, "Worktop", Vector3(0.0, _definition.height + 0.03, 0.0),
		Vector3(size.x + 0.18, 0.08, size.y + 0.12), accent, false
	)
	CityKit.add_box(
		self, "Gantry", Vector3(0.0, _definition.height + 0.42, -size.y * 0.4),
		Vector3(size.x * 0.9, 0.06, 0.12), accent, false, false
	)


## A stove: a body, hob plates and an extractor above it.
func _build_cook_station(
	size: Vector2, body: StandardMaterial3D, accent: StandardMaterial3D
) -> void:
	CityKit.add_box(
		self, "Range", Vector3(0.0, _definition.height * 0.45, 0.0),
		Vector3(size.x, _definition.height * 0.9, size.y), body
	)
	for i in 4:
		CityKit.add_box(
			self, "Hob%d" % i,
			Vector3(
				-size.x * 0.3 + float(i % 2) * size.x * 0.6, _definition.height * 0.92,
				-size.y * 0.18 + float(i / 2) * size.y * 0.36
			),
			Vector3(0.34, 0.04, 0.34), accent, false, false
		)
	CityKit.add_box(
		self, "Extractor", Vector3(0.0, _definition.height + 0.75, 0.0),
		Vector3(size.x + 0.2, 0.24, size.y + 0.2), body, false, false
	)


## A marked-out stretch of floor with a lit edge.
func _build_dance_floor(
	size: Vector2, body: StandardMaterial3D, _accent: StandardMaterial3D
) -> void:
	CityKit.add_box(
		self, "Floor", Vector3(0.0, 0.02, 0.0), Vector3(size.x, 0.04, size.y), body, false, false
	)
	var glow := CityKit.make_emissive_material(_definition.accent_color, 1.1)
	for i in 4:
		var along := i % 2 == 0
		var sign_of := 1.0 if i < 2 else -1.0
		CityKit.add_box(
			self, "Edge%d" % i,
			Vector3(
				0.0 if along else sign_of * size.x * 0.5,
				0.05, sign_of * size.y * 0.5 if along else 0.0
			),
			Vector3(size.x if along else 0.10, 0.06, 0.10 if along else size.y),
			glow, false, false
		)


## A booth or a light rig: a dark body with something lit on it.
func _build_rig(size: Vector2, body: StandardMaterial3D, _accent: StandardMaterial3D) -> void:
	CityKit.add_box(
		self, "Body", Vector3(0.0, _definition.height * 0.5, 0.0),
		Vector3(size.x, _definition.height, size.y), body
	)
	CityKit.add_box(
		self, "Lamps", Vector3(0.0, _definition.height + 0.06, 0.0),
		Vector3(size.x * 0.8, 0.10, size.y * 0.6),
		CityKit.make_emissive_material(_definition.accent_color, 1.6), false, false
	)


## How full a shelf looks, in blocks the colour of whatever is on it. Rebuilt on
## change rather than scaled, because "four boxes left" reads from above and a
## progress bar does not.
func refresh() -> void:
	if _goods == null or placed == null:
		return
	for child in _goods.get_children():
		child.queue_free()

	_refresh_prompt()
	if not placed.is_shelf() or placed.stock_quantity <= 0:
		return

	var item := placed.item()
	if item == null:
		return
	var capacity := maxi(placed.capacity(), 1)
	var columns := 5
	var filled := clampi(
		ceili(float(placed.stock_quantity) / float(capacity) * float(columns)), 1, columns
	)
	var material := CityKit.make_material(item.icon_color, 0.8)
	var spacing := _definition.placement_size.x / float(columns)
	for i in filled:
		CityKit.add_box(
			_goods, "Stack%d" % i,
			Vector3(-_definition.placement_size.x * 0.5 + spacing * (float(i) + 0.5), 0.0, 0.0),
			Vector3(spacing * 0.7, 0.24, _definition.placement_size.y * 0.6),
			material, false, false
		)


# --- Interaction ---------------------------------------------------------

func _build_interactable() -> void:
	_interactable = Interactable.new()
	_interactable.focus_priority = 1
	_interactable.interacted.connect(_on_interacted)
	CityKit.attach_interactable(
		self, _interactable, Vector3(0.0, 0.9, _definition.placement_size.y * 0.5 + 0.7), 1.6
	)
	_refresh_prompt()


## What standing in front of a piece of equipment offers.
##
## Phase H had two answers and a fall-through to "Manage Shelf", which was fine
## while everything was either a till, a stock room or a shelf. It is not fine
## in a restaurant: a dining table is not a shelf, and being told to manage one
## is the interface lying about what the object is.
func _refresh_prompt() -> void:
	if _interactable == null or placed == null:
		return
	match _definition.role:
		EquipmentData.Role.SHELF:
			var item := placed.item()
			_interactable.prompt_action = "Manage Shelf"
			_interactable.prompt_subtitle = (
				"empty" if item == null
				else "%s  %d / %d" % [item.display_name, placed.stock_quantity, placed.capacity()]
			)
		EquipmentData.Role.CHECKOUT, EquipmentData.Role.PASS, EquipmentData.Role.BAR, \
		EquipmentData.Role.RECEPTION:
			_interactable.prompt_action = "Work Here"
			_interactable.prompt_subtitle = business.business_name if business != null else ""
		EquipmentData.Role.STORAGE, EquipmentData.Role.COLD_STORE:
			_interactable.prompt_action = "Store Room"
			_interactable.prompt_subtitle = "%d / %d units" % [
				business.storage_used(), business.storage_capacity()
			] if business != null else ""
		EquipmentData.Role.SEATING, EquipmentData.Role.MACHINE, \
		EquipmentData.Role.DANCE_FLOOR:
			_interactable.prompt_action = _definition.display_name
			_interactable.prompt_subtitle = "%d of %d in use" % [
				occupants, maxi(_definition.customer_slots, 1)
			]
		_:
			# Cook stations, booths, rigs, doors: things staff work at rather
			# than things the player operates. The dashboard is where they are
			# managed, so that is where the prompt goes.
			_interactable.prompt_action = _definition.display_name
			_interactable.prompt_subtitle = business.business_name if business != null else ""


func _on_interacted(interactor: Node3D) -> void:
	match _definition.role:
		EquipmentData.Role.SHELF:
			GameManager.request_screen(&"shelf", self, interactor)
		EquipmentData.Role.CHECKOUT, EquipmentData.Role.PASS, EquipmentData.Role.BAR, \
		EquipmentData.Role.RECEPTION:
			register_requested.emit(self)
		_:
			GameManager.request_screen(&"business", self, interactor)
