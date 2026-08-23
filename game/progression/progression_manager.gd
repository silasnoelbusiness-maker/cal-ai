extends Node
## Reads the rest of the game and says how far the player has got.
##
## §86 and §100 ask for a progression path; §97 asks that scattered milestone
## logic be unified "where practical". The practical part matters: businesses,
## lifestyle and the underworld already announce their own milestones and they
## keep doing it. This file does not take those over. It listens, writes them
## into one journal (§98), and adds the long-range goals on top.
##
## The one rule that makes that safe: nothing here owns a number. Every metric
## is fetched live from whoever does own it, which is why loading an old save
## cannot double-count and why a debug tool that hands the player a million
## dollars moves the goals immediately.

signal goal_completed(goal: Goal)
signal goals_changed()
signal journal_entry_added(entry: Dictionary)
signal pinned_changed()

## How many goals the HUD shows at once. §95 — a few, not forty.
const MAX_PINNED := 3

## How long between sweeps of the goal table. Goals are long-range; checking
## them four times a second would cost more than it tells anybody.
const CHECK_INTERVAL := 2.0

## Journal entries kept. A long game should not grow without limit, and the
## oldest entries are the ones nobody scrolls back to.
const MAX_JOURNAL := 200

## What kind of thing happened, which is all the timeline needs to colour it.
enum Kind { GOAL, MILESTONE, BUSINESS, PROPERTY, LEGAL, CRIMINAL, LIFE }

const KIND_NAMES := {
	Kind.GOAL: "Goal",
	Kind.MILESTONE: "Milestone",
	Kind.BUSINESS: "Business",
	Kind.PROPERTY: "Property",
	Kind.LEGAL: "Legal",
	Kind.CRIMINAL: "Underworld",
	Kind.LIFE: "Life",
}

## Every question this file knows how to answer. A goal naming anything else is
## a bug, and a test pins that the catalogue only uses keys from here.
const METRICS: Array[StringName] = [
	&"cash", &"net_worth", &"lifetime_income", &"illegal_income",
	&"debt_free_wealth", &"lifestyle",
	&"shifts_worked", &"customers_served",
	&"businesses", &"employees", &"managers", &"company_value",
	&"brands", &"warehouses",
	&"properties", &"vehicles_owned",
	&"contacts_known", &"illegal_jobs", &"criminal_reputation",
	&"best_escape", &"best_trust", &"requests_filled",
]

## Net worth that counts as "wealthy and owing nothing" for the debt-free goal.
const DEBT_FREE_WEALTH := 100000

@export var save_id: StringName = &"progression"
@export var reset_on_missing_save: bool = true

## goal_id -> the day it was met. Completion is remembered, never re-awarded.
var _completed: Dictionary = {}
var _pinned: Array[StringName] = []
## Set once the player has manually chosen a pin, after which the suggestions
## stop rearranging their list behind them.
var _pins_are_theirs: bool = false
var _journal: Array[Dictionary] = []
var _goals: Array[Goal] = []
var _by_id: Dictionary = {}
var _timer: float = 0.0
## Suppresses toasts while a save is being applied, so loading a long game does
## not replay fifty notifications at once (§167).
var _quiet: bool = false


func _ready() -> void:
	add_to_group(&"saveable")
	_goals = GoalCatalogue.all()
	for goal in _goals:
		_by_id[goal.goal_id] = goal
	set_process(true)
	_connect_sources()


func _connect_sources() -> void:
	# Every one of these already existed and already told the player. All that
	# is added here is a line in the journal.
	BusinessManager.milestone_reached.connect(_on_business_milestone)
	BusinessManager.business_created.connect(_on_business_created)
	BusinessManager.business_sold.connect(_on_business_sold)
	LifestyleManager.milestone_reached.connect(_on_lifestyle_milestone)
	RealEstate.property_bought.connect(_on_property_bought)
	RealEstate.mortgage_settled.connect(_on_mortgage_settled)
	VehicleRegistry.vehicle_bought.connect(_on_vehicle_bought)
	LegalManager.arrest_recorded.connect(_on_arrest)
	LegalManager.record_tier_changed.connect(_on_record_tier)
	Underworld.reputation_changed.connect(_on_reputation)
	Underworld.contact_unlocked.connect(_on_contact_unlocked)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	evaluate()


