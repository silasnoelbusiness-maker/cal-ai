class_name EmployeeData
extends RefCounted
## One worker: who they are, what they cost and when they are in.
##
## RefCounted rather than a Resource because employees are generated at runtime
## and saved as plain data — there is no .tres to author, and a candidate the
## player never hires should not linger as a resource.

enum Role { CASHIER, STOCKER, BARISTA, MANAGER }

## What a role is worth per hour before skill is taken into account. A manager
## is deliberately dear: they make expansion possible and they eat the margin.
const BASE_WAGE := {
	Role.CASHIER: 18, Role.STOCKER: 19, Role.BARISTA: 20, Role.MANAGER: 30,
}

const FIRST_NAMES: Array[String] = [
	"Alex", "Sam", "Jordan", "Riley", "Casey", "Morgan", "Devon", "Quinn",
	"Robin", "Ellis", "Frankie", "Marlow", "Sasha", "Toni", "Wren",
]
const LAST_NAMES: Array[String] = [
	"Vance", "Okafor", "Delgado", "Hartley", "Nakamura", "Brennan", "Ferreira",
	"Whitlock", "Mbeki", "Sorensen", "Castellan", "Ahmed", "Lindqvist",
]

var employee_id: StringName = &""
var employee_name: String = "Worker"
var hourly_wage: int = 18
## 0-100 each. Which one matters depends on the role they are put in, so a
## brilliant barista on a till is an expensive cashier.
var skill_checkout: int = 50
var skill_stocking: int = 50
var skill_barista: int = 50
var skill_management: int = 50
## Hours worked in each role, which is what slowly raises the matching skill.
var experience: float = 0.0
var role: Role = Role.CASHIER
var shift_start_hour: int = 9
var shift_end_hour: int = 17
var assigned_business: StringName = &""

## Reset each business day. Wages are charged from hours_worked_today, so a
## worker who never turned up is never paid.
var hours_worked_today: float = 0.0
## Hours worked but not yet paid for. Wages are charged in a lump when the shift
## ends rather than by the minute, so the ledger reads like a wage slip.
var hours_unpaid: float = 0.0
var customers_served_today: int = 0
var sales_processed_today: int = 0


## A candidate off the street.
##
## Skills and wages move together, so a cheap worker is a slow one — which is the
## trade the player is actually making. `calibre` shifts the whole band, so the
## hiring list offers a beginner, somebody solid and somebody expensive rather
## than three interchangeable people.
static func generate(
	rng: RandomNumberGenerator, id: StringName, role: Role = Role.CASHIER,
	calibre: float = -1.0
) -> EmployeeData:
	var worker := EmployeeData.new()
	worker.employee_id = id
	worker.employee_name = "%s %s" % [
		FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)],
		LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
	]
	worker.role = role

	var band := calibre if calibre >= 0.0 else rng.randf()
	var floor_skill := lerpf(20.0, 60.0, band)
	worker.skill_checkout = _roll_skill(rng, floor_skill)
	worker.skill_stocking = _roll_skill(rng, floor_skill)
	worker.skill_barista = _roll_skill(rng, floor_skill)
	worker.skill_management = _roll_skill(rng, floor_skill)
	worker.hourly_wage = worker.expected_wage(rng.randf_range(-1.5, 1.5))
	return worker


static func _roll_skill(rng: RandomNumberGenerator, floor_skill: float) -> int:
	return clampi(roundi(floor_skill + rng.randf_range(0.0, 32.0)), 10, 98)


## What this person expects to be paid in their current role: the role's base
## wage, scaled by how good they are at it.
func expected_wage(noise: float = 0.0) -> int:
	var base: int = BASE_WAGE.get(role, 18)
	var quality := clampf(float(relevant_skill()) / 100.0, 0.0, 1.0)
	return clampi(roundi(float(base) * lerpf(0.75, 1.35, quality) + noise), 10, 60)


## The one skill that matters for the job they are doing.
func relevant_skill() -> int:
	match role:
		Role.STOCKER:
			return skill_stocking
		Role.BARISTA:
			return skill_barista
		Role.MANAGER:
			return skill_management
		_:
			return skill_checkout


