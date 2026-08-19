extends Node
## The city, above the level of any one district.
##
## Owns the register of districts and the answer to "where is this?" — which
## district a position is in, how busy it should be, what it costs to rent there.
## Everything that used to assume one square of map asks here instead.
##
## It deliberately owns no geometry. Districts build themselves and register what
## they are; this is the index.

signal district_registered(district: DistrictData)
signal player_district_changed(district: DistrictData)

## How often the player's district is re-checked. A rectangle test is cheap, but
## not free, and nobody crosses a district boundary sixty times a second.
const CHECK_INTERVAL := 0.5

var _districts: Array[DistrictData] = []
var _by_id: Dictionary = {}
var _player_district: DistrictData = null
var _announced: Dictionary = {}
var _timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func register(district: DistrictData) -> void:
	if district == null or _by_id.has(district.district_id):
		return
	_districts.append(district)
	_by_id[district.district_id] = district
	district_registered.emit(district)


func get_districts() -> Array[DistrictData]:
	return _districts.duplicate()


func by_id(id: StringName) -> DistrictData:
	return _by_id.get(id)


func count() -> int:
	return _districts.size()


## Which district a point is in. Falls back to the nearest one, so a position on
## a connecting road between two districts always has an answer.
func district_at(position: Vector3) -> DistrictData:
	var nearest: DistrictData = null
	var best := INF
	for district in _districts:
		var distance := district.distance_to(position)
		if distance <= 0.0:
			return district
		if distance < best:
			best = distance
			nearest = district
	return nearest


func player_district() -> DistrictData:
	return _player_district


## The bounds of the whole city, which the map draws itself from.
func city_bounds() -> Rect2:
	if _districts.is_empty():
		return Rect2(-100.0, -100.0, 200.0, 200.0)
	var bounds := _districts[0].world_bounds
	for i in range(1, _districts.size()):
		bounds = bounds.merge(_districts[i].world_bounds)
	return bounds


# --- Lookups the rest of the game uses -----------------------------------

func traffic_density_at(position: Vector3) -> float:
	var district := district_at(position)
	return district.traffic_density if district != null else 1.0


func pedestrian_density_at(position: Vector3) -> float:
	var district := district_at(position)
	return district.pedestrian_density if district != null else 1.0


func commercial_demand_at(position: Vector3) -> float:
	var district := district_at(position)
	return district.commercial_demand_modifier if district != null else 1.0


func police_presence_at(position: Vector3) -> float:
	var district := district_at(position)
	return district.police_presence if district != null else 1.0


# --- Where the player is -------------------------------------------------

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	_refresh_player_district()


func _refresh_player_district() -> void:
	var player := GameManager.player
	if player == null or _districts.is_empty():
		return
	var district := district_at(player.global_position)
	if district == _player_district:
		return
	_player_district = district
	player_district_changed.emit(district)
	_announce(district)


## Named the first time the player arrives, and not every time they cross back
## and forth over the line afterwards.
func _announce(district: DistrictData) -> void:
	if district == null or _announced.has(district.district_id):
		return
	_announced[district.district_id] = true
	var text := district.display_name.to_upper()
	if not district.subtitle.is_empty():
		text += "\n" + district.subtitle
	GameManager.notify(text, GameManager.Tone.INFO)


## Development and testing entry point.
func forget_announcements() -> void:
	_announced.clear()
