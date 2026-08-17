extends CanvasLayer
## Dev-only crime readout, hidden by default.
##
## The same idea as the traffic overlay, and kept separate from it for the same
## reason: the HUD is the shipping interface and this is scaffolding. Deleting
## this node and its two input actions removes the whole thing.
##
## F3 toggles the readout. F4 puts a steel pipe in the player's bag, because
## testing melee otherwise means finding one first.
##
## What it shows is the thing the stars alone cannot: the points behind them. A
## player at two stars cannot tell whether they are one shoplifting or one
## robbery away from three, and neither can a developer tuning the table.

const REFRESH_INTERVAL := 0.25

const PIPE: ItemData = preload("res://items/definitions/steel_pipe.tres")

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
	panel.position = Vector2(18.0, 320.0)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.92)
	add_child(panel)

	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.071, 0.043, 0.047, 0.82)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	box.corner_radius_top_left = 5
	box.corner_radius_top_right = 5
	box.corner_radius_bottom_left = 5
	box.corner_radius_bottom_right = 5
	panel.add_theme_stylebox_override("panel", box)

	_label = Label.new()
	_label.name = "Readout"
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.96, 0.88, 0.86))
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_crime_overlay"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_give_weapon"):
		give_weapon()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_refresh()


func give_weapon() -> void:
	var player := GameManager.player
	if player == null or not player.has_method("get_inventory"):
		return
	var inventory: Inventory = player.call("get_inventory")
	if inventory.count_of(PIPE.id) > 0:
		GameManager.notify("ALREADY CARRYING A PIPE", GameManager.Tone.INFO)
		return
	if inventory.add(PIPE, 1) > 0:
		GameManager.notify("DEBUG: STEEL PIPE ADDED", GameManager.Tone.INFO)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	_refresh()


func _refresh() -> void:
	var lines: Array[String] = ["CRIME  (F3 hide, F4 give pipe)"]

	var next_at := WantedManager.points_for_level(WantedManager.level + 1)
	var to_next := "max" if next_at <= 0 else "%d to go" % maxi(next_at - WantedManager.points, 0)
	lines.append(
		"  wanted %d★   %d pts   next %s" % [WantedManager.level, WantedManager.points, to_next]
	)
	lines.append(
		"  units %d / %d   pressure x%.2f   fine $%d"
		% [
			WantedManager.get_active_responders(),
			WantedManager.get_response_budget(),
			WantedManager.get_pursuit_pressure(),
			WantedManager.get_bust_fine(),
		]
	)
	if WantedManager.is_escaping():
		lines.append("  ESCAPING  %.1fs left" % WantedManager.get_escape_seconds_left())

	var stats := CrimeManager.get_statistics()
	lines.append(
		"  stolen %d   jacked %d   lifted %d   robbed %d   assaults %d"
		% [
			stats.get(&"vehicles_stolen", 0), stats.get(&"cars_carjacked", 0),
			stats.get(&"items_shoplifted", 0), stats.get(&"stores_robbed", 0),
			stats.get(&"assaults", 0),
		]
	)
	lines.append(
		"  busted %d   escaped %d   crime income $%d   fines $%d"
		% [
			stats.get(&"times_busted", 0), stats.get(&"times_escaped", 0),
			stats.get(&"illegal_income", 0), stats.get(&"fines_paid", 0),
		]
	)

	var player := GameManager.player as Player
	if player != null:
		var weapon := player.get_combat().get_active_weapon()
		var held: ItemData = player.get_equipped_item()
		lines.append(
			"  in hand %s   %d dmg   %.1fm"
			% [
				held.display_name if held != null else weapon.display_name,
				roundi(weapon.damage), weapon.attack_range,
			]
		)
		var inventory: Inventory = player.get_inventory()
		if inventory.has_stolen_goods():
			lines.append("  carrying %d stolen item(s)" % inventory.stolen_count())

	var history := CrimeManager.get_history()
	var shown := 0
	for i in range(history.size() - 1, -1, -1):
		if shown >= 4:
			break
		var record: Dictionary = history[i]
		lines.append(
			"  #%d %s  %s%s"
			% [
				record.get("id", 0), record.get("type_name", "?"),
				"reported" if record.get("reported", false)
					else ("seen" if record.get("witnessed", false) else "unseen"),
				"  (+%d)" % int(record.get("wanted_points", 0)),
			]
		)
		shown += 1

	_label.text = "\n".join(lines)
