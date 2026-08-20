extends CanvasLayer
## Dev-only audio readout, hidden by default.
##
## The fifth of its kind, and the same rules as the traffic, crime, business and
## world overlays: not part of the HUD, never visible in a normal game, deleted
## by removing this node and its input action.
##
## F12 toggles it. It exists because audio bugs are invisible — a siren that
## never starts, a bed that never fades, forty voices where six were budgeted —
## and a number on screen is the only way to see them.

const REFRESH_INTERVAL := 0.25

var _label: Label = null
var _timer: float = 0.0


func _ready() -> void:
	layer = 100
	_build_label()
	visible = false
	set_process(false)


func _build_label() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(18.0, 120.0)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.92)
	add_child(panel)

	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.055, 0.043, 0.067, 0.82)
	box.set_content_margin_all(10.0)
	box.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", box)

	_label = Label.new()
	_label.name = "Readout"
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.929, 0.882, 0.973))
	panel.add_child(_label)


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_audio_overlay"):
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	_refresh()


func _refresh() -> void:
	var lines: Array[String] = ["AUDIO  (F12 hide)"]
	lines.append("  voices %d of %d   npc footsteps %d" % [
		AudioManager.active_voices(), AudioManager.pool_size(),
		Footsteps.active_npc_voices(),
	])
	lines.append("  ambience %s" % AmbienceDirector.current_profile())
	lines.append("  music %s" % MusicDirector.State.keys()[MusicDirector.get_state()])

	var engines := 0
	var sirens := 0
	for node in get_tree().get_nodes_in_group(&"vehicle"):
		var audio := node.get_node_or_null("Audio") as VehicleAudio
		if audio == null:
			continue
		if audio.is_siren_sounding():
			sirens += 1
		var engine := audio.get_node_or_null("Engine") as AudioStreamPlayer3D
		if engine != null and engine.playing:
			engines += 1
	lines.append("  engines %d   sirens %d" % [engines, sirens])

	var player := GameManager.player
	if player != null:
		lines.append("  underfoot %s" % SurfaceMap.display_name(SurfaceMap.under(player)))

	lines.append("  buses:")
	for bus in AudioBuses.ALL:
		lines.append("    %-14s %3d%%" % [
			AudioBuses.display_name(bus), int(round(AudioBuses.get_volume(bus) * 100.0))
		])

	_label.text = "\n".join(lines)
