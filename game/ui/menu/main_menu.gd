extends Control
## The title screen.
##
## A separate scene from the game, deliberately: running the world behind a menu
## would mean a district, a crowd, traffic and an economy ticking away for a
## backdrop nobody is playing. The backdrop here is a still gradient and the
## game's own type, which costs nothing and looks composed.
##
## The scene tree starts here rather than in main.tscn, so the game boots to a
## menu the way a game does. The headless harness loads main.tscn directly and
## never sees this, which is what keeps the test suite unaffected.

const GAME_SCENE := "res://main.tscn"

## Shown under the title while the game loads, one at a time. Original, and
## about this game rather than filler.
const TIPS: Array[String] = [
	"Businesses keep trading while you are away, if somebody is on the till.",
	"A crime nobody sees is a crime nobody reports.",
	"Rent in Central buys footfall. Whether it buys profit is up to you.",
	"Managers reorder stock on their own — inside the budget you set them.",
	"Press M for the city map. Set a destination and the route is drawn for you.",
	"Breaking line of sight starts the escape countdown. Staying hidden ends it.",
]

var _settings: SettingsScreen = null
var _load_panel: Control = null
var _status: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	MusicDirector.set_state(MusicDirector.State.MENU)


func _build() -> void:
	# A vertical gradient rather than two flat rectangles: the hard line where
	# one colour met the other read as a rendering fault rather than as a
	# design, which is the opposite of what a title screen is for.
	var sky := TextureRect.new()
	sky.name = "Backdrop"
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.035, 0.047, 0.078))
	gradient.set_color(1, Color(0.098, 0.145, 0.235))
	gradient.add_point(0.62, Color(0.055, 0.078, 0.129))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 8
	texture.height = 256
	sky.texture = texture
	add_child(sky)

	_build_skyline()

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 96
	column.offset_top = -220
	column.offset_bottom = 220
	column.custom_minimum_size = Vector2(300, 0)
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	column.add_child(MenuKit.title())
	# A rule in the accent under the title. One line, and it is what turns a
	# heading floating in a gradient into a masthead.
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Palette.UI_ACCENT
	rule.custom_minimum_size = Vector2(72, 3)
	column.add_child(rule)
	column.add_child(MenuKit.spacer(6))
	column.add_child(MenuKit.subtitle("An original city, and whatever you make of it."))
	column.add_child(MenuKit.spacer(28))

	var continue_slot := SaveManager.most_recent_slot()
	var continue_button := (
		MenuKit.button("CONTINUE") if continue_slot >= 0
		else MenuKit.disabled_button("CONTINUE")
	)
	if continue_slot >= 0:
		continue_button.pressed.connect(func() -> void: _load_slot(continue_slot))
		# The one button the returning player wants, given the accent so the
		# eye lands on it. Everything else on this screen is the same weight,
		# which is why nothing on it read as the way in.
		MenuKit.make_primary(continue_button)
	column.add_child(continue_button)

	var new_game := MenuKit.button("NEW GAME")
	new_game.pressed.connect(_on_new_game)
	column.add_child(new_game)

	var load_game := (
		MenuKit.button("LOAD GAME") if continue_slot >= 0
		else MenuKit.disabled_button("LOAD GAME")
	)
	load_game.pressed.connect(_open_load_panel)
	column.add_child(load_game)

	var settings := MenuKit.button("SETTINGS")
	settings.pressed.connect(func() -> void: _settings.open())
	column.add_child(settings)

	var quit := MenuKit.button("QUIT")
	quit.pressed.connect(_on_quit)
	column.add_child(quit)

	column.add_child(MenuKit.spacer(20))
	_status = MenuKit.small(TIPS[randi() % TIPS.size()])
	_status.custom_minimum_size = Vector2(420, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	_settings = SettingsScreen.new()
	_settings.name = "Settings"
	add_child(_settings)

	_build_load_panel()


## A silhouette of the city along the bottom, drawn from the same palette the
## world uses. Deliberately not a render of the game: running a district, a
## crowd, traffic and an economy behind a menu nobody is playing costs more than
## the picture is worth.
func _build_skyline() -> void:
	var strip := Control.new()
	strip.name = "Skyline"
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -300
	strip.offset_bottom = 0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("StreetCapitalSkyline")
	var x := -40.0
	var index := 0
	while x < 2100.0:
		var width := rng.randf_range(46.0, 132.0)
		var height := rng.randf_range(70.0, 250.0)
		var block := ColorRect.new()
		block.name = "Block%d" % index
		# Further blocks sit paler, which is the whole of the depth cue.
		block.color = Color(0.075, 0.098, 0.153).lerp(
			Color(0.129, 0.169, 0.243), rng.randf()
		)
		block.position = Vector2(x, 300.0 - height)
		block.size = Vector2(width, height)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(block)

		# A scattering of lit windows: what makes the silhouette read as a city
		# rather than as a bar chart.
		for i in int(rng.randf_range(0.0, 5.0)):
			var window := ColorRect.new()
			window.color = Color(0.976, 0.878, 0.647, rng.randf_range(0.22, 0.55))
			window.size = Vector2(5.0, 7.0)
			window.position = Vector2(
				rng.randf_range(6.0, maxf(width - 12.0, 8.0)),
				rng.randf_range(10.0, maxf(height - 16.0, 12.0))
			)
			window.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.add_child(window)

		x += width + rng.randf_range(-6.0, 14.0)
		index += 1


# --- Load game --------------------------------------------------------------

func _build_load_panel() -> void:
	_load_panel = Control.new()
	_load_panel.name = "LoadPanel"
	_load_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_panel.visible = false
	add_child(_load_panel)

	var dim := ColorRect.new()
	dim.color = Palette.UI_BACKDROP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_panel.add_child(dim)

	var frame := MenuKit.panel()
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -320
	frame.offset_right = 320
	frame.offset_top = -220
	frame.offset_bottom = 220
	_load_panel.add_child(frame)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)


