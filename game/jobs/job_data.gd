class_name JobData
extends Resource
## Definition of one legal job.
##
## A job is pure data: hours, pay, and what the player needs to be able to work
## it. New jobs are new .tres files. Wages, schedules, requirements and shift
## limits are already separate fields so later jobs can vary them; experience,
## promotions and mini-games slot in as extra fields on this resource.

@export var id: StringName = &""
@export var title: String = "Worker"
@export var employer: String = "Employer"
@export_multiline var description: String = ""

@export_group("Shift")
@export var shift_hours: float = 4.0
@export var pay: int = 120
## Shifts the player may work at this station per in-game day.
@export var shifts_per_day: int = 2

@export_group("Requirements")
## §36 and §112 — only *some* work checks. Basic warehouse and courier shifts
## take anybody, because a player who cannot earn at all is a player with
## nowhere to go. A trusted role can turn somebody down, and above this record
## level it does. Zero means the job never asks.
@export var max_record_tier: int = 0
## The player must have at least this much energy to clock on.
@export var min_energy: float = 20.0
## Energy the shift costs on top of the normal drain over those hours.
@export var energy_cost: float = 26.0

@export_group("Opening hours")
@export_range(0, 23) var opens_hour: int = 6
@export_range(0, 24) var closes_hour: int = 22


func is_open_at(hour: int) -> bool:
	if opens_hour == closes_hour:
		return true
	if opens_hour < closes_hour:
		return hour >= opens_hour and hour < closes_hour
	return hour >= opens_hour or hour < closes_hour


func get_shift_minutes() -> int:
	return int(round(shift_hours * 60.0))


func get_pay_summary() -> String:
	return "%s · %.0fh shift · $%d" % [title, shift_hours, pay]
