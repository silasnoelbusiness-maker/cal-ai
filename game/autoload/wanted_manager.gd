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

## Architecture supports five; levels 4 and 5 are reachable by points but have no
## distinct police behaviour yet.
const MAX_LEVEL := 5

@export_group("Heat")
## Wanted points at which each star lights up. Index is the level, so a player
## on 45 points is at two stars. Everything the player does adds points to one
## meter rather than setting a star count directly, which is what makes crimes
## stack: a theft then a robbery is worse than either alone, and changing what a
## crime is worth is editing CrimeManager.PROFILES, not this file.
@export var level_thresholds: Array[int] = [0, 20, 40, 70, 110, 160]
## Points are not shed during a chase. The escape countdown clears them outright
## when it completes, which is the only way heat ever goes away.
@export var points: int = 0

@export_group("Escape")
## Seconds of not being seen before "ESCAPING..." begins.
@export var sight_grace_seconds: float = 1.6
## Escape countdown per wanted level. Index 0 is unused.
@export var escape_seconds_by_level: Array[float] = [0.0, 18.0, 26.0, 32.0, 38.0, 45.0]

@export_group("Response")
## How far from the crime an officer will answer a call, per level.
@export var response_radius_by_level: Array[float] = [0.0, 75.0, 140.0, 200.0, 260.0, 320.0]
## How many units may be out on a call at once, per level. A cap rather than a
## target: the district is small, and twenty patrol cars in it is a traffic jam,
## not a manhunt.
@export var response_budget_by_level: Array[int] = [0, 2, 3, 5, 6, 8]
## Multiplies police pursuit speed and persistence per level, so three stars
## feels heavier than one without needing a second set of AI.
@export var pursuit_pressure_by_level: Array[float] = [1.0, 1.0, 1.1, 1.25, 1.35, 1.45]

@export_group("Arrest")
@export var arrest_distance: float = 2.8
## Police cars can reach in from a little further than an officer on foot.
@export var vehicle_arrest_distance: float = 4.6
## A player moving faster than this cannot be grabbed — no arrests at 80 km/h.
@export var arrest_max_player_speed: float = 7.0
## Fine per wanted level at the moment of arrest. Index 0 is unused.
@export var bust_fine_by_level: Array[int] = [0, 100, 250, 500, 750, 1000]
## How long the BUSTED overlay holds before play resumes.
@export var bust_hold_seconds: float = 2.6
## Anything the player was carrying that is flagged stolen is seized on arrest.
## Legitimately bought goods are never touched.
@export var confiscate_stolen_goods: bool = true

var level: int = 0
## Where police think the player is. Never the player's live position.
var last_known_position: Vector3 = Vector3.ZERO

## Fine the player could not cover at the moment of arrest. Nothing collects it
## yet; it exists so a later debt or court system has a figure to work from
## rather than the arrest silently forgiving the difference.
var unpaid_penalty: int = 0

## Units currently out on the call. See the dispatch section below.
var _responders: Array[Node] = []

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
##
## The crime's points are *added*, not assigned. That is the whole of the
## escalation rule: a theft leaves the player on 20, robbing a store afterwards
## takes them to 60, and carjacking on top of that to 95 — three stars — without
## any crime needing to know what the others were worth.
func on_crime_reported(record: Dictionary) -> void:
	var position: Vector3 = record.get("position", last_known_position)
	last_known_position = position
	_note_sighting()
	add_points(int(record.get("wanted_points", 10)), position)


## Adds heat and lights whatever star that reaches. The only way the level goes
## up.
func add_points(amount: int, origin: Vector3 = Vector3.INF) -> void:
	if amount <= 0:
		return
	if origin != Vector3.INF:
		last_known_position = origin
	points += amount
	var reached := level_for_points(points)
	if reached > level:
		_set_level(reached)
		GameManager.notify("POLICE ALERTED\n%s" % _stars_text(), GameManager.Tone.BAD)
	elif is_wanted():
		# Already wanted and still under the next threshold: the player should
		# still know the heat went up, and the police should re-anchor on the
		# fresh crime rather than keep searching the old scene.
		GameManager.notify("WANTED LEVEL RISING", GameManager.Tone.BAD)
	_cancel_escaping()


## Star count for a points total. Public because the HUD debug overlay and the
## tests both want to reason about the thresholds without duplicating them.
func level_for_points(value: int) -> int:
	var reached := 0
	for candidate in range(1, level_thresholds.size()):
		if value >= int(level_thresholds[candidate]):
			reached = candidate
	return mini(reached, MAX_LEVEL)


