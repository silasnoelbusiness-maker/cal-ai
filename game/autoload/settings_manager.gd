extends Node
## Everything the player chose, kept apart from everything the player did.
##
## Settings persist to `user://settings.cfg` and have nothing to do with save
## games: changing the music volume must not need a save slot, and loading an
## old save must not reset the resolution. That separation is the whole point of
## this file existing rather than the options living in SaveManager.
##
## A missing or malformed config falls back to defaults rather than failing, so
## a half-written file after a crash costs the player their preferences and not
## their ability to start the game.

signal settings_changed(section: StringName)

const PATH := "user://settings.cfg"

enum Preset { LOW, MEDIUM, HIGH }

## What each graphics preset actually changes. Presets exist so the player can
## make one decision instead of six; the individual keys stay settable for
## anybody who wants them.
const PRESETS := {
	Preset.LOW: {
		"shadows": false,
		"shadow_distance": 60.0,
		"ambient_occlusion": false,
		"bloom": false,
		"render_scale": 0.8,
	},
	Preset.MEDIUM: {
		"shadows": true,
		"shadow_distance": 120.0,
		"ambient_occlusion": false,
		"bloom": true,
		"render_scale": 1.0,
	},
	Preset.HIGH: {
		"shadows": true,
		"shadow_distance": 190.0,
		"ambient_occlusion": true,
		"bloom": true,
		"render_scale": 1.0,
	},
}

const DEFAULT_GAMEPLAY := {
	"camera_sensitivity": 1.0,
	"zoom_sensitivity": 1.0,
	"camera_shake": 0.6,
	"show_prompts": true,
}

const DEFAULT_DISPLAY := {
	"mode": 0,  # 0 windowed, 1 borderless, 2 fullscreen
	"vsync": true,
	"preset": Preset.MEDIUM,
}

## The actions the controls screen shows, in the order it shows them. Anything
## not listed here is still rebindable in principle; this is the shortlist that
## fits on a screen.
const BINDABLE: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"sprint", &"interact", &"enter_vehicle", &"handbrake",
	&"city_map", &"business_menu", &"attack", &"pause_menu",
]

var _audio: Dictionary = {}
var _display: Dictionary = {}
var _gameplay: Dictionary = {}
var _bindings: Dictionary = {}
var _defaults_captured: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure_layout()
	_capture_default_bindings()
	_reset_to_defaults()
	load_settings()
	apply_all()


# --- Reading ---------------------------------------------------------------

func audio_volume(bus: StringName) -> float:
	return float(_audio.get(bus, AudioBuses.DEFAULT_VOLUMES.get(bus, 0.8)))


func gameplay(key: String) -> Variant:
	return _gameplay.get(key, DEFAULT_GAMEPLAY.get(key))


func display(key: String) -> Variant:
	return _display.get(key, DEFAULT_DISPLAY.get(key))


func preset() -> Preset:
	return _display.get("preset", Preset.MEDIUM)


func graphics(key: String) -> Variant:
	return PRESETS[preset()].get(key)


# --- Writing ---------------------------------------------------------------

func set_audio_volume(bus: StringName, fraction: float) -> void:
	_audio[bus] = clampf(fraction, 0.0, 1.0)
	AudioBuses.set_volume(bus, _audio[bus])
	settings_changed.emit(&"audio")
	save_settings()


func set_gameplay(key: String, value: Variant) -> void:
	_gameplay[key] = value
	settings_changed.emit(&"gameplay")
	save_settings()


func set_display(key: String, value: Variant) -> void:
	_display[key] = value
	apply_display()
	settings_changed.emit(&"display")
	save_settings()


func set_preset(new_preset: Preset) -> void:
	_display["preset"] = new_preset
	apply_graphics()
	settings_changed.emit(&"display")
	save_settings()


# --- Applying --------------------------------------------------------------

func apply_all() -> void:
	for bus in AudioBuses.ALL:
		AudioBuses.set_volume(bus, audio_volume(bus))
	apply_display()
	apply_bindings()


func apply_display() -> void:
	# Headless has no window to configure, and asking for one crashes the tests.
	if DisplayServer.get_name() == "headless":
		return
	match int(display("mode")):
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(display("vsync")) else DisplayServer.VSYNC_DISABLED
	)
	apply_graphics()