func _open_load_panel() -> void:
	var column := _find_load_column()
	if column == null:
		return
	for child in column.get_children():
		child.queue_free()

	column.add_child(MenuKit.heading("LOAD GAME"))
	var saves := SaveManager.list_saves()
	if saves.is_empty():
		column.add_child(MenuKit.body("No saved games found.", Palette.UI_MUTED))
	for summary in saves:
		column.add_child(_save_row(summary))

	column.add_child(MenuKit.spacer(8))
	var back := MenuKit.button("BACK", 150.0)
	back.pressed.connect(func() -> void: _load_panel.visible = false)
	column.add_child(back)

	_load_panel.visible = true


func _find_load_column() -> VBoxContainer:
	for child in _load_panel.get_children():
		if child is PanelContainer:
			return child.get_node_or_null("Column") as VBoxContainer
	return null


## One line per slot: what it is, when it was saved, and enough about the game
## to tell it from the others without loading it.
func _save_row(summary: Dictionary) -> Control:
	# str(), not String(): the summary comes back through JSON, so cash is a
	# float and String(float) is not a constructor GDScript has. Reading a save
	# list is the only place these values are touched, so the first time it was
	# tried with a save actually on disk was the first time it was seen.
	var row := MenuKit.button(
		"%s   ·   Day %d, %s   ·   $%s   ·   %s" % [
			"AUTOSAVE" if bool(summary.get("autosave", false))
				else "SLOT %d" % int(summary.get("slot", 0)),
			int(summary.get("day", 1)),
			str(summary.get("time", "")),
			EconomyManager.with_thousands_separator(int(summary.get("cash", 0))),
			str(summary.get("district", "")),
		],
		560.0
	)
	row.pressed.connect(func() -> void: _load_slot(int(summary.get("slot", 1))))
	return row


# --- Actions ---------------------------------------------------------------

func _on_new_game() -> void:
	# Nothing is overwritten by starting a new game: saving is explicit and the
	# autosave has its own slot, so there is nothing to warn about.
	_enter_game(-1)


func _load_slot(slot: int) -> void:
	_enter_game(slot)


## Swaps the menu for the world, then restores a slot if one was asked for.
##
## The load happens a frame after the scene change so every autoload has seen
## the new tree — restoring into a half-built world was the first thing that
## went wrong here.
func _enter_game(slot: int) -> void:
	_status.text = "Loading…"
	var tree := get_tree()
	tree.change_scene_to_file(GAME_SCENE)
	if slot < 0:
		MusicDirector.refresh_world_state()
		return
	await tree.process_frame
	await tree.process_frame
	if not SaveManager.load_from_slot(slot):
		# A slot that will not load must not strand the player in a blank
		# world: they get a fresh game and are told why.
		GameManager.notify("SAVE COULD NOT BE LOADED", GameManager.Tone.BAD)
	MusicDirector.refresh_world_state()


func _on_quit() -> void:
	get_tree().quit()
