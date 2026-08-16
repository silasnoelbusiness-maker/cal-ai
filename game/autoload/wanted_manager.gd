extends Node
## Owns the wanted level, the escape countdown and the bust.
##
## Split deliberately from CrimeManager, which only records what happened, and
## from WitnessSystem, which only decides whether anyone saw it. This file is
## the one place that answers "how much heat is the player under, and what
## happens next" — police units read it, they do not each keep their own idea of
## the chase.
##
## The escape rule is the important one: police never track the player directly.
## They are told where the player was last *seen*, and if nobody has seen them
## for `sight_grace_seconds` the escape countdown starts. Officers then search
## that last known position rather than following the player through walls.

signal level_changed(level: int)
signal escaping_started(seconds: float)
signal escaping_cancelled()
signal wanted_cleared()
## Emitted the moment the arrest lands, before the fine is charged.
signal bust_started()
signal bust_finished(fine_paid: int)

## Architecture supports five; phases beyond E fill in 3-5.
const MAX_LEVEL := 5

@export_group("Escape")
## Seconds of not being seen before "ESCAPING..." begins.
@export var sight_grace_seconds: float = 1.6
## Escape countdown per wanted level. Index 0 is unused.
@export var escape_seconds_by_level: Array[float] = [0.0, 18.0, 26.0, 32.0, 38.0, 45.0]

@export_group("Response")
## How far from the crime an officer will answer a call, per level.
@export var response_radius_by_level: Array[float] = [0.0, 75.0, 140.0, 200.0, 260.0, 320.0]

@export_group("Arrest")
@export var arrest_distance: float = 2.8
## Police cars can reach in from a little further than an officer on foot.
@export var vehicle_arrest_distance: float = 4.6
## A player moving faster than this cannot be grabbed — no arrests at 80 km/h.
@export var arrest_max_player_speed: float = 7.0
@export var bust_fine: int = 150
## How long the BUSTED overlay holds before play resumes.
@export var bust_hold_seconds: float = 2.6

var level: int = 0
## Where police think the player is. Never the player's live position.
var last_known_position: Vector3 = Vector3.ZERO

var _escaping: bool = false
var _escape_time_left: float = 0.0
var _time_since_seen: float = 0.0
var _busting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Wanted state is not saved; a loaded game starts clean, which the brief
	# explicitly allows and which avoids restoring a chase with no pursuers.
	SaveManager.game_loaded.connect(_on_game_loaded)


## Development-only. F6 / F7 set a wanted level outright and F9 clears it, so a
## chase can be started without committing a crime first. Delete this method and
## the three input actions for a release build.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_wanted_1"):
		set_level(1)
	elif event.is_action_pressed("debug_wanted_2"):
		set_level(2)
	elif event.is_action_pressed("debug_clear_wanted"):
		clear_wanted("WANTED LEVEL CLEARED")
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if level <= 0 or _busting or GameManager.is_paused():
		return

	_time_since_seen += delta

	if not _escaping and _time_since_seen >= sight_grace_seconds:
		_begin_escaping()
	elif _escaping:
		_escape_time_left -= delta
		if _escape_time_left <= 0.0:
			clear_wanted("WANTED LEVEL CLEARED")


# --- Queries -------------------------------------------------------------

func is_wanted() -> bool:
	return level > 0


func is_escaping() -> bool:
	return _escaping


func is_busting() -> bool:
	return _busting


func get_escape_seconds_left() -> float:
	return maxf(_escape_time_left, 0.0)


func get_response_radius() -> float:
	return _lookup(response_radius_by_level, level, 100.0)


# --- Crime -> heat -------------------------------------------------------

## Called by WitnessSystem once a crime has actually been reported. An
## unreported crime never reaches this method, which is what makes an unseen
## theft free.
func on_crime_reported(record: Dictionary) -> void:
	var stars := int(record.get("wanted_value", 1))
	var position: Vector3 = record.get("position", last_known_position)
	last_known_position = position
	_note_sighting()
	raise_to(maxi(level + (1 if is_wanted() else 0), stars), position)


## Sets the wanted level, never lowering it. `origin` seeds where police start
## looking.
func raise_to(new_level: int, origin: Vector3 = Vector3.INF) -> void:
	new_level = clampi(new_level, 0, MAX_LEVEL)
	if new_level <= level:
		return
	if origin != Vector3.INF:
		last_known_position = origin
	_set_level(new_level)
	_cancel_escaping()
	GameManager.notify("POLICE ALERTED\n%s" % _stars_text(), GameManager.Tone.BAD)


