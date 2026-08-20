class_name ScreenKit
extends RefCounted
## The frame every Phase M screen is built in.
##
## The business screens are laid out in .tscn files and the front end is built
## in code; these are built in code, because their contents are lists whose
## length depends on what the player owns and what the shop is holding today.
## Putting the frame here means the dealership, the mechanic, the garage and
## the furniture shop are visibly the same program without eight copies of the
## same dim-and-panel arrangement.

const TEXT := Palette.UI_TEXT
const MUTED := Palette.UI_MUTED
const GOOD := Palette.MONEY
const BAD := Palette.LOSS
const ACCENT := Palette.UI_ACCENT


## Builds the standard shell into `screen` and returns its parts:
##   {"title": Label, "subtitle": Label, "body": VBoxContainer,
##    "status": Label, "actions": HBoxContainer}
static func build_frame(screen: Control, minimum: Vector2 = Vector2(860, 620)) -> Dictionary:
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.visible = false

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Palette.UI_BACKDROP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)

	# A CenterContainer rather than hand-set anchors: a PanelContainer sizes
	# itself to its contents, and mixing the two pins the panel to the corner.
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(centre)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.add_theme_stylebox_override(
		"panel", UITheme.slab(Color(0.055, 0.063, 0.082, 0.96), Palette.UI_LINE, 10, 22)
	)
	frame.custom_minimum_size = minimum
	centre.add_child(frame)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)

	var title := BusinessUIKit.label("", 24, TEXT)
	title.name = "Title"
	column.add_child(title)

	var subtitle := BusinessUIKit.label("", 13, MUTED)
	subtitle.name = "Subtitle"
	column.add_child(subtitle)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var status := BusinessUIKit.label("", 13, MUTED)
	status.name = "Status"
	column.add_child(status)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)

	return {
		"title": title, "subtitle": subtitle, "body": body,
		"status": status, "actions": actions,
	}


## A scrolling list inside the body, for the screens whose contents are longer
## than the panel.
static func scroller(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column


## A label-and-value line, the same shape the business screens use.
static func row(name: String, value: String, emphasis: bool = false) -> PanelContainer:
	return BusinessUIKit.row([
		BusinessUIKit.stretch_label(name, 14, MUTED),
		BusinessUIKit.value_label(value, 15 if emphasis else 14, ACCENT if emphasis else TEXT),
	])


## A 0-100 rating drawn as a bar with the number beside it. What makes the
## showroom board readable at a glance rather than a column of integers.
static func stat_bar(name: String, value: int, highlight: bool = false) -> PanelContainer:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(210, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT if highlight else Color(0.478, 0.612, 0.706)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.08)
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", track)

	return BusinessUIKit.row([
		BusinessUIKit.stretch_label(name, 13, MUTED),
		bar,
		BusinessUIKit.value_label(str(value), 13, TEXT),
	])


static func heading(text: String) -> Label:
	var node := BusinessUIKit.label(text, 15, ACCENT)
	node.add_theme_constant_override("line_spacing", 6)
	return node


static func spacer(height: float = 8.0) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node


static func money(amount: int) -> String:
	return "$%s" % EconomyManager.with_thousands_separator(amount)


## A yes/no over the top of whatever is already on screen. Used for anything
## that moves real money, so a mis-click cannot cost the player a car.
static func confirm(
	parent: Control, question: String, detail: String, on_yes: Callable
) -> Control:
	var overlay := Control.new()
	overlay.name = "Confirm"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(centre)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(
		"panel", UITheme.slab(Color(0.075, 0.086, 0.110, 0.99), Palette.UI_LINE, 10, 20)
	)
	frame.custom_minimum_size = Vector2(460, 0)
	centre.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)
	column.add_child(BusinessUIKit.label(question, 18, TEXT))
	if not detail.is_empty():
		column.add_child(BusinessUIKit.label(detail, 13, MUTED))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	var no := BusinessUIKit.button("NO", 120.0)
	no.pressed.connect(func() -> void:
		AudioManager.play_ui(&"ui_back")
		overlay.queue_free()
	)
	buttons.add_child(no)

	var yes := BusinessUIKit.button("YES", 120.0)
	yes.pressed.connect(func() -> void:
		AudioManager.play_ui(&"ui_confirm")
		overlay.queue_free()
		on_yes.call()
	)
	buttons.add_child(yes)
	return overlay
