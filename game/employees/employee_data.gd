class_name EmployeeData
extends RefCounted
## One worker: who they are, what they cost and when they are in.
##
## RefCounted rather than a Resource because employees are generated at runtime
## and saved as plain data — there is no .tres to author, and a candidate the
## player never hires should not linger as a resource.

enum Role { CASHIER, STOCKER }

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
## 0-100. Checkout skill sets how fast they serve; stocking skill is stored for
## the restocking role, which is a smaller part of Phase H.
var skill_checkout: int = 50
var skill_stocking: int = 50
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


## A candidate off the street. Wages and skills move together, so a cheap
## worker is a slow one — which is the trade the player is actually making.
static func generate(rng: RandomNumberGenerator, id: StringName) -> EmployeeData:
	var worker := EmployeeData.new()
	worker.employee_id = id
	worker.employee_name = "%s %s" % [
		FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)],
		LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
	]
	worker.skill_checkout = rng.randi_range(25, 90)
	worker.skill_stocking = rng.randi_range(25, 90)
	# $14 at hopeless, $26 at excellent, with a couple of dollars of noise.
	var quality := float(worker.skill_checkout + worker.skill_stocking) * 0.5 / 100.0
	worker.hourly_wage = clampi(
		roundi(14.0 + quality * 12.0 + rng.randf_range(-2.0, 2.0)), 12, 30
	)
	return worker


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
	worker.role = int(state.get("role", 0)) as Role
	worker.shift_start_hour = int(state.get("shift_start", 9))
	worker.shift_end_hour = int(state.get("shift_end", 17))
	worker.assigned_business = StringName(state.get("business", ""))
	return worker
