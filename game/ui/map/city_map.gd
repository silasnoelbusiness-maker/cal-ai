extends Control
## The city map.
##
## Drawn rather than authored: the streets come from the road network the cars
## actually drive on and the district outlines from the districts themselves, so
## the map cannot disagree with the city. Markers are gathered fresh each time it
## opens for the same reason.
##
## M opens it, clicking a marker selects it, and SET DESTINATION hands it to
## MapManager — which is what the HUD arrow and the courier job both read.

signal opened()
signal closed()

## Padding inside the drawing area, in pixels.
const MARGIN := 26.0
const MARKER_RADIUS := 6.0

@onready var _canvas: Control = %MapCanvas
@onready var _title: Label = %MapTitle
@onready var _filters: HBoxContainer = %MapFilters
@onready var _selection: Label = %MapSelection
@onready var _actions: HBoxContainer = %MapActions

var _markers: Array[MapMarker] = []
var _selected: MapMarker = null
var _scale: float = 1.0
var _origin: Vector2 = Vector2.ZERO
var _bounds: Rect2 = Rect2()


func _ready() -> void:
	visible = false
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
	set_process(false)


func is_open() -> bool:
	return visible


func open() -> void:
	_markers = MapManager.visible_markers()
	_selected = null
	_build_filters()
	_refresh_selection()
	visible = true
	set_process(true)
	_canvas.queue_redraw()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	closed.emit()


## The player marker moves while the map is up, so it redraws — cheaply, because
## the map is a few hundred lines and some circles.
func _process(_delta: float) -> void:
	_canvas.queue_redraw()


# --- Projection ----------------------------------------------------------

## Works out the world-to-screen transform for the whole city, keeping the aspect
## ratio so streets stay square.
func _measure() -> void:
	_bounds = WorldManager.city_bounds().grow(20.0)
	var area := _canvas.size - Vector2(MARGIN, MARGIN) * 2.0
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0 or area.x <= 0.0:
		_scale = 1.0
		_origin = Vector2.ZERO
		return
	_scale = minf(area.x / _bounds.size.x, area.y / _bounds.size.y)
	var drawn := _bounds.size * _scale
	_origin = (_canvas.size - drawn) * 0.5 - _bounds.position * _scale


func _to_map(position: Vector3) -> Vector2:
	return _origin + Vector2(position.x, position.z) * _scale


func _to_world(point: Vector2) -> Vector3:
	var flat := (point - _origin) / maxf(_scale, 0.0001)
	return Vector3(flat.x, 0.0, flat.y)


# --- Drawing -------------------------------------------------------------

func _draw_map() -> void:
	_measure()
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.086, 0.098, 0.118))

	_draw_districts()
	_draw_streets()
	_draw_route()
	_draw_markers()
	_draw_player()


## District outlines and their names, so the player can see the shape of the
## city and where one part of it ends.
func _draw_districts() -> void:
	for district in WorldManager.get_districts():
		var top_left := _to_map(
			Vector3(district.world_bounds.position.x, 0.0, district.world_bounds.position.y)
		)
		var bottom_right := _to_map(
			Vector3(district.world_bounds.end.x, 0.0, district.world_bounds.end.y)
		)
		var rect := Rect2(top_left, bottom_right - top_left)
		_canvas.draw_rect(rect, Color(0.129, 0.145, 0.176), true)
		_canvas.draw_rect(rect, Color(1, 1, 1, 0.10), false, 1.0)
		_canvas.draw_string(
			ThemeDB.fallback_font, top_left + Vector2(10.0, 22.0),
			district.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.612, 0.647, 0.702)
		)


## Every lane the traffic can drive on, drawn as short segments from each node to
## its successors. The map is therefore literally a picture of the road network.
func _draw_streets() -> void:
	var network := get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	if network == null:
		return
	var colour := Color(0.298, 0.318, 0.361)
	for i in network.node_count():
		var from := _to_map(network.node_position(i))
		for j in network.successors(i):
			_canvas.draw_line(from, _to_map(network.node_position(j)), colour, 2.4)


func _draw_route() -> void:
	var route := MapManager.route_to_destination()
	if route.size() < 2:
		return
	var points := PackedVector2Array()
	for point in route:
		points.append(_to_map(point))
	_canvas.draw_polyline(points, Color(0.478, 0.792, 0.961, 0.9), 3.0)