# --- Metrics -------------------------------------------------------------

## The single place that knows how to ask the game a question. Anything not
## listed returns 0 rather than erroring: a goal referring to a metric that
## has not been built yet simply never completes.
func value_for(metric: StringName) -> float:
	match metric:
		&"cash":
			return float(EconomyManager.cash)
		&"net_worth":
			return float(BusinessManager.net_worth())
		&"lifetime_income":
			return float(EconomyManager.total_income)
		&"illegal_income":
			return float(EconomyManager.illegal_income)
		&"debt_free_wealth":
			# One goal, two conditions: rich, and owing nobody. Expressed as a
			# 0-or-1 metric so the goal table stays a table.
			var owed := BusinessManager.total_debt() + RealEstate.total_mortgage_debt()
			var rich := BusinessManager.net_worth() >= DEBT_FREE_WEALTH
			return 1.0 if rich and owed <= 0 else 0.0
		&"lifestyle":
			return float(LifestyleManager.score())
		&"shifts_worked":
			return float(LifeStats.get_counter(&"shifts_worked"))
		&"customers_served":
			return float(BusinessManager.get_statistic(&"customers_served"))
		&"businesses":
			return float(BusinessManager.owned_count())
		&"employees":
			return float(BusinessManager.total_employees())
		&"managers":
			return float(_manager_count())
		&"company_value":
			return float(CompanyManager.company_value())
		&"brands":
			return float(CompanyManager.brand_count())
		&"warehouses":
			return float(LogisticsManager.warehouses().size())
		&"properties":
			return float(RealEstate.portfolio().size())
		&"vehicles_owned":
			return float(VehicleRegistry.count())
		&"contacts_known":
			return float(Underworld.contacts().size())
		&"illegal_jobs":
			return float(Underworld.career.total_jobs())
		&"criminal_reputation":
			return float(Underworld.reputation)
		&"best_escape":
			return float(CrimeManager.get_statistic(&"highest_escape_level"))
		&"best_trust":
			return float(_best_trust())
		&"requests_filled":
			return float(Underworld.career.requests_filled)
	return 0.0


func _manager_count() -> int:
	var total := 0
	for worker in BusinessManager.all_employees():
		if worker.role == EmployeeData.Role.MANAGER:
			total += 1
	return total


func _best_trust() -> int:
	var best := 0
	for bond in Underworld.relationships():
		best = maxi(best, bond.trust)
	return best


# --- Goals ---------------------------------------------------------------

func all_goals() -> Array[Goal]:
	return _goals.duplicate()


func goal_by_id(id: StringName) -> Goal:
	return _by_id.get(id, null)


func is_complete(id: StringName) -> bool:
	return _completed.has(id)


## The day a goal was met, or -1.
func completed_on(id: StringName) -> int:
	return int(_completed.get(id, -1))


func completed_count(track: int = -1) -> int:
	if track < 0:
		return _completed.size()
	var total := 0
	for id in _completed:
		var goal: Goal = _by_id.get(id, null)
		if goal != null and goal.track == track:
			total += 1
	return total


func progress_of(goal: Goal) -> float:
	if goal == null:
		return 0.0
	if _completed.has(goal.goal_id):
		return 1.0
	return goal.progress(value_for(goal.metric))


