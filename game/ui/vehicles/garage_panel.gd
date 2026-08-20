class_name GaragePanel
extends Control
## A garage: its terms if it is not yours yet, its bays if it is.
##
## Storing is only offered for a car standing outside — the same rule the
## mechanic works by, and for the same reason. Retrieving puts the car back in
## a bay with everything it had when it went in.

signal opened()
signal closed()

## How close a car has to be to the garage to be put into it.
const DRIVE_IN_RADIUS := 14.0

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _garage: GarageProperty = null


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(760, 560))
	_body = ScreenKit.scroller(_parts["body"])
	VehicleRegistry.fleet_changed.connect(_on_fleet_changed)


func is_open() -> bool:
	return visible


func open(garage: GarageProperty) -> void:
	if garage == null:
		return
	_garage = garage
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_garage = null
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	_parts["title"].text = _garage.display_name.to_upper()
	_parts["subtitle"].text = "%s  ·  Your cash: %s" % [
		_garage.address, EconomyManager.get_cash_string()
	]
	_parts["status"].text = ""

	if not _garage.is_leased_by_player():
		_build_terms()
	else:
		_build_bays()

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func _build_terms() -> void:
	_body.add_child(ScreenKit.row("Capacity", "%d vehicles" % _garage.capacity))
	_body.add_child(ScreenKit.row(
		"Rent", "%s every %d days" % [
			ScreenKit.money(_garage.rent_amount), _garage.rent_interval_days
		]
	))
	_body.add_child(ScreenKit.row("Deposit", ScreenKit.money(_garage.deposit)))
	_body.add_child(ScreenKit.row("To take it on", ScreenKit.money(_garage.move_in_cost()), true))
	_body.add_child(ScreenKit.spacer(6))
	_body.add_child(BusinessUIKit.label(
		"Somewhere off the street to keep a car. Nothing stolen goes in.",
		13, ScreenKit.MUTED
	))

	var rent := BusinessUIKit.button("RENT GARAGE", 180.0)
	rent.disabled = not EconomyManager.can_afford(_garage.move_in_cost())
	rent.pressed.connect(func() -> void:
		if PropertyManager.lease_garage(_garage):
			AudioManager.play_ui(&"money")
			_rebuild()
		else:
			_note("That did not go through.", ScreenKit.BAD)
	)
	_parts["actions"].add_child(rent)
	if rent.disabled:
		_note("You need %s to take this on." % ScreenKit.money(_garage.move_in_cost()), ScreenKit.BAD)


func _build_bays() -> void:
	_body.add_child(ScreenKit.row("Bays", _garage.occupancy_label(), true))
	if _garage.is_overdue():
		_body.add_child(ScreenKit.row("Rent", "OVERDUE — %s" % ScreenKit.money(_garage.arrears)))

	_body.add_child(ScreenKit.spacer(6))
	_body.add_child(ScreenKit.heading("IN THE GARAGE"))
	var stored := VehicleRegistry.stored_in(_garage.garage_id)
	if stored.is_empty():
		_body.add_child(BusinessUIKit.label("Empty.", 14, ScreenKit.MUTED))
	for record in stored:
		_body.add_child(_stored_row(record))
	for i in _garage.free_bays():
		_body.add_child(ScreenKit.row("Bay %d" % (stored.size() + i + 1), "Empty"))

	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("OUTSIDE"))
	var outside := _vehicles_outside()
	if outside.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Drive something of yours up to the doors to put it away.", 14, ScreenKit.MUTED
		))
	for record in outside:
		_body.add_child(_outside_row(record))

	# The distinction the whole system rests on: a stolen car is not yours, and
	# a garage is not a way to launder one into being yours.
	if _stolen_nearby():
		_body.add_child(ScreenKit.spacer(6))
		_body.add_child(BusinessUIKit.label(
			"CANNOT STORE STOLEN VEHICLE", 14, ScreenKit.BAD
		))


func _stored_row(record: OwnedVehicle) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(record.display_name(), 15, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  %s  ·  %s" % [
			record.mileage_label(), record.condition_label(),
			ScreenKit.money(record.market_value())
		], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	var take := BusinessUIKit.button("RETRIEVE", 140.0)
	take.pressed.connect(func() -> void: _retrieve(record))
	line.add_child(take)
	return frame


func _outside_row(record: OwnedVehicle) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(record.display_name(), 15, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  %s" % [record.mileage_label(), record.condition_label()], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	var put := BusinessUIKit.button("STORE", 140.0)
	put.disabled = _garage.is_full()
	put.pressed.connect(func() -> void: _store(record))
	line.add_child(put)
	return frame


## The player's own cars standing near the doors.
func _vehicles_outside() -> Array[OwnedVehicle]:
	var found: Array[OwnedVehicle] = []
	for record in VehicleRegistry.get_fleet():
		if record.is_stored() or not record.is_spawned():
			continue
		if record.node.global_position.distance_to(_garage.global_position) <= DRIVE_IN_RADIUS:
			found.append(record)
	return found


## Whether there is a car outside that is not the player's — a stolen one, or
## somebody else's entirely. What the refusal notice is about.
func _stolen_nearby() -> bool:
	for node in get_tree().get_nodes_in_group(&"vehicle"):
		var car := node as Vehicle
		if car == null or VehicleRegistry.owns(car):
			continue
		if car.global_position.distance_to(_garage.global_position) <= DRIVE_IN_RADIUS:
			return true
	return false


func _store(record: OwnedVehicle) -> void:
	var result := VehicleRegistry.store(record, _garage.garage_id)
	match result:
		VehicleRegistry.StoreResult.OK:
			AudioManager.play(&"car_door", AudioBuses.VEHICLES, -8.0)
			_note("%s put away." % record.display_name(), ScreenKit.GOOD)
			_garage.refresh()
		VehicleRegistry.StoreResult.GARAGE_FULL:
			_note("GARAGE FULL", ScreenKit.BAD)
		VehicleRegistry.StoreResult.STOLEN_VEHICLE:
			_note("CANNOT STORE STOLEN VEHICLE", ScreenKit.BAD)
		_:
			_note("That did not go in.", ScreenKit.BAD)
	_rebuild()


func _retrieve(record: OwnedVehicle) -> void:
	# Out into the bay it was standing in, so a car does not appear to shuffle
	# along the row on its way out.
	var bay := _garage.bay_for(VehicleRegistry.stored_in(_garage.garage_id).find(record))
	if VehicleRegistry.retrieve(record, bay):
		AudioManager.play(&"car_door", AudioBuses.VEHICLES, -8.0)
		_note("%s is outside." % record.display_name(), ScreenKit.GOOD)
		_garage.refresh()
	else:
		_note("That did not come out.", ScreenKit.BAD)
	_rebuild()


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_fleet_changed() -> void:
	if visible and _garage != null:
		_rebuild()
