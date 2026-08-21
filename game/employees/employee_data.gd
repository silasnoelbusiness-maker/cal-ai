class_name EmployeeData
extends RefCounted
## One worker: who they are, what they cost and when they are in.
##
## RefCounted rather than a Resource because employees are generated at runtime
## and saved as plain data — there is no .tres to author, and a candidate the
## player never hires should not linger as a resource.

## Appended to, never reordered: saves store the role as an integer.
enum Role {
	CASHIER, STOCKER, BARISTA, MANAGER,
	COOK, SERVER, RECEPTIONIST, CLEANER, SECURITY, BARTENDER, ENTERTAINER,
}

## What a role is worth per hour before skill is taken into account. A manager
## is deliberately dear: they make expansion possible and they eat the margin.
## A cook and a doorman are dear for the opposite reason — a restaurant without
## one cannot serve and a venue without one cannot fill.
const BASE_WAGE := {
	Role.CASHIER: 18, Role.STOCKER: 19, Role.BARISTA: 20, Role.MANAGER: 30,
	Role.COOK: 26, Role.SERVER: 19, Role.RECEPTIONIST: 18, Role.CLEANER: 16,
	Role.SECURITY: 24, Role.BARTENDER: 21, Role.ENTERTAINER: 28,
}

## The one skill each role is paid for. Everything that asks "how good are they
## at their job" comes through here rather than through a match statement in
## six different files.
const ROLE_SKILL := {
	Role.CASHIER: &"checkout", Role.STOCKER: &"stocking", Role.BARISTA: &"barista",
	Role.MANAGER: &"management", Role.COOK: &"cooking", Role.SERVER: &"checkout",
	Role.RECEPTIONIST: &"checkout", Role.CLEANER: &"cleaning",
	Role.SECURITY: &"security", Role.BARTENDER: &"checkout",
	Role.ENTERTAINER: &"entertainment",
}

