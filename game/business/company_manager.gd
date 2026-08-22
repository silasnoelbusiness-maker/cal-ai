extends Node
## The company above the businesses.
##
## BusinessManager owns each shop: its till, its stock, its people, its books.
## This owns everything that is true of several shops at once — the brands they
## trade under, the name over all of it, the staff seen as one payroll rather
## than eight, and the question "which of my nine places is the problem today".
##
## Kept out of BusinessManager on purpose. That file already knows how a single
## business works, and a company is not a bigger business: it aggregates,
## compares and moves people, and it owns no money of its own. Every figure here
## is derived from the branches, so there is exactly one place a number lives.

signal company_changed()
signal brand_created(brand: BrandData)
signal brand_changed(brand: BrandData)
signal branch_opened(brand: BrandData, business: BusinessInstance)
signal employee_transferred(worker: EmployeeData, from_id: StringName, to_id: StringName)
signal milestone_reached(milestone: StringName, description: String)

enum TransferResult { OK, NO_EMPLOYEE, NO_TARGET, SAME_BUSINESS, ROLE_NOT_USED, SCHEDULE_CLASH }

## The company's own milestones, separate from the single-business ones
## BusinessManager already tracks. Each is [id, headline, kind, threshold].
const MILESTONES: Array = [
	[&"three_locations", "3 ACTIVE LOCATIONS", &"locations", 3],
	[&"five_locations", "5 ACTIVE LOCATIONS", &"locations", 5],
	[&"ten_employees", "10 EMPLOYEES", &"employees", 10],
	[&"twentyfive_employees", "25 EMPLOYEES", &"employees", 25],
	[&"three_brands", "3 BRANDS", &"brands", 3],
	[&"value_100k", "$100,000 COMPANY VALUE", &"value", 100000],
	[&"value_500k", "$500,000 COMPANY VALUE", &"value", 500000],
	[&"value_1m", "$1,000,000 COMPANY VALUE", &"value", 1000000],
	[&"first_restaurant", "FIRST RESTAURANT", &"type", &"restaurant"],
	[&"first_gym", "FIRST GYM", &"type", &"gym"],
	[&"first_venue", "FIRST NIGHTLIFE VENUE", &"type", &"nightclub"],
	# Phase P. These are reached by doing a thing rather than by crossing a
	# number, so they are marked directly rather than checked each day.
	[&"first_warehouse", "FIRST WAREHOUSE", &"manual", 0],
	[&"first_van", "FIRST COMPANY VAN", &"manual", 0],
	[&"thousand_units", "1,000 UNITS DISTRIBUTED", &"units", 1000],
	[&"five_routes", "5 ACTIVE ROUTES", &"manual", 0],
	[&"branch_saved", "FIRST BRANCH SAVED FROM DISTRESS", &"manual", 0],
]

## Premium a well-run chain adds to the sum of its shops. A name people know is
## worth something; it is not worth more than the shops themselves.
const BRAND_PREMIUM_CEILING := 0.18

var save_id: StringName = &"company"

## The company's name has lived on BusinessManager since Phase I, and the
## profile screen has read it from there ever since. It stays there: two copies
## of one string is two things to keep in step, and the load order decides which
## of them wins. This owns the *meaning* of the company; that owns the field.
var company_id: StringName = &"player_company"
var _brands: Array[BrandData] = []
var _next_brand_number: int = 1
var _milestones_reached: Dictionary = {}
## Alerts already raised this hour, so a manager with a problem says it once.
var _alerts_sent: Dictionary = {}
## Set while a branch of a known brand is being founded, so the automatic
## "every business gets a brand" rule stands aside and lets it join that one.
var _pending_brand: BrandData = null


func _ready() -> void:
	add_to_group(&"saveable")
	TimeManager.day_passed.connect(_on_day_passed)
	TimeManager.hour_passed.connect(_on_hour_passed)
	# A newly founded business becomes a chain of one straight away, so the
	# company screen never has an entry with no brand behind it.
	BusinessManager.business_created.connect(_on_business_created)
	# A sold business stops being a branch. The signal carries a name rather
	# than the instance, so the brands are pruned against the register instead
	# of against whatever was sold — which also catches any other way a
	# business might leave.
	BusinessManager.business_sold.connect(_on_business_sold)
	# A Phase N save has no company block at all, so load_state never runs for
	# it. Migration is hung off the load itself rather than off the block, which
	# is the difference between "old saves work" and "old saves work if they
	# happen to contain the new thing".
	SaveManager.game_loaded.connect(_on_game_loaded)


