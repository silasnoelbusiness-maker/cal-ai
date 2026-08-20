class_name FurnitureStorePanel
extends Control
## Kingston Furnishings, from the counter.
##
## One category at a time, three tiers in each, with a quantity box for the
## things people buy several of. Everything is delivered to whichever flat the
## player currently lives in, so there is nothing to carry and nothing to decide
## until it arrives.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _tab_bar: TabBar = null
var _list: VBoxContainer = null
var _categories: Array = []
var _category: int = 0


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(820, 600))
	_build()
	EconomyManager.cash_changed.connect(_on_cash_changed)
	HomeManager.furniture_changed.connect(_on_furniture_changed)


func is_open() -> bool:
	return visible


func open() -> void:
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


func _build() -> void:
	var body: VBoxContainer = _parts["body"]
	_categories = FurnitureCatalogue.categories()

	_tab_bar = TabBar.new()
	for category in _categories:
		_tab_bar.add_tab(FurnitureData.category_name(category))
	_tab_bar.tab_changed.connect(func(index: int) -> void:
		_category = index
		_rebuild()
	)
	body.add_child(_tab_bar)

	_list = ScreenKit.scroller(body)

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	_parts["title"].text = "KINGSTON FURNISHINGS"
	var home := PropertyManager.current_home()
	_parts["subtitle"].text = "Delivering to %s  ·  Your cash: %s" % [
		home.address if home != null else "nowhere yet", EconomyManager.get_cash_string()
	]
	if home == null:
		_note("You need somewhere to live before anything can be delivered.", ScreenKit.BAD)
	elif HomeManager.pending_count() > 0:
		_note("%d item%s on the van." % [
			HomeManager.pending_count(), "" if HomeManager.pending_count() == 1 else "s"
		], ScreenKit.MUTED)
	else:
		_parts["status"].text = ""

	if _categories.is_empty():
		return
	for item in FurnitureCatalogue.in_category(_categories[_category]):
		_list.add_child(_item_row(item, home != null))


func _item_row(item: FurnitureData, can_buy: bool) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(item.display_name, 15, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  lifestyle +%d  ·  comfort +%d" % [
			FurnitureData.tier_name(item.tier), item.lifestyle_value, item.comfort_value
		], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	line.add_child(BusinessUIKit.value_label(ScreenKit.money(item.purchase_price), 15, ScreenKit.TEXT))

	# A quantity box, because nobody wants to open this menu six times to buy
	# six chairs.
	var quantity := BusinessUIKit.spin(1, 12, 1)
	quantity.custom_minimum_size = Vector2(70, 0)
	line.add_child(quantity)

	var buy := BusinessUIKit.button("BUY", 110.0)
	buy.disabled = not can_buy or not EconomyManager.can_afford(item.purchase_price)
	buy.pressed.connect(func() -> void: _buy(item, int(quantity.value)))
	line.add_child(buy)
	return frame


func _buy(item: FurnitureData, quantity: int) -> void:
	var result := HomeManager.buy(item.furniture_id, quantity)
	if result != HomeManager.BuyResult.OK:
		AudioManager.play_ui(&"ui_error")
		_note("You cannot afford that.", ScreenKit.BAD)
		return
	AudioManager.play_ui(&"money")
	_note("Ordered. It will be at home shortly.", ScreenKit.GOOD)
	_rebuild()


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible:
		_rebuild()


func _on_furniture_changed() -> void:
	if visible:
		_rebuild()
