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
enum SizeClass { SMALL, MEDIUM, LARGE }

@export var property_id: StringName = &""
## Which part of the city this stands in. Set by whoever builds the street, and
## read by anything that wants the district's own demand or rent on top of the
## address's.
@export var district_id: StringName = &"harbour_row"
@export var address: String = "1 Main Street"
## Which way the shopfront faces, in degrees. Set by whichever district places
## the door, because only it knows which wall the unit is in.
@export var sign_yaw: float = 0.0
## The colour of the sign board behind the business name.
@export var sign_colour: Color = Color(0.157, 0.196, 0.278)
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
## What may trade here. A retail unit takes a shop or a cafe; a food-service
## unit is plumbed and extracted for a kitchen; a large commercial unit is the
## only thing a gym or a venue fits in. Empty means retail, which is what every
## unit built before Phase O was.
@export var business_classes: Array[StringName] = [&"retail"]

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
## Rent that could not be collected. Phase Q is when this finally means
## something: past enough missed payments the landlord serves notice.
@export var arrears: int = 0
## Day the landlord takes the unit back, once notice has been served. -1 when
## there is no notice outstanding, which is the ordinary case.
@export var eviction_day: int = -1
## The business trading from here, if any. Kept as a hint for the save file; the
## live answer always comes from BusinessManager.
@export var business_id: StringName = &""

## Stable id for the save file. Defaults from property_id in _ready.
@export var save_id: StringName = &""
## Set by RealEstate when the player buys the building. A unit the player owns
## still has all its lease machinery — the business trading from it is still
## its tenant — but there is no longer a landlord to pay, which is the whole
## economics of owning your own premises.
@export var owned_by_player: bool = false


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
	board.position = Vector3(0.0, 2.35, 0.35)
	# The door knows which way the shop faces; the sign has to face the same
	# way, or a shop on a north-facing wall advertises itself to the bricks.
	board.rotation_degrees.y = sign_yaw
	add_child(board)

	# A board behind the letters. A name floating on a wall reads as a debug
	# label; the same name on a panel reads as a shop.
	CityKit.add_box(
		board, "Panel", Vector3(0.0, 0.0, -0.06), Vector3(4.6, 1.15, 0.10),
		Palette.tinted(&"panel_navy", sign_colour), false, false
	)
	CityKit.add_box(
		board, "PanelTrim", Vector3(0.0, -0.60, -0.06), Vector3(4.7, 0.09, 0.13),
		Palette.of(&"metal_pale"), false, false
	)

	var name_plate := Label3D.new()
	name_plate.name = "Name"
	name_plate.text = business.business_name.to_upper()
	name_plate.font_size = 96
	name_plate.pixel_size = 0.0055
	name_plate.position = Vector3(0.0, 0.16, 0.0)
	name_plate.modulate = Color(0.96, 0.94, 0.88)
	name_plate.outline_size = 18
	name_plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	name_plate.double_sided = false
	board.add_child(name_plate)

	var state := Label3D.new()
	state.name = "State"
	state.text = "OPEN" if business.is_open() else "CLOSED"
	state.font_size = 56
	state.pixel_size = 0.0055
	state.position = Vector3(0.0, -0.30, 0.0)
	state.modulate = Color(0.35, 0.95, 0.45) if business.is_open() else Color(0.85, 0.35, 0.30)
	state.outline_size = 14
	state.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	state.double_sided = false
	board.add_child(state)


# --- Queries -------------------------------------------------------------

func is_vacant() -> bool:
	return status == Status.VACANT


## Whether rent is owed to anybody. Owning the freehold means it is not.
func has_landlord() -> bool:
	return not owned_by_player


## Rebuilds the door's prompt and sign after ownership changed.
func refresh_state() -> void:
	_refresh_prompt()
	_refresh_sign()


## Whether this unit is zoned and big enough for a given kind of business.
## The one place §113 lives: nothing else has to know that a nightclub needs
## more than a corner shop.
func accepts_business(definition: BusinessTypeData) -> bool:
	if definition == null:
		return false
	var classes := business_classes if not business_classes.is_empty() else [&"retail"]
	if not classes.has(definition.property_class):
		return false
	return floor_area >= definition.minimum_floor_area


## Kinds of business the player could put in here, for the founding screen.
func allowed_business_types() -> Array[BusinessTypeData]:
	var found: Array[BusinessTypeData] = []
	for definition in BusinessCatalogue.TYPES:
		if accepts_business(definition):
			found.append(definition)
	return found


func class_label() -> String:
	var classes := business_classes if not business_classes.is_empty() else [&"retail"]
	match StringName(classes[0]):
		&"food_service":
			return "Food service unit"
		&"large_commercial":
			return "Large commercial unit"
		&"office":
			return "Office"
		_:
			return "Retail unit"


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


## Whether the landlord has served notice on this unit.
##
## Only ever true for a leased unit with a landlord. A unit the player owns
## has nobody to be evicted by — the risk there is the mortgage, and confusing
## the two would take a building off somebody who had already bought it.
func is_under_eviction() -> bool:
	return eviction_day >= 0 and has_landlord()


## Days left to find the arrears. Zero means the deadline is today.
func days_to_eviction(today: int) -> int:
	return maxi(eviction_day - today, 0) if is_under_eviction() else 0


## How many rent payments have been missed, from the arrears and the rent.
## Derived rather than counted separately: two numbers that must agree is two
## numbers that eventually will not.
func missed_rent_payments() -> int:
	if rent_amount <= 0:
		return 0
	return int(float(arrears) / float(rent_amount))


# --- Leasing -------------------------------------------------------------

## Signs the lease. The money has already been taken by PropertyManager, which
## owns the transaction; this records the relationship.
func begin_lease(new_tenant: StringName) -> void:
	status = Status.LEASED
	tenant_id = new_tenant
	next_rent_due_day = TimeManager.day_index + rent_interval_days
	arrears = 0
	eviction_day = -1
	_refresh_prompt()
	leased.emit(new_tenant)


## Occupancy without a lease, for a unit the player has bought outright. There
## is no deposit and no rent because there is no landlord; what it grants is the
## right to trade from the unit, which is what the door and BusinessManager both
## check for. Rent day skips it — see PropertyManager.charge_due_rent.
func occupy_as_owner() -> void:
	if not owned_by_player or status == Status.LEASED:
		return
	status = Status.LEASED
	tenant_id = &"player"
	next_rent_due_day = -1
	arrears = 0
	_refresh_prompt()
	_refresh_sign()
	leased.emit(tenant_id)


func end_lease() -> void:
	status = Status.VACANT
	tenant_id = &""
	business_id = &""
	next_rent_due_day = -1
	eviction_day = -1
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
		return "yours" if owned_by_player else "leased"
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
		"eviction_day": eviction_day,
		"rent_amount": rent_amount,
		"deposit": deposit,
		"business_id": String(business_id),
	}


func load_state(state: Dictionary) -> void:
	status = int(state.get("status", int(status))) as Status
	tenant_id = StringName(state.get("tenant", String(tenant_id)))
	next_rent_due_day = int(state.get("next_rent_due_day", next_rent_due_day))
	arrears = int(state.get("arrears", arrears))
	# A save from before eviction existed has no notice outstanding, which is
	# the right answer rather than a default that evicts somebody on load.
	eviction_day = int(state.get("eviction_day", -1))
	rent_amount = int(state.get("rent_amount", rent_amount))
	deposit = int(state.get("deposit", deposit))
	business_id = StringName(state.get("business_id", String(business_id)))
	_refresh_prompt()
	_refresh_sign()
