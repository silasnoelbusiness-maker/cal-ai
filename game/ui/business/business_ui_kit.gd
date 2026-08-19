class_name BusinessUIKit
extends RefCounted
## Shared furniture for the business screens.
##
## The business panels are built in code rather than laid out in scenes, because
## their contents are lists whose length depends on what the player owns. This
## keeps the styling in one place so the property screen and the dashboard look
## like the same program.

## Drawn from the shared palette, so a profit figure here is the same green as
## a profit figure on the map and on the HUD.
const TEXT := Palette.UI_TEXT
const MUTED := Palette.UI_MUTED
const GOOD := Palette.MONEY
const BAD := Palette.LOSS
const ACCENT := Palette.UI_ACCENT


static func panel_style(background: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(10)
	return style


static func row_style() -> StyleBoxFlat:
	return panel_style(Color(0.098, 0.114, 0.149, 0.92), Color(1, 1, 1, 0.10), 8)


## A status chip: OPEN, CLOSED, LOW STOCK. Colour carries the meaning, so the
## same state never appears in two different colours across two screens.
static func status_chip(text: String, colour: Color) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.pill(colour))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var text_node := label(text, 12, colour)
	text_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(text_node)
	return frame


static func label(text: String, size: int = 14, colour: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", colour)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node


## A label that takes whatever width is left, so the value beside it lines up
## down the right-hand edge of a list.
static func stretch_label(text: String, size: int = 14, colour: Color = TEXT) -> Label:
	var node := label(text, size, colour)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func value_label(text: String, size: int = 14, colour: Color = TEXT) -> Label:
	var node := label(text, size, colour)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	node.custom_minimum_size = Vector2(110, 0)
	return node


static func button(text: String, minimum_width: float = 110.0) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(minimum_width, 32)
	node.add_theme_font_size_override("font_size", 13)
	return node


static func row(children: Array) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", row_style())
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	for child in children:
		box.add_child(child)
	frame.add_child(box)
	return frame


static func heading(text: String) -> Label:
	var node := label(text.to_upper(), 12, MUTED)
	return node


static func spin(minimum: float, maximum: float, value: float, step: float = 1.0) -> SpinBox:
	var node := SpinBox.new()
	node.min_value = minimum
	node.max_value = maximum
	node.step = step
	node.value = value
	node.custom_minimum_size = Vector2(96, 30)
	return node


static func money(amount: int) -> String:
	return "-$%d" % absi(amount) if amount < 0 else "$%d" % amount


static func tone_for(amount: int) -> Color:
	if amount > 0:
		return GOOD
	return BAD if amount < 0 else TEXT
