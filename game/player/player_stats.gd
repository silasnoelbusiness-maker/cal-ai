class_name PlayerStats
extends Node
## Health / energy / hunger for the player.
##
## Hunger drains off the clock rather than off the frame, so the drain rate is
## tied to in-game time and costs nothing per frame. Values are deliberately
## forgiving for V0.1 — the needs exist to give food, sleep and sprinting a
## purpose, not to nag the player.

signal health_changed(value: float, max_value: float)
signal energy_changed(value: float, max_value: float)
signal hunger_changed(value: float, max_value: float)
signal exhausted()
signal died()

const MAX_VALUE := 100.0

@export_group("Drain")
## Hunger lost per in-game minute. A day is 1440 of them, so 0.055 empties a
## full bar in a little over a day and a 35-point meal buys about ten hours:
## breakfast and something in the evening. Needs are meant to be a rhythm, not
## an alarm.
@export var hunger_per_minute: float = 0.055
## Energy lost per in-game minute while awake. Slower than hunger, because
## sleep comes round once a day and meals do not.
@export var energy_per_minute: float = 0.042
## Extra energy lost per real second of sprinting.
@export var sprint_energy_per_second: float = 3.0
## Energy recovered per real second while standing still.
@export var idle_energy_per_second: float = 0.4
@export_group("Hunger")
## Hunger at or below this is felt: energy goes faster and the player is slower
## on their feet. Above it, being a little peckish costs nothing at all.
@export var hungry_below: float = 25.0
## How much faster energy goes while hungry.
@export var hungry_energy_multiplier: float = 1.8
@export_group("Tiredness")
## Energy at or below this and the player is dragging.
@export var tired_below: float = 20.0
## Movement multiplier when dragging. Noticeable, never crippling: a tired
## player must always still be able to get themselves home.
@export var tired_speed_multiplier: float = 0.78
@export_group("Recovery")
## Health regained per in-game minute while fed and rested, so a beating heals
## on its own over a day or so and one bad night cannot end a save. Nothing
## comes back while hungry.
@export var recovery_health_per_minute: float = 0.02
## Both hunger and energy must be above this fraction of full to recover.
@export var recovery_needs_fraction: float = 0.5
@export_group("Starvation")
## Health lost per in-game minute once hunger hits zero.
@export var starving_health_per_minute: float = 0.08

var health: float = MAX_VALUE
var energy: float = MAX_VALUE
var hunger: float = MAX_VALUE

var _was_exhausted: bool = false
var _is_dead: bool = false
## Clock reading the drain has already been charged up to.
var _drained_to_minutes: float = 0.0


func _ready() -> void:
	_drained_to_minutes = TimeManager.total_minutes
	# Both signals funnel into the same elapsed-time calculation. Sleeping and
	# work shifts jump the clock by hours at once, so counting drain per signal
	# would under-charge them by orders of magnitude; charging by elapsed
	# minutes is exact and immune to the two signals overlapping.
	TimeManager.minute_passed.connect(_on_clock_advanced)
	TimeManager.time_skipped.connect(_on_time_skipped)
	# A clock that was set rather than advanced must not be billed as elapsed
	# time — resync the watermark instead of charging for the jump.
	TimeManager.clock_synced.connect(_resync_drain_clock)
	# Push initial values so any UI built after us starts in sync.
	health_changed.emit(health, MAX_VALUE)
	energy_changed.emit(energy, MAX_VALUE)
	hunger_changed.emit(hunger, MAX_VALUE)


func has_energy_to_sprint(threshold: float = 1.0) -> bool:
	return energy > threshold


## Called by the player controller while sprinting.
func drain_sprint_energy(delta: float) -> void:
	add_energy(-sprint_energy_per_second * delta)


## Called by the player controller while standing still.
func recover_idle_energy(delta: float) -> void:
	add_energy(idle_energy_per_second * delta)


func add_health(amount: float) -> void:
	if is_zero_approx(amount):
		return
	health = clampf(health + amount, 0.0, MAX_VALUE)
	health_changed.emit(health, MAX_VALUE)
	if health <= 0.0 and not _is_dead:
		_is_dead = true
		died.emit()
	elif health > 0.0:
		_is_dead = false


func add_energy(amount: float) -> void:
	if is_zero_approx(amount):
		return
	energy = clampf(energy + amount, 0.0, MAX_VALUE)
	energy_changed.emit(energy, MAX_VALUE)
	var now_exhausted := energy <= 0.0
	if now_exhausted and not _was_exhausted:
		exhausted.emit()
	_was_exhausted = now_exhausted


func add_hunger(amount: float) -> void:
	if is_zero_approx(amount):
		return
	hunger = clampf(hunger + amount, 0.0, MAX_VALUE)
	hunger_changed.emit(hunger, MAX_VALUE)


## Used by the save system in a later phase.
func restore_values(new_health: float, new_energy: float, new_hunger: float) -> void:
	health = clampf(new_health, 0.0, MAX_VALUE)
	energy = clampf(new_energy, 0.0, MAX_VALUE)
	hunger = clampf(new_hunger, 0.0, MAX_VALUE)
	_is_dead = health <= 0.0
	_was_exhausted = energy <= 0.0
	_drained_to_minutes = TimeManager.total_minutes
	health_changed.emit(health, MAX_VALUE)
	energy_changed.emit(energy, MAX_VALUE)
	hunger_changed.emit(hunger, MAX_VALUE)


func _on_clock_advanced(_hour: int, _minute: int) -> void:
	_charge_drain()


func _on_time_skipped(_minutes: int) -> void:
	_charge_drain()


func _resync_drain_clock() -> void:
	_drained_to_minutes = TimeManager.total_minutes


## Charges needs for however much in-game time has passed since the last
## charge. Safe to call as often as you like — a second call with no elapsed
## time does nothing.
func _charge_drain() -> void:
	var now := TimeManager.total_minutes
	var elapsed := now - _drained_to_minutes
	if elapsed <= 0.0:
		_drained_to_minutes = now
		return
	_drained_to_minutes = now

	# Hunger is charged first so a player who goes hungry during this stretch
	# pays the faster energy rate for it rather than the following one.
	var was_hungry := is_hungry()
	add_hunger(-hunger_per_minute * elapsed)
	var energy_rate := energy_per_minute
	if was_hungry or is_hungry():
		energy_rate *= hungry_energy_multiplier
	add_energy(-energy_rate * elapsed)
	if hunger <= 0.0:
		add_health(-starving_health_per_minute * elapsed)
	elif can_recover():
		add_health(recovery_health_per_minute * elapsed)


## Hungry enough for it to cost them something.
func is_hungry() -> bool:
	return hunger <= hungry_below


func is_tired() -> bool:
	return energy <= tired_below


## What the player's legs are worth right now. One multiplier applied to both
## walking and sprinting, so tiredness reads the same whatever they are doing.
func movement_multiplier() -> float:
	return tired_speed_multiplier if is_tired() else 1.0


## Health only comes back to somebody both fed and rested. That is the whole
## recovery path: eat, sleep, wait. No medical system, and nothing you can buy
## that undoes a hospital trip.
func can_recover() -> bool:
	if health >= MAX_VALUE:
		return false
	var threshold := MAX_VALUE * recovery_needs_fraction
	return hunger >= threshold and energy >= threshold
