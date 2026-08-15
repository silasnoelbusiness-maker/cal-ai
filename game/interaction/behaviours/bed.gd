class_name Bed
extends Interactable
## Sleeping.
##
## Sleeps through to a target hour rather than for a fixed block, so going to
## bed late means a shorter night — which is what makes energy worth managing.
## Hunger keeps draining across the skip (PlayerStats works off elapsed clock
## time), so the player wakes up needing breakfast. That is the loop.

signal slept(minutes: int)

## The hour the player wakes at.
@export_range(0, 23) var wake_hour: int = 7
## Never sleep for less than this, even if it overshoots the wake hour.
@export var min_sleep_minutes: int = 180
@export_group("Restores")
@export var energy_restore: float = 100.0
@export var health_restore: float = 12.0


## In-game minutes from now until the next `wake_hour`, floored at the minimum.
func get_sleep_minutes() -> int:
	var now := TimeManager.minute_of_day
	var target := wake_hour * TimeManager.MINUTES_PER_HOUR
	var minutes := target - now
	if minutes <= 0:
		minutes += TimeManager.MINUTES_PER_DAY
	return maxi(minutes, min_sleep_minutes)


func can_interact(interactor: Node3D) -> bool:
	if not super.can_interact(interactor):
		return false
	return interactor != null and interactor.has_method("get_stats")


func _perform(interactor: Node3D) -> void:
	var minutes := get_sleep_minutes()
	TimeManager.advance_minutes(minutes)

	var stats: PlayerStats = interactor.call("get_stats")
	if stats != null:
		stats.add_energy(energy_restore)
		stats.add_health(health_restore)

	slept.emit(minutes)
	GameManager.notify(
		"SLEPT %dH %02dM\nWoke at %s" % [
			minutes / 60, minutes % 60, TimeManager.get_time_string()
		],
		GameManager.Tone.GOOD
	)
