extends Control
## The 8-slot bag screen.
##
## Slot widgets are built once and then refreshed in place, so opening the panel
## does not churn the scene tree. It reads an Inventory and calls back into it;
## it holds no item state of its own.

signal opened()
signal closed()

const COLUMNS := 4
const SLOT_SIZE := Vector2(128, 116)

@onready var _grid: GridContainer = %SlotGrid
@onready var _hint: Label = %InventoryHint

var _inventory: Inventory = null
var _user: Node = null
var _icons: Array[ColorRect] = []
var _names: Array[Label] = []
var _counts: Array[Label] = []
var _panels: Array[PanelContainer] = []

var _filled_style: StyleBoxFlat
var _empty_style: StyleBoxFlat


func _ready() -> void:
	visible = false
	_grid.columns = COLUMNS
	_filled_style = _make_slot_style(Color(0.106, 0.122, 0.157, 0.92), Color(1, 1, 1, 0.22))
	_empty_style = _make_slot_style(Color(0.078, 0.086, 0.106, 0.72), Color(1, 1, 1, 0.09))


func is_open() -> bool:
	return visible


func open(user: Node) -> void:
	_bind(user)
	if _inventory == null:
		return
	visible = true
	_refresh()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _bind(user: Node) -> void:
	if user == _user:
		return
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)

	_user = user
	_inventory = null
	if user != null and user.has_method("get_inventory"):
		_inventory = user.call("get_inventory")
	if _inventory == null:
		return

	_inventory.changed.connect(_refresh)
	_build_slots(_inventory.get_slots().size())


func _build_slots(count: int) -> void:
	if _panels.size() == count:
		return
	for child in _grid.get_children():
		child.queue_free()
	_icons.clear()
	_names.clear()
	_counts.clear()
	_panels.clear()

	for i in count:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = SLOT_SIZE
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.tooltip_text = "Click to use"
		panel.gui_input.connect(_on_slot_gui_input.bind(i))
		_grid.add_child(panel)

		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 6)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(box)

		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(44, 44)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)

		var item_name := Label.new()
		item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_name.add_theme_font_size_override("font_size", 13)
		item_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(item_name)

		var count_label := Label.new()
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 12)
		count_label.add_theme_color_override("font_color", Color(0.71, 0.75, 0.82))
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(count_label)

		_panels.append(panel)
		_icons.append(icon)
		_names.append(item_name)
		_counts.append(count_label)


func _refresh() -> void:
	if _inventory == null:
		return
	var slots := _inventory.get_slots()
	for i in _panels.size():
		var slot := slots[i] if i < slots.size() else null
		var filled := slot != null and not slot.is_empty()
		_panels[i].add_theme_stylebox_override(
			"panel", _filled_style if filled else _empty_style
		)
		if filled:
			_icons[i].color = slot.item.icon_color
			_names[i].text = slot.item.display_name
			_counts[i].text = "x%d" % slot.quantity
			_panels[i].tooltip_text = "%s\n%s\nClick to use" % [
				slot.item.display_name, slot.item.get_effect_line()
			]
		else:
			_icons[i].color = Color(1, 1, 1, 0.05)
			_names[i].text = "—"
			_counts[i].text = ""
			_panels[i].tooltip_text = "Empty"

	var used := 0
	for slot in slots:
		if not slot.is_empty():
			used += 1
	_hint.text = "%d / %d slots used  ·  click an item to use it  ·  TAB or ESC to close" % [
		used, slots.size()
	]


func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	if _inventory == null or _user == null:
		return
	_inventory.use_slot(index, _user)
	accept_event()


func _make_slot_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	return style
