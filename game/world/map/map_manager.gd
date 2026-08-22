extends Node
## What the city map knows.
##
## Two jobs: gather the markers worth showing, and remember where the player has
## asked to go. It owns no geometry and caches nothing — the markers are built
## from whatever the world currently holds, so a shop that closed a minute ago
## says CLOSED without anything having to tell the map.

signal destination_changed(marker: MapMarker)
signal destination_reached(marker: MapMarker)

## How close counts as arriving.
@export var arrival_radius: float = 12.0

var _destination: MapMarker = null
var _filters: Dictionary = {}
var _timer: float = 0.0


func _ready() -> void:
	for category in MapMarker.Category.values():
		_filters[category] = true


# --- Markers -------------------------------------------------------------

## Everything worth putting on the map, gathered fresh.
func collect_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	markers.append_array(_business_markers())
	markers.append_array(_property_markers())
	markers.append_array(_residence_markers())
	markers.append_array(_job_markers())
	markers.append_array(_service_markers())
	markers.append_array(_vehicle_markers())
	markers.append_array(_for_sale_markers())
	markers.append_array(_owned_property_markers())
	markers.append_array(_warehouse_markers())
	markers.append_array(_delivery_markers())
	markers.append_array(_underworld_markers())
	return markers


func visible_markers() -> Array[MapMarker]:
	var shown: Array[MapMarker] = []
	for marker in collect_markers():
		if is_category_shown(marker.category):
			shown.append(marker)
	return shown


func _business_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for business in BusinessManager.get_businesses():
		var unit := PropertyManager.by_id(business.property_id)
		if unit == null:
			continue
		# One marker kind for every business the player owns, whatever it is:
		# five icons for five types is exactly the map clutter §115 warns off.
		# What kind it is goes in the line underneath, where it is useful.
		var definition := business.type_data()
		var detail := business.status_text()
		if definition != null:
			detail = "%s · %s" % [definition.display_name.to_upper(), detail]
		var brand := CompanyManager.brand_for_business(business)
		if brand != null and brand.branch_count() > 1:
			detail += " · %s" % brand.brand_name.to_upper()
		if business.missing_requirements().has("Ingredients"):
			detail += " · NO INGREDIENTS"
		elif business.total_shelf_units() == 0 and not business.serves_prepared_goods() \
				and not business.catalogue().is_empty() and not business.serves_from_storage():
			detail += " · LOW STOCK"
		markers.append(MapMarker.make(
			MapMarker.Category.OWNED_BUSINESS, business.business_name,
			unit.global_position, detail, business.business_id
		))
	return markers


func _property_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for unit in PropertyManager.get_properties():
		if not unit.is_vacant():
			continue
		markers.append(MapMarker.make(
			MapMarker.Category.AVAILABLE_PROPERTY, unit.address, unit.global_position,
			"AVAILABLE · $%d rent" % unit.rent_amount, unit.property_id
		))
	return markers


## Everything on the market that the player has actually walked past. A board
## has to have been read before the address appears here — the city is meant to
## be driven around rather than browsed from a menu.
func _for_sale_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for listing in RealEstate.discovered_listings():
		var door := RealEstate.door_for(listing.property_id)
		if door == null:
			continue
		markers.append(MapMarker.make(
			MapMarker.Category.FOR_SALE, listing.address, door.global_position,
			"FOR SALE · $%s · %s" % [
				EconomyManager.with_thousands_separator(listing.asking_price),
				listing.yield_label()
			],
			listing.property_id
		))
	return markers


## What the player owns, whether it is let, empty or lived in. Rentals read as
## rentals: the detail line is the money, because that is what the owner of a
## let flat is looking for on a map.
func _owned_property_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for record in RealEstate.portfolio():
		var door := RealEstate.door_for(record.property_id)
		if door == null:
			continue
		var rent := 0
		for tenant in RealEstate.tenants_in(record.property_id):
			rent += tenant.rent_amount
		var detail := record.use_label().to_upper()
		if rent > 0:
			detail += " · $%s per 7 days" % EconomyManager.with_thousands_separator(rent)
		markers.append(MapMarker.make(
			MapMarker.Category.MY_PROPERTY, record.address, door.global_position,
			detail, record.property_id
		))
	return markers


## §122 — the depots, with how full they are, since that is the one number a
## player looks at the map to decide about.
func _warehouse_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for warehouse in LogisticsManager.warehouses():
		var unit := PropertyManager.by_id(warehouse.property_id)
		if unit == null:
			continue
		markers.append(MapMarker.make(
			MapMarker.Category.WAREHOUSE, warehouse.display_name, unit.global_position,
			"%d of %d units  ·  %d racks" % [
				warehouse.used(), warehouse.capacity(), warehouse.racks
			],
			warehouse.warehouse_id
		))
	return markers


## §123 — where a run the player took on themselves has to end up. Only ever
## the player's own: a company van finding its own way is not the player's
## problem and does not belong on their map.
func _delivery_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for order in LogisticsManager.player_runs():
		var where := LogisticsManager.place_position(
			order.destination_kind, order.destination_id
		)
		if where == Vector3.ZERO:
			continue
		markers.append(MapMarker.make(
			MapMarker.Category.DELIVERY,
			LogisticsManager.place_name(order.destination_kind, order.destination_id),
			where, "DELIVERING  ·  %s" % order.cargo_text(), order.transfer_id
		))
	return markers