# --- The company ---------------------------------------------------------

func get_company_name() -> String:
	return BusinessManager.company_name


## The player names their own company. Anything is allowed except nothing.
func set_company_name(value: String) -> bool:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return false
	BusinessManager.company_name = trimmed.left(40)
	company_changed.emit()
	return true


func _on_business_created(business: BusinessInstance) -> void:
	if business == null or brand_for_business(business) != null:
		return
	if _pending_brand != null and _pending_brand.business_type == business.type_id:
		attach_branch(_pending_brand, business)
		return
	var brand := create_brand(business.business_name, business.type_id)
	brand.brand_reputation = business.reputation
	attach_branch(brand, business)


## Founds a business and puts it under a brand.
##
## Pass a brand to open a branch of an existing chain — the new shop takes the
## brand's name and the address as its identifier, which is the whole of §44 —
## or pass nothing to start a new one under the name given.
func found_business(
	business_name: String, type_id: StringName, property: CommercialProperty,
	brand: BrandData = null
) -> BusinessInstance:
	if brand != null and brand.business_type != type_id:
		brand = null
	# The capital test lives here rather than in BusinessManager.create_business
	# so that debug tools and tests can still stand a business up from nothing,
	# while the player is held to it every time they open one themselves.
	var definition := BusinessCatalogue.by_id(type_id)
	if definition != null and not EconomyManager.can_afford(definition.startup_cost):
		GameManager.notify(
			"YOU NEED $%s TO OPEN A %s" % [
				EconomyManager.with_thousands_separator(definition.startup_cost),
				definition.display_name.to_upper(),
			],
			GameManager.Tone.BAD
		)
		return null
	_pending_brand = brand
	var chosen_name := business_name
	if brand != null:
		chosen_name = brand.branch_name(_short_address(property))
	var business := BusinessManager.create_business(chosen_name, type_id, property)
	_pending_brand = null
	return business


## The bit of an address a sign would carry: the street, not the number.
func _short_address(property: CommercialProperty) -> String:
	if property == null:
		return ""
	var parts := property.address.split(" ", false)
	if parts.size() <= 1:
		return property.address
	# Drop a leading house number; keep whatever the street is called.
	if parts[0].is_valid_int():
		parts.remove_at(0)
	return " ".join(parts)


func _on_business_sold(_business_name: String, _proceeds: int) -> void:
	prune_brands()


func _on_game_loaded(_slot: int) -> void:
	migrate_unbranded()


## Drops branch ids that no longer name a business, and with them any brand
## left with nothing under it. A chain of none is not a chain.
func prune_brands() -> int:
	var dropped := 0
	for brand in _brands.duplicate():
		for id in brand.branch_ids.duplicate():
			if BusinessManager.by_id(id) == null:
				brand.remove_branch(id)
				dropped += 1
		if brand.branch_ids.is_empty():
			_brands.erase(brand)
	if dropped > 0:
		company_changed.emit()
	return dropped


# --- Brands --------------------------------------------------------------

func brands() -> Array[BrandData]:
	return _brands.duplicate()


func brand_count() -> int:
	return _brands.size()


func brand_by_id(brand_id: StringName) -> BrandData:
	for brand in _brands:
		if brand.brand_id == brand_id:
			return brand
	return null


func brand_for_business(business: BusinessInstance) -> BrandData:
	if business == null:
		return null
	return brand_by_id(business.brand_id)


## Brands of a given type, which is what "open another branch of..." offers.
func brands_of_type(type_id: StringName) -> Array[BrandData]:
	var found: Array[BrandData] = []
	for brand in _brands:
		if brand.business_type == type_id:
			found.append(brand)
	return found


func create_brand(
	brand_name: String, type_id: StringName, colour: Color = Color(0.286, 0.478, 0.678)
) -> BrandData:
	var brand := BrandData.new()
	brand.brand_id = StringName("brand_%d" % _next_brand_number)
	_next_brand_number += 1
	brand.brand_name = brand_name.strip_edges().left(32)
	if brand.brand_name.is_empty():
		brand.brand_name = "Brand %d" % (_brands.size() + 1)
	brand.business_type = type_id
	brand.brand_color = colour
	brand.company_id = company_id
	brand.founded_on_day = TimeManager.day_index
	_brands.append(brand)
	brand_created.emit(brand)
	company_changed.emit()
	_check_milestones()
	return brand


