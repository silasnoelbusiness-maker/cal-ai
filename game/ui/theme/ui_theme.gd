class_name UITheme
extends RefCounted
## One Theme for the whole game, built in code and applied at the window root.
##
## The screens were written as layout logic with styling sprinkled through them.
## Rather than rewrite them — the information they show is right, and rewriting
## risks the systems behind them — this sets the look once, at the root, so every
## Panel, Button, Label and bar in the game inherits it. A screen only overrides
## a value now when it genuinely means something different.
##
## Colours come from `Palette`, so the interface and the city share one set.

const RADIUS := 8
const FONT_SIZE := 14


## Builds the theme. Cached, because every call would otherwise mint a fresh set
## of styleboxes for the same look.
static var _theme: Theme = null

static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE

	_style_panels(theme)
	_style_buttons(theme)
	_style_text(theme)
	_style_bars(theme)
	_style_containers(theme)

	_theme = theme
	return theme


## A rounded, slightly translucent slab. Everything in the interface is one of
## these at some depth, which is most of what makes a set of screens feel like
## one program.
static func slab(
	background: Color, border: Color, radius: int = RADIUS, margin: int = 12
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


static func _style_panels(theme: Theme) -> void:
	var panel := slab(Palette.UI_PANEL, Palette.UI_LINE, RADIUS, 14)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	# Popups and tooltips sit above everything, so they are darker and tighter.
	var floating := slab(Palette.UI_BACKDROP, Color(1, 1, 1, 0.14), 6, 8)
	theme.set_stylebox("panel", "PopupPanel", floating)
	theme.set_stylebox("panel", "TooltipPanel", floating)


static func _style_buttons(theme: Theme) -> void:
	var normal := slab(Palette.UI_RAISED, Color(1, 1, 1, 0.10), 6, 8)
	var hover := slab(Color(0.161, 0.184, 0.239), Color(1, 1, 1, 0.20), 6, 8)
	var pressed := slab(Color(0.220, 0.365, 0.549), Color(1, 1, 1, 0.28), 6, 8)
	var disabled := slab(Color(0.086, 0.098, 0.129, 0.8), Color(1, 1, 1, 0.05), 6, 8)
	var focus := slab(Color(0, 0, 0, 0), Palette.UI_ACCENT, 6, 8)

	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBoxFlat = {
			"normal": normal, "hover": hover, "pressed": pressed,
			"disabled": disabled, "focus": focus,
		}[state]
		for kind in ["Button", "OptionButton", "MenuButton", "CheckButton"]:
			theme.set_stylebox(state, kind, style)

	for kind in ["Button", "OptionButton", "MenuButton", "CheckButton"]:
		theme.set_color("font_color", kind, Palette.UI_TEXT)
		theme.set_color("font_hover_color", kind, Color.WHITE)
		theme.set_color("font_pressed_color", kind, Color.WHITE)
		theme.set_color("font_disabled_color", kind, Color(0.435, 0.463, 0.514))
		theme.set_font_size("font_size", kind, 13)

	# Tabs read as a row of buttons rather than as folder tabs, which suits a
	# management screen better than a document metaphor.
	theme.set_stylebox("tab_selected", "TabBar", pressed)
	theme.set_stylebox("tab_unselected", "TabBar", normal)
	theme.set_stylebox("tab_hovered", "TabBar", hover)
	theme.set_color("font_selected_color", "TabBar", Color.WHITE)
	theme.set_color("font_unselected_color", "TabBar", Palette.UI_MUTED)


static func _style_text(theme: Theme) -> void:
	theme.set_color("font_color", "Label", Palette.UI_TEXT)
	theme.set_color("font_color", "RichTextLabel", Palette.UI_TEXT)
	theme.set_color("default_color", "RichTextLabel", Palette.UI_TEXT)

	var field := slab(Color(0.043, 0.051, 0.075, 0.9), Color(1, 1, 1, 0.12), 5, 6)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", slab(Color(0, 0, 0, 0), Palette.UI_ACCENT, 5, 6))
	theme.set_color("font_color", "LineEdit", Palette.UI_TEXT)
	theme.set_color("caret_color", "LineEdit", Palette.UI_ACCENT)


static func _style_bars(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.08)
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.UI_ACCENT
	fill.set_corner_radius_all(4)
	theme.set_stylebox("background", "ProgressBar", track)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", Palette.UI_TEXT)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1, 1, 1, 0.22)
	grabber.set_corner_radius_all(4)
	for kind in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", kind, track)
		theme.set_stylebox("grabber", kind, grabber)
		var lit := StyleBoxFlat.new()
		lit.bg_color = Color(1, 1, 1, 0.34)
		lit.set_corner_radius_all(4)
		theme.set_stylebox("grabber_highlight", kind, lit)
		theme.set_stylebox("grabber_pressed", kind, lit)


static func _style_containers(theme: Theme) -> void:
	var empty := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", empty)
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("margin_left", "MarginContainer", 4)
	theme.set_constant("margin_right", "MarginContainer", 4)

	var line := StyleBoxFlat.new()
	line.bg_color = Palette.UI_LINE
	line.content_margin_top = 1
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_stylebox("separator", "VSeparator", line)


## A coloured pill, for statuses: OPEN, LOW STOCK, WANTED. Returns a stylebox
## the caller puts behind a label.
static func pill(colour: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(colour.r, colour.g, colour.b, 0.18)
	style.border_color = Color(colour.r, colour.g, colour.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


## Development entry point: drops the cached theme so an edit can be re-read.
static func forget() -> void:
	_theme = null
