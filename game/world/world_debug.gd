extends CanvasLayer
## Dev-only world readout, hidden by default.
##
## Fourth of its kind, and the same rules as the traffic, crime and business
## overlays: not part of the HUD, never visible in a normal game, deleted by
## removing this node and its input action.
##
## F11 toggles the readout. While it is up, number keys switch on the world
## debug view — district bounds, lane nodes, walk graph, property ids and map
## markers, drawn in the world itself rather than on the panel.

const REFRESH_INTERVAL := 0.25

## The world view layers, in the order the number keys switch them.
enum Layer { DISTRICTS, ROAD_NODES, ROAD_LINKS, WALK_PATHS, PROPERTY_IDS, MARKERS }

const LAYER_KEYS := {
	KEY_1: Layer.DISTRICTS,
	KEY_2: Layer.ROAD_NODES,
	KEY_3: Layer.ROAD_LINKS,
	KEY_4: Layer.WALK_PATHS,
	KEY_5: Layer.PROPERTY_IDS,
	KEY_6: Layer.MARKERS,
}

const LAYER_NAMES := {
	Layer.DISTRICTS: "district bounds",
	Layer.ROAD_NODES: "road nodes",
	Layer.ROAD_LINKS: "traffic connections",
	Layer.WALK_PATHS: "pedestrian paths",
	Layer.PROPERTY_IDS: "property ids",
	Layer.MARKERS: "map markers",
}

## Drawn a little above the road so the lines are not inside it.
const DRAW_HEIGHT := 0.35

var _label: Label = null
var _timer: float = 0.0
var _enabled_layers: Dictionary = {}
var _lines: MeshInstance3D = null
var _labels: Node3D = null
var _line_material: StandardMaterial3D = null


func _ready() -> void:
	layer = 100
	_build_label()
	visible = false
	set_process(false)


func _build_label() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(18.0, 300.0)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.92)
	add_child(panel)

	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.043, 0.047, 0.067, 0.82)
	box.set_content_margin_all(10.0)
	box.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", box)

	_label = Label.new()
	_label.name = "Readout"
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.855, 0.898, 0.984))
	panel.add_child(_label)


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_refresh()
	else:
		# Leaving the overlay takes the world view with it. A debug line left
		# lying in the world after the panel is gone is a bug report waiting to
		# be filed.
		_enabled_layers.clear()
		_redraw_world()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_world_overlay"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return
	var keycode := (event as InputEventKey).keycode
	if keycode == KEY_0:
		_enabled_layers.clear()
	elif LAYER_KEYS.has(keycode):
		var layer_id: int = LAYER_KEYS[keycode]
		if _enabled_layers.has(layer_id):
			_enabled_layers.erase(layer_id)
		else:
			_enabled_layers[layer_id] = true
	else:
		return
	get_viewport().set_input_as_handled()
	_redraw_world()
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	_refresh()


# --- The readout ---------------------------------------------------------

func _refresh() -> void:
	var lines: Array[String] = ["WORLD  (F11 hide)"]

	var here := WorldManager.player_district()
	lines.append("  in: %s" % (here.display_name if here != null else "-"))
	var names: Array[String] = []
	for district in WorldManager.get_districts():
		names.append("%s%s" % [district.display_name, " *" if district == here else ""])
	lines.append("  districts loaded: %d   %s" % [WorldManager.count(), ", ".join(names)])

	if here != null:
		lines.append("  traffic x%.2f   people x%.2f   police x%.2f   demand x%.2f" % [
			here.traffic_density, here.pedestrian_density,
			here.police_presence, here.commercial_demand_modifier,
		])

	lines.append("  active: %d traffic   %d pedestrians   %d police" % [
		_active_traffic(), _active_pedestrians(), _active_police(),
	])

	var near := 0
	var far := 0
	for business in BusinessManager.get_businesses():
		if BusinessManager.is_player_present(business):
			near += 1
		else:
			far += 1
	lines.append("  businesses: %d simulated near   %d far" % [near, far])

	var nav := get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	var roads := get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	lines.append("  graph: %d walk   %d road   %d lane nodes" % [
		nav.point_count(NavGraph.Layer.WALK) if nav != null else 0,
		nav.point_count(NavGraph.Layer.ROAD) if nav != null else 0,
		roads.node_count() if roads != null else 0,
	])
	lines.append("  markers: %d" % MapManager.collect_markers().size())
	lines.append("  fps %d   frame %.1f ms" % [
		Engine.get_frames_per_second(),
		1000.0 / maxf(float(Engine.get_frames_per_second()), 1.0),
	])

	var view: Array[String] = []
	for key: int in LAYER_KEYS:
		var layer_id: int = LAYER_KEYS[key]
		view.append("%s%s" % [
			LAYER_NAMES[layer_id],
			" ON" if _enabled_layers.has(layer_id) else "",
		])
	lines.append("  view  1-6: %s   0 none" % "  ".join(view))

	_label.text = "\n".join(lines)


## Only what is actually running counts: the tests and the far-district rules
## both park NPCs by disabling them, and a readout that counted those would say
## the city is busy while nothing is moving.
func _active_traffic() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"vehicle"):
		if node.can_process() and (node as Node3D).visible:
			count += 1
	return count