## Puts a business under a brand. A branch may only join a brand of its own
## kind — a coffee shop cannot be a branch of a chain of gyms.
func attach_branch(brand: BrandData, business: BusinessInstance) -> bool:
	if brand == null or business == null:
		return false
	if brand.business_type != business.type_id:
		return false
	detach_branch(business)
	if not brand.add_branch(business.business_id):
		return false
	business.brand_id = brand.brand_id
	branch_opened.emit(brand, business)
	brand_changed.emit(brand)
	company_changed.emit()
	_check_milestones()
	return true


func detach_branch(business: BusinessInstance) -> void:
	if business == null:
		return
	var brand := brand_for_business(business)
	if brand != null:
		brand.remove_branch(business.business_id)
		brand_changed.emit(brand)
	business.brand_id = &""
	company_changed.emit()


func branches_of(brand: BrandData) -> Array[BusinessInstance]:
	var found: Array[BusinessInstance] = []
	if brand == null:
		return found
	for id in brand.branch_ids:
		var business := BusinessManager.by_id(id)
		if business != null:
			found.append(business)
	return found


## Everything a brand did today, added up, plus which of its branches did it
## best. The whole of the brand view.
func brand_summary(brand: BrandData) -> Dictionary:
	var branches := branches_of(brand)
	var revenue := 0
	var profit := 0
	var customers := 0
	var value := 0
	var reputation := 0.0
	var best: BusinessInstance = null
	for business in branches:
		revenue += business.revenue_today
		profit += business.profit_today()
		customers += business.customer_count_today
		value += business.estimated_value()
		reputation += business.reputation
		if best == null or business.profit_today() > best.profit_today():
			best = business
	return {
		"brand": brand,
		"name": brand.brand_name,
		"branches": branches.size(),
		"revenue_today": revenue,
		"profit_today": profit,
		"customers_today": customers,
		"value": value,
		"reputation": roundi(brand.brand_reputation),
		"branch_reputation": roundi(reputation / float(maxi(branches.size(), 1))),
		"best_branch": best.business_name if best != null else "",
	}


# --- Locations -----------------------------------------------------------

## Every branch side by side, best profit first. What §85 asks for and what
## makes one shop obviously worth more attention than another.
func location_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for business in BusinessManager.get_businesses():
		var brand := brand_for_business(business)
		rows.append({
			"business": business,
			"name": business.business_name,
			"brand": brand.brand_name if brand != null else "Independent",
			"type": business.type_data().display_name if business.type_data() != null else "",
			"district": _district_name(business.district_id()),
			"revenue_today": business.revenue_today,
			"profit_today": business.profit_today(),
			"customers_today": business.customer_count_today,
			"lost_today": business.lost_sales_today,
			"staff": business.employees.size(),
			"value": business.estimated_value(),
			"status": business.status_text(),
		})
	rows.sort_custom(func(a, b): return int(a["profit_today"]) > int(b["profit_today"]))
	return rows


# --- Money ---------------------------------------------------------------

## What the operating company is worth. Deliberately not the player's net
## worth: no house, no car, no personal cash. Just the businesses and the
## premium a chain with a name earns on top of them.
func company_value() -> int:
	var total := 0
	for business in BusinessManager.get_businesses():
		total += business.estimated_value()
	total += brand_premium()
	return total


func brand_premium() -> int:
	var premium := 0.0
	for brand in _brands:
		if brand.branch_count() < 2:
			continue
		var branch_value := 0
		for business in branches_of(brand):
			branch_value += business.estimated_value()
		premium += (
			float(branch_value)
			* BRAND_PREMIUM_CEILING
			* clampf(brand.brand_reputation / 100.0, 0.0, 1.0)
		)
	return roundi(premium)


func revenue_today() -> int:
	var total := 0
	for business in BusinessManager.get_businesses():
		total += business.revenue_today
	return total


func profit_today() -> int:
	var total := 0
	for business in BusinessManager.get_businesses():
		total += business.profit_today()
	return total


func total_business_debt() -> int:
	return BusinessManager.total_debt()


