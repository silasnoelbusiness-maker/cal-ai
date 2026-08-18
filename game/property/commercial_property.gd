class_name CommercialProperty
extends Portal
## A shop unit on the street: its details, its lease, and its front door.
##
## Extends Portal rather than sitting beside one because a leased unit *is* a
## door — the same camera reframing and the same destination-by-group lookup the
## flat and the market already use. Vacant, the door opens the letting details
## instead; leased, it opens the shop.
##
## Lease state lives here rather than in the manager: this node is the thing the
## save file already knows how to persist, and a second copy of "who rents what"
## is a bug waiting to happen.

signal leased(tenant_id: StringName)
signal lease_ended()
signal rent_charged(amount: int)
signal rent_overdue(amount: int)
## Raised whenever the door's own signage should be rebuilt — the name over it,
## or whether it reads OPEN.
signal sign_changed()

enum Status { VACANT, LEASED }
## How big the unit is. The interior is built to match, and a bigger room holds
## more equipment and more customers at once.
enum SizeClass { SMALL, MEDIUM }

@export var property_id: StringName = &""
@export var address: String = "1 Main Street"
@export var property_type: String = "Retail Unit"
@export var size_class: SizeClass = SizeClass.SMALL
## Square metres. Shown to the player, and the basis of the size label.
@export var floor_area: int = 48

@export_group("Trade")
## How many customers can be inside at once, and how long a queue they will
## tolerate. A small unit is a small shop however much money is poured into it.
@export var customer_capacity: int = 6
@export var queue_capacity: int = 4
## How much passing trade the address itself brings. A premium pitch costs more
## rent and is worth more customers; a back street is the other way round.
@export_range(0.5, 2.0, 0.05) var location_demand_modifier: float = 1.0

@export_group("Terms")
@export var rent_amount: int = 650
@export var deposit: int = 500
## In-game days between rent charges. Seven keeps the pressure visible in a
## prototype where a day is a few minutes.
@export var rent_interval_days: int = 7

@export_group("State")
@export var status: Status = Status.VACANT
@export var tenant_id: StringName = &""
@export var next_rent_due_day: int = -1
## Rent that could not be collected. Nothing evicts on it yet; the number exists
## so eviction has something to read when it arrives.
@export var arrears: int = 0
## The business trading from here, if any. Kept as a hint for the save file; the
## live answer always comes from BusinessManager.
@export var business_id: StringName = &""

## Stable id for the save file. Defaults from property_id in _ready.
@export var save_id: StringName = &""


func _ready() -> void:
	if save_id == &"":
		save_id = StringName("property_%s" % property_id)
	add_to_group(&"commercial_property")
	add_to_group(&"saveable")
	prompt_subtitle = address
	sign_changed.connect(_rebuild_sign)
	BusinessManager.business_created.connect(_on_business_changed)
	BusinessManager.business_changed.connect(_on_business_changed)
	BusinessManager.business_opened.connect(_on_business_changed)
	BusinessManager.business_closed.connect(_on_business_changed)
	_refresh_prompt()
	_rebuild_sign.call_deferred()


func _on_business_changed(business: BusinessInstance) -> void:
	if business != null and business.property_id != property_id:
		return
	_refresh_prompt()
	_rebuild_sign()


## The name over the door, and whether it is open.
##
## This is how a player tells their own shops apart from the street: a sign that
## says SILAS MARKET and whether they can walk in. Rebuilt rather than animated
## because it changes a handful of times a day.
func _rebuild_sign() -> void:
	var existing := get_node_or_null("Signage")
	if existing != null:
		existing.free()
	var business := BusinessManager.business_for_property(property_id)
	if business == null:
		return

	var board := Node3D.new()
	board.name = "Signage"
	board.position = Vector3(0.0, 1.5, 0.35)
	add_child(board)

	var name_plate := Label3D.new()
	name_plate.name = "Name"
	name_plate.text = business.business_name.to_upper()
	name_plate.font_size = 96
	name_plate.pixel_size = 0.006
	name_plate.modulate = Color(0.96, 0.94, 0.88)
	name_plate.outline_size = 18
	name_plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	name_plate.double_sided = false
	board.add_child(name_plate)

	var state := Label3D.new()
	state.name = "State"
	state.text = "OPEN" if business.is_open() else "CLOSED"
	state.font_size = 64
	state.pixel_size = 0.006
	state.position = Vector3(0.0, -0.45, 0.0)
	state.modulate = Color(0.35, 0.95, 0.45) if business.is_open() else Color(0.85, 0.35, 0.30)
	state.outline_size = 14
	state.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	state.double_sided = false
	board.add_child(state)