## Pushes the current preset into the running scene: the sun's shadows, the
## environment's post-processing, and the viewport's render scale.
##
## Looked up rather than held, because the world is torn down and rebuilt every
## time the player returns to the menu and starts again.
func apply_graphics() -> void:
	var values: Dictionary = PRESETS[preset()]
	var tree := get_tree()
	if tree == null:
		return

	# Found by type rather than by group: the districts build their own sun and
	# environment, and a preset that only worked when somebody remembered to
	# join a group would fail silently the first time somebody forgot.
	if tree.current_scene != null:
		for light in _find_all(tree.current_scene, "DirectionalLight3D"):
			var sun := light as DirectionalLight3D
			sun.shadow_enabled = bool(values["shadows"])
			sun.directional_shadow_max_distance = float(values["shadow_distance"])

		for node in _find_all(tree.current_scene, "WorldEnvironment"):
			var world := node as WorldEnvironment
			if world.environment == null:
				continue
			world.environment.ssao_enabled = bool(values["ambient_occlusion"])
			world.environment.glow_enabled = bool(values["bloom"])

	var viewport := tree.root
	if viewport != null and DisplayServer.get_name() != "headless":
		viewport.scaling_3d_scale = float(values["render_scale"])


## Every node of a class below `root`. Small and recursive on purpose: it runs
## when a preset changes, which is a handful of times per session.
func _find_all(root: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(_find_all(child, type_name))
	return found


# --- Controls --------------------------------------------------------------

## Remembers what the project shipped with, so RESET TO DEFAULTS has something
## to reset to that is not itself a saved value.
func _capture_default_bindings() -> void:
	for action in BINDABLE:
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		for event in InputMap.action_get_events(action):
			events.append(event.duplicate())
		_defaults_captured[action] = events


func binding_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string(
				(event as InputEventKey).physical_keycode
			)
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "Left Mouse"
				MOUSE_BUTTON_RIGHT:
					return "Right Mouse"
				MOUSE_BUTTON_MIDDLE:
					return "Middle Mouse"
				_:
					return "Mouse %d" % (event as InputEventMouseButton).button_index
	return "—"


## Which other action already uses this key, or an empty name if none does.
## Rebinding asks first rather than quietly creating two actions on one key.
func conflict_for(action: StringName, event: InputEvent) -> StringName:
	for other in BINDABLE:
		if other == action or not InputMap.has_action(other):
			continue
		for existing in InputMap.action_get_events(other):
			if existing.is_match(event):
				return other
	return &""


func rebind(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	_bindings[action] = _describe_event(event)
	settings_changed.emit(&"controls")
	save_settings()


func reset_bindings() -> void:
	_bindings.clear()
	for action in _defaults_captured:
		InputMap.action_erase_events(action)
		for event in _defaults_captured[action]:
			InputMap.action_add_event(action, event)
	settings_changed.emit(&"controls")
	save_settings()


func apply_bindings() -> void:
	for action in _bindings:
		var event := _event_from(String(_bindings[action]))
		if event == null or not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


## Bindings are stored as text rather than as serialised events, so a config
## file stays readable and a future engine version cannot fail to parse it.
func _describe_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key:%d" % (event as InputEventKey).physical_keycode
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


func _event_from(text: String) -> InputEvent:
	var parts := text.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "key":
		var key := InputEventKey.new()
		key.physical_keycode = int(parts[1])
		return key
	if parts[0] == "mouse":
		var button := InputEventMouseButton.new()
		button.button_index = int(parts[1])
		return button
	return null


# --- Persistence -----------------------------------------------------------

func _reset_to_defaults() -> void:
	_audio = AudioBuses.DEFAULT_VOLUMES.duplicate(true)
	_display = DEFAULT_DISPLAY.duplicate(true)
	_gameplay = DEFAULT_GAMEPLAY.duplicate(true)
	_bindings = {}


func load_settings() -> bool:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return false
	# A file that parses but contains none of our sections is not our file —
	# a truncated write or something else entirely. Treated as missing, so the
	# defaults stand in rather than a half-read config being trusted.
	if not (config.has_section("audio") or config.has_section("display")
			or config.has_section("gameplay") or config.has_section("controls")):
		return false
	for bus in AudioBuses.ALL:
		if config.has_section_key("audio", String(bus)):
			_audio[bus] = clampf(float(config.get_value("audio", String(bus))), 0.0, 1.0)
	for key in DEFAULT_DISPLAY:
		if config.has_section_key("display", key):
			_display[key] = config.get_value("display", key)
	for key in DEFAULT_GAMEPLAY:
		if config.has_section_key("gameplay", key):
			_gameplay[key] = config.get_value("gameplay", key)
	if config.has_section("controls"):
		for action in config.get_section_keys("controls"):
			_bindings[StringName(action)] = config.get_value("controls", action)
	return true


func save_settings() -> void:
	var config := ConfigFile.new()
	for bus in _audio:
		config.set_value("audio", String(bus), _audio[bus])
	for key in _display:
		config.set_value("display", key, _display[key])
	for key in _gameplay:
		config.set_value("gameplay", key, _gameplay[key])
	for action in _bindings:
		config.set_value("controls", String(action), _bindings[action])
	config.save(PATH)


## Development and testing entry point: back to shipped defaults, applied and
## saved, without touching any save game.
func restore_defaults() -> void:
	_reset_to_defaults()
	reset_bindings()
	apply_all()
	save_settings()
	settings_changed.emit(&"all")