## The tier the player has reached on a track: the highest tier where every
## goal is done, so one unfinished early goal cannot be skipped past.
func tier_on(track: int) -> Goal.Tier:
	var reached := Goal.Tier.STARTING
	for tier in [
		Goal.Tier.STARTING, Goal.Tier.ENTREPRENEUR, Goal.Tier.OWNER,
		Goal.Tier.CEO, Goal.Tier.TYCOON, Goal.Tier.MOGUL,
	]:
		var any := false
		var all_done := true
		for goal in _goals:
			if goal.track != track or goal.tier != tier:
				continue
			any = true
			if not _completed.has(goal.goal_id):
				all_done = false
				break
		if any and all_done:
			reached = tier
		elif any:
			break
	return reached


## Sweeps the table. Cheap enough to call from a test after changing anything.
func evaluate() -> int:
	var newly := 0
	for goal in _goals:
		if _completed.has(goal.goal_id):
			continue
		if not goal.is_met(value_for(goal.metric)):
			continue
		_completed[goal.goal_id] = TimeManager.day_index
		newly += 1
		_note(
			Kind.GOAL, goal.label,
			"%s — %s" % [goal.track_name(), Goal.tier_name(goal.track, goal.tier)]
		)
		goal_completed.emit(goal)
		if not _quiet:
			GameManager.notify(
				"GOAL REACHED\n%s" % goal.label.to_upper(), GameManager.Tone.GOOD
			)
		if _pinned.has(goal.goal_id):
			_pinned.erase(goal.goal_id)
			pinned_changed.emit()
	if newly > 0:
		goals_changed.emit()
	return newly


# --- Pinned goals --------------------------------------------------------

## What the HUD shows: whatever the player pinned, topped up with the nearest
## unfinished goals so a new player is never looking at an empty list.
func pinned() -> Array[Goal]:
	var out: Array[Goal] = []
	for id in _pinned:
		var goal: Goal = _by_id.get(id, null)
		if goal != null and not _completed.has(id):
			out.append(goal)
	if not _pins_are_theirs:
		for goal in suggestions():
			if out.size() >= MAX_PINNED:
				break
			if not out.has(goal):
				out.append(goal)
	return out


## Unfinished goals ordered by how close they are, lowest tier first. This is
## what makes the suggested list read like "next", not "random".
func suggestions() -> Array[Goal]:
	var open: Array[Goal] = []
	for goal in _goals:
		if not _completed.has(goal.goal_id):
			open.append(goal)
	open.sort_custom(_closer_first)
	return open


func _closer_first(a: Goal, b: Goal) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	var pa := a.progress(value_for(a.metric))
	var pb := b.progress(value_for(b.metric))
	if not is_equal_approx(pa, pb):
		return pa > pb
	return String(a.goal_id) < String(b.goal_id)


func is_pinned(id: StringName) -> bool:
	return _pinned.has(id)


func pin(id: StringName) -> bool:
	if not _by_id.has(id) or _completed.has(id) or _pinned.has(id):
		return false
	if _pinned.size() >= MAX_PINNED:
		return false
	_pinned.append(id)
	_pins_are_theirs = true
	Onboarding.report(&"goal_pinned")
	pinned_changed.emit()
	return true


func unpin(id: StringName) -> void:
	if not _pinned.has(id):
		return
	_pinned.erase(id)
	# Emptying the list by hand is a request to be left alone, not a reset:
	# the suggestions stay off until the player asks for them back.
	_pins_are_theirs = true
	pinned_changed.emit()


## Hands the list back to the game's own judgement.
func clear_pins() -> void:
	_pinned.clear()
	_pins_are_theirs = false
	pinned_changed.emit()


# --- Journal -------------------------------------------------------------

func journal() -> Array[Dictionary]:
	return _journal.duplicate()


## Most recent first, which is how the timeline reads it.
func recent(limit: int = 20) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start := maxi(0, _journal.size() - limit)
	for i in range(_journal.size() - 1, start - 1, -1):
		out.append(_journal[i])
	return out


