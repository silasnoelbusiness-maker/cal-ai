class_name MenuKit
extends RefCounted
## Shared furniture for the front end.
##
## The menus are built in code for the same reason the business screens are:
## their contents depend on what exists — how many saves, how many bindings —
## and a scene full of placeholder rows that get rewritten at runtime is worse
## than a builder. This keeps the title screen, the settings and the pause menu
## looking like one program.
##
## Everything here reads its colours from Palette, so the front end and the city
## share a palette rather than resembling each other.

const TITLE_SIZE := 54
const HEADING_SIZE := 22
const BODY_SIZE := 15
const SMALL_SIZE := 13


## The game's name, set as one label so every screen spells it the same way.
static func title(text: String = "STREET CAPITAL") -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", TITLE_SIZE)
	node.add_theme_color_override("font_color", Palette.UI_TEXT)
	# Wide tracking is most of what makes a typographic title read as a title
	# rather than as a large label.
	node.add_theme_constant_override("line_spacing", 0)
	return node


static func subtitle(text: String) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", BODY_SIZE)
	node.add_theme_color_override("font_color", Palette.UI_MUTED)
	return node


static func heading(text: String) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", HEADING_SIZE)
	node.add_theme_color_override("font_color", Palette.UI_TEXT)
	return node


static func body(text: String, colour: Color = Palette.UI_TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", BODY_SIZE)
	node.add_theme_color_override("font_color", colour)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node


static func small(text: String, colour: Color = Palette.UI_MUTED) -> Label:
	var node := body(text, colour)
	node.add_theme_font_size_override("font_size", SMALL_SIZE)
	return node


## A menu button. Wired to a click sound here rather than at every call site,
## so no screen can forget.
static func button(text: String, minimum_width: float = 260.0) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(minimum_width, 42)
	node.add_theme_font_size_override("font_size", 16)
	node.focus_mode = Control.FOCUS_ALL
	node.pressed.connect(func() -> void: AudioManager.play_ui(&"ui_click"))
	node.mouse_entered.connect(func() -> void: AudioManager.play_ui(&"ui_hover", -12.0))
	return node


## A button that is present but cannot be used — CONTINUE with no save behind
## it. Disabled rather than hidden, so the menu does not change shape.
## Marks a button as the screen's primary action: filled in the accent rather
## than outlined in it. Applied to one button per screen and never two — a page
## with two primary actions has none.
static func make_primary(node: Button) -> void:
	var fill := Palette.UI_ACCENT.darkened(0.32)
	node.add_theme_stylebox_override(
		"normal", UITheme.slab(fill, Palette.UI_ACCENT, 6, 10)
	)
	node.add_theme_stylebox_override(
		"hover", UITheme.slab(Palette.UI_ACCENT.darkened(0.16), Color.WHITE, 6, 10)
	)
	node.add_theme_stylebox_override(
		"pressed", UITheme.slab(Palette.UI_ACCENT, Color.WHITE, 6, 10)
	)
	node.add_theme_color_override("font_color", Color(0.949, 0.973, 1.0))


static func disabled_button(text: String, minimum_width: float = 260.0) -> Button:
	var node := button(text, minimum_width)
	node.disabled = true
	return node


static func panel(background: Color = Palette.UI_PANEL) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", UITheme.slab(background, Palette.UI_LINE, 8, 18))
	return node


## A row with a label on the left and a control on the right, which is the shape
## of every line in the settings screen.
static func setting_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label := body(label_text)
	name_label.custom_minimum_size = Vector2(210, 30)
	row.add_child(name_label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## A labelled slider that reports whole percentages, because "0.63" is not a
## volume anybody has an opinion about.
static func percent_slider(value: float) -> HBoxContainer:
	var wrapper := HBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 12)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = round(value * 100.0)
	slider.custom_minimum_size = Vector2(240, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.add_child(slider)

	var readout := body("%d%%" % int(slider.value))
	readout.name = "Readout"
	readout.custom_minimum_size = Vector2(56, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wrapper.add_child(readout)

	slider.value_changed.connect(
		func(new_value: float) -> void: readout.text = "%d%%" % int(new_value)
	)
	return wrapper


static func option(items: Array, selected: int) -> OptionButton:
	var node := OptionButton.new()
	for item in items:
		node.add_item(String(item))
	node.selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	node.custom_minimum_size = Vector2(200, 32)
	node.item_selected.connect(func(_index: int) -> void: AudioManager.play_ui(&"ui_click"))
	return node


static func toggle(pressed: bool) -> CheckButton:
	var node := CheckButton.new()
	node.button_pressed = pressed
	node.toggled.connect(func(_on: bool) -> void: AudioManager.play_ui(&"ui_click"))
	return node


static func spacer(height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node