## Every marker gets a dot. Names are fitted around each other rather than drawn
## on top of each other: a city-centre street with four addresses on it turned
## into one illegible smear the first time this drew them all unconditionally.
##
## A name that will not fit is dropped, not shrunk — the dot is still there to
## click, and clicking it names it in the panel underneath.
func _draw_markers() -> void:
	var font := ThemeDB.fallback_font
	var taken: Array[Rect2] = []
	# The selected marker is labelled first so it always wins its space, then the
	# rest in the order the categories matter.
	var order := _markers.duplicate()
	order.sort_custom(
		func(a: MapMarker, b: MapMarker) -> bool:
			return _label_priority(a) < _label_priority(b)
	)

	# The dots go down first and are reserved, so a name never lands on top of a
	# marker it does not belong to.
	for marker in _markers:
		var at := _to_map(marker.position)
		var colour := MapMarker.category_colour(marker.category)
		_canvas.draw_circle(at, MARKER_RADIUS + 2.0, Color(0.043, 0.051, 0.063, 0.9))
		_canvas.draw_circle(at, MARKER_RADIUS, colour)
		if marker == _selected:
			_canvas.draw_arc(at, MARKER_RADIUS + 5.0, 0.0, TAU, 24, Color.WHITE, 2.0)
		taken.append(Rect2(at - Vector2(8.0, 8.0), Vector2(16.0, 16.0)))

	for marker in order:
		var at := _to_map(marker.position)
		var size := font.get_string_size(marker.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		# Four places to try, in order of preference: beside the dot, then above
		# or below it.
		var placed := false
		for offset: Vector2 in [
			Vector2(10.0, 4.0), Vector2(-10.0 - size.x, 4.0),
			Vector2(-size.x * 0.5, -10.0), Vector2(-size.x * 0.5, 20.0),
		]:
			var origin := at + offset
			if origin.x < 2.0 or origin.x + size.x > _canvas.size.x - 2.0:
				continue
			var box := Rect2(origin + Vector2(-2.0, -11.0), size + Vector2(4.0, 4.0))
			var clash := false
			for other in taken:
				if other.intersects(box):
					clash = true
					break
			if clash:
				continue
			taken.append(box)
			_canvas.draw_string(
				font, origin, marker.label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MapMarker.category_colour(marker.category)
			)
			placed = true
			break
		if not placed:
			continue


## Which names get the space when two want it. The one the player has selected,
## then the places that are theirs, then everything else.
func _label_priority(marker: MapMarker) -> int:
	if marker == _selected:
		return 0
	match marker.category:
		MapMarker.Category.HOME:
			return 1
		MapMarker.Category.OWNED_BUSINESS:
			return 2
		MapMarker.Category.AVAILABLE_PROPERTY:
			return 3
		MapMarker.Category.LANDMARK:
			return 4
		MapMarker.Category.JOB:
			return 5
		_:
			return 6


## Where the player is, and which way they are pointing.
func _draw_player() -> void:
	var player := GameManager.player
	if player == null:
		return
	var at := _to_map(player.global_position)
	var facing: Vector3 = (
		player.call("get_facing") if player.has_method("get_facing") else Vector3.FORWARD
	)
	var heading := Vector2(facing.x, facing.z).normalized()
	var side := Vector2(-heading.y, heading.x)
	_canvas.draw_colored_polygon(
		PackedVector2Array([
			at + heading * 11.0, at - heading * 6.0 + side * 6.0, at - heading * 6.0 - side * 6.0
		]),
		Color(0.965, 0.965, 0.980)
	)


# --- Interaction ---------------------------------------------------------

func _on_canvas_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	_select_nearest(click.position)


## Whatever the click landed nearest, within reach of it.
func _select_nearest(point: Vector2) -> void:
	_measure()
	var best: MapMarker = null
	var best_distance := 22.0
	for marker in _markers:
		var distance := point.distance_to(_to_map(marker.position))
		if distance < best_distance:
			best_distance = distance
			best = marker
	_selected = best
	_refresh_selection()
	_canvas.queue_redraw()


func _refresh_selection() -> void:
	for child in _actions.get_children():
		child.queue_free()

	if _selected == null:
		var current := MapManager.get_destination()
		_selection.text = (
			"Heading for %s" % current.label if current != null
			else "Click a marker to select it."
		)
		if current != null:
			var clear := BusinessUIKit.button("CLEAR DESTINATION", 190.0)
			clear.pressed.connect(_on_clear_destination)
			_actions.add_child(clear)
		return

	var detail := _selected.detail
	if not detail.is_empty():
		detail = "  ·  " + detail
	_selection.text = "%s%s  ·  %s" % [
		_selected.label, detail, _district_name_for(_selected.position)
	]

	var set_destination := BusinessUIKit.button("SET DESTINATION", 190.0)
	set_destination.pressed.connect(_on_set_destination)
	_actions.add_child(set_destination)

	if _selected.category == MapMarker.Category.OWNED_BUSINESS:
		var view := BusinessUIKit.button("VIEW BUSINESS", 170.0)
		view.pressed.connect(_on_view_business)
		_actions.add_child(view)


func _district_name_for(position: Vector3) -> String:
	var district := WorldManager.district_at(position)
	return district.display_name if district != null else "Somewhere"


func _on_set_destination() -> void:
	MapManager.set_destination(_selected)
	_refresh_selection()


func _on_clear_destination() -> void:
	MapManager.clear_destination()
	_refresh_selection()


func _on_view_business() -> void:
	var business := BusinessManager.by_id(_selected.target_id)
	close()
	GameManager.close_menus()
	if business != null:
		GameManager.request_screen(&"business_direct", null, null)
		BusinessManager.business_changed.emit(business)


# --- Filters -------------------------------------------------------------

func _build_filters() -> void:
	for child in _filters.get_children():
		child.queue_free()
	for category in MapMarker.Category.values():
		var button := BusinessUIKit.button(MapMarker.category_name(category).to_upper(), 130.0)
		button.toggle_mode = true
		button.button_pressed = MapManager.is_category_shown(category)
		button.pressed.connect(_on_filter_toggled.bind(category))
		_filters.add_child(button)


func _on_filter_toggled(category: int) -> void:
	MapManager.toggle_category(category)
	_markers = MapManager.visible_markers()
	if _selected != null and not MapManager.is_category_shown(_selected.category):
		_selected = null
		_refresh_selection()
	_canvas.queue_redraw()
