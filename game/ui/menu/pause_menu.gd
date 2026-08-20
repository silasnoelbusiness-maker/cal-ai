class_name PauseMenu
extends Control
## The in-game pause screen, in the same clothes as the title screen.
##
## Lives in the HUD rather than in its own scene so pausing costs nothing —
## no scene change, no reload — and reads GameManager's existing pause state
## rather than inventing a second one.

const MENU_SCENE := "res://ui/menu/main_menu.tscn"

var _settings: SettingsScreen = null
var _column: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	GameManager.state_changed.connect(_on_state_changed)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Palette.UI_BACKDROP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var frame := MenuKit.panel()
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -200
	frame.offset_right = 200
	frame.offset_top = -230
	frame.offset_bottom = 230
	add_child(frame)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	frame.add_child(_column)

	_column.add_child(MenuKit.heading("PAUSED"))
	_column.add_child(MenuKit.spacer(6))

	var resume := MenuKit.button("RESUME", 340.0)
	resume.pressed.connect(func() -> void: GameManager.toggle_pause())
	_column.add_child(resume)

	var save := MenuKit.button("SAVE GAME", 340.0)
	save.pressed.connect(_open_save)
	_column.add_child(save)

	var load_button := MenuKit.button("LOAD GAME", 340.0)
	load_button.pressed.connect(_open_load)
	_column.add_child(load_button)

	var settings := MenuKit.button("SETTINGS", 340.0)
	settings.pressed.connect(func() -> void: _settings.open())
	_column.add_child(settings)

	var to_menu := MenuKit.button("MAIN MENU", 340.0)
	to_menu.pressed.connect(_quit_to_menu)
	_column.add_child(to_menu)

	var quit := MenuKit.button("QUIT TO DESKTOP", 340.0)
	quit.pressed.connect(func() -> void: get_tree().quit())
	_column.add_child(quit)

	_status = MenuKit.small("")
	_column.add_child(_status)

	_settings = SettingsScreen.new()
	_settings.name = "Settings"
	add_child(_settings)


func _on_state_changed(_state: int) -> void:
	visible = GameManager.is_paused()


## Save and load both offer the three manual slots. The autosave is listed for
## loading but never written to by hand — it belongs to the game.
func _open_save() -> void:
	_show_slots("SAVE TO", SaveManager.MANUAL_SLOTS, func(slot: int) -> void:
		if SaveManager.save_to_slot(slot):
			_status.text = "Saved to slot %d." % slot
			AudioManager.play_ui(&"ui_confirm")
		else:
			_status.text = "Could not save to slot %d." % slot
			AudioManager.play_ui(&"ui_error")
	)


func _open_load() -> void:
	var slots: Array[int] = []
	for summary in SaveManager.list_saves():
		slots.append(int(summary.get("slot", 1)))
	if slots.is_empty():
		_status.text = "No saved games to load."
		AudioManager.play_ui(&"ui_error")
		return
	_show_slots("LOAD FROM", slots, func(slot: int) -> void:
		if SaveManager.load_from_slot(slot):
			GameManager.toggle_pause()
		else:
			_status.text = "Slot %d could not be read." % slot
			AudioManager.play_ui(&"ui_error")
	)


## A small slot picker built in place, rather than a third screen: the pause
## menu is the only thing that uses it.
func _show_slots(title: String, slots: Array, on_pick: Callable) -> void:
	for child in _column.get_children():
		child.queue_free()
	_column.add_child(MenuKit.heading(title))
	for slot in slots:
		var summary := SaveManager.describe_slot(int(slot))
		var label := "SLOT %d — empty" % int(slot)
		if not summary.is_empty():
			label = "%s — Day %d, %s, $%s" % [
				"AUTOSAVE" if bool(summary.get("autosave", false))
					else "SLOT %d" % int(slot),
				int(summary.get("day", 1)),
				str(summary.get("time", "")),
				EconomyManager.with_thousands_separator(int(summary.get("cash", 0))),
			]
		var button := MenuKit.button(label, 340.0)
		button.pressed.connect(func() -> void: on_pick.call(int(slot)))
		_column.add_child(button)

	var back := MenuKit.button("BACK", 340.0)
	back.pressed.connect(_rebuild)
	_column.add_child(back)
	_status = MenuKit.small("")
	_column.add_child(_status)


func _rebuild() -> void:
	for child in _column.get_children():
		child.queue_free()
	# Rebuilt on the next frame, once the old rows are actually gone.
	await get_tree().process_frame
	var parent := _column.get_parent()
	_column.queue_free()
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	parent.add_child(_column)
	_populate_main()


func _populate_main() -> void:
	_column.add_child(MenuKit.heading("PAUSED"))
	for entry in [
		["RESUME", func() -> void: GameManager.toggle_pause()],
		["SAVE GAME", _open_save],
		["LOAD GAME", _open_load],
		["SETTINGS", func() -> void: _settings.open()],
		["MAIN MENU", _quit_to_menu],
		["QUIT TO DESKTOP", func() -> void: get_tree().quit()],
	]:
		var button := MenuKit.button(String(entry[0]), 340.0)
		button.pressed.connect(entry[1] as Callable)
		_column.add_child(button)
	_status = MenuKit.small("")
	_column.add_child(_status)


## Back to the title screen, with the world torn down rather than left running
## underneath it — including its audio, which is the thing most likely to be
## forgotten.
func _quit_to_menu() -> void:
	GameManager.state = GameManager.State.PLAYING
	get_tree().paused = false
	MusicDirector.set_state(MusicDirector.State.MENU)
	AmbienceDirector.set_space(AmbienceDirector.Space.EXTERIOR)
	get_tree().change_scene_to_file(MENU_SCENE)
