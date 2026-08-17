class_name RestrictedArea
extends Area3D
## Somewhere the player is not supposed to be.
##
## Reusable rather than per-place: behind a shop counter, the warehouse staff
## floor and the back of the precinct are the same rule with different labels.
## A place becomes restricted by adding one of these and giving it a name.
##
## The player gets a warning first and a grace period to leave. Only staying
## after the warning files a crime, so brushing past a counter is never a
## criminal act — which matters when the camera is top-down and precise
## positioning is hard.

signal warned()
signal offence_committed()

@export var area_name: String = "RESTRICTED AREA"
## Seconds after the warning before it becomes trespassing.
@export var grace_seconds: float = 4.0
## Once an offence is filed, this long before the same area can file another.
## Without it, standing in a staff room quietly generates a crime every frame.
@export var repeat_seconds: float = 20.0
## Set false while the player has business here — a shop being robbed is not
## also going to complain about where the robber is standing.
@export var enforced: bool = true

var _player_inside: bool = false
var _time_inside: float = 0.0
var _warned: bool = false
var _cooldown: float = 0.0


func _ready() -> void:
	add_to_group(&"restricted_area")
	# Detects the player layer (2) only. Pedestrians and police walk wherever
	# they like; this is about the player breaking a rule.
	collision_layer = 0
	collision_mask = 1 << 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	if not _player_inside or not enforced or GameManager.is_paused():
		return

	_time_inside += delta
	if not _warned:
		_warned = true
		GameManager.notify("%s\nLEAVE NOW" % area_name, GameManager.Tone.BAD)
		warned.emit()
		return

	if _time_inside >= grace_seconds and _cooldown <= 0.0:
		_commit()


func is_player_inside() -> bool:
	return _player_inside


func _commit() -> void:
	_cooldown = repeat_seconds
	var player := GameManager.player
	CrimeManager.report_crime(
		CrimeManager.CrimeType.TRESPASSING,
		global_position,
		player,
		self,
		false,
		{"area_name": area_name}
	)
	offence_committed.emit()


func _on_body_entered(body: Node3D) -> void:
	if body != GameManager.player:
		return
	_player_inside = true
	_time_inside = 0.0
	_warned = false


func _on_body_exited(body: Node3D) -> void:
	if body != GameManager.player:
		return
	_player_inside = false
	_time_inside = 0.0
	_warned = false
