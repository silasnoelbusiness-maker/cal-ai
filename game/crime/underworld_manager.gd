extends Node

## The criminal side of the ledger: who the player knows, what they are worth
## on the street, and where illegal money comes from.
##
## Kept entirely apart from the company. §108 is explicit that committing a
## crime does not make the player's businesses criminal, and nothing in this
## file touches a business, a brand or a branch's books. What it owns is a
## reputation, a handful of contacts, whatever job is running, and a tally of
## illegal earnings by source.
##
## §69 keeps the money itself simple. Illegal earnings land in the player's
## pocket like any other income — EconomyManager has had a CRIME source since
## Phase J — and this records which kind of crime produced them. §109 allows
## tagging the source and explicitly forbids building laundering on top of it,
## so that is exactly as far as this goes.

signal reputation_changed(value: int, tier: CriminalReputation.Tier)
signal contact_unlocked(contact: CriminalContactData)
signal job_offered(job: IllegalJobData)
signal job_accepted(job: IllegalJobData)
signal job_completed(job: IllegalJobData)
signal job_failed(job: IllegalJobData, reason: String)
signal illegal_income(amount: int, category: CrimeData.Income)
## Phase R. Standing with one named person, as against the street generally.
signal trust_changed(contact_id: StringName, trust: int, tier: ContactRelationship.Tier)
signal chain_tier_unlocked(contact_id: StringName, chain: JobChain)
signal request_posted(request: ContactRequest)
signal request_filled(request: ContactRequest, payout: int)
signal career_changed()

## What a chop shop pays, as a fraction of the car's value before condition.
## §73 — a strong discount, so one luxury car is a good night rather than
## retirement.
const CHOP_BASE_RATE := 0.22
## And what a name on the street adds to that.
const CHOP_REPUTATION_BONUS := 0.18
## In-game minutes a buyer takes between cars, so the same street cannot be
## farmed. §74 and §184.
const CHOP_COOLDOWN_MINUTES := 300.0
## Each successive car within one demand window is worth less, which is the
## other half of §184: the exploit is repetition, not any single sale.
const CHOP_REPEAT_FALLOFF := 0.65
## Reputation lost for a job abandoned or failed. §81 — modest.
const FAILED_JOB_REPUTATION := 3
const BUST_REPUTATION := 2

var save_id: StringName = &"underworld"
var reset_on_missing_save: bool = true

var reputation: int = 0
## Contacts the player has actually met. §125 — one is discoverable from the
## start; the rest have to be earned.
var _unlocked: Dictionary = {}
## contact id -> game minute they will next have work.
var _cooldowns: Dictionary = {}
## Jobs currently on offer or running, newest last.
var _jobs: Array[IllegalJobData] = []
var _next_job: int = 1
## Illegal earnings by CrimeData.Income.
var _earnings: Dictionary = {}
## How many vehicles this buyer has taken recently, for the falloff.
var _recent_chops: int = 0
var _chop_ready_minute: float = 0.0

## Statistics. §143.
var jobs_completed: int = 0
var jobs_failed: int = 0
var vehicles_delivered: int = 0
var goods_sold: int = 0

# --- Phase R --------------------------------------------------------------

## How many offers a contact keeps on the table at once. §69 — a small rotating
## set, not one job and not a menu of twenty.
const BOARD_SIZE := {
	CriminalContactData.Kind.BROKER: 3,
	CriminalContactData.Kind.FENCE: 2,
	CriminalContactData.Kind.VEHICLE_BUYER: 2,
}
## Days a request stands before it lapses and a new one can be asked for. §67.
const REQUEST_DAYS := 3
## Trust for filling a request, and the smaller amount for ordinary trade.
const TRADE_TRUST := 1

## contact_id -> ContactRelationship.
var _trust: Dictionary = {}
var career: CriminalCareer = CriminalCareer.new()
var _requests: Array[ContactRequest] = []
var _next_request: int = 1
## Chain rungs already announced, so unlocking one is news exactly once.
var _announced_chains: Dictionary = {}


func _ready() -> void:
	add_to_group(&"saveable")
	TimeManager.hour_passed.connect(_on_hour_passed)
	WantedManager.bust_finished.connect(_on_busted)
	# §95 and §98 — the crimes the game already has feed this rather than
	# needing their own reward paths. Robbing a till is what completes a
	# robbery contract; stealing a car is what earns the standing to be
	# offered better ones.
	CrimeManager.crime_reported.connect(_on_crime)


