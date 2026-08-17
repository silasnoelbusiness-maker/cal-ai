class_name CombatController
extends Node
## The player's fists, and whatever they are holding.
##
## Lives beside the InteractionController as a child of the player, for the same
## reason: the player controller owns movement and nothing else. This owns what
## is in the player's hand, what a swing hits, and what the law makes of it.
##
## Every attack runs through a WeaponData — bare hands included — so a bat, a
## crowbar or a later ranged weapon is a resource, not a branch. Targeting is
## deliberately forgiving: a wide arc, a generous reach and the target nearest to
## straight ahead. Precise aiming with WASD under a top-down camera is not a
## skill worth asking for.

signal attacked(target: Node3D)
signal equipped_changed(item: ItemData)

## Bare hands, used whenever nothing is equipped.
const FISTS: WeaponData = preload("res://items/weapons/fists.tres")

## Groups searched for something to hit. Anything in them that can take damage is
## a valid target; anything that cannot is ignored, so adding a breakable prop is
## a group tag rather than a change here.
const TARGET_GROUPS: Array[StringName] = [&"pedestrian"]

@export_group("Assault reporting")
## One assault is filed per victim per this many seconds. Without it a flurry of
## punches on one person files five crimes and five lots of heat, which reads as
## a bug however correct each individual record is.
@export var assault_report_interval: float = 20.0

@export_group("Knocked out")
## Seconds the screen holds while the player is out cold.
@export var down_hold_seconds: float = 2.4
## Health the player comes round with.
@export var revive_health: float = 35.0
## In-game minutes lost while unconscious.
@export var down_minutes: int = 90

var _player: Player = null
var _stats: PlayerStats = null
var _equipped: ItemData = null
var _cooldown: float = 0.0
## Instance id of each recent victim, and the time left before hitting them
## counts as a fresh assault.
var _recent_victims: Dictionary = {}
var _down: bool = false


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("CombatController must be a child of the Player.")
		set_process(false)
		return
	# Fetched by node rather than through the player's @onready property: a
	# child is ready before its parent, so that property is still null here.
	_stats = _player.get_node_or_null("Stats") as PlayerStats
	if _stats != null:
		_stats.died.connect(_on_player_died)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	for id in _recent_victims.keys():
		var left: float = float(_recent_victims[id]) - delta
		if left <= 0.0:
			_recent_victims.erase(id)
		else:
			_recent_victims[id] = left


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("attack"):
		return
	if not can_attack():
		return
	attack()
	get_viewport().set_input_as_handled()


# --- Equipment -----------------------------------------------------------

func get_equipped_item() -> ItemData:
	return _equipped


## What the next swing uses. Never null — empty hands are a weapon too.
func get_active_weapon() -> WeaponData:
	if _equipped != null and _equipped.weapon_data != null:
		return _equipped.weapon_data
	return FISTS


## Puts an item in the hand, or takes it back out if it is already there.
## Returns true when the state changed, which is what tells the inventory the
## use did something.
func equip_item(item: ItemData) -> bool:
	if item == null or not item.can_equip:
		return false
	if _equipped == item:
		unequip_item()
		return true
	_equipped = item
	equipped_changed.emit(_equipped)
	return true


func unequip_item() -> void:
	if _equipped == null:
		return
	_equipped = null
	equipped_changed.emit(null)


# --- Attacking -----------------------------------------------------------

func get_cooldown_left() -> float:
	return _cooldown


func can_attack() -> bool:
	if _player == null or _down or _player.is_driving():
		return false
	if GameManager.is_paused() or GameManager.cutscene_active:
		return false
	return _cooldown <= 0.0


## Swings. Returns whoever was hit, or null for a miss — a miss still costs the
## cooldown, so flailing is not free.
func attack() -> Node3D:
	if not can_attack():
		return null
	var weapon := get_active_weapon()
	_cooldown = weapon.cooldown

	var target := find_target(weapon)
	attacked.emit(target)
	if target == null:
		return null

	var direction := target.global_position - _player.global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
	else:
		direction = _player.get_facing()

	var floored := bool(target.call("take_damage", weapon.damage, direction))
	_shove(target, direction, weapon.knockback)
	if weapon.attacks_are_crimes:
		_report_assault(target, floored)
	return target


## The nearest thing to straight ahead, within reach and inside the arc. Angle
## dominates the score so the person the player is facing wins over somebody
## marginally closer off to one side.
func find_target(weapon: WeaponData = null) -> Node3D:
	if _player == null:
		return null
	var using := weapon if weapon != null else get_active_weapon()
	var origin := _player.global_position
	var facing := _player.get_facing()
	var half_arc := deg_to_rad(using.arc_degrees * 0.5)

	var best: Node3D = null
	var best_score := INF
	for group in TARGET_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or body == _player or not body.has_method("take_damage"):
				continue
			if body.has_method("is_incapacitated") and body.call("is_incapacitated"):
				continue

			var offset := body.global_position - origin
			offset.y = 0.0
			var distance := offset.length()
			if distance > using.attack_range or distance < 0.01:
				continue
			var angle := facing.angle_to(offset / distance)
			if angle > half_arc:
				continue

			var score := rad_to_deg(angle) + distance * 4.0
			if score < best_score:
				best_score = score
				best = body
	return best


## A shove rather than physics: NPCs are kinematic, so the hit asks them to move
## themselves on their next physics frame.
func _shove(target: Node3D, direction: Vector3, distance: float) -> void:
	if distance > 0.0 and target.has_method("shove"):
		target.call("shove", direction, distance)


func _report_assault(victim: Node3D, floored: bool) -> void:
	var id := victim.get_instance_id()
	if _recent_victims.has(id):
		return
	_recent_victims[id] = assault_report_interval
	CrimeManager.report_crime(
		CrimeManager.CrimeType.ASSAULT,
		victim.global_position,
		_player,
		victim,
		false,
		{"intent": CrimeManager.Intent.INTENTIONAL, "victim_down": floored}
	)


# --- Being knocked out ---------------------------------------------------

func is_down() -> bool:
	return _down


## Losing a fight is not the same as being arrested. There is no fine, nothing
## is confiscated, and the player wakes where they fell — but if the police were
## already after them, being unconscious in the street is how an arrest happens,
## so the bust runs instead.
func _on_player_died() -> void:
	if _down:
		return
	_down = true
	GameManager.cutscene_active = true
	GameManager.notify("KNOCKED OUT", GameManager.Tone.BAD)

	await get_tree().create_timer(down_hold_seconds, true, false, false).timeout

	GameManager.cutscene_active = false
	if WantedManager.level > 0:
		# Picked up where they lay.
		_stats.restore_values(revive_health, _stats.energy, _stats.hunger)
		WantedManager.request_bust()
	else:
		TimeManager.advance_minutes(down_minutes)
		_stats.restore_values(revive_health, _stats.energy, _stats.hunger)
		GameManager.notify("YOU CAME ROUND", GameManager.Tone.INFO)
	_down = false