## Everything the company overview shows, in one call so a screen never has to
## add anything up itself.
func company_summary() -> Dictionary:
	var businesses := BusinessManager.get_businesses()
	var staff := 0
	var districts := {}
	for business in businesses:
		staff += business.employees.size()
		districts[business.district_id()] = true
	return {
		"name": get_company_name(),
		"businesses": businesses.size(),
		"brands": _brands.size(),
		"locations": businesses.size(),
		"districts": districts.size(),
		"employees": staff,
		"company_value": company_value(),
		"brand_premium": brand_premium(),
		"revenue_today": revenue_today(),
		"profit_today": profit_today(),
		"business_cash": BusinessManager.total_business_cash(),
		"business_debt": total_business_debt(),
		"property_equity": RealEstate.total_equity(),
		"net_worth": BusinessManager.net_worth(),
	}


# --- Staff ---------------------------------------------------------------

## Everybody the company employs, as rows the staffing screen can print
## without asking a business anything.
func staff_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var hour := TimeManager.hour
	for business in BusinessManager.get_businesses():
		for worker in business.employees:
			rows.append({
				"employee": worker,
				"business": business,
				"name": worker.employee_name,
				"role": worker.role,
				"role_name": worker.get_role_name(),
				"business_name": business.business_name,
				"business_id": business.business_id,
				"shift": worker.schedule_text(),
				"wage": worker.hourly_wage,
				"skill": worker.relevant_skill(),
				"on_shift": worker.is_on_shift(hour),
			})
	rows.sort_custom(func(a, b): return String(a["business_name"]) < String(b["business_name"]))
	return rows


func total_employees() -> int:
	return BusinessManager.total_employees()


## Moving somebody from one branch to another. The same person arrives — same
## id, same skills, same history — which is the whole point, and the old
## branch stops having them rather than keeping a copy.
func transfer_employee(
	worker: EmployeeData, target: BusinessInstance
) -> TransferResult:
	if worker == null:
		return TransferResult.NO_EMPLOYEE
	if target == null:
		return TransferResult.NO_TARGET
	var source := BusinessManager.by_id(worker.assigned_business)
	if source == null:
		return TransferResult.NO_EMPLOYEE
	if source.business_id == target.business_id:
		return TransferResult.SAME_BUSINESS
	var definition := target.type_data()
	if definition != null and not definition.uses_role(int(worker.role)):
		return TransferResult.ROLE_NOT_USED

	var from_id := source.business_id
	source.fire(worker.employee_id)
	# Shifts that named the old branch would have them working somewhere they
	# no longer are, so they follow the person.
	for slot in worker.shifts:
		if slot.business_id == from_id:
			slot.business_id = target.business_id
	target.hire(worker)
	employee_transferred.emit(worker, from_id, target.business_id)
	company_changed.emit()
	GameManager.notify(
		"TRANSFERRED\n%s  ·  %s" % [worker.employee_name.to_upper(), target.business_name.to_upper()],
		GameManager.Tone.INFO
	)
	return TransferResult.OK


static func describe_transfer(result: TransferResult) -> String:
	match result:
		TransferResult.NO_EMPLOYEE:
			return "That person does not work for you."
		TransferResult.NO_TARGET:
			return "No such branch."
		TransferResult.SAME_BUSINESS:
			return "They already work there."
		TransferResult.ROLE_NOT_USED:
			return "That branch has no use for the job they do."
		TransferResult.SCHEDULE_CLASH:
			return "Their shifts would clash with the ones they already have."
		_:
			return "Transferred."


# --- Schedules -----------------------------------------------------------

## Everything wrong with somebody's week, in words. Empty means the rota is
## sound. Checked across every branch, because the whole reason transfers and
## multi-shift rotas need validating is that a person cannot be in two shops at
## the same hour.
func schedule_problems(worker: EmployeeData) -> Array[String]:
	var problems: Array[String] = []
	if worker == null:
		return problems
	var rota := worker.weekly_shifts()
	for slot in rota:
		if not slot.is_valid():
			problems.append("%s %s is not a real shift." % [slot.day_name(), slot.time_text()])
	for pair in worker.internal_conflicts():
		problems.append("%s overlaps %s." % [
			rota[pair.x].time_text(), rota[pair.y].time_text()
		])
	# Two branches wanting the same hour of the same person.
	for i in rota.size():
		for j in range(i + 1, rota.size()):
			var here := _shift_business(worker, rota[i])
			var there := _shift_business(worker, rota[j])
			if here != there and rota[i].overlaps(rota[j]):
				problems.append("Booked at two locations during %s." % rota[i].time_text())
	return problems