# --- Reputation ----------------------------------------------------------

func tier() -> CriminalReputation.Tier:
	return CriminalReputation.tier_for(reputation)


func tier_name() -> String:
	return CriminalReputation.name_for(reputation)


## Reputation moving can open a rung on somebody's ladder, since §61 gates on
## both numbers. Checked after every change rather than only on trust.
func _review_all_chains() -> void:
	for contact in contacts():
		_review_chains(contact.contact_id)


func add_reputation(amount: int, reason: String = "") -> void:
	if amount == 0:
		return
	var before := tier()
	reputation = clampi(reputation + amount, 0, CriminalReputation.MAX_REPUTATION)
	reputation_changed.emit(reputation, tier())
	if amount > 0 and tier() > before:
		GameManager.notify(
			"WORD GETS AROUND\n%s" % tier_name(), GameManager.Tone.GOOD
		)
		AudioManager.play(&"reputation", AudioBuses.SFX, -7.0)
		CrimeManager.add_statistic(&"criminal_tiers_reached")
		_review_unlocks()
	elif amount < 0 and not reason.is_empty():
		GameManager.notify(reason, GameManager.Tone.BAD)
	_review_all_chains()


# --- Contacts ------------------------------------------------------------

func is_unlocked(contact_id: StringName) -> bool:
	return _unlocked.has(contact_id)


func contacts() -> Array[CriminalContactData]:
	var found: Array[CriminalContactData] = []
	for contact in CriminalContactData.all():
		if is_unlocked(contact.contact_id):
			found.append(contact)
	return found


func contact_by_id(id: StringName) -> CriminalContactData:
	return CriminalContactData.by_id(id)


## Whether a contact will deal with the player at all. Unlocking is meeting
## them; this is whether they think you are worth their time today.
func will_deal(contact: CriminalContactData) -> bool:
	return contact != null and reputation >= contact.reputation_required