## §134 — contacts the player has actually met, and the objective of whatever
## job is running. Nothing here reveals a place before it has been found: an
## unmet contact has no marker, which is the whole of §126's discovery.
func _underworld_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return markers
	for node in tree.get_nodes_in_group(&"criminal_contact"):
		var door := node as CriminalContactPoint
		if door == null or not Underworld.is_unlocked(door.contact_id):
			continue
		var contact := door.contact()
		if contact == null:
			continue
		markers.append(MapMarker.make(
			MapMarker.Category.CONTACT, contact.display_name,
			door.global_position,
			contact.kind_label() if Underworld.will_deal(contact)
				else "%s  ·  closed to you" % contact.kind_label(),
			contact.contact_id
		))

	# The job itself, if one is running and it has somewhere to be.
	var job := Underworld.active_job()
	if job != null and job.objective == IllegalJobData.Objective.ROBBERY_CONTRACT:
		var target := tree.root.get_node_or_null(NodePath(String(job.target_id)))
		if target is Node3D:
			markers.append(MapMarker.make(
				MapMarker.Category.OBJECTIVE, job.target_name,
				(target as Node3D).global_position,
				job.objective_label().to_upper(), job.job_id
			))
	return markers


func _residence_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for node in get_tree().get_nodes_in_group(&"residence"):
		var home := node as ResidenceProperty
		if home == null:
			continue
		var detail := "HOME" if home.is_current_home() else (
			"LEASED" if home.is_leased_by_player() else "TO LET · $%d" % home.rent_amount
		)
		markers.append(MapMarker.make(
			MapMarker.Category.HOME, home.address, home.global_position, detail, home.residence_id
		))
	return markers


func _job_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for node in get_tree().get_nodes_in_group(&"job_station"):
		var station := node as Node3D
		if station == null:
			continue
		markers.append(MapMarker.make(
			MapMarker.Category.JOB, String(station.get("prompt_subtitle")),
			station.global_position, "Work"
		))
	for node in get_tree().get_nodes_in_group(&"courier_depot"):
		markers.append(MapMarker.make(
			MapMarker.Category.JOB, "Central Depot", (node as Node3D).global_position,
			"Courier work"
		))
	return markers


## Police stations, NPC shops and the city's landmarks — the things that are not
## the player's but are worth navigating by.
func _service_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for node in get_tree().get_nodes_in_group(&"bust_release_point"):
		markers.append(MapMarker.make(
			MapMarker.Category.POLICE, "Precinct House", (node as Node3D).global_position
		))
	for node in get_tree().get_nodes_in_group(&"shop"):
		var shop := node as Shop
		# Only counters out on the street: a player-owned till inside a leased
		# unit is already on the map as a business.
		if shop == null or shop.save_id != &"":
			continue
		markers.append(MapMarker.make(
			MapMarker.Category.SHOP, shop.shop_name, shop.global_position,
			"OPEN" if shop.is_open() else "CLOSED"
		))
	for node in get_tree().get_nodes_in_group(&"landmark"):
		var landmark := node as Node3D
		markers.append(MapMarker.make(
			MapMarker.Category.LANDMARK, String(landmark.get_meta("label", landmark.name)),
			landmark.global_position
		))
	return markers


## The player's own cars, wherever they were left. Its own category so it can
## be switched off: somebody who collects cars should not have their map buried
## under their own garage.
func _vehicle_markers() -> Array[MapMarker]:
	var markers: Array[MapMarker] = []
	for record in VehicleRegistry.get_fleet():
		var where := record.position
		var detail := "%s  ·  %s" % [record.condition_label(), record.mileage_label()]
		if record.is_stored():
			var garage := PropertyManager.garage_by_id(record.garage_id)
			if garage == null:
				continue
			where = garage.global_position
			detail = "IN %s" % garage.display_name.to_upper()
		markers.append(MapMarker.make(
			MapMarker.Category.MY_VEHICLE, record.display_name(), where, detail,
			record.instance_id
		))
	return markers


# --- Filters -------------------------------------------------------------

func is_category_shown(category: int) -> bool:
	return bool(_filters.get(category, true))


func set_category_shown(category: int, shown: bool) -> void:
	_filters[category] = shown


func toggle_category(category: int) -> void:
	set_category_shown(category, not is_category_shown(category))


# --- Destination ---------------------------------------------------------

func get_destination() -> MapMarker:
	return _destination


func has_destination() -> bool:
	return _destination != null


func set_destination(marker: MapMarker) -> void:
	_destination = marker
	destination_changed.emit(marker)
	if marker != null:
		GameManager.notify("DESTINATION SET\n%s" % marker.label.to_upper(), GameManager.Tone.INFO)


func clear_destination() -> void:
	if _destination == null:
		return
	_destination = null
	destination_changed.emit(null)


## Metres from the player to where they said they were going, or -1.
func distance_to_destination() -> float:
	var player := GameManager.player
	if _destination == null or player == null:
		return -1.0
	var offset := _destination.position - player.global_position
	offset.y = 0.0
	return offset.length()


## The route there, on whichever graph suits how the player is travelling.
## Drawn on the map rather than followed, so a road that is not the shortest way
## is still the way a car has to go.
func route_to_destination() -> PackedVector3Array:
	var player := GameManager.player
	var nav := get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	if _destination == null or player == null or nav == null:
		return PackedVector3Array()
	var layer := (
		NavGraph.Layer.ROAD if player.has_method("is_driving") and player.call("is_driving")
		else NavGraph.Layer.WALK
	)
	return nav.find_path(layer, player.global_position, _destination.position)


func _process(delta: float) -> void:
	if _destination == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.4
	var distance := distance_to_destination()
	if distance >= 0.0 and distance <= arrival_radius:
		var reached := _destination
		_destination = null
		destination_changed.emit(null)
		destination_reached.emit(reached)
