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
## Which residence this bed belongs to. Only the bed in the player's current
## home is theirs to sleep in — a flat they merely rent out, or a show flat they
## have not taken on, is somebody else's bedroom.
@export var residence_id: StringName = &""


## Extra health a good bed gives back on top of the fitted one.
##
## Deliberately small. A bed the player bought should be worth having and must
## not be worth having so much that the game is about beds — the fitted bed
## already restores energy in full, so this is a comfort bonus, not a
## requirement, and an unfurnished flat remains perfectly playable.
const MAX_COMFORT_BONUS := 10.0


func comfort_bonus() -> float:
	if residence_id == StringName(""):
		return 0.0
	var best := HomeManager.best_bed(residence_id)
	if best == null:
		return 0.0
	# The kingsize is worth fourteen comfort; that is the top of the scale.
	return clampf(float(best.comfort_value) / 14.0, 0.0, 1.0) * MAX_COMFORT_BONUS


## In-game minutes from now until the next `wake_hour`, floored at the minimum.
func get_sleep_minutes() -> int:
	var now := TimeManager.minute_of_day
	var target := wake_hour * TimeManager.MINUTES_PER_HOUR
	var minutes := target - now
	if minutes <= 0:
		minutes += TimeManager.MINUTES_PER_DAY
	return maxi(minutes, min_sleep_minutes)


## True when this bed is in the place the player currently calls home. A bed with
## no residence set (a test scene, a future safehouse) is always available.
func is_players_bed() -> bool:
	if residence_id == StringName(""):
		return true
	var home := PropertyManager.current_home()
	return home != null and home.residence_id == residence_id


func can_interact(interactor: Node3D) -> bool:
	if not super.can_interact(interactor):
		return false
	if interactor == null or not interactor.has_method("get_stats"):
		return false
	return is_players_bed()


## The base class only shows `unavailable_prompt` when the whole interactable is
## switched off. This bed is on — it just is not yours — so it says so itself.
func get_prompt_text() -> String:
	if available and not is_players_bed():
		return unavailable_prompt
	return super.get_prompt_text()


func _perform(interactor: Node3D) -> void:
	var minutes := get_sleep_minutes()
	TimeManager.advance_minutes(minutes)

	var stats: PlayerStats = interactor.call("get_stats")
	if stats != null:
		stats.add_energy(energy_restore)
		stats.add_health(health_restore + comfort_bonus())

	AudioManager.play(&"sleep", AudioBuses.SFX, -6.0)
	slept.emit(minutes)
	# Waking up is the most natural break there is, so the game saves itself.
	SaveManager.autosave("slept")
	GameManager.notify(
		"SLEPT %dH %02dM\nWoke at %s" % [
			minutes / 60, minutes % 60, TimeManager.get_time_string()
		],
		GameManager.Tone.GOOD
	)
