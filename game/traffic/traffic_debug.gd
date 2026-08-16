extends CanvasLayer
## Dev-only traffic readout, hidden by default.
##
## Kept out of the HUD scene deliberately: the HUD is the shipping interface and
## this is scaffolding. Deleting this node and its two input actions removes the
## whole thing, and nothing else references it.
##
## F1 toggles the readout, F2 cycles the density setting. F5/F6/F7/F8/F9/F12 are
## already spoken for by saving, the wanted-level keys and the vehicle unstick.

## Seconds between refreshes. The overlay is diagnostic, not a speedometer.
const REFRESH_INTERVAL := 0.25

const DENSITY_NAMES := ["LOW", "MEDIUM", "HIGH"]
const STATE_NAMES := ["DRIVING", "WAITING", "STUCK"]
const COLOUR_NAMES := ["RED", "YELLOW", "GREEN"]

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
	box.bg_color = Color(0.043, 0.051, 0.071, 0.82)
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
	_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.96))
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_traffic_overlay"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_traffic_density"):
		cycle_density()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_refresh()


## Steps LOW -> MEDIUM -> HIGH -> LOW. The manager takes the new population from
## the next upkeep tick, so the streets fill or thin out over a few seconds
## rather than all at once.
func cycle_density() -> void:
	var manager := _manager()
	if manager == null:
		return
	manager.density = ((manager.density + 1) % DENSITY_NAMES.size()) as TrafficManager.Density
	GameManager.notify("TRAFFIC DENSITY %s" % DENSITY_NAMES[manager.density], GameManager.Tone.INFO)
	if visible:
		_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	_refresh()


func _refresh() -> void:
	var manager := _manager()
	if manager == null:
		_label.text = "TRAFFIC\n  no manager in this scene"
		return

	var lines: Array[String] = ["TRAFFIC  (F1 hide, F2 density)"]
	lines.append(
		"  density %s   %d / %d cars"
		% [
			DENSITY_NAMES[manager.density],
			manager.get_active_count(),
			manager.get_target_population(),
		]
	)

	var driving := 0
	var waiting := 0
	var stuck := 0
	var total_speed := 0.0
	for car in manager.get_vehicles():
		if not is_instance_valid(car):
			continue
		total_speed += car.get_speed_kmh()
		var driver := car.get_node_or_null("Driver") as TrafficDriver
		if driver == null:
			continue
		match driver.state:
			TrafficDriver.State.WAITING:
				waiting += 1
			TrafficDriver.State.STUCK:
				stuck += 1
			_:
				driving += 1
	var count := maxi(manager.get_active_count(), 1)
	lines.append(
		"  driving %d   waiting %d   stuck %d   avg %.0f km/h"
		% [driving, waiting, stuck, total_speed / float(count)]
	)

	for light: TrafficLight in get_tree().get_nodes_in_group(&"traffic_light"):
		lines.append(
			"  %s  NS %s / EW %s"
			% [
				light.name,
				COLOUR_NAMES[light.colour_for(false)],
				COLOUR_NAMES[light.colour_for(true)],
			]
		)

	var network := get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	if network != null:
		lines.append("  lane nodes %d" % network.node_count())

	_label.text = "\n".join(lines)


func _manager() -> TrafficManager:
	return get_tree().get_first_node_in_group(&"traffic_manager") as TrafficManager