# --- Queries -------------------------------------------------------------

func is_vacant() -> bool:
	return status == Status.VACANT


func is_leased_by_player() -> bool:
	return status == Status.LEASED and tenant_id == &"player"


func size_label() -> String:
	return "Small" if size_class == SizeClass.SMALL else "Medium"


## A one-word verdict on the address, for the letting details.
func location_label() -> String:
	if location_demand_modifier >= 1.15:
		return "High"
	return "Low" if location_demand_modifier <= 0.9 else "Average"


## Deposit plus the first rent, which is what the player actually has to have in
## hand to sign.
func move_in_cost() -> int:
	return deposit + rent_amount


func days_until_rent() -> int:
	return maxi(next_rent_due_day - TimeManager.day_index, 0)


# --- Leasing -------------------------------------------------------------

## Signs the lease. The money has already been taken by PropertyManager, which
## owns the transaction; this records the relationship.
func begin_lease(new_tenant: StringName) -> void:
	status = Status.LEASED
	tenant_id = new_tenant
	next_rent_due_day = TimeManager.day_index + rent_interval_days
	arrears = 0
	_refresh_prompt()
	leased.emit(new_tenant)


func end_lease() -> void:
	status = Status.VACANT
	tenant_id = &""
	business_id = &""
	next_rent_due_day = -1
	_refresh_prompt()
	_refresh_sign()
	lease_ended.emit()


func is_rent_due() -> bool:
	return status == Status.LEASED and next_rent_due_day >= 0 and TimeManager.day_index >= next_rent_due_day


## Called by PropertyManager once the money has moved (or failed to).
func settle_rent(paid: bool) -> void:
	next_rent_due_day = TimeManager.day_index + rent_interval_days
	if paid:
		rent_charged.emit(rent_amount)
		return
	arrears += rent_amount
	rent_overdue.emit(arrears)


# --- Door ----------------------------------------------------------------

## Vacant, the door is an estate agent's board; leased, it is a door.
func _perform(interactor: Node3D) -> void:
	if is_vacant():
		GameManager.request_screen(&"property", self, interactor)
		return
	# The room behind the door is built on demand; make sure it is there before
	# somebody is teleported into it.
	var unit := _interior()
	if unit != null:
		unit.ensure_built()
	super._perform(interactor)


func _interior() -> RetailUnit:
	for node in get_tree().get_nodes_in_group(&"retail_unit"):
		var unit := node as RetailUnit
		if unit != null and unit.property_id == property_id:
			return unit
	return null


func can_interact(interactor: Node3D) -> bool:
	# The letting details are always available, even though a vacant unit has no
	# interior to travel to yet — which is what Portal.can_interact would check.
	if is_vacant():
		return available
	return super.can_interact(interactor)


func get_prompt_text() -> String:
	if not available:
		return unavailable_prompt
	if is_vacant():
		return "%s — View Property" % key_hint
	return super.get_prompt_text()


func _refresh_prompt() -> void:
	prompt_action = "View Property" if is_vacant() else "Enter %s" % _tenant_name()
	prompt_subtitle = address if is_vacant() else "%s · %s" % [address, _status_line()]


func _tenant_name() -> String:
	var business := BusinessManager.business_for_property(property_id)
	return business.business_name if business != null else "Unit"


func _status_line() -> String:
	var business := BusinessManager.business_for_property(property_id)
	if business == null:
		return "leased"
	return business.status_text()


## Asks whatever drew the signage to redraw it: the name over the door, and
## whether it currently reads OPEN.
func _refresh_sign() -> void:
	sign_changed.emit()


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"status": int(status),
		"tenant": String(tenant_id),
		"next_rent_due_day": next_rent_due_day,
		"arrears": arrears,
		"rent_amount": rent_amount,
		"deposit": deposit,
		"business_id": String(business_id),
	}


func load_state(state: Dictionary) -> void:
	status = int(state.get("status", int(status))) as Status
	tenant_id = StringName(state.get("tenant", String(tenant_id)))
	next_rent_due_day = int(state.get("next_rent_due_day", next_rent_due_day))
	arrears = int(state.get("arrears", arrears))
	rent_amount = int(state.get("rent_amount", rent_amount))
	deposit = int(state.get("deposit", deposit))
	business_id = StringName(state.get("business_id", String(business_id)))
	_refresh_prompt()
	_refresh_sign()
