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

@export var property_id: StringName = &""
@export var address: String = "1 Main Street"
@export var property_type: String = "Retail Unit"
@export var size_label: String = "Small"
## Square metres. Shown to the player and used by nothing else yet.
@export var floor_area: int = 48

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

## Stable id for the save file. Defaults from property_id in _ready.
@export var save_id: StringName = &""


func _ready() -> void:
	if save_id == &"":
		save_id = StringName("property_%s" % property_id)
	add_to_group(&"commercial_property")
	add_to_group(&"saveable")
	prompt_subtitle = address
	_refresh_prompt()


# --- Queries -------------------------------------------------------------

func is_vacant() -> bool:
	return status == Status.VACANT


func is_leased_by_player() -> bool:
	return status == Status.LEASED and tenant_id == &"player"


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
	super._perform(interactor)


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
	}


func load_state(state: Dictionary) -> void:
	status = int(state.get("status", int(status))) as Status
	tenant_id = StringName(state.get("tenant", String(tenant_id)))
	next_rent_due_day = int(state.get("next_rent_due_day", next_rent_due_day))
	arrears = int(state.get("arrears", arrears))
	rent_amount = int(state.get("rent_amount", rent_amount))
	deposit = int(state.get("deposit", deposit))
	_refresh_prompt()
	_refresh_sign()