func _shift_business(worker: EmployeeData, slot: ShiftSlot) -> StringName:
	return slot.business_id if slot.business_id != &"" else worker.assigned_business


## Whether a proposed shift can be added without a clash. The screen asks this
## before it writes anything, so a bad rota is refused rather than repaired.
func can_add_shift(worker: EmployeeData, slot: ShiftSlot) -> bool:
	if worker == null or slot == null or not slot.is_valid():
		return false
	for existing in worker.weekly_shifts():
		if existing.overlaps(slot):
			return false
	return true


## Hours a branch is open with nobody rostered in a role it cannot trade
## without. What §117 asks for, said as a sentence.
func staffing_gaps(business: BusinessInstance) -> Array[String]:
	var gaps: Array[String] = []
	if business == null:
		return gaps
	var definition := business.type_data()
	if definition == null:
		return gaps
	for role in definition.required_staff_roles:
		var uncovered: Array[int] = []
		for hour in range(24):
			if not business.within_opening_hours(hour):
				continue
			if business.rostered(int(role), hour) == null:
				uncovered.append(hour)
		if uncovered.is_empty():
			continue
		gaps.append("NO %s SCHEDULED %02d:00-%02d:00" % [
			EmployeeData.name_of_role(int(role)).to_upper(),
			uncovered[0], (uncovered[uncovered.size() - 1] + 1) % 24
		])
	return gaps


# --- Operations ----------------------------------------------------------

## Today's problems across the whole company, worst first. Every branch's
## operating model is asked what is wrong with it and the answers are pooled,
## so a new business type contributes its own problems without this knowing
## what a kitchen is.
## `hour` defaults to now, which is what a live screen wants. Anything asking
## about a particular hour — a test, a report on the lunch rush — says so,
## because a company-wide answer computed at a different hour from the branch
## answer beside it is two questions pretending to be one.
func bottleneck_report(limit: int = 8, at_hour: int = -1) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var hour := at_hour if at_hour >= 0 else TimeManager.hour
	for business in BusinessManager.get_businesses():
		for issue in business.model().bottlenecks(business, hour):
			var row := issue.duplicate()
			row["business"] = business
			row["business_name"] = business.business_name
			found.append(row)
	found.sort_custom(func(a, b): return float(a["severity"]) > float(b["severity"]))
	return found.slice(0, maxi(limit, 1))


## Role utilisation across a branch, averaged over the day so far.
func utilisation_rows(business: BusinessInstance) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if business == null:
		return rows
	for role: int in business.role_load_today:
		rows.append({
			"label": EmployeeData.name_of_role(role).to_upper(),
			"load": BusinessInstance.average_load(business.role_load_today, role),
		})
	for id: StringName in business.equipment_load_today:
		var data := EquipmentCatalogue.by_id(id)
		rows.append({
			"label": (data.display_name if data != null else String(id)).to_upper(),
			"load": BusinessInstance.average_load(business.equipment_load_today, id),
		})
	rows.sort_custom(func(a, b): return float(a["load"]) > float(b["load"]))
	return rows


# --- The clock -----------------------------------------------------------

func _on_hour_passed(_hour: int) -> void:
	_alerts_sent.clear()
	_raise_manager_alerts()


## A manager tells the player what is wrong once, not every hour until it is
## fixed. Anything already said this hour is dropped.
func _raise_manager_alerts() -> void:
	for business in BusinessManager.get_businesses():
		if not business.has_manager() or not business.is_open():
			continue
		var issues := business.model().bottlenecks(business, TimeManager.hour)
		if issues.is_empty():
			continue
		var worst: Dictionary = issues[0]
		for issue in issues:
			if float(issue["severity"]) > float(worst["severity"]):
				worst = issue
		if float(worst["severity"]) < 0.6:
			continue
		var key := "%s/%s" % [business.business_id, worst["id"]]
		if _alerts_sent.has(key):
			continue
		_alerts_sent[key] = true
		GameManager.notify(
			"%s\n%s" % [String(worst["headline"]), business.business_name.to_upper()],
			GameManager.Tone.BAD
		)


