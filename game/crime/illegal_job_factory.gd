class_name IllegalJobFactory
extends RefCounted

## Makes a job a contact can plausibly offer.
##
## §185 asks for variety within valid data pools and no impossible targets, so
## every job this builds names something the game can actually produce: a
## vehicle class the dealership sells and the streets carry, an item a shop
## stocks, a business that exists. Nothing here invents a target and hopes.
##
## Rewards scale with reputation because §82 unlocks higher-value work rather
## than better weapons, and with risk because §139 wants crime to pay better
## than a courier run while still costing something when it goes wrong.

## Vehicle classes a buyer might ask for, cheapest first.
const VEHICLE_TARGETS: Array[StringName] = [
	&"hatchback", &"sedan", &"van", &"suv", &"coupe",
]

## What the work pays before reputation, by risk band.
const BASE_REWARD := {
	IllegalJobData.Risk.LOW: 1200,
	IllegalJobData.Risk.MEDIUM: 2600,
	IllegalJobData.Risk.HIGH: 5200,
	IllegalJobData.Risk.EXTREME: 9000,
}


## Builds one offer.
##
## Phase R adds the optional `chain` — the rung of this contact's ladder the
## player has earned. When one is given it decides which objectives are on the
## table and multiplies the money, so higher standing produces genuinely
## different work rather than the same work with a bigger number. Without one
## the Phase Q behaviour is unchanged, which is what the older tests expect.
static func build(
	id: StringName, contact: CriminalContactData, reputation: int,
	chain: JobChain = null
) -> IllegalJobData:
	if contact == null or contact.job_types.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var job: IllegalJobData = null
	if chain != null and not chain.objectives.is_empty():
		var objective: int = chain.objectives[rng.randi_range(0, chain.objectives.size() - 1)]
		job = _for_objective(objective, id, contact, reputation, rng)
		if job != null:
			job.reward = int(round(float(job.reward) * chain.reward_multiplier / 50.0)) * 50
		return job
	var kind: StringName = contact.job_types[
		rng.randi_range(0, contact.job_types.size() - 1)
	]
	match kind:
		&"vehicle_delivery":
			return _vehicle_delivery(id, contact, reputation, rng)
		&"stolen_goods_run":
			return _stolen_goods(id, contact, reputation, rng)
		&"robbery_contract":
			return _robbery(id, contact, reputation, rng)
		&"high_risk_theft":
			return _high_risk_theft(id, contact, reputation, rng)
	return null


static func _for_objective(
	objective: int, id: StringName, contact: CriminalContactData,
	reputation: int, rng: RandomNumberGenerator
) -> IllegalJobData:
	match objective:
		IllegalJobData.Objective.VEHICLE_DELIVERY:
			return _vehicle_delivery(id, contact, reputation, rng)
		IllegalJobData.Objective.STOLEN_GOODS_RUN:
			return _stolen_goods(id, contact, reputation, rng)
		IllegalJobData.Objective.ROBBERY_CONTRACT:
			return _robbery(id, contact, reputation, rng)
		IllegalJobData.Objective.HIGH_RISK_THEFT:
			return _high_risk_theft(id, contact, reputation, rng)
		IllegalJobData.Objective.MULTI_STOP_RUN:
			return _multi_stop(id, contact, reputation, rng)
		IllegalJobData.Objective.RETRIEVE_STASH:
			return _retrieve(id, contact, reputation, rng)
	return null


## §79 — a package collected and dropped at two or three marked points, against
## a clock. The parcel is deliberately nothing: it is a thing to be moved, and
## the game never says what is in it.
static func _multi_stop(
	id: StringName, contact: CriminalContactData, reputation: int,
	rng: RandomNumberGenerator
) -> IllegalJobData:
	var stops := rng.randi_range(2, 3)
	var job := IllegalJobData.make(
		id, contact.contact_id, IllegalJobData.Objective.MULTI_STOP_RUN,
		&"", "a sealed parcel, %d drops" % stops,
		_reward(IllegalJobData.Risk.MEDIUM, reputation, rng),
		IllegalJobData.Risk.MEDIUM, 5, 4, stops
	)
	return job


