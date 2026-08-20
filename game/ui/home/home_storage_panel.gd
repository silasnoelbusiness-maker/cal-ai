class_name HomeStoragePanel
extends Control
## The cupboard.
##
## Two columns, pockets on the left and the cupboard on the right, and items
## move one way or the other. Nothing is created or destroyed here — a thing put
## away is the same thing taken back out, which is the only property this screen
## really has to have.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _columns: HBoxContainer = null
var _residence_id: StringName = &""


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(820, 560))
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 16)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts["body"].add_child(_columns)

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


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


func _player_inventory() -> Inventory:
	var player := GameManager.player
	return player.get_inventory() if player != null and player.has_method("get_inventory") else null


func _rebuild() -> void:
	for child in _columns.get_children():
		child.queue_free()

	var box := HomeManager.storage_for(_residence_id)
	var pockets := _player_inventory()
	var home := PropertyManager.residence_by_id(_residence_id)

	_parts["title"].text = "HOME STORAGE"
	_parts["subtitle"].text = "%s  ·  %d of %d slots used" % [
		home.address if home != null else "", _used(box), box.slot_count
	]
	_parts["status"].text = ""

	_columns.add_child(_column("YOUR POCKETS", pockets, true))
	_columns.add_child(_column("THE CUPBOARD", box, false))


func _used(box: Inventory) -> int:
	var count := 0
	for slot in box.get_slots():
		if not slot.is_empty():
			count += 1
	return count


## One side of the screen. `to_storage` says which way its buttons move things.
func _column(title: String, inventory: Inventory, to_storage: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	column.add_child(ScreenKit.heading(title))

	if inventory == null:
		column.add_child(BusinessUIKit.label("Not available.", 13, ScreenKit.MUTED))
		return column

	var any := false
	for index in inventory.get_slots().size():
		var slot := inventory.get_slot(index)
		if slot.is_empty():
			continue
		any = true
		column.add_child(_slot_row(inventory, index, slot, to_storage))
	if not any:
		column.add_child(BusinessUIKit.label("Empty.", 13, ScreenKit.MUTED))
	return column


func _slot_row(
	inventory: Inventory, index: int, slot: InventorySlot, to_storage: bool
) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	frame.add_child(line)

	line.add_child(BusinessUIKit.stretch_label(
		"%s x%d" % [slot.item.display_name, slot.quantity], 14, ScreenKit.TEXT
	))
	if slot.has_stolen():
		line.add_child(BusinessUIKit.label("STOLEN", 11, ScreenKit.BAD))

	var move := BusinessUIKit.button("PUT AWAY" if to_storage else "TAKE", 130.0)
	move.pressed.connect(func() -> void: _transfer(inventory, index, to_storage))
	line.add_child(move)
	return frame


## Moves one slot's worth across. The receiving side is asked how much it can
## take first, so nothing is ever removed from one side without arriving at the
## other — which is the only way a transfer can be safe.
func _transfer(from: Inventory, index: int, to_storage: bool) -> void:
	var slot := from.get_slot(index)
	if slot == null or slot.is_empty():
		return
	var box := HomeManager.storage_for(_residence_id)
	var pockets := _player_inventory()
	var to: Inventory = box if to_storage else pockets
	if to == null:
		return

	var item := slot.item
	var stolen := slot.stolen
	var quantity := slot.quantity
	var room := to.space_for(item)
	if room <= 0:
		_note("No room for that." if to_storage else "Your pockets are full.", ScreenKit.BAD)
		AudioManager.play_ui(&"ui_error")
		return

	var moving := mini(quantity, room)
	var moving_stolen := mini(stolen, moving)
	from.remove_from_slot(index, moving)
	if moving_stolen > 0:
		to.add(item, moving_stolen, true)
	if moving - moving_stolen > 0:
		to.add(item, moving - moving_stolen, false)
	AudioManager.play_ui(&"ui_click")
	_rebuild()


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)