func _on_day_passed(_day_index: int) -> void:
	for brand in _brands:
		var branches := branches_of(brand)
		if branches.is_empty():
			continue
		var total := 0.0
		var revenue := 0
		for business in branches:
			total += business.reputation
			revenue += int(business.last_report.get("revenue", 0))
		brand.drift_towards(total / float(branches.size()))
		brand.lifetime_revenue += revenue
		brand_changed.emit(brand)
	_check_milestones()
	company_changed.emit()


# --- Milestones ----------------------------------------------------------

func reached_milestones() -> Array:
	var found: Array = []
	for entry in MILESTONES:
		if _milestones_reached.has(entry[0]):
			found.append({"id": entry[0], "description": entry[1]})
	return found


func has_milestone(id: StringName) -> bool:
	return _milestones_reached.has(id)


func _check_milestones() -> void:
	var businesses := BusinessManager.get_businesses()
	var owned_types := {}
	for business in businesses:
		owned_types[business.type_id] = true
	var counts := {
		&"locations": businesses.size(),
		&"employees": total_employees(),
		&"brands": _brands.size(),
		&"value": company_value(),
		&"units": LogisticsManager.units_distributed,
	}
	for entry in MILESTONES:
		var id: StringName = entry[0]
		if _milestones_reached.has(id):
			continue
		var kind: StringName = entry[2]
		var reached := false
		if kind == &"manual":
			# Marked when the thing happens, not counted from a total.
			continue
		elif kind == &"type":
			reached = owned_types.has(StringName(entry[3]))
		else:
			reached = int(counts.get(kind, 0)) >= int(entry[3])
		if reached:
			_reach_milestone(id, String(entry[1]))


## Marks a milestone that is reached by doing something rather than by a total
## crossing a line — taking a warehouse on, buying the first van.
func note_milestone(id: StringName) -> void:
	if _milestones_reached.has(id):
		return
	for entry in MILESTONES:
		if StringName(entry[0]) == id:
			_reach_milestone(id, String(entry[1]))
			return


func note_milestone_if(id: StringName, condition: bool) -> void:
	if condition:
		note_milestone(id)


func _reach_milestone(id: StringName, description: String) -> void:
	_milestones_reached[id] = true
	milestone_reached.emit(id, description)
	# Subtle: a line of text and the ordinary confirmation cue. Nothing is
	# awarded, because the milestone is the reward for now.
	GameManager.notify("COMPANY MILESTONE\n%s" % description, GameManager.Tone.GOOD)
	AudioManager.play_ui(&"ui_confirm")


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var stored: Array = []
	for brand in _brands:
		stored.append(brand.to_dict())
	var milestones: Array = []
	for id: StringName in _milestones_reached:
		milestones.append(String(id))
	return {
		"brands": stored,
		"next_brand": _next_brand_number,
		"milestones": milestones,
	}


func load_state(state: Dictionary) -> void:
	clear()
	for entry in state.get("brands", []):
		_brands.append(BrandData.from_dict(entry))
	_next_brand_number = int(state.get("next_brand", _brands.size() + 1))
	for id in state.get("milestones", []):
		_milestones_reached[StringName(id)] = true
	migrate_unbranded()
	company_changed.emit()


## Every business the player owns belongs to a brand, even if they never asked
## for one. A Phase N save has none, so each business becomes a chain of one
## under its own name — nothing changes for the player, and the company screen
## has something coherent to show.
func migrate_unbranded() -> int:
	var made := 0
	for business in BusinessManager.get_businesses():
		if business.brand_id != &"" and brand_by_id(business.brand_id) != null:
			continue
		var brand := create_brand(business.business_name, business.type_id)
		brand.brand_reputation = business.reputation
		brand.founded_on_day = business.founded_on_day
		attach_branch(brand, business)
		made += 1
	return made


func clear() -> void:
	_brands.clear()
	_milestones_reached.clear()
	_alerts_sent.clear()
	_next_brand_number = 1


## A district's name as a person would write it. The rows used to carry the id
## straight through, which put "harbour_row" on a screen the player reads.
func _district_name(district_id: StringName) -> String:
	var district := WorldManager.by_id(district_id)
	if district != null:
		return district.display_name
	return String(district_id).capitalize()
