class_name FurnishingPanel
extends Control
## Arranging a flat.
##
## Two lists: what is in the room, and what is waiting to go in it. Placing and
## moving both close the screen and hand over to the placement mode, because
## putting something down is done in the room rather than in a menu.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _list: VBoxContainer = null
var _residence_id: StringName = &""


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(800, 600))
	_list = ScreenKit.scroller(_parts["body"])
	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)
	HomeManager.furniture_changed.connect(_on_furniture_changed)


func is_open() -> bool:
	return visible


func open(residence_id: StringName) -> void:
	_residence_id = residence_id
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


func _room() -> ApartmentInterior:
	for node in get_tree().get_nodes_in_group(&"residence_interior"):
		var room := node as ApartmentInterior
		if room != null and room.residence_id == _residence_id:
			return room
	return null


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	var home := PropertyManager.residence_by_id(_residence_id)
	_parts["title"].text = "FURNISHING"
	_parts["subtitle"].text = "%s  ·  comfort %d%%  ·  lifestyle +%d" % [
		home.address if home != null else "", HomeManager.comfort_of(_residence_id),
		HomeManager.furniture_lifestyle(_residence_id)
	]
	_parts["status"].text = ""

	_list.add_child(ScreenKit.heading("IN THIS ROOM"))
	var placed := HomeManager.placed_in(_residence_id)
	if placed.is_empty():
		_list.add_child(BusinessUIKit.label("Nothing of yours yet.", 14, ScreenKit.MUTED))
	for record in placed:
		_list.add_child(_placed_row(record))

	_list.add_child(ScreenKit.spacer(10))
	_list.add_child(ScreenKit.heading("WAITING TO GO IN"))
	var stored := HomeManager.in_storage()
	if stored.is_empty():
		_list.add_child(BusinessUIKit.label(
			"Nothing in storage. Kingston Furnishings on Kingston Road sells the rest.",
			14, ScreenKit.MUTED
		))
	for record in stored:
		_list.add_child(_stored_row(record))


func _placed_row(record: OwnedFurniture) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var definition := record.data()
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(record.display_name(), 15, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  lifestyle +%d" % [
			FurnitureData.category_name(definition.category), definition.lifestyle_value
		], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	var move := BusinessUIKit.button("MOVE", 120.0)
	move.pressed.connect(func() -> void: _move(record))
	line.add_child(move)

	var store := BusinessUIKit.button("STORE", 120.0)
	store.pressed.connect(func() -> void:
		HomeManager.store(record)
		AudioManager.play_ui(&"ui_click")
		_rebuild()
	)
	line.add_child(store)
	return frame


func _stored_row(record: OwnedFurniture) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var definition := record.data()
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(record.display_name(), 15, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  sells back for %s" % [
			FurnitureData.category_name(definition.category),
			ScreenKit.money(definition.resale_value())
		], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	var place := BusinessUIKit.button("PLACE", 120.0)
	place.pressed.connect(func() -> void: _place(record))
	line.add_child(place)

	var sell := BusinessUIKit.button("SELL", 120.0)
	sell.pressed.connect(func() -> void:
		var paid := HomeManager.sell(record)
		AudioManager.play_ui(&"money" if paid > 0 else &"ui_error")
		_rebuild()
	)
	line.add_child(sell)
	return frame


func _controller() -> FurniturePlacement:
	return get_tree().get_first_node_in_group(&"furniture_placement") as FurniturePlacement


func _place(record: OwnedFurniture) -> void:
	var controller := _controller()
	var room := _room()
	if controller == null or room == null:
		_note("Nowhere to put that.", ScreenKit.BAD)
		return
	GameManager.close_menus()
	controller.begin(room, record)


func _move(record: OwnedFurniture) -> void:
	var controller := _controller()
	var room := _room()
	if controller == null or room == null:
		_note("Nowhere to put that.", ScreenKit.BAD)
		return
	GameManager.close_menus()
	controller.begin_move(room, record)


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_furniture_changed() -> void:
	if visible:
		_rebuild()