## Points needed to reach a level, for the debug overlay and for tests.
func points_for_level(target: int) -> int:
	if target <= 0 or target >= level_thresholds.size():
		return 0
	return int(level_thresholds[target])


func get_response_budget() -> int:
	if level <= 0 or level >= response_budget_by_level.size():
		return 0
	return int(response_budget_by_level[level])


## How hard the police push at the current level. Police AI multiplies its
## speeds and timeouts by this rather than each unit deciding for itself.
func get_pursuit_pressure() -> float:
	return _lookup(pursuit_pressure_by_level, level, 1.0)


# --- Dispatch ------------------------------------------------------------
#
# How many units are on the call, rather than how far away they are. The radius
# decides who *could* answer; this decides how many actually do, so one star is
# a patrol car and three stars is a response. Units ask before they set off and
# say so when they go home; nothing else keeps a list of who is chasing.

## Units currently answering the call.
func get_active_responders() -> int:
	_responders = _responders.filter(func(u: Node) -> bool: return is_instance_valid(u))
	return _responders.size()


## Asks to join the response. `already_engaged` is for a unit that can see the
## player right now: it is past the point of being told to stay at its post, so
## it joins over budget and is counted rather than being turned away.
func request_dispatch(unit: Node, already_engaged: bool = false) -> bool:
	if unit == null or level <= 0:
		return false
	if _responders.has(unit):
		return true
	if not already_engaged and get_active_responders() >= get_response_budget():
		return false
	_responders.append(unit)
	return true


func release_dispatch(unit: Node) -> void:
	_responders.erase(unit)


func is_dispatched(unit: Node) -> bool:
	return _responders.has(unit)


## Raises the level to at least `new_level` by topping the points up to its
## threshold. Going through the meter rather than setting the star directly is
## what stops the two disagreeing — there is one number, and the stars are a
## reading of it.
func raise_to(new_level: int, origin: Vector3 = Vector3.INF) -> void:
	new_level = clampi(new_level, 0, MAX_LEVEL)
	if new_level <= level:
		return
	var needed := points_for_level(new_level) - points
	if needed > 0:
		add_points(needed, origin)


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
	points = points_for_level(new_level)
	_set_level(new_level)
	_cancel_escaping()
	_note_sighting()


func clear_wanted(message: String = "") -> void:
	if level == 0 and not _escaping and points == 0:
		return
	var was_escaping := _escaping
	_cancel_escaping()
	points = 0
	_responders.clear()
	_set_level(0)
	if was_escaping:
		CrimeManager.add_statistic(&"times_escaped")
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


## What an arrest costs at the current level.
func get_bust_fine() -> int:
	if level <= 0 or level >= bust_fine_by_level.size():
		return int(bust_fine_by_level[1]) if bust_fine_by_level.size() > 1 else 0
	return int(bust_fine_by_level[level])


func request_bust() -> void:
	if _busting or level <= 0:
		return
	_bust()


# --- Internals -----------------------------------------------------------

func _set_level(new_level: int) -> void:
	if level == new_level:
		return
	level = new_level
	CrimeManager.raise_statistic(&"highest_wanted_level", level)
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

	# Never overdraw: a player with $40 pays $40, not a negative balance. What is
	# left unpaid is tracked rather than forgiven, so a debt system later has
	# something to read; nothing charges it yet.
	var due := get_bust_fine()
	var fine: int = mini(due, EconomyManager.cash)
	if fine > 0:
		EconomyManager.spend(fine, "Police fine", EconomyManager.Source.LEGAL)
	unpaid_penalty += due - fine
	CrimeManager.add_statistic(&"times_busted")
	CrimeManager.add_statistic(&"fines_paid", fine)

	if confiscate_stolen_goods:
		_seize_stolen_goods(player)

	_move_to_release_point(player)
	points = 0
	_set_level(0)
	wanted_cleared.emit()

	_busting = false
	GameManager.cutscene_active = false
	bust_finished.emit(fine)


## Stolen goods are seized; anything bought legitimately is left alone. The
## distinction is per-stack metadata on the inventory, so this is one call and
## cannot touch a legally-owned item by accident.
func _seize_stolen_goods(player: Node) -> void:
	if player == null or not player.has_method("get_inventory"):
		return
	var inventory = player.call("get_inventory")
	if inventory == null or not inventory.has_method("remove_stolen"):
		return
	var seized: int = inventory.call("remove_stolen")
	if seized > 0:
		GameManager.notify("STOLEN GOODS SEIZED\n%d item%s" % [seized, "" if seized == 1 else "s"], GameManager.Tone.BAD)


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
	points = 0
	clear_wanted("")
