class_name ResidenceProperty
extends Portal
## Somewhere to live.
##
## The same shape as CommercialProperty and for the same reason: to let, the door
## shows the terms; leased, it is the way in. What differs is what the lease
## buys — a bed to sleep in and somewhere to wake up — so this also carries which
## home is the current one.
##
## The starter flat is one of these with its lease already signed, so nothing has
## to special-case where the player begins.

signal leased()
signal made_home()

@export var residence_id: StringName = &"larkspur"
@export var address: String = "Larkspur Apartments"
@export var display_name: String = "Studio Flat"
@export var district_id: StringName = &"harbour_row"
@export var size_label: String = "Studio"
@export_multiline var amenities: String = "Bed · Wardrobe"
## 0-100. What living here says about you, and the largest single component of
## the lifestyle score. Deliberately not derived from the rent: a dear flat in a
## bad spot is dear, not impressive.
@export var lifestyle_value: int = 10
## Off-street spaces that come with the place. Nothing enforces them yet beyond
## the parking marker outside; it is what the premium flat's private bay is.
@export var parking_slots: int = 0

@export_group("Terms")
@export var rent_amount: int = 220
@export var deposit: int = 200
@export var rent_interval_days: int = 7

@export_group("State")
@export var leased_by_player: bool = false
@export var is_home: bool = false
@export var next_rent_due_day: int = -1
@export var arrears: int = 0
@export var save_id: StringName = &""


func _ready() -> void:
	if save_id == &"":
		save_id = StringName("residence_%s" % residence_id)
	add_to_group(&"residence")
	add_to_group(&"saveable")
	if leased_by_player and next_rent_due_day < 0:
		next_rent_due_day = TimeManager.day_index + rent_interval_days
	_refresh_prompt()


func is_leased_by_player() -> bool:
	return leased_by_player


func is_current_home() -> bool:
	return is_home


func move_in_cost() -> int:
	return deposit + rent_amount


func is_rent_due() -> bool:
	return leased_by_player and next_rent_due_day >= 0 and TimeManager.day_index >= next_rent_due_day


func settle_rent(paid: bool) -> void:
	next_rent_due_day = TimeManager.day_index + rent_interval_days
	if not paid:
		arrears += rent_amount


## Signs the lease. The money has already moved; this records the relationship.
func begin_lease() -> void:
	leased_by_player = true
	next_rent_due_day = TimeManager.day_index + rent_interval_days
	arrears = 0
	_refresh_prompt()
	leased.emit()


## Gives the place up. A home the player is still living in cannot be dropped
## without choosing somewhere else first — waking up nowhere is not a state.
func end_lease() -> void:
	leased_by_player = false
	is_home = false
	next_rent_due_day = -1
	_refresh_prompt()


func set_as_home() -> void:
	if not leased_by_player:
		return
	for node in get_tree().get_nodes_in_group(&"residence"):
		var other := node as ResidenceProperty
		if other != null and other != self:
			other.is_home = false
			other._refresh_prompt()
	is_home = true
	_refresh_prompt()
	made_home.emit()


# --- Door ----------------------------------------------------------------

func _perform(interactor: Node3D) -> void:
	if not leased_by_player:
		GameManager.request_screen(&"residence", self, interactor)
		return
	super._perform(interactor)


func can_interact(interactor: Node3D) -> bool:
	if not leased_by_player:
		return available
	return super.can_interact(interactor)


func get_prompt_text() -> String:
	if not available:
		return unavailable_prompt
	if not leased_by_player:
		return "%s — View Apartment" % key_hint
	return super.get_prompt_text()


func _refresh_prompt() -> void:
	prompt_action = "Enter Apartment" if leased_by_player else "View Apartment"
	prompt_subtitle = "%s%s" % [address, "  ·  HOME" if is_home else ""]


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"leased": leased_by_player,
		"home": is_home,
		"next_rent_due_day": next_rent_due_day,
		"arrears": arrears,
	}


func load_state(state: Dictionary) -> void:
	leased_by_player = bool(state.get("leased", leased_by_player))
	is_home = bool(state.get("home", is_home))
	next_rent_due_day = int(state.get("next_rent_due_day", next_rent_due_day))
	arrears = int(state.get("arrears", arrears))
	_refresh_prompt()