## The player has found somebody. §126 — discovery is walking into their place
## or being introduced, not a cutscene.
func unlock(contact_id: StringName) -> bool:
	var contact := CriminalContactData.by_id(contact_id)
	if contact == null or _unlocked.has(contact_id):
		return false
	_unlocked[contact_id] = true
	contact_unlocked.emit(contact)
	GameManager.notify(
		"CONTACT MADE\n%s  ·  %s" % [
			contact.display_name.to_upper(), contact.kind_label()
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play_ui(&"ui_confirm")
	return true


## Anybody the player's reputation has earned them an introduction to.
func _review_unlocks() -> void:
	for contact in CriminalContactData.all():
		if _unlocked.has(contact.contact_id):
			continue
		if reputation >= contact.reputation_required and contact.reputation_required > 0:
			unlock(contact.contact_id)


# --- The fence -----------------------------------------------------------

## What a fence would give for what the player is carrying. §67.
func fence_quote(inventory: Node) -> Dictionary:
	var units := 0
	var value := 0
	if inventory != null and inventory.has_method("stolen_stacks"):
		for entry in inventory.call("stolen_stacks"):
			var item: ItemData = entry["item"]
			var quantity := int(entry["quantity"])
			units += quantity
			value += _goods_value(item) * quantity
	var rate := CriminalReputation.fence_rate(reputation)
	return {
		"units": units,
		"value": value,
		"rate": rate,
		"payout": int(round(float(value) * rate)),
	}


## Sells everything stolen the player is carrying. One call, so the goods
## cannot leave the bag without the money arriving.
func sell_to_fence(inventory: Node) -> int:
	var quote := fence_quote(inventory)
	if int(quote["units"]) <= 0:
		GameManager.notify("YOU HAVE NOTHING THEY WANT", GameManager.Tone.BAD)
		return 0
	var payout := int(quote["payout"])
	# §63 — an ordinary sale always works and always pays the standing rate.
	# What a request adds is a premium on the part of the load they asked for,
	# and their trust. §152: selling them the wrong thing is simply a sale.
	var request := request_from(&"quayside_fence")
	var bonus := 0
	var filled := false
	if request != null and request.kind == ContactRequest.Kind.GOODS:
		var matching := _count_stolen(inventory, request.target_id)
		if matching >= request.quantity:
			bonus = int(round(float(payout) * request.bonus))
			filled = true
	var removed := int(inventory.call("remove_stolen"))
	if removed <= 0:
		return 0
	payout += bonus
	_credit(payout, CrimeData.Income.STOLEN_GOODS, "Fence sale")
	goods_sold += removed
	CrimeManager.add_statistic(&"stolen_goods_sold", removed)
	add_reputation(1 + int(float(removed) / 8.0))
	GameManager.notify(
		"SOLD ON\n%d items  ·  $%s%s" % [
			removed, EconomyManager.with_thousands_separator(payout),
			"  ·  order filled" if filled else ""
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"money", AudioBuses.SFX, -8.0)
	career.lifetime_illegal_income += payout
	if filled:
		_fill_request(request, payout)
	else:
		_gain_trust(&"quayside_fence", TRADE_TRUST)
	_advance_job(IllegalJobData.Objective.STOLEN_GOODS_RUN, &"", removed)
	return payout


## How many of one particular line the player is carrying unpaid-for. What a
## goods request is measured against.
func _count_stolen(inventory: Node, item_id: StringName) -> int:
	if inventory == null or not inventory.has_method("stolen_stacks"):
		return 0
	var found := 0
	for entry in inventory.call("stolen_stacks"):
		var item: ItemData = entry["item"]
		if item != null and item.id == item_id:
			found += int(entry["quantity"])
	return found


func _goods_value(item: ItemData) -> int:
	if item == null:
		return 0
	return maxi(item.price, item.get_wholesale_cost())


# --- The chop shop -------------------------------------------------------

func chop_ready() -> bool:
	return TimeManager.total_minutes >= _chop_ready_minute


func chop_minutes_left() -> float:
	return maxf(_chop_ready_minute - TimeManager.total_minutes, 0.0)


## §72 — only genuinely stolen vehicles. A car the player bought is theirs, and
## the way to turn that into money is the dealership.
func chop_eligible(record: OwnedVehicle) -> bool:
	return record != null and record.stolen


## What the buyer would pay. §73: base value, condition, and who you are.
func chop_quote(record: OwnedVehicle) -> Dictionary:
	if record == null:
		return {"eligible": false, "payout": 0, "reason": "No vehicle."}
	if not chop_eligible(record):
		return {
			"eligible": false, "payout": 0,
			"reason": "They only take cars that are not yours.",
		}
	var base := record.market_value()
	var rate := CHOP_BASE_RATE + CHOP_REPUTATION_BONUS * (
		float(reputation) / float(CriminalReputation.MAX_REPUTATION)
	)
	var falloff := pow(CHOP_REPEAT_FALLOFF, float(_recent_chops))
	var payout := int(round(float(base) * rate * falloff))
	return {
		"eligible": true,
		"payout": maxi(payout, 50),
		"base": base,
		"rate": rate,
		"falloff": falloff,
		"ready": chop_ready(),
		"reason": "" if chop_ready() else "They cannot move another one yet.",
	}


## Hands the car over. It leaves the registry — §71 — and the money is illegal.
func deliver_to_chop_shop(record: OwnedVehicle) -> int:
	var quote := chop_quote(record)
	if not bool(quote.get("eligible", false)):
		GameManager.notify(
			String(quote.get("reason", "They will not take it.")), GameManager.Tone.BAD
		)
		return 0
	if not chop_ready():
		GameManager.notify("THEY CANNOT MOVE ANOTHER ONE YET", GameManager.Tone.BAD)
		return 0

	var payout := int(quote["payout"])
	# §66 — a car they actually asked for is worth more than any car, and still
	# well under what it would fetch legally. §154 — if it does not meet the
	# request they say so and it becomes an ordinary sale rather than a refusal,
	# because refusing would leave the player holding a hot car with nowhere to
	# put it.
	var request := request_from(&"dock_road_garage")
	var filled := false
	if request != null and request.kind == ContactRequest.Kind.VEHICLE:
		var check := vehicle_matches(request, record)
		if bool(check["ok"]):
			payout += int(round(float(payout) * request.bonus))
			filled = true
		else:
			GameManager.notify(String(check["reason"]), GameManager.Tone.BAD)
	var model := record.display_name()
	var was := record.model_id
	if not VehicleRegistry.remove(record):
		return 0
	# The police stop looking for a car that no longer exists.
	PoliceMemory.forget_vehicle(record.instance_id)

	_recent_chops += 1
	_chop_ready_minute = TimeManager.total_minutes + CHOP_COOLDOWN_MINUTES
	_credit(payout, CrimeData.Income.VEHICLE_CRIME, "Vehicle sold on")
	vehicles_delivered += 1
	CrimeManager.add_statistic(&"vehicles_delivered")
	add_reputation(3)
	GameManager.notify(
		"CAR TAKEN OFF YOUR HANDS\n%s  ·  $%s" % [
			model.to_upper(), EconomyManager.with_thousands_separator(payout)
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"money", AudioBuses.SFX, -7.0)
	career.lifetime_illegal_income += payout
	career.best_single_payout = maxi(career.best_single_payout, payout)
	if filled:
		_fill_request(request, payout)
	else:
		_gain_trust(&"dock_road_garage", TRADE_TRUST)
	_advance_job(IllegalJobData.Objective.VEHICLE_DELIVERY, was, 1)
	return payout


# --- Jobs ----------------------------------------------------------------

func jobs() -> Array[IllegalJobData]:
	return _jobs.duplicate()


func offered_jobs() -> Array[IllegalJobData]:
	var found: Array[IllegalJobData] = []
	for job in _jobs:
		if job.status == IllegalJobData.Status.OFFERED:
			found.append(job)
	return found


func active_job() -> IllegalJobData:
	for job in _jobs:
		if job.is_active():
			return job
	return null


func jobs_from(contact_id: StringName) -> Array[IllegalJobData]:
	var found: Array[IllegalJobData] = []
	for job in _jobs:
		if job.contact_id == contact_id and job.is_open():
			found.append(job)
	return found


func job_by_id(id: StringName) -> IllegalJobData:
	for job in _jobs:
		if job.job_id == id:
			return job
	return null


func contact_ready(contact: CriminalContactData) -> bool:
	if contact == null:
		return false
	return TimeManager.total_minutes >= float(_cooldowns.get(contact.contact_id, 0.0))


## Puts work on the table, if this contact has any and is willing.
func offer_job(contact: CriminalContactData) -> IllegalJobData:
	if contact == null or contact.job_types.is_empty():
		return null
	if not will_deal(contact) or not contact_ready(contact):
		return null
	if not jobs_from(contact.contact_id).is_empty():
		return jobs_from(contact.contact_id)[0]
	var job := IllegalJobFactory.build(
		StringName("job_%d" % _next_job), contact, reputation
	)
	if job == null:
		return null
	_next_job += 1
	_jobs.append(job)
	_cooldowns[contact.contact_id] = TimeManager.total_minutes + contact.cooldown_minutes
	job_offered.emit(job)
	return job


func accept_job(job: IllegalJobData) -> bool:
	if job == null or job.status != IllegalJobData.Status.OFFERED:
		return false
	if active_job() != null:
		GameManager.notify("YOU ARE ALREADY ON SOMETHING", GameManager.Tone.BAD)
		return false
	job.status = IllegalJobData.Status.ACTIVE
	job.progress = 0
	job.deadline_minute = (
		TimeManager.total_minutes + float(job.time_limit_hours) * 60.0
		if job.time_limit_hours > 0 else -1.0
	)
	job_accepted.emit(job)
	GameManager.notify(
		"JOB TAKEN\n%s  ·  %s" % [job.objective_label().to_upper(), job.target_name],
		GameManager.Tone.GOOD
	)
	AudioManager.play_ui(&"ui_confirm")
	return true


func decline_job(job: IllegalJobData) -> void:
	if job == null or job.status != IllegalJobData.Status.OFFERED:
		return
	_jobs.erase(job)


## Gives a job up. §81 — walking away costs a little standing.
func abandon_job(job: IllegalJobData) -> bool:
	if job == null or not job.is_active():
		return false
	_fail(job, "You walked away from it.", true)
	return true


## Progress on whatever is running, if this is the kind of thing it wanted.
func _advance_job(
	objective: IllegalJobData.Objective, target: StringName, amount: int
) -> void:
	var job := active_job()
	if job == null or job.objective != objective:
		return
	if job.target_id != &"" and target != &"" and job.target_id != target:
		return
	job.progress += amount
	if job.progress < job.target_quantity:
		GameManager.notify(
			"JOB  %d of %d" % [job.progress, job.target_quantity], GameManager.Tone.INFO
		)
		return
	_complete(job)


## Public entry for the objectives finished by something other than a sale —
## a robbery contract is completed by robbing the till.
func note_objective(
	objective: IllegalJobData.Objective, target: StringName, amount: int = 1
) -> void:
	_advance_job(objective, target, amount)


func _complete(job: IllegalJobData) -> void:
	job.status = IllegalJobData.Status.COMPLETE
	# §74 — a speciality is worth a little more money in its own line of work.
	var payout := int(round(float(job.reward) * (1.0 + career.payout_bonus(job.objective))))
	job.reward = payout
	_credit(payout, CrimeData.Income.ILLEGAL_JOBS, "Job paid")
	add_reputation(job.reputation_reward)
	jobs_completed += 1
	CrimeManager.add_statistic(&"illegal_jobs_completed")
	# The two halves of Phase R's underworld: this person now trusts you a
	# little more, and your career has one more of this kind of job in it.
	var link := relationship(job.contact_id)
	link.jobs_done += 1
	link.total_paid += payout
	var chain := chain_for(job.contact_id)
	_gain_trust(job.contact_id, chain.trust_reward if chain != null else 5)
	career.credit(job.objective)
	career.lifetime_illegal_income += payout
	career.best_single_payout = maxi(career.best_single_payout, payout)
	career_changed.emit()
	job_completed.emit(job)
	GameManager.notify(
		"JOB DONE\n%s  ·  $%s  ·  +%d reputation" % [
			job.objective_label().to_upper(),
			EconomyManager.with_thousands_separator(job.reward),
			job.reputation_reward,
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"money", AudioBuses.SFX, -6.0)


func _fail(job: IllegalJobData, reason: String, walked_away: bool = false) -> void:
	if job == null or job.is_finished():
		return
	job.status = IllegalJobData.Status.FAILED
	jobs_failed += 1
	add_reputation(-FAILED_JOB_REPUTATION)
	# §57 — the person let down is the one who minds, and walking away costs
	# more than being unlucky. Nobody else's opinion changes.
	var link := relationship(job.contact_id)
	link.jobs_failed += 1
	_lose_trust(
		job.contact_id,
		ContactRelationship.ABANDON_LOSS if walked_away else ContactRelationship.FAILURE_LOSS
	)
	if walked_away:
		career.jobs_abandoned += 1
	else:
		career.jobs_failed += 1
	career_changed.emit()
	job_failed.emit(job, reason)
	GameManager.notify("JOB FAILED\n%s" % reason, GameManager.Tone.BAD)
	AudioManager.play_ui(&"ui_error")


# --- Trust, chains, requests and the career (Phase R) --------------------

## The relationship with one contact, created on first use. §54 — separate from
## `reputation`, which is how known the player is in general.
func relationship(contact_id: StringName) -> ContactRelationship:
	if not _trust.has(contact_id):
		_trust[contact_id] = ContactRelationship.make(contact_id)
	return _trust[contact_id]


func trust_in(contact_id: StringName) -> int:
	return relationship(contact_id).trust


func relationships() -> Array[ContactRelationship]:
	var found: Array[ContactRelationship] = []
	for contact in contacts():
		if _trust.has(contact.contact_id):
			found.append(_trust[contact.contact_id])
	return found


func _gain_trust(contact_id: StringName, amount: int, reason: String = "") -> void:
	if contact_id == &"" or amount <= 0:
		return
	var link := relationship(contact_id)
	var before := link.tier()
	if link.gain(amount) <= 0:
		return
	trust_changed.emit(contact_id, link.trust, link.tier())
	if link.tier() != before:
		AudioManager.play(&"contact_trust", AudioBuses.SFX, -9.0)
		GameManager.notify(
			"%s  ·  %s" % [_contact_name(contact_id).to_upper(), link.tier_name().to_upper()],
			GameManager.Tone.GOOD
		)
	elif reason != "":
		GameManager.notify(reason, GameManager.Tone.GOOD)
	_review_chains(contact_id)


## §57 — modest, and only with the person actually let down.
func _lose_trust(contact_id: StringName, amount: int) -> void:
	if contact_id == &"" or amount <= 0:
		return
	var link := relationship(contact_id)
	if link.lose(amount) <= 0:
		return
	trust_changed.emit(contact_id, link.trust, link.tier())


func _contact_name(contact_id: StringName) -> String:
	var contact := contact_by_id(contact_id)
	return contact.display_name if contact != null else String(contact_id)


## The rung of this contact's ladder the player has earned. §61 — both numbers.
func chain_for(contact_id: StringName) -> JobChain:
	return JobChain.current(contact_id, reputation, trust_in(contact_id))


func next_chain_for(contact_id: StringName) -> JobChain:
	return JobChain.next(contact_id, reputation, trust_in(contact_id))


## Announces a newly reachable rung, once. Called whenever either number moves.
func _review_chains(contact_id: StringName) -> void:
	var chain := chain_for(contact_id)
	if chain == null or _announced_chains.has(chain.chain_id):
		return
	_announced_chains[chain.chain_id] = true
	var link := relationship(contact_id)
	if chain.tier <= link.chain_tier:
		return
	link.chain_tier = chain.tier
	AudioManager.play(&"career_tier", AudioBuses.SFX, -9.0)
	GameManager.notify(
		"NEW WORK\n%s  ·  %s" % [_contact_name(contact_id).to_upper(), chain.display_name],
		GameManager.Tone.GOOD
	)
	chain_tier_unlocked.emit(contact_id, chain)


# --- The board -----------------------------------------------------------

## Tops a contact's offers up to their board size. §69 — the broker keeps
## several on the table; the others keep fewer, because they are not brokers.
##
## Every offer is built by the factory from live world data, so §71's rule that
## a job never names a missing property or an unavailable model is kept by the
## same code that kept it in Phase Q.
func refresh_board(contact: CriminalContactData) -> Array[IllegalJobData]:
	if contact == null or not will_deal(contact):
		return []
	var wanted := int(BOARD_SIZE.get(contact.kind, 1))
	var chain := chain_for(contact.contact_id)
	var guard := 0
	while jobs_from(contact.contact_id).size() < wanted and guard < 8:
		guard += 1
		var job := IllegalJobFactory.build(
			StringName("job_%d" % _next_job), contact, reputation, chain
		)
		if job == null:
			break
		_next_job += 1
		_jobs.append(job)
		job_offered.emit(job)
	_cooldowns[contact.contact_id] = TimeManager.total_minutes + contact.cooldown_minutes
	return jobs_from(contact.contact_id)


# --- Requests ------------------------------------------------------------

func requests() -> Array[ContactRequest]:
	var found: Array[ContactRequest] = []
	for request in _requests:
		if request.is_open(TimeManager.day_index):
			found.append(request)
	return found


func request_from(contact_id: StringName) -> ContactRequest:
	for request in _requests:
		if request.contact_id == contact_id and request.is_open(TimeManager.day_index):
			return request
	return null


## Asks a contact what they want, if they have not already said and are the
## sort of person who asks. §62 and §65.
func post_request(contact: CriminalContactData) -> ContactRequest:
	if contact == null or not will_deal(contact):
		return null
	if request_from(contact.contact_id) != null:
		return request_from(contact.contact_id)
	var request: ContactRequest = null
	match contact.kind:
		CriminalContactData.Kind.FENCE:
			request = _goods_request(contact)
		CriminalContactData.Kind.VEHICLE_BUYER:
			request = _vehicle_request(contact)
		_:
			return null
	if request == null:
		return null
	_requests.append(request)
	AudioManager.play(&"request_posted", AudioBuses.SFX, -11.0)
	GameManager.notify(
		"WANTED\n%s  ·  %s" % [contact.display_name.to_upper(), request.headline()],
		GameManager.Tone.INFO
	)
	request_posted.emit(request)
	return request


## Something the fence has actually asked for, drawn from the item catalogue so
## the thing named is always something the world contains — §71.
##
## §62 suggests a category. The catalogue has three (food, drink, other), so a
## category request would name most of what anybody carries and mean nothing;
## a specific line asks for something the player has to go and get, which is
## the point of a request existing at all.
func _goods_request(contact: CriminalContactData) -> ContactRequest:
	var goods := ItemCatalogue.all()
	if goods.is_empty():
		return null
	var pick: ItemData = goods[randi() % goods.size()]
	var request := ContactRequest.make(
		StringName("req_%d" % _next_request), contact.contact_id,
		ContactRequest.Kind.GOODS, pick.id, pick.display_name,
		3 + randi() % 4, TimeManager.day_index + REQUEST_DAYS
	)
	_next_request += 1
	request.bonus = 0.25 + 0.05 * float(int(relationship(contact.contact_id).tier()))
	request.trust_reward = 6
	request.reputation_reward = 2
	return request


## A class of car, or — once this person trusts the player — one named model.
## §65 and §68. Both come off the vehicle catalogue, so the car asked for is
## always one the game can actually produce.
func _vehicle_request(contact: CriminalContactData) -> ContactRequest:
	var link := relationship(contact.contact_id)
	var named := int(link.tier()) >= int(ContactRelationship.Tier.TRUSTED)
	var ids := VehicleCatalogue.purchasable_ids()
	if ids.is_empty():
		return null
	var pick := VehicleCatalogue.data_for(ids[randi() % ids.size()])
	if pick == null:
		return null
	var request := ContactRequest.make(
		StringName("req_%d" % _next_request), contact.contact_id,
		ContactRequest.Kind.VEHICLE,
		pick.id if named else StringName(pick.vehicle_class.to_lower()),
		pick.display_name if named else "Any %s" % pick.vehicle_class.to_lower(),
		1, TimeManager.day_index + REQUEST_DAYS
	)
	_next_request += 1
	request.bonus = 0.35 + 0.08 * float(int(link.tier()))
	# §68 — a reason not to wreck it on the way. Only the pickier requests ask.
	request.minimum_condition = 70.0 if named else 0.0
	request.trust_reward = 8 if named else 5
	request.reputation_reward = 3
	return request


## Whether a vehicle satisfies a request: the right class or the right model,
## and in good enough order.
func vehicle_matches(request: ContactRequest, record: OwnedVehicle) -> Dictionary:
	if request == null or record == null:
		return {"ok": false, "reason": "Nothing asked for."}
	var data := record.data()
	if data == null:
		return {"ok": false, "reason": "They do not know what that is."}
	var wanted_model := request.target_id == data.id
	var wanted_class := request.target_id == StringName(data.vehicle_class.to_lower())
	if not wanted_model and not wanted_class:
		return {"ok": false, "reason": "That is not what they asked for."}
	if record.condition < request.minimum_condition:
		return {
			"ok": false,
			"reason": "They asked for %d%% or better. That is %d%%." % [
				roundi(request.minimum_condition), roundi(record.condition)
			],
		}
	return {"ok": true, "reason": ""}


func _fill_request(request: ContactRequest, payout: int) -> void:
	request.filled = true
	var link := relationship(request.contact_id)
	link.requests_filled += 1
	career.requests_filled += 1
	_gain_trust(request.contact_id, request.trust_reward)
	add_reputation(request.reputation_reward)
	request_filled.emit(request, payout)
	career_changed.emit()


# --- Career --------------------------------------------------------------

func speciality() -> CriminalCareer.Path:
	return career.speciality()


func speciality_name() -> String:
	return CriminalCareer.path_name(career.speciality())


func _on_hour_passed(_hour: int) -> void:
	# §90 — a job with a clock on it can run out.
	var job := active_job()
	if job != null and job.is_overdue():
		_fail(job, "The time ran out.")
	# The buyer's demand recovers.
	if chop_ready() and _recent_chops > 0:
		_recent_chops = maxi(_recent_chops - 1, 0)
	_forget_settled()
	_forget_lapsed_requests()


## Doing a crime is worth something on the street, whether anybody asked for
## it or not. Deliberately small — §80 warns against rewarding random harm, and
## the reward table in CrimeData gives violence nothing.
func _on_crime(record: Dictionary) -> void:
	var data := CrimeData.for_type(int(record.get("type", 0)))
	if data.criminal_reputation_reward > 0:
		add_reputation(1)
	match int(record.get("type", 0)):
		CrimeManager.CrimeType.STORE_ROBBERY, CrimeManager.CrimeType.ROBBERY:
			var target: Variant = record.get("target")
			var id: StringName = (
				StringName(target.get_path()) if target is Node else &""
			)
			note_objective(IllegalJobData.Objective.ROBBERY_CONTRACT, id)


func _on_busted(_fine: int) -> void:
	# §90 — being caught loses whatever was running.
	var job := active_job()
	if job != null:
		_fail(job, "You were picked up.")
	add_reputation(-BUST_REPUTATION)


## §67 — a request that was not filled in time simply lapses, and the contact
## is free to ask for something else.
func _forget_lapsed_requests() -> void:
	var today := TimeManager.day_index
	for request in _requests.duplicate():
		if request.filled or today > request.expires_on_day:
			_requests.erase(request)


func _forget_settled() -> void:
	var settled: Array[IllegalJobData] = []
	for job in _jobs:
		if job.is_finished():
			settled.append(job)
	while settled.size() > 12:
		_jobs.erase(settled.pop_front())


# --- Money ---------------------------------------------------------------

## Illegal earnings by source. §68.
func earnings() -> Dictionary:
	return _earnings.duplicate()


func earnings_of(category: CrimeData.Income) -> int:
	return int(_earnings.get(category, 0))


func total_illegal_income() -> int:
	var total := 0
	for key in _earnings:
		total += int(_earnings[key])
	return total


func _credit(amount: int, category: CrimeData.Income, reason: String) -> void:
	if amount <= 0:
		return
	EconomyManager.deposit(amount, reason, EconomyManager.Source.CRIME)
	_earnings[category] = earnings_of(category) + amount
	illegal_income.emit(amount, category)


# --- Save ----------------------------------------------------------------

func clear() -> void:
	reputation = 0
	_trust.clear()
	_requests.clear()
	_announced_chains.clear()
	_next_request = 1
	career = CriminalCareer.new()
	_unlocked.clear()
	_cooldowns.clear()
	_jobs.clear()
	_earnings.clear()
	_next_job = 1
	_recent_chops = 0
	_chop_ready_minute = 0.0
	jobs_completed = 0
	jobs_failed = 0
	vehicles_delivered = 0
	goods_sold = 0


func save_state() -> Dictionary:
	var stored: Array = []
	for job in _jobs:
		if job.is_open():
			stored.append(job.to_dict())
	var cooldowns := {}
	for id: StringName in _cooldowns:
		cooldowns[String(id)] = float(_cooldowns[id])
	var money := {}
	for key in _earnings:
		money[str(int(key))] = int(_earnings[key])
	var links: Array = []
	for id: StringName in _trust:
		links.append((_trust[id] as ContactRelationship).to_dict())
	var asks: Array = []
	for request in _requests:
		if request.is_open(TimeManager.day_index):
			asks.append(request.to_dict())
	return {
		"reputation": reputation,
		"unlocked": _unlocked.keys().map(func(id): return String(id)),
		"cooldowns": cooldowns,
		"jobs": stored,
		"next_job": _next_job,
		"earnings": money,
		"recent_chops": _recent_chops,
		"chop_ready": _chop_ready_minute,
		"jobs_completed": jobs_completed,
		"jobs_failed": jobs_failed,
		"vehicles_delivered": vehicles_delivered,
		"goods_sold": goods_sold,
		"trust": links,
		"requests": asks,
		"next_request": _next_request,
		"career": career.to_dict(),
		"chains": _announced_chains.keys().map(func(id): return String(id)),
	}


func load_state(state: Dictionary) -> void:
	clear()
	reputation = int(state.get("reputation", 0))
	for id in state.get("unlocked", []):
		_unlocked[StringName(id)] = true
	for key in state.get("cooldowns", {}):
		_cooldowns[StringName(key)] = float(state["cooldowns"][key])
	for entry in state.get("jobs", []):
		_jobs.append(IllegalJobData.from_dict(entry))
	_next_job = int(state.get("next_job", _jobs.size() + 1))
	for key in state.get("earnings", {}):
		_earnings[int(key)] = int(state["earnings"][key])
	_recent_chops = int(state.get("recent_chops", 0))
	_chop_ready_minute = float(state.get("chop_ready", 0.0))
	jobs_completed = int(state.get("jobs_completed", 0))
	jobs_failed = int(state.get("jobs_failed", 0))
	vehicles_delivered = int(state.get("vehicles_delivered", 0))
	goods_sold = int(state.get("goods_sold", 0))

	# Phase R. §108 — a Phase Q save has none of this, so unlocked contacts are
	# given a starting trust derived from what the player has already done with
	# them rather than being reset to strangers. Nothing is invented: it comes
	# off the reputation and the completed-job count that save already carried.
	for entry in state.get("trust", []):
		if entry is Dictionary:
			var link := ContactRelationship.from_dict(entry)
			_trust[link.contact_id] = link
	for entry in state.get("requests", []):
		if entry is Dictionary:
			_requests.append(ContactRequest.from_dict(entry))
	_next_request = int(state.get("next_request", _requests.size() + 1))
	var career_state: Variant = state.get("career", {})
	if career_state is Dictionary and not (career_state as Dictionary).is_empty():
		career = CriminalCareer.from_dict(career_state)
	for id in state.get("chains", []):
		_announced_chains[StringName(id)] = true
	if not state.has("trust"):
		_migrate_trust()

	reputation_changed.emit(reputation, tier())
	career_changed.emit()


## Gives a pre-Phase-R save a plausible starting relationship with everybody it
## had already unlocked. Half the general reputation, capped well below the
## tiers that open the good work, so an old save keeps its standing without
## being handed a career it never had.
func _migrate_trust() -> void:
	for id: StringName in _unlocked:
		var link := relationship(id)
		link.trust = clampi(int(float(reputation) * 0.5), 0, 40)
		link.jobs_done = 0
	if jobs_completed > 0:
		career.contract_jobs = jobs_completed
