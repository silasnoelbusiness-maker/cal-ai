class_name JobStation
extends Interactable
## The place a job is worked from — the warehouse gate, a shop counter, a depot.
##
## The station owns the state that belongs to *this* workplace (shifts worked
## today) while the JobData resource owns the terms. A second job is a second
## station with a different resource.

signal shift_started()
signal shift_completed(pay: int)
signal shift_refused(reason: Refusal)

enum Refusal { NONE, CLOSED, TOO_TIRED, NO_SHIFTS_LEFT, NO_WORKER }

@export var job: JobData

var _shifts_worked_today: int = 0
var _tracked_day: int = -1


func _ready() -> void:
	_tracked_day = TimeManager.day_index
	TimeManager.day_passed.connect(_on_day_passed)
	TimeManager.hour_passed.connect(_on_hour_passed)
	TimeManager.clock_synced.connect(_refresh_prompt)
	_refresh_prompt()


## Everything that would stop a shift starting, in the order the player should
## hear about it.
func get_refusal(worker: Node3D) -> Refusal:
	if job == null:
		return Refusal.NO_WORKER
	if worker == null or not worker.has_method("get_stats"):
		return Refusal.NO_WORKER
	if not job.is_open_at(TimeManager.hour):
		return Refusal.CLOSED
	if _shifts_worked_today >= job.shifts_per_day:
		return Refusal.NO_SHIFTS_LEFT

	var stats: PlayerStats = worker.call("get_stats")
	if stats == null:
		return Refusal.NO_WORKER
	if stats.energy < job.min_energy:
		return Refusal.TOO_TIRED
	return Refusal.NONE


func get_shifts_left() -> int:
	if job == null:
		return 0
	return maxi(0, job.shifts_per_day - _shifts_worked_today)


func _perform(interactor: Node3D) -> void:
	var refusal := get_refusal(interactor)
	if refusal != Refusal.NONE:
		shift_refused.emit(refusal)
		GameManager.notify(describe_refusal(refusal, job), GameManager.Tone.BAD)
		return

	shift_started.emit()

	# The clock skip drives hunger and energy drain through PlayerStats, so a
	# shift costs the player real time as well as effort.
	TimeManager.advance_minutes(job.get_shift_minutes())
	var stats: PlayerStats = interactor.call("get_stats")
	stats.add_energy(-job.energy_cost)

	EconomyManager.deposit(job.pay, "Shift — %s" % job.title)
	_shifts_worked_today += 1
	_refresh_prompt()

	shift_completed.emit(job.pay)
	GameManager.notify("SHIFT COMPLETE\n+$%d" % job.pay, GameManager.Tone.GOOD)


static func describe_refusal(refusal: Refusal, job_data: JobData) -> String:
	match refusal:
		Refusal.CLOSED:
			if job_data != null:
				return "CLOSED\nShifts run %02d:00 – %02d:00" % [
					job_data.opens_hour, job_data.closes_hour
				]
			return "CLOSED"
		Refusal.TOO_TIRED:
			return "TOO TIRED TO WORK\nSleep or drink something first"
		Refusal.NO_SHIFTS_LEFT:
			return "NO SHIFTS LEFT TODAY\nCome back tomorrow"
		_:
			return "CANNOT WORK HERE"


func _on_day_passed(day_index: int) -> void:
	_tracked_day = day_index
	_shifts_worked_today = 0
	_refresh_prompt()


func _on_hour_passed(_hour: int) -> void:
	_refresh_prompt()


## Keeps the prompt honest about whether a shift can actually be started.
func _refresh_prompt() -> void:
	if job == null:
		return
	var open := job.is_open_at(TimeManager.hour)
	var has_shifts := get_shifts_left() > 0
	available = open and has_shifts
	if not open:
		unavailable_prompt = "CLOSED · shifts from %02d:00" % job.opens_hour
	elif not has_shifts:
		unavailable_prompt = "NO SHIFTS LEFT TODAY"
	else:
		unavailable_prompt = ""
