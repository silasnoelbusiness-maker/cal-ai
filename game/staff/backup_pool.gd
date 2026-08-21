class_name BackupPool
extends RefCounted
## Who the company can call in when a shift goes uncovered.
##
## Phase O left CALL_BACKUP as a permission with nothing behind it. This is the
## behind it. The whole thing is one question asked carefully — *who could
## actually cover this, right now* — and the care is the point: a backup system
## that summons somebody already working somewhere else is not a feature, it is
## a duplication bug with a friendly notification.
##
## Nobody is created. Everybody who turns up is a real employee of another
## branch who is off shift, willing, and able to get there.

## How long somebody takes to cross the city to cover a shift. Not instant:
## §56 is explicit that a body appearing out of nowhere is wrong, and a delay
## is also what stops backup being strictly better than rostering properly.
const TRAVEL_MINUTES_SAME_DISTRICT := 25.0
const TRAVEL_MINUTES_ACROSS_CITY := 55.0


## Everybody in the company who has been marked as available to be called.
static func members() -> Array[EmployeeData]:
	var found: Array[EmployeeData] = []
	for business in BusinessManager.get_businesses():
		for worker in business.employees:
			if worker.available_for_backup:
				found.append(worker)
	return found


## Whether one person could cover one role at one branch at one hour.
##
## Every clause here is a way somebody could otherwise be in two places at
## once, or be summoned to a job they cannot do.
static func is_eligible(
	worker: EmployeeData, business: BusinessInstance, role: int, hour: int
) -> bool:
	if worker == null or business == null:
		return false
	if not worker.available_for_backup:
		return false
	# Already at work somewhere, including at a branch that is not this one.
	if worker.is_on_shift(hour):
		return false
	# Owed weeks of wages: they are not doing anyone a favour.
	if not worker.will_work():
		return false
	# The branch has to have a use for the job.
	var definition := business.type_data()
	if definition != null and not definition.uses_role(role):
		return false
	# And they have to be able to do it. A cleaner is not a cook.
	return can_cover(worker, role)


## Whether somebody can stand in for a role. Their own role always counts;
## beyond that it is the skill the role is paid for that decides, so a capable
## person covers a job they were not hired into and a hopeless one does not.
static func can_cover(worker: EmployeeData, role: int) -> bool:
	if worker == null:
		return false
	if int(worker.role) == role:
		return true
	var key: StringName = EmployeeData.ROLE_SKILL.get(role, &"checkout")
	return worker.skill_named(key) >= 45


## The best person to call for a job, or null. Best means most able, then
## nearest — a competent stranger beats an incompetent neighbour.
static func best_for(
	business: BusinessInstance, role: int, hour: int
) -> EmployeeData:
	var best: EmployeeData = null
	var best_score := -1.0
	for worker in members():
		if not is_eligible(worker, business, role, hour):
			continue
		var key: StringName = EmployeeData.ROLE_SKILL.get(role, &"checkout")
		var score := float(worker.skill_named(key))
		if int(worker.role) == role:
			score += 25.0
		if _same_district(worker, business):
			score += 10.0
		if score > best_score:
			best_score = score
			best = worker
	return best


static func _same_district(worker: EmployeeData, business: BusinessInstance) -> bool:
	var home := BusinessManager.by_id(worker.assigned_business)
	if home == null or business == null:
		return false
	return home.district_id() == business.district_id()


## How long they take to get there.
static func travel_minutes(worker: EmployeeData, business: BusinessInstance) -> float:
	return TRAVEL_MINUTES_SAME_DISTRICT if _same_district(worker, business) \
		else TRAVEL_MINUTES_ACROSS_CITY


## Every eligible person for a role, for the staffing screen to show.
static func candidates(
	business: BusinessInstance, role: int, hour: int
) -> Array[EmployeeData]:
	var found: Array[EmployeeData] = []
	for worker in members():
		if is_eligible(worker, business, role, hour):
			found.append(worker)
	return found


## The rows the backup section of the staffing screen prints.
static func roster() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var hour := TimeManager.hour
	for worker in members():
		var home := BusinessManager.by_id(worker.assigned_business)
		var covering := BusinessManager.by_id(worker.backup_business_id)
		var roles: Array[String] = []
		for role: int in EmployeeData.ROLE_NAMES:
			if can_cover(worker, role):
				roles.append(String(EmployeeData.ROLE_NAMES[role]))
		rows.append({
			"employee": worker,
			"name": worker.employee_name,
			"home": home.business_name if home != null else "Unassigned",
			"roles": roles,
			"available": not worker.is_on_shift(hour),
			"assignment": covering.business_name if covering != null else "",
		})
	return rows
