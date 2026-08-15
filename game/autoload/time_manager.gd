extends Node
## In-game clock.
##
## Everything schedule-driven (shop opening hours, NPC routines, rent, shift
## timers) should subscribe to the signals here rather than reading the clock
## every frame. The clock is stored as a single float of "minutes since the
## start of the save", which keeps day rollover and time-skips trivial.

signal minute_passed(hour: int, minute: int)
signal hour_passed(hour: int)
signal day_passed(day_index: int)
signal phase_changed(phase: Phase)
## Emitted whenever time jumps forward in one step (sleeping, work shifts).
signal time_skipped(minutes: int)

enum Phase { MORNING, DAY, EVENING, NIGHT }

const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := 1440
const DAY_NAMES: Array[String] = [
	"MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY",
]

## How many in-game minutes elapse per real second. 1.0 => a full day lasts
## 24 real minutes. Tune here; nothing else should assume a rate.
@export var minutes_per_real_second: float = 1.0
## Set true to freeze the clock without pausing the whole game.
@export var clock_stopped: bool = false

var _elapsed_minutes: float = 8.0 * MINUTES_PER_HOUR  # start Monday 08:00
var _last_minute: int = -1
var _last_hour: int = -1
var _last_day: int = -1
var _phase: Phase = Phase.MORNING


func _ready() -> void:
	_last_minute = minute
	_last_hour = hour
	_last_day = day_index
	_phase = _phase_for_hour(hour)


func _process(delta: float) -> void:
	if clock_stopped:
		return
	_elapsed_minutes += delta * minutes_per_real_second
	_emit_elapsed_signals()


# --- Public read-only clock state ----------------------------------------

var total_minutes: float:
	get: return _elapsed_minutes

var day_index: int:
	get: return int(_elapsed_minutes / MINUTES_PER_DAY)

var minute_of_day: int:
	get: return int(_elapsed_minutes) % MINUTES_PER_DAY

var hour: int:
	get: return minute_of_day / MINUTES_PER_HOUR

var minute: int:
	get: return minute_of_day % MINUTES_PER_HOUR

## 0.0 at midnight, 0.5 at noon. Used by the day/night lighting.
var day_fraction: float:
	get: return fmod(_elapsed_minutes, float(MINUTES_PER_DAY)) / float(MINUTES_PER_DAY)


func get_day_name() -> String:
	return DAY_NAMES[day_index % DAY_NAMES.size()]


func get_time_string() -> String:
	return "%02d:%02d" % [hour, minute]


func get_phase() -> Phase:
	return _phase


func get_phase_name() -> String:
	return Phase.keys()[_phase]


## Jump the clock forward. Used by sleeping and work shifts.
func advance_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	_elapsed_minutes += float(minutes)
	time_skipped.emit(minutes)
	_emit_elapsed_signals()


func advance_hours(hours: float) -> void:
	advance_minutes(int(round(hours * MINUTES_PER_HOUR)))


## Restores a saved clock. Kept separate from advance_* so no skip signals fire.
func set_total_minutes(value: float) -> void:
	_elapsed_minutes = maxf(0.0, value)
	_last_minute = minute
	_last_hour = hour
	_last_day = day_index
	_set_phase(_phase_for_hour(hour))


# --- Internals -----------------------------------------------------------

## Fires the discrete clock signals. Time skips can cross many hours at once,
## so hour/day signals are emitted per elapsed unit rather than just once.
func _emit_elapsed_signals() -> void:
	if minute == _last_minute and hour == _last_hour and day_index == _last_day:
		return

	if minute != _last_minute or hour != _last_hour:
		_last_minute = minute
		minute_passed.emit(hour, minute)

	while _last_hour != hour or _last_day != day_index:
		_last_hour = (_last_hour + 1) % 24
		if _last_hour == 0:
			_last_day += 1
			day_passed.emit(_last_day)
		hour_passed.emit(_last_hour)

	_set_phase(_phase_for_hour(hour))


func _set_phase(new_phase: Phase) -> void:
	if new_phase == _phase:
		return
	_phase = new_phase
	phase_changed.emit(_phase)


func _phase_for_hour(h: int) -> Phase:
	if h >= 5 and h < 11:
		return Phase.MORNING
	if h >= 11 and h < 17:
		return Phase.DAY
	if h >= 17 and h < 21:
		return Phase.EVENING
	return Phase.NIGHT
