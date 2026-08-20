class_name VehicleDetailPanel
extends Control
## One car on the showroom floor.
##
## What the stand beside a display car opens: the name, the price, the class and
## the five figures, then BUY, COMPARE and CLOSE. Comparing hands off to the
## sales desk screen, which is where two cars can be put side by side — this
## screen is about one of them.

signal opened()
signal closed()
signal compare_requested(model_id: StringName)

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _model_id: StringName = &""


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(680, 520))
	_body = ScreenKit.scroller(_parts["body"])
	EconomyManager.cash_changed.connect(_on_cash_changed)


func is_open() -> bool:
	return visible


func open(model_id: StringName) -> void:
	if VehicleCatalogue.data_for(model_id) == null:
		return
	_model_id = model_id
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	var definition := VehicleCatalogue.data_for(_model_id)
	_parts["title"].text = definition.display_name.to_upper()
	_parts["subtitle"].text = "%s  ·  Your cash: %s" % [
		VehicleCatalogue.subtitle(_model_id), EconomyManager.get_cash_string()
	]
	_parts["status"].text = definition.description

	_body.add_child(ScreenKit.row("Price", ScreenKit.money(definition.price_new), true))
	_body.add_child(ScreenKit.row("Class", definition.vehicle_class))
	_body.add_child(ScreenKit.row("Top speed", "%d km/h" % roundi(definition.get_max_speed_kmh())))
	_body.add_child(ScreenKit.spacer(6))

	var ratings := definition.showroom_ratings()
	for stat in ratings:
		_body.add_child(ScreenKit.stat_bar(String(stat), int(ratings[stat]), stat == "Prestige"))

	var actions: HBoxContainer = _parts["actions"]

	var compare := BusinessUIKit.button("COMPARE", 140.0)
	compare.pressed.connect(func() -> void: compare_requested.emit(_model_id))
	actions.add_child(compare)

	var buy := BusinessUIKit.button("BUY", 130.0)
	buy.disabled = not EconomyManager.can_afford(definition.price_new)
	buy.pressed.connect(_on_buy_pressed)
	actions.add_child(buy)

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	actions.add_child(close_button)


func _on_buy_pressed() -> void:
	var definition := VehicleCatalogue.data_for(_model_id)
	ScreenKit.confirm(
		self,
		"BUY %s FOR %s?" % [definition.display_name.to_upper(), ScreenKit.money(definition.price_new)],
		"Collect it from the bay on Riverside Drive.",
		func() -> void:
			var stock := get_tree().get_first_node_in_group(&"dealership_stock") as Dealership
			var at := stock.collection_transform() if stock != null else Transform3D.IDENTITY
			var result := VehicleRegistry.buy(_model_id, at, definition.price_new)
			if result == VehicleRegistry.BuyResult.OK:
				AudioManager.play_ui(&"money")
				GameManager.close_menus()
			else:
				AudioManager.play_ui(&"ui_error")
				_parts["status"].text = "That did not go through."
	)


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible:
		_rebuild()