## How a role reads on a wage slip.
const ROLE_NAMES := {
	Role.CASHIER: "Cashier", Role.STOCKER: "Stocker", Role.BARISTA: "Barista",
	Role.MANAGER: "Manager", Role.COOK: "Cook", Role.SERVER: "Server",
	Role.RECEPTIONIST: "Receptionist", Role.CLEANER: "Cleaner",
	Role.SECURITY: "Security", Role.BARTENDER: "Bartender",
	Role.ENTERTAINER: "DJ",
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
## Added in Phase O. A worker restored from an older save is average at all
## four, which is the same thing the barista skill did when it arrived.
var skill_cooking: int = 50
var skill_cleaning: int = 50
var skill_security: int = 50
var skill_entertainment: int = 50
## Hours worked in each role, which is what slowly raises the matching skill.
var experience: float = 0.0
var role: Role = Role.CASHIER
## The first shift of the week, kept as plain fields because every screen and
## every test written before Phase O reads them. `shifts` is the truth; these
## two mirror whichever shift starts earliest, and an employee with no weekly
## schedule at all works these hours every day.
var shift_start_hour: int = 9
var shift_end_hour: int = 17
## The full week. Empty means "the single shift above, every day" — which is
## what every employee in a Phase N save meant.
var shifts: Array[ShiftSlot] = []
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
	worker.skill_cooking = _roll_skill(rng, floor_skill)
	worker.skill_cleaning = _roll_skill(rng, floor_skill)
	worker.skill_security = _roll_skill(rng, floor_skill)
	worker.skill_entertainment = _roll_skill(rng, floor_skill)
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
	return skill_named(ROLE_SKILL.get(role, &"checkout"))


func skill_named(key: StringName) -> int:
	match key:
		&"stocking":
			return skill_stocking
		&"barista":
			return skill_barista
		&"management":
			return skill_management
		&"cooking":
			return skill_cooking
		&"cleaning":
			return skill_cleaning
		&"security":
			return skill_security
		&"entertainment":
			return skill_entertainment
		_:
			return skill_checkout


func set_skill_named(key: StringName, value: int) -> void:
	var capped := clampi(value, 0, 100)
	match key:
		&"stocking":
			skill_stocking = capped
		&"barista":
			skill_barista = capped
		&"management":
			skill_management = capped
		&"cooking":
			skill_cooking = capped
		&"cleaning":
			skill_cleaning = capped
		&"security":
			skill_security = capped
		&"entertainment":
			skill_entertainment = capped
		_:
			skill_checkout = capped


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
	var key: StringName = ROLE_SKILL.get(role, &"checkout")
	set_skill_named(key, mini(roundi(float(skill_named(key)) + hours * 0.25), 100))


# --- The week ------------------------------------------------------------

## The schedule as shifts, whatever it was stored as. An employee who has never
## been given a weekly rota works their single shift every day, which is what
## the plain start and end hours have always meant.
func weekly_shifts() -> Array[ShiftSlot]:
	if not shifts.is_empty():
		return shifts
	if shift_end_hour == shift_start_hour:
		return []
	return [ShiftSlot.make(shift_start_hour, shift_end_hour, int(role))]


func shifts_on(weekday: int) -> Array[ShiftSlot]:
	var found: Array[ShiftSlot] = []
	for slot in weekly_shifts():
		if slot.weekday == ShiftSlot.EVERY_DAY or slot.weekday == weekday:
			found.append(slot)
	return found


## Replaces the whole rota. The plain start and end hours follow the earliest
## shift so nothing that reads them is left describing a week that is gone.
func set_weekly_shifts(new_shifts: Array[ShiftSlot]) -> void:
	shifts = new_shifts.duplicate()
	_sync_primary_shift()


func add_shift(slot: ShiftSlot) -> bool:
	if slot == null or not slot.is_valid():
		return false
	if shifts.is_empty():
		shifts = weekly_shifts()
	shifts.append(slot)
	_sync_primary_shift()
	return true


func remove_shift(index: int) -> bool:
	if shifts.is_empty():
		shifts = weekly_shifts()
	if index < 0 or index >= shifts.size():
		return false
	shifts.remove_at(index)
	_sync_primary_shift()
	return true


func clear_shifts() -> void:
	shifts = []
	shift_start_hour = 9
	shift_end_hour = 9


func _sync_primary_shift() -> void:
	if shifts.is_empty():
		return
	var earliest: ShiftSlot = shifts[0]
	for slot in shifts:
		if slot.start_hour < earliest.start_hour:
			earliest = slot
	shift_start_hour = earliest.start_hour
	shift_end_hour = earliest.end_hour


## Hours across a whole week, which is what wages are actually estimated from
## once somebody works two shifts on a Friday and none on a Sunday.
func weekly_hours() -> float:
	var total := 0.0
	for slot in weekly_shifts():
		total += slot.length_hours() * (7.0 if slot.weekday == ShiftSlot.EVERY_DAY else 1.0)
	return total


## Hours on one day. The wage run bills by the day, so this is what it uses.
func scheduled_hours(weekday: int = ShiftSlot.EVERY_DAY) -> float:
	var total := 0.0
	for slot in shifts_on(weekday) if weekday >= 0 else weekly_shifts():
		total += slot.length_hours()
	return total


## Whether they are at work. `on_weekday` defaults to today, so every existing
## caller that asks by the hour alone keeps working and now respects a rota
## that differs by day.
func is_on_shift(hour: int, on_weekday: int = -2) -> bool:
	var day := on_weekday
	if day == -2:
		day = TimeManager.weekday
	for slot in weekly_shifts():
		if slot.covers(hour, day):
			return true
	return false


## What job they are doing at this hour. A person can be a server at lunch and
## a bartender at night, and the shift says which.
func role_at(hour: int, on_weekday: int = -2) -> int:
	var day := on_weekday
	if day == -2:
		day = TimeManager.weekday
	for slot in weekly_shifts():
		if slot.covers(hour, day):
			return slot.role
	return int(role)


## Which branch they are at during this hour, or their home branch.
func business_at(hour: int, on_weekday: int = -2) -> StringName:
	var day := on_weekday
	if day == -2:
		day = TimeManager.weekday
	for slot in weekly_shifts():
		if slot.covers(hour, day):
			return slot.business_id if slot.business_id != &"" else assigned_business
	return assigned_business


## Shifts of this employee's own rota that clash with each other. Returned as
## pairs of indices so a screen can point at both.
func internal_conflicts() -> Array[Vector2i]:
	var clashes: Array[Vector2i] = []
	var rota := weekly_shifts()
	for i in rota.size():
		for j in range(i + 1, rota.size()):
			if rota[i].overlaps(rota[j]):
				clashes.append(Vector2i(i, j))
	return clashes


## Seconds one customer takes to serve. A poor cashier is roughly twice as slow
## as a good one, which is what the wage is buying.
func checkout_seconds() -> float:
	return lerpf(4.5, 1.6, clampf(float(skill_checkout) / 100.0, 0.0, 1.0))


## Multiplier on how long it takes them to make something. A good one is about
## twice the speed of a poor one.
##
## Reads the skill their *role* is paid for rather than the barista skill it was
## written against, because Phase O put cooks in kitchens and a cook whose speed
## came from how well they pull an espresso is nobody's idea of a kitchen.
func preparation_scale() -> float:
	return lerpf(1.6, 0.7, clampf(float(relevant_skill()) / 100.0, 0.0, 1.0))


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
	return String(ROLE_NAMES.get(role, String(Role.keys()[role]).capitalize()))


static func name_of_role(value: int) -> String:
	return String(ROLE_NAMES.get(value, "Staff"))


## The rota in one line. Several shifts read as a count rather than a wall of
## times, because a card has one line for this and a rota screen has the rest.
func schedule_text() -> String:
	var rota := weekly_shifts()
	if rota.is_empty():
		return "Not scheduled"
	if rota.size() == 1:
		return rota[0].time_text()
	return "%s +%d more" % [rota[0].time_text(), rota.size() - 1]


## Multiplier on how long a service task takes this person. A good one is about
## twice the speed of a poor one, which is the same trade the till has always
## made and the number the restaurant floor and the bar both use.
func service_scale() -> float:
	return lerpf(1.5, 0.72, clampf(float(skill_checkout) / 100.0, 0.0, 1.0))


## How much cleanliness one hour of this cleaner puts back.
func cleaning_rate() -> float:
	return lerpf(4.0, 11.0, clampf(float(skill_cleaning) / 100.0, 0.0, 1.0))


func to_dict() -> Dictionary:
	return {
		"id": String(employee_id),
		"name": employee_name,
		"wage": hourly_wage,
		"skill_checkout": skill_checkout,
		"skill_stocking": skill_stocking,
		"skill_barista": skill_barista,
		"skill_management": skill_management,
		"skill_cooking": skill_cooking,
		"skill_cleaning": skill_cleaning,
		"skill_security": skill_security,
		"skill_entertainment": skill_entertainment,
		"experience": experience,
		"role": int(role),
		"shift_start": shift_start_hour,
		"shift_end": shift_end_hour,
		"shifts": _shifts_to_array(),
		"business": String(assigned_business),
	}


func _shifts_to_array() -> Array:
	var out: Array = []
	for slot in shifts:
		out.append(slot.to_dict())
	return out


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
	# Phase O's four skills. A worker hired before they existed is average at
	# them rather than useless, so a save is not punished for being old.
	worker.skill_cooking = int(state.get("skill_cooking", 50))
	worker.skill_cleaning = int(state.get("skill_cleaning", 50))
	worker.skill_security = int(state.get("skill_security", 50))
	worker.skill_entertainment = int(state.get("skill_entertainment", 50))
	worker.experience = float(state.get("experience", 0.0))
	worker.role = int(state.get("role", 0)) as Role
	worker.shift_start_hour = int(state.get("shift_start", 9))
	worker.shift_end_hour = int(state.get("shift_end", 17))
	for entry in state.get("shifts", []):
		worker.shifts.append(ShiftSlot.from_dict(entry))
	worker.assigned_business = StringName(state.get("business", ""))
	return worker
