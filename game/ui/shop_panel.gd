extends Control
## The buy screen for any Shop.
##
## Rows are generated from the shop's stock list, so this panel never needs to
## know what a convenience store sells. It calls Shop.buy() and reports whatever
## reason comes back.

signal opened()
signal closed()

@onready var _title: Label = %ShopTitle
@onready var _cash: Label = %ShopCash
@onready var _rows: VBoxContainer = %StockRows
@onready var _status: Label = %ShopStatus

var _shop: Shop = null
var _buyer: Node = null
var _row_style: StyleBoxFlat


func _ready() -> void:
	visible = false
	_row_style = StyleBoxFlat.new()
	_row_style.bg_color = Color(0.106, 0.122, 0.157, 0.9)
	_row_style.border_color = Color(1, 1, 1, 0.14)
	_row_style.set_border_width_all(1)
	_row_style.set_corner_radius_all(6)
	_row_style.set_content_margin_all(12)
	EconomyManager.cash_changed.connect(_on_cash_changed)


func is_open() -> bool:
	return visible


func open(shop: Shop, buyer: Node) -> void:
	if shop == null:
		return
	_shop = shop
	_buyer = buyer
	_title.text = shop.shop_name.to_upper()
	_status.text = ""
	_refresh_cash()
	_build_rows()
	visible = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_shop = null
	_buyer = null
	closed.emit()


func _build_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()

	for item: ItemData in _shop.stock:
		if item == null:
			continue
		_rows.add_child(_make_row(item))


func _make_row(item: ItemData) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _row_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	frame.add_child(row)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.color = item.icon_color
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)

	var name_label := Label.new()
	name_label.text = item.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	text.add_child(name_label)

	var effect_label := Label.new()
	effect_label.text = item.get_effect_line()
	effect_label.add_theme_font_size_override("font_size", 13)
	effect_label.add_theme_color_override("font_color", Color(0.694, 0.729, 0.784))
	text.add_child(effect_label)

	var price_label := Label.new()
	price_label.text = "$%d" % _shop.get_price(item)
	price_label.add_theme_font_size_override("font_size", 20)
	price_label.add_theme_color_override("font_color", Color(0.639, 0.929, 0.686))
	price_label.custom_minimum_size = Vector2(70, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(price_label)

	var buy := Button.new()
	buy.text = "BUY"
	buy.custom_minimum_size = Vector2(84, 40)
	buy.pressed.connect(_on_buy_pressed.bind(item))
	row.add_child(buy)

	return frame


func _on_buy_pressed(item: ItemData) -> void:
	if _shop == null:
		return
	var result := _shop.buy(item, _buyer)
	if result == Shop.Result.OK:
		_status.text = "Bought %s for $%d" % [item.display_name, _shop.get_price(item)]
		_status.add_theme_color_override("font_color", Color(0.596, 0.918, 0.639))
	else:
		_status.text = Shop.describe_result(result)
		_status.add_theme_color_override("font_color", Color(0.965, 0.549, 0.502))


func _on_cash_changed(_balance: int, _delta: int) -> void:
	_refresh_cash()


func _refresh_cash() -> void:
	_cash.text = "Your cash: %s" % EconomyManager.get_cash_string()