## Puts somebody into a different job. Their wage follows the role, because a
## cashier promoted to manager does not stay on a cashier's money.
func assign_role(new_role: Role) -> void:
	if role == new_role:
		return
	role = new_role
	hourly_wage = expected_wage()


## An hour of work makes somebody slightly better at what they were doing.
## Deliberately slow: about two in-game weeks of full shifts to move a skill ten
## points, and nothing here is a skill tree.
func add_experience(hours: float) -> void:
	experience += hours
	var gain := hours * 0.25
	match role:
		Role.STOCKER:
			skill_stocking = mini(roundi(float(skill_stocking) + gain), 100)
		Role.BARISTA:
			skill_barista = mini(roundi(float(skill_barista) + gain), 100)
		Role.MANAGER:
			skill_management = mini(roundi(float(skill_management) + gain), 100)
		_:
			skill_checkout = mini(roundi(float(skill_checkout) + gain), 100)


## Hours between the two clock hours, handling a shift that crosses midnight.
func scheduled_hours() -> float:
	if shift_end_hour == shift_start_hour:
		return 0.0
	if shift_end_hour > shift_start_hour:
		return float(shift_end_hour - shift_start_hour)
	return float(24 - shift_start_hour + shift_end_hour)


func is_on_shift(hour: int) -> bool:
	if shift_end_hour == shift_start_hour:
		return false
	if shift_end_hour > shift_start_hour:
		return hour >= shift_start_hour and hour < shift_end_hour
	return hour >= shift_start_hour or hour < shift_end_hour


## Seconds one customer takes to serve. A poor cashier is roughly twice as slow
## as a good one, which is what the wage is buying.
func checkout_seconds() -> float:
	return lerpf(4.5, 1.6, clampf(float(skill_checkout) / 100.0, 0.0, 1.0))


## Multiplier on a drink's preparation time. A good barista is about twice the
## speed of a poor one.
func preparation_scale() -> float:
	return lerpf(1.6, 0.7, clampf(float(skill_barista) / 100.0, 0.0, 1.0))


## Units of stock a stocker moves per minute on shift.
func stocking_rate() -> float:
	return lerpf(6.0, 18.0, clampf(float(skill_stocking) / 100.0, 0.0, 1.0))


## How well a manager runs the place while nobody is watching, 0-1. Feeds the
## automation and the far simulation rather than being a flat bonus.
func management_quality() -> float:
	return clampf(float(skill_management) / 100.0, 0.0, 1.0)


func is_manager() -> bool:
	return role == Role.MANAGER


func wage_for_hours(hours: float) -> int:
	return maxi(0, roundi(float(hourly_wage) * hours))


func get_role_name() -> String:
	return Role.keys()[role].capitalize()


func schedule_text() -> String:
	return "%02d:00-%02d:00" % [shift_start_hour, shift_end_hour]


func to_dict() -> Dictionary:
	return {
		"id": String(employee_id),
		"name": employee_name,
		"wage": hourly_wage,
		"skill_checkout": skill_checkout,
		"skill_stocking": skill_stocking,
		"skill_barista": skill_barista,
		"skill_management": skill_management,
		"experience": experience,
		"role": int(role),
		"shift_start": shift_start_hour,
		"shift_end": shift_end_hour,
		"business": String(assigned_business),
	}


static func from_dict(state: Dictionary) -> EmployeeData:
	var worker := EmployeeData.new()
	worker.employee_id = StringName(state.get("id", ""))
	worker.employee_name = String(state.get("name", "Worker"))
	worker.hourly_wage = int(state.get("wage", 18))
	worker.skill_checkout = int(state.get("skill_checkout", 50))
	worker.skill_stocking = int(state.get("skill_stocking", 50))
	# Saves written before the extra roles existed have neither skill; a worker
	# from one of them is average at the jobs that did not yet exist.
	worker.skill_barista = int(state.get("skill_barista", 50))
	worker.skill_management = int(state.get("skill_management", 50))
	worker.experience = float(state.get("experience", 0.0))
	worker.role = int(state.get("role", 0)) as Role
	worker.shift_start_hour = int(state.get("shift_start", 9))
	worker.shift_end_hour = int(state.get("shift_end", 17))
	worker.assigned_business = StringName(state.get("business", ""))
	return worker