## §80 — fetch a marked package back from somewhere and hand it over. Same
## abstraction, one leg instead of several.
static func _retrieve(
	id: StringName, contact: CriminalContactData, reputation: int,
	rng: RandomNumberGenerator
) -> IllegalJobData:
	return IllegalJobData.make(
		id, contact.contact_id, IllegalJobData.Objective.RETRIEVE_STASH,
		&"", "a package somebody left behind",
		_reward(IllegalJobData.Risk.LOW, reputation, rng),
		IllegalJobData.Risk.LOW, 8, 3, 1
	)


## §85 — get a car of the kind they asked for and bring it in. Uses the theft
## and chop-shop gameplay that already exists.
static func _vehicle_delivery(
	id: StringName, contact: CriminalContactData, reputation: int,
	rng: RandomNumberGenerator
) -> IllegalJobData:
	# Better standing means they ask for better cars, which is §82's unlock
	# expressed as work rather than as equipment.
	var reach := clampi(
		1 + int(float(reputation) / 25.0), 1, VEHICLE_TARGETS.size()
	)
	var model: StringName = VEHICLE_TARGETS[rng.randi_range(0, reach - 1)]
	var data := VehicleCatalogue.data_for(model)
	var label := data.display_name if data != null else String(model).capitalize()
	var risk := (
		IllegalJobData.Risk.HIGH if reach >= 4 else IllegalJobData.Risk.MEDIUM
	)
	return IllegalJobData.make(
		id, contact.contact_id, IllegalJobData.Objective.VEHICLE_DELIVERY,
		model, label, _reward(risk, reputation, rng), risk, 8, 4
	)


## §86 — pick contraband up and bring it in. Abstract on purpose: the goods are
## "stolen goods", a category the inventory already understands.
static func _stolen_goods(
	id: StringName, contact: CriminalContactData, reputation: int,
	rng: RandomNumberGenerator
) -> IllegalJobData:
	var quantity := rng.randi_range(4, 10)
	return IllegalJobData.make(
		id, contact.contact_id, IllegalJobData.Objective.STOLEN_GOODS_RUN,
		&"", "%d items of stolen goods" % quantity,
		_reward(IllegalJobData.Risk.LOW, reputation, rng),
		IllegalJobData.Risk.LOW, 12, 2, quantity
	)


## §87 — rob a till they have picked out. Reuses the robbery the game has had
## since Phase J; the contact only chooses where.
static func _robbery(
	id: StringName, contact: CriminalContactData, reputation: int,
	rng: RandomNumberGenerator
) -> IllegalJobData:
	var shops := _robbable_shops()
	if shops.is_empty():
		return null
	var target: Node = shops[rng.randi_range(0, shops.size() - 1)]
	var label: Variant = target.get("shop_name")
	return IllegalJobData.make(
		id, contact.contact_id, IllegalJobData.Objective.ROBBERY_CONTRACT,
		StringName(target.get_path()),
		String(label) if label != null else "a shop",
		_reward(IllegalJobData.Risk.HIGH, reputation, rng),
		IllegalJobData.Risk.HIGH, 6, 5
	)


## §88 — a harder version of a theft the game already has. A premium car,
## which is the one target the world reliably has and the police mind about.
static func _high_risk_theft(
	id: StringName, contact: CriminalContactData, reputation: int,
	rng: RandomNumberGenerator
) -> IllegalJobData:
	var model: StringName = VEHICLE_TARGETS[VEHICLE_TARGETS.size() - 1]
	var data := VehicleCatalogue.data_for(model)
	return IllegalJobData.make(
		id, contact.contact_id, IllegalJobData.Objective.VEHICLE_DELIVERY,
		model, "%s — and they will notice" % (
			data.display_name if data != null else String(model).capitalize()
		),
		_reward(IllegalJobData.Risk.EXTREME, reputation, rng),
		IllegalJobData.Risk.EXTREME, 6, 7
	)


static func _reward(
	risk: IllegalJobData.Risk, reputation: int, rng: RandomNumberGenerator
) -> int:
	var base := int(BASE_REWARD.get(risk, 2000))
	# A name on the street is worth up to half as much again.
	var standing := 1.0 + 0.5 * clampf(
		float(reputation) / float(CriminalReputation.MAX_REPUTATION), 0.0, 1.0
	)
	var spread := rng.randf_range(0.9, 1.15)
	return int(round(float(base) * standing * spread / 50.0)) * 50


static func _robbable_shops() -> Array[Node]:
	var found: Array[Node] = []
	for node in Engine.get_main_loop().get_nodes_in_group(&"shop"):
		found.append(node)
	return found
