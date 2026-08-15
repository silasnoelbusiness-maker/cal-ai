class_name RestoreSpot
extends Interactable
## A spot that tops the player's needs back up: park benches, drinking
## fountains, and later beds and food.
##
## Data-driven on purpose — one script covers every "sit down and recover"
## object in the city, and the apartment bed in Phase B is the same script with
## bigger numbers and a longer time skip.

@export_group("Restores")
@export var health: float = 0.0
@export var energy: float = 0.0
@export var hunger: float = 0.0
@export_group("Cost")
## In-game minutes the clock jumps forward when used.
@export var time_cost_minutes: int = 0
## Real seconds before the spot can be used again.
@export var cooldown_seconds: float = 4.0
@export_group("Feedback")
@export var success_message: String = ""

var _cooldown_left: float = 0.0


func _ready() -> void:
	# Only ticks while a cooldown is running.
	set_process(false)


func _process(delta: float) -> void:
	if _cooldown_left <= 0.0:
		set_process(false)
		return
	_cooldown_left -= delta
	if _cooldown_left <= 0.0:
		available = true


func can_interact(interactor: Node3D) -> bool:
	if not super.can_interact(interactor):
		return false
	return interactor != null and interactor.has_method("get_stats")


func _perform(interactor: Node3D) -> void:
	var stats: PlayerStats = interactor.call("get_stats")
	if stats == null:
		return

	stats.add_health(health)
	stats.add_energy(energy)
	stats.add_hunger(hunger)

	if time_cost_minutes > 0:
		TimeManager.advance_minutes(time_cost_minutes)

	if not success_message.is_empty():
		GameManager.notify(success_message, GameManager.Tone.GOOD)

	if cooldown_seconds > 0.0:
		available = false
		_cooldown_left = cooldown_seconds
		set_process(true)