func _note(kind: Kind, title: String, detail: String = "") -> void:
	var entry := {
		"day": TimeManager.day_index,
		"hour": TimeManager.hour,
		"kind": int(kind),
		"title": title,
		"detail": detail,
	}
	_journal.append(entry)
	if _journal.size() > MAX_JOURNAL:
		_journal = _journal.slice(_journal.size() - MAX_JOURNAL)
	journal_entry_added.emit(entry)


static func kind_name(kind: int) -> String:
	return String(KIND_NAMES.get(kind, "Milestone"))


# --- Listeners -----------------------------------------------------------

func _on_business_milestone(_id: StringName, description: String) -> void:
	_note(Kind.MILESTONE, description)


func _on_business_created(business: BusinessInstance) -> void:
	_note(Kind.BUSINESS, "Opened %s" % business.business_name)


func _on_business_sold(business_name: String, proceeds: int) -> void:
	_note(Kind.BUSINESS, "Sold %s" % business_name, "$%d" % proceeds)


func _on_lifestyle_milestone(_id: StringName, label: String) -> void:
	_note(Kind.MILESTONE, label)


func _on_property_bought(record: PropertyRecord) -> void:
	_note(Kind.PROPERTY, "Bought %s" % record.address, record.kind_label())


func _on_mortgage_settled(_loan: MortgageData) -> void:
	_note(Kind.PROPERTY, "Paid off a mortgage")


func _on_vehicle_bought(record: OwnedVehicle) -> void:
	LifeStats.add(&"vehicles_bought")
	_note(Kind.LIFE, "Bought a %s" % record.display_name())


func _on_arrest(record: ArrestRecord) -> void:
	_note(Kind.LEGAL, "Arrested", record.headline())


func _on_record_tier(tier: CriminalRecord.Tier) -> void:
	_note(Kind.LEGAL, "Record: %s" % CriminalRecord.tier_name(tier))


func _on_reputation(_value: int, tier: CriminalReputation.Tier) -> void:
	_note(Kind.CRIMINAL, "Reputation: %s" % CriminalReputation.tier_name(tier))


func _on_contact_unlocked(contact: CriminalContactData) -> void:
	_note(Kind.CRIMINAL, "Met %s" % contact.display_name)


# --- Save ----------------------------------------------------------------

func clear() -> void:
	_completed.clear()
	_pinned.clear()
	_pins_are_theirs = false
	_journal.clear()
	_timer = 0.0
	goals_changed.emit()
	pinned_changed.emit()


func save_state() -> Dictionary:
	var done := {}
	for id in _completed:
		done[String(id)] = int(_completed[id])
	var pins: Array = []
	for id in _pinned:
		pins.append(String(id))
	return {
		"completed": done,
		"pinned": pins,
		"pins_are_theirs": _pins_are_theirs,
		"journal": _journal.duplicate(true),
	}


func load_state(state: Dictionary) -> void:
	_completed.clear()
	var done: Dictionary = state.get("completed", {})
	for id in done:
		var name := StringName(id)
		# A goal that no longer exists is dropped rather than kept, so an old
		# save cannot resurrect a retired goal into the count.
		if _by_id.has(name):
			_completed[name] = int(done[id])
	_pinned.clear()
	for id in state.get("pinned", []):
		var name := StringName(id)
		if _by_id.has(name) and not _completed.has(name) and _pinned.size() < MAX_PINNED:
			_pinned.append(name)
	_pins_are_theirs = bool(state.get("pins_are_theirs", false))
	_journal.clear()
	for entry in state.get("journal", []):
		if entry is Dictionary:
			_journal.append((entry as Dictionary).duplicate())
	# §164 and §167 — a save from before this system was built arrives with an
	# empty record while the player is already a millionaire. Catching it up is
	# right; announcing thirty goals at once is not, so the sweep runs silent
	# and the goals are simply marked done.
	_quiet = true
	evaluate()
	_quiet = false
	goals_changed.emit()
	pinned_changed.emit()
