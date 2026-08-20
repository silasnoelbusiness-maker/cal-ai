class_name GarageProperty
extends Interactable
## Somewhere to keep a car that is not the street.
##
## A garage is rented, not bought, so it is not an asset and never appears in
## net worth — what it holds is. The bays are real: three cars fit in a
## three-car garage and a fourth is told so, which is what makes the larger one
## on the other side of the city worth its rent.
##
## Deliberately an Interactable rather than a Portal. There is no interior to
## walk into; the player drives up, and the panel is the garage.

signal leased()
signal rent_state_changed()

@export var garage_id: StringName = &"harbour_garage"
@export var display_name: String = "Harbour Garage"
@export var address: String = "Dock Road"
@export var district_id: StringName = &"harbour_row"
## How many cars fit. The bays drawn in the world are built to match, so this
## is the number in both senses.
@export var capacity: int = 3

@export_group("Terms")
@export var rent_amount: int = 260
@export var deposit: int = 300
@export var rent_interval_days: int = 7

@export_group("State")
@export var leased_by_player: bool = false
@export var next_rent_due_day: int = -1
@export var arrears: int = 0
@export var save_id: StringName = &""

## Where a retrieved car is put down, in order. Set by whoever builds the
## garage, because only it knows where its bays are.
var bay_transforms: Array[Transform3D] = []


static func all(tree: SceneTree) -> Array[GarageProperty]:
	var found: Array[GarageProperty] = []
	for node in tree.get_nodes_in_group(&"garage"):
		var garage := node as GarageProperty
		if garage != null:
			found.append(garage)
	return found


static func by_id(tree: SceneTree, id: StringName) -> GarageProperty:
	for garage in all(tree):
		if garage.garage_id == id:
			return garage
	return null


## How close the player has to be for the stored cars to be drawn in their bays.
const VIEW_RANGE := 70.0

## The cars drawn in the bays, keyed by instance id. Pictures, not vehicles —
## the real car is a record with no node while it is in here.
var _bay_props: Dictionary = {}
var _view_timer: float = 0.0


func _ready() -> void:
	if save_id == &"":
		save_id = StringName("garage_%s" % garage_id)
	add_to_group(&"garage")
	add_to_group(&"saveable")
	if leased_by_player and next_rent_due_day < 0:
		next_rent_due_day = TimeManager.day_index + rent_interval_days
	_refresh_prompt()
	set_process(true)


## Keeps what is drawn in the bays matching what is actually stored. A garage
## the player is nowhere near draws nothing, which is the whole reason storing a
## car is cheaper than leaving it out.
func _process(delta: float) -> void:
	_view_timer -= delta
	if _view_timer > 0.0:
		return
	_view_timer = 0.5

	var player := GameManager.player
	var in_view := (
		leased_by_player and player != null
		and player.global_position.distance_to(global_position) <= VIEW_RANGE
	)
	var wanted: Dictionary = {}
	if in_view:
		var stored := VehicleRegistry.stored_in(garage_id)
		for i in stored.size():
			wanted[stored[i].instance_id] = i

	for id: StringName in _bay_props.keys():
		if not wanted.has(id):
			var prop: Node = _bay_props[id]
			if is_instance_valid(prop):
				prop.queue_free()
			_bay_props.erase(id)

	for id: StringName in wanted:
		if _bay_props.has(id) and is_instance_valid(_bay_props[id]):
			continue
		var record := VehicleRegistry.by_id(id)
		if record == null:
			continue
		_bay_props[id] = _draw_bay_car(record, int(wanted[id]))


func _draw_bay_car(record: OwnedVehicle, bay_index: int) -> Node3D:
	var scene := VehicleCatalogue.scene_for(record.model_id)
	if scene == null:
		return null
	var car: Vehicle = scene.instantiate()
	car.name = "Bay_%s" % record.instance_id
	car.display_only = true
	var tinted: VehicleData = car.data.duplicate()
	tinted.body_color = record.paint_color
	car.data = tinted
	var spot := bay_for(bay_index)
	get_parent().add_child(car)
	car.global_transform = spot
	return car


func is_leased_by_player() -> bool:
	return leased_by_player


func move_in_cost() -> int:
	return deposit + rent_amount


func used_bays() -> int:
	return VehicleRegistry.stored_in(garage_id).size()


func free_bays() -> int:
	return maxi(capacity - used_bays(), 0)


func is_full() -> bool:
	return free_bays() <= 0


func occupancy_label() -> String:
	return "%d / %d VEHICLES" % [used_bays(), capacity]


## Where the next car out should be put down. Bays are used in order, and a
## garage whose bays somehow ran out puts the car at its own door rather than
## refusing to give it back.
func bay_for(index: int) -> Transform3D:
	if bay_transforms.is_empty():
		return Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, 0.4, 4.0))
	return bay_transforms[clampi(index, 0, bay_transforms.size() - 1)]


func next_free_bay() -> Transform3D:
	return bay_for(used_bays())


# --- Rent ----------------------------------------------------------------

func is_rent_due() -> bool:
	return leased_by_player and next_rent_due_day >= 0 and TimeManager.day_index >= next_rent_due_day


## Rent going unpaid never costs the player a car. The garage says so and keeps
## saying so; what an unpaid bill eventually leads to is a later problem, and
## seizing a $100,000 vehicle over $260 would be a worse game than not.
func settle_rent(paid: bool) -> void:
	next_rent_due_day = TimeManager.day_index + rent_interval_days
	if not paid:
		arrears += rent_amount
	else:
		arrears = 0
	_refresh_prompt()
	rent_state_changed.emit()


func is_overdue() -> bool:
	return arrears > 0


func begin_lease() -> void:
	leased_by_player = true
	next_rent_due_day = TimeManager.day_index + rent_interval_days
	arrears = 0
	_refresh_prompt()
	leased.emit()


## Gives it up. Anything still inside comes out onto the forecourt first —
## ending a lease must never be a way to lose a car.
func end_lease() -> void:
	for record in VehicleRegistry.stored_in(garage_id):
		VehicleRegistry.retrieve(record, next_free_bay())
	leased_by_player = false
	next_rent_due_day = -1
	arrears = 0
	_refresh_prompt()


# --- Interaction ---------------------------------------------------------

func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"garage", self, interactor)


func _refresh_prompt() -> void:
	prompt_action = "Garage" if leased_by_player else "View Garage"
	var detail := display_name
	if leased_by_player:
		detail += "  ·  %s" % occupancy_label()
		if is_overdue():
			detail += "  ·  RENT OVERDUE"
	else:
		detail += "  ·  TO LET"
	prompt_subtitle = detail


func refresh() -> void:
	_refresh_prompt()


func get_prompt_text() -> String:
	_refresh_prompt()
	return super.get_prompt_text()


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"leased": leased_by_player,
		"next_rent_due_day": next_rent_due_day,
		"arrears": arrears,
	}


func load_state(state: Dictionary) -> void:
	leased_by_player = bool(state.get("leased", leased_by_player))
	next_rent_due_day = int(state.get("next_rent_due_day", next_rent_due_day))
	arrears = int(state.get("arrears", arrears))
	_refresh_prompt()