func _active_pedestrians() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"pedestrian"):
		if node.can_process():
			count += 1
	return count


func _active_police() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"police"):
		if node.can_process():
			count += 1
	return count


# --- The world view ------------------------------------------------------

func _ensure_draw_nodes() -> void:
	if _lines != null and is_instance_valid(_lines):
		return
	var root := get_tree().current_scene
	if root == null:
		return

	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.no_depth_test = true

	_lines = MeshInstance3D.new()
	_lines.name = "WorldDebugLines"
	_lines.mesh = ImmediateMesh.new()
	_lines.material_override = _line_material
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_lines)

	_labels = Node3D.new()
	_labels.name = "WorldDebugLabels"
	root.add_child(_labels)


func _redraw_world() -> void:
	_ensure_draw_nodes()
	if _lines == null:
		return
	var mesh := _lines.mesh as ImmediateMesh
	mesh.clear_surfaces()
	for child in _labels.get_children():
		child.queue_free()

	if _enabled_layers.is_empty():
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if _enabled_layers.has(Layer.DISTRICTS):
		_draw_district_bounds(mesh)
	if _enabled_layers.has(Layer.ROAD_NODES):
		_draw_road_nodes(mesh)
	if _enabled_layers.has(Layer.ROAD_LINKS):
		_draw_road_links(mesh)
	if _enabled_layers.has(Layer.WALK_PATHS):
		_draw_walk_paths(mesh)
	mesh.surface_end()

	if _enabled_layers.has(Layer.PROPERTY_IDS):
		_draw_property_ids()
	if _enabled_layers.has(Layer.MARKERS):
		_draw_markers()


func _line(mesh: ImmediateMesh, from: Vector3, to: Vector3, colour: Color) -> void:
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(to)


func _draw_district_bounds(mesh: ImmediateMesh) -> void:
	for district in WorldManager.get_districts():
		var rect := district.world_bounds
		var height := DRAW_HEIGHT + 4.0
		var corners := [
			Vector3(rect.position.x, height, rect.position.y),
			Vector3(rect.end.x, height, rect.position.y),
			Vector3(rect.end.x, height, rect.end.y),
			Vector3(rect.position.x, height, rect.end.y),
		]
		var colour := Color(0.98, 0.78, 0.35)
		for i in corners.size():
			_line(mesh, corners[i], corners[(i + 1) % corners.size()], colour)


func _draw_road_nodes(mesh: ImmediateMesh) -> void:
	var roads := get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	if roads == null:
		return
	var colour := Color(0.45, 0.85, 1.0)
	for index in roads.node_count():
		var at := roads.node_position(index)
		at.y = DRAW_HEIGHT
		_line(mesh, at + Vector3(-0.5, 0.0, 0.0), at + Vector3(0.5, 0.0, 0.0), colour)
		_line(mesh, at + Vector3(0.0, 0.0, -0.5), at + Vector3(0.0, 0.0, 0.5), colour)
		# A stub in the direction of travel, so a lane pointing the wrong way is
		# visible rather than something to work out from the car that took it.
		_line(mesh, at, at + roads.node_direction(index) * 1.4, Color(0.3, 0.6, 0.8))


func _draw_road_links(mesh: ImmediateMesh) -> void:
	var roads := get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	if roads == null:
		return
	var colour := Color(0.55, 0.95, 0.65)
	for index in roads.node_count():
		var from := roads.node_position(index)
		from.y = DRAW_HEIGHT
		for next in roads.successors(index):
			var to := roads.node_position(next)
			to.y = DRAW_HEIGHT
			_line(mesh, from, to, colour)


func _draw_walk_paths(mesh: ImmediateMesh) -> void:
	var nav := get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	if nav == null:
		return
	# The walk layer has no public edge list, so this samples routes between
	# pedestrians and where they are heading — which is what actually matters
	# when a pedestrian is walking through a wall.
	var colour := Color(0.85, 0.6, 0.98)
	for node in get_tree().get_nodes_in_group(&"pedestrian"):
		var walker: Node3D = node as Node3D
		if walker == null or not walker.has_method("debug_path"):
			continue
		var path: PackedVector3Array = walker.call("debug_path")
		for i in range(1, path.size()):
			var from := path[i - 1]
			var to := path[i]
			from.y = DRAW_HEIGHT
			to.y = DRAW_HEIGHT
			_line(mesh, from, to, colour)


func _draw_property_ids() -> void:
	for property in PropertyManager.get_properties():
		_add_label(
			property.global_position + Vector3(0.0, 2.6, 0.0),
			"%s\n%s" % [property.property_id, property.address],
			Color(0.98, 0.85, 0.5)
		)
	for home in PropertyManager.get_residences():
		_add_label(
			home.global_position + Vector3(0.0, 2.6, 0.0),
			"%s\n%s" % [home.residence_id, home.address],
			Color(0.55, 0.78, 0.99)
		)


func _draw_markers() -> void:
	for marker in MapManager.collect_markers():
		_add_label(
			marker.position + Vector3(0.0, 4.0, 0.0),
			"%s\n%s" % [MapMarker.category_name(marker.category).to_upper(), marker.label],
			MapMarker.category_colour(marker.category)
		)


func _add_label(at: Vector3, text: String, colour: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.01
	label.modulate = colour
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = at
	_labels.add_child(label)