## Development and testing entry point; also used by the bust to reset heat.
func set_level(new_level: int) -> void:
	new_level = clampi(new_level, 0, MAX_LEVEL)
	if new_level == level:
		return
	if new_level == 0:
		clear_wanted("")
		return
	if GameManager.player != null:
		last_known_position = GameManager.player.global_position
	_set_level(new_level)
	_cancel_escaping()
	_note_sighting()


func clear_wanted(message: String = "") -> void:
	if level == 0 and not _escaping:
		return
	_cancel_escaping()
	_set_level(0)
	wanted_cleared.emit()
	if not message.is_empty():
		GameManager.notify(message, GameManager.Tone.GOOD)


# --- Police feedback -----------------------------------------------------

## Called by any police unit that currently has eyes on the player. This is the
## only way last_known_position is ever updated during a chase.
func notify_player_seen(position: Vector3) -> void:
	if level <= 0:
		return
	last_known_position = position
	_note_sighting()
	if _escaping:
		_cancel_escaping()
		escaping_cancelled.emit()
		GameManager.notify("SPOTTED", GameManager.Tone.BAD)


## Police ask; the manager decides. Keeps the "can they actually grab me" rule
## in one place instead of duplicated in every unit.
func can_arrest(distance: float, from_vehicle: bool) -> bool:
	if level <= 0 or _busting:
		return false
	var reach := vehicle_arrest_distance if from_vehicle else arrest_distance
	if distance > reach:
		return false
	var player := GameManager.player
	if player == null:
		return false
	var speed := 0.0
	if player.has_method("get_vehicle") and player.call("get_vehicle") != null:
		speed = player.call("get_vehicle").call("get_planar_speed")
	elif player.has_method("get_planar_speed"):
		speed = player.call("get_planar_speed")
	return speed <= arrest_max_player_speed


func request_bust() -> void:
	if _busting or level <= 0:
		return
	_bust()


# --- Internals -----------------------------------------------------------

func _set_level(new_level: int) -> void:
	if level == new_level:
		return
	level = new_level
	level_changed.emit(level)


func _note_sighting() -> void:
	_time_since_seen = 0.0


func _begin_escaping() -> void:
	_escaping = true
	_escape_time_left = _lookup(escape_seconds_by_level, level, 20.0)
	escaping_started.emit(_escape_time_left)
	GameManager.notify("ESCAPING...", GameManager.Tone.INFO)


func _cancel_escaping() -> void:
	_escaping = false
	_escape_time_left = 0.0


## The arrest. Freezes play with the existing cutscene flag (not the pause
## menu, so Esc cannot skip it), holds the overlay, then charges, relocates and
## hands control back.
func _bust() -> void:
	_busting = true
	_cancel_escaping()
	GameManager.cutscene_active = true
	bust_started.emit()

	var player := GameManager.player
	_release_stolen_vehicle(player)

	# Runs while the tree is paused.
	await get_tree().create_timer(bust_hold_seconds, true, false, false).timeout

	# Never overdraw: a player with $40 pays $40, not a negative balance.
	var fine: int = mini(bust_fine, EconomyManager.cash)
	if fine > 0:
		EconomyManager.spend(fine, "Police fine")

	_move_to_release_point(player)
	_set_level(0)
	wanted_cleared.emit()

	_busting = false
	GameManager.cutscene_active = false
	bust_finished.emit(fine)


## A stolen car goes back where it was parked. The player's own car is left
## exactly where they left it — being arrested must not cost them ownership.
func _release_stolen_vehicle(player: Node) -> void:
	if player == null or not player.has_method("get_vehicle"):
		return
	var vehicle = player.call("get_vehicle")
	if vehicle == null:
		return
	vehicle.call("exit_driver", true)
	if not vehicle.call("is_player_owned"):
		vehicle.call("return_to_spawn")


func _move_to_release_point(player: Node) -> void:
	if player == null:
		return
	var marker := get_tree().get_first_node_in_group(&"bust_release_point") as Node3D
	var destination := (
		marker.global_transform if marker != null
		else Transform3D(Basis(), player.global_position)
	)
	GameManager.teleport_player(destination)


func _stars_text() -> String:
	return "★".repeat(level) + "☆".repeat(MAX_LEVEL - level)


func _lookup(table: Array, index: int, fallback: float) -> float:
	if index < 0 or index >= table.size():
		return fallback
	return float(table[index])


func _on_game_loaded(_slot: int) -> void:
	clear_wanted("")
