class_name SettingsScreen
extends Control
## Audio, graphics, gameplay and controls, in four tabs.
##
## Built from SettingsManager rather than holding its own copy of anything, so
## opening this from the title screen and from the pause menu shows the same
## values, and closing it cannot lose a change — every control writes straight
## through and SettingsManager persists on write.

signal closed()

const TABS: Array[String] = ["AUDIO", "GRAPHICS", "GAMEPLAY", "CONTROLS"]

var _tab_bar: TabBar = null
var _page: VBoxContainer = null
var _rebinding: StringName = &""
var _rebind_notice: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func open() -> void:
	visible = true
	_show_tab(0)
	AudioManager.play_ui(&"ui_confirm")


func close() -> void:
	_rebinding = &""
	visible = false
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Palette.UI_BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	# A CenterContainer rather than hand-set anchors: a PanelContainer sizes
	# itself to its contents, and mixing that with manual offsets produced a
	# panel pinned to the top-left with its labels cut off.
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var frame := MenuKit.panel()
	frame.custom_minimum_size = Vector2(780, 580)
	centre.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	frame.add_child(column)

	column.add_child(MenuKit.heading("SETTINGS"))

	_tab_bar = TabBar.new()
	for tab in TABS:
		_tab_bar.add_tab(tab)
	_tab_bar.tab_changed.connect(_show_tab)
	column.add_child(_tab_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 10)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_page)

	_rebind_notice = MenuKit.small("")
	column.add_child(_rebind_notice)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(footer)
	var back := MenuKit.button("BACK", 150.0)
	back.pressed.connect(close)
	footer.add_child(back)


func _show_tab(index: int) -> void:
	# Called both by the tab bar and directly (open(), the screenshot harness),
	# so the bar is told which tab it is on rather than assumed to know. Setting
	# it to the value it already holds does not re-emit, so this cannot recurse.
	if _tab_bar.current_tab != index:
		_tab_bar.current_tab = index
	for child in _page.get_children():
		child.queue_free()
	match index:
		0:
			_build_audio()
		1:
			_build_graphics()
		2:
			_build_gameplay()
		_:
			_build_controls()


# --- Audio -----------------------------------------------------------------

func _build_audio() -> void:
	_page.add_child(MenuKit.small(
		"Volumes apply immediately and are kept separately from your save."
	))
	for bus in AudioBuses.ALL:
		var wrapper := MenuKit.percent_slider(SettingsManager.audio_volume(bus))
		var slider := wrapper.get_node("Slider") as HSlider
		slider.value_changed.connect(
			func(value: float) -> void:
				SettingsManager.set_audio_volume(bus, value / 100.0)
		)
		# One click when the handle is released, not one per pixel of travel.
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed:
					AudioManager.play_ui(&"ui_click", -10.0)
		)
		_page.add_child(MenuKit.setting_row(AudioBuses.display_name(bus), wrapper))


# --- Graphics ---------------------------------------------------------------

func _build_graphics() -> void:
	var preset := MenuKit.option(["LOW", "MEDIUM", "HIGH"], int(SettingsManager.preset()))
	preset.item_selected.connect(
		func(index: int) -> void: SettingsManager.set_preset(index as SettingsManager.Preset)
	)
	_page.add_child(MenuKit.setting_row("Quality preset", preset))

	var mode := MenuKit.option(
		["WINDOWED", "BORDERLESS", "FULLSCREEN"], int(SettingsManager.display("mode"))
	)
	mode.item_selected.connect(
		func(index: int) -> void: SettingsManager.set_display("mode", index)
	)
	_page.add_child(MenuKit.setting_row("Display mode", mode))

	var vsync := MenuKit.toggle(bool(SettingsManager.display("vsync")))
	vsync.toggled.connect(
		func(on: bool) -> void: SettingsManager.set_display("vsync", on)
	)
	_page.add_child(MenuKit.setting_row("VSync", vsync))

	_page.add_child(MenuKit.spacer(8))
	_page.add_child(MenuKit.small("This preset sets:"))
	var values: Dictionary = SettingsManager.PRESETS[SettingsManager.preset()]
	for key in values:
		_page.add_child(MenuKit.small(
			"    %s — %s" % [String(key).capitalize(), values[key]], Palette.DIM
		))


# --- Gameplay ---------------------------------------------------------------

func _build_gameplay() -> void:
	for entry in [
		["Camera sensitivity", "camera_sensitivity"],
		["Zoom sensitivity", "zoom_sensitivity"],
		["Camera shake", "camera_shake"],
	]:
		var key: String = entry[1]
		var wrapper := MenuKit.percent_slider(float(SettingsManager.gameplay(key)))
		var slider := wrapper.get_node("Slider") as HSlider
		slider.max_value = 200.0 if key != "camera_shake" else 100.0
		slider.value = round(float(SettingsManager.gameplay(key)) * 100.0)
		slider.value_changed.connect(
			func(value: float) -> void: SettingsManager.set_gameplay(key, value / 100.0)
		)
		_page.add_child(MenuKit.setting_row(String(entry[0]), wrapper))

	var prompts := MenuKit.toggle(bool(SettingsManager.gameplay("show_prompts")))
	prompts.toggled.connect(
		func(on: bool) -> void: SettingsManager.set_gameplay("show_prompts", on)
	)
	_page.add_child(MenuKit.setting_row("Interaction prompts", prompts))


# --- Controls ---------------------------------------------------------------

func _build_controls() -> void:
	_page.add_child(MenuKit.small("Click a binding, then press the key you want."))
	for action in SettingsManager.BINDABLE:
		if not InputMap.has_action(action):
			continue
		var button := MenuKit.button(SettingsManager.binding_label(action), 180.0)
		button.pressed.connect(func() -> void: _begin_rebind(action, button))
		_page.add_child(
			MenuKit.setting_row(String(action).capitalize().replace("_", " "), button)
		)

	_page.add_child(MenuKit.spacer(10))
	var reset := MenuKit.button("RESET TO DEFAULTS", 220.0)
	reset.pressed.connect(_confirm_reset)
	_page.add_child(reset)


func _begin_rebind(action: StringName, button: Button) -> void:
	_rebinding = action
	button.text = "PRESS A KEY"
	_rebind_notice.text = "Listening for a new key for %s. Escape cancels." % action


func _confirm_reset() -> void:
	SettingsManager.reset_bindings()
	AudioManager.play_ui(&"ui_confirm")
	_rebind_notice.text = "Controls reset to defaults."
	_show_tab(3)


func _input(event: InputEvent) -> void:
	if not visible or _rebinding == &"":
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()

	var key := event as InputEventKey
	if key.physical_keycode == KEY_ESCAPE:
		_rebinding = &""
		_rebind_notice.text = "Rebinding cancelled."
		_show_tab(3)
		return

	var clash := SettingsManager.conflict_for(_rebinding, key)
	if clash != &"":
		# Told, not silently allowed: two actions on one key is a bug the
		# player would otherwise have to discover in the middle of a chase.
		AudioManager.play_ui(&"ui_error")
		_rebind_notice.text = "%s is already used by %s." % [
			OS.get_keycode_string(key.physical_keycode), clash
		]
		_rebinding = &""
		_show_tab(3)
		return

	SettingsManager.rebind(_rebinding, key)
	AudioManager.play_ui(&"ui_confirm")
	_rebind_notice.text = "Bound %s to %s." % [
		OS.get_keycode_string(key.physical_keycode), _rebinding
	]
	_rebinding = &""
	_show_tab(3)
