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
	var best := service_point()
	var best_distance := INF
	for offset in sides:
		var point: Vector3 = global_transform * offset
		if not _on_open_floor(point):
			continue
		var distance := origin.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


## The way in behind a counter: round one end rather than over the top of it.
## Which end depends on where the member of staff is coming from.
func staff_approach_from(origin: Vector3) -> Vector3:
	var along := global_transform.basis.x.normalized() * (_definition.placement_size.x * 0.5 + 0.95)
	var behind := staff_point()
	var best := behind
	var best_distance := INF
	for point in [behind + along, behind - along]:
		if not _on_open_floor(point):
			continue
		var distance := origin.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


func _on_open_floor(point: Vector3) -> bool:
	if unit == null or not unit.has_method("is_inside_floor"):
		return true
	return bool(unit.call("is_inside_floor", unit.to_local(point)))


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
		_:
			CityKit.add_box(
				self, "Unit", Vector3(0.0, _definition.height * 0.5, 0.0),
				Vector3(size.x, _definition.height, size.y), body
			)

	_goods = Node3D.new()
	_goods.name = "Goods"
	_goods.position = Vector3(0.0, _definition.height + 0.12, 0.0)
	add_child(_goods)


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


func _refresh_prompt() -> void:
	if _interactable == null or placed == null:
		return
	match _definition.role:
		EquipmentData.Role.CHECKOUT:
			_interactable.prompt_action = "Work Register"
			_interactable.prompt_subtitle = business.business_name if business != null else ""
		EquipmentData.Role.STORAGE:
			_interactable.prompt_action = "Store Room"
			_interactable.prompt_subtitle = "%d / %d units" % [
				business.storage_used(), business.storage_capacity()
			] if business != null else ""
		_:
			var item := placed.item()
			_interactable.prompt_action = "Manage Shelf"
			_interactable.prompt_subtitle = (
				"empty" if item == null
				else "%s  %d / %d" % [item.display_name, placed.stock_quantity, placed.capacity()]
			)


func _on_interacted(interactor: Node3D) -> void:
	match _definition.role:
		EquipmentData.Role.CHECKOUT:
			register_requested.emit(self)
		EquipmentData.Role.STORAGE:
			GameManager.request_screen(&"business", self, interactor)
		_:
			GameManager.request_screen(&"shelf", self, interactor)
