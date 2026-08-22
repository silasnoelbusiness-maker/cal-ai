class_name JobChain
extends RefCounted

## A contact's own ladder of work.
##
## §59 asks for short progression chains and is explicit that these are not
## story missions. So a chain is four rungs of the same *kind* of work getting
## bigger, gated on both the general reputation Phase Q tracks and the trust in
## this particular person (§61). Nothing here has dialogue, characters or a
## plot; it decides what is on offer and no more.

var chain_id: StringName = &""
var contact_id: StringName = &""
var tier: int = 1
var display_name: String = "Work"
var blurb: String = ""
## Which objectives this rung may generate. Ids from IllegalJobData.Objective.
var objectives: Array[int] = []
## Both gates, per §61. One stat farmed in one place is not enough.
var reputation_required: int = 0
var trust_required: int = 0
## Multiplies the reward the job factory would otherwise produce.
var reward_multiplier: float = 1.0
## What finishing one of these is worth with this contact.
var trust_reward: int = 5


static func make(
	id: StringName, contact: StringName, rung: int, name: String, text: String,
	kinds: Array[int], reputation: int, trust: int, reward: float, gain: int
) -> JobChain:
	var chain := JobChain.new()
	chain.chain_id = id
	chain.contact_id = contact
	chain.tier = rung
	chain.display_name = name
	chain.blurb = text
	chain.objectives = kinds
	chain.reputation_required = reputation
	chain.trust_required = trust
	chain.reward_multiplier = reward
	chain.trust_reward = gain
	return chain


func is_open(reputation: int, trust: int) -> bool:
	return reputation >= reputation_required and trust >= trust_required


## Every chain in the game, by contact. Three ladders, one per career path in
## §72: goods, vehicles, contracts. Kept as data in one place so the underworld
## screen, the job factory and the tests all read the same ladder.
static func catalogue() -> Array[JobChain]:
	var goods := IllegalJobData.Objective.STOLEN_GOODS_RUN
	var vehicle := IllegalJobData.Objective.VEHICLE_DELIVERY
	var robbery := IllegalJobData.Objective.ROBBERY_CONTRACT
	var theft := IllegalJobData.Objective.HIGH_RISK_THEFT
	var multi := IllegalJobData.Objective.MULTI_STOP_RUN
	var stash := IllegalJobData.Objective.RETRIEVE_STASH

	return [
		# The fence: moving things.
		JobChain.make(
			&"fence_1", &"quayside_fence", 1, "Odds and ends",
			"Whatever comes off the street.", [goods], 0, 0, 1.0, 5
		),
		JobChain.make(
			&"fence_2", &"quayside_fence", 2, "Standing orders",
			"They want particular things now, and more of them.", [goods, stash],
			15, 20, 1.25, 6
		),
		JobChain.make(
			&"fence_3", &"quayside_fence", 3, "The rounds",
			"Several drops in one night, and a clock on it.", [multi, stash],
			35, 45, 1.6, 8
		),
		JobChain.make(
			&"fence_4", &"quayside_fence", 4, "The good stuff",
			"They only ask people they are sure of.", [theft, multi],
			60, 70, 2.1, 10
		),

		# The garage: cars.
		JobChain.make(
			&"garage_1", &"dock_road_garage", 1, "Anything on four wheels",
			"Common cars, no questions, small money.", [vehicle], 10, 0, 1.0, 5
		),
		JobChain.make(
			&"garage_2", &"dock_road_garage", 2, "To order",
			"A class of car rather than any car.", [vehicle], 25, 20, 1.3, 6
		),
		JobChain.make(
			&"garage_3", &"dock_road_garage", 3, "Named plates",
			"One specific car, in one piece.", [vehicle, stash], 45, 45, 1.7, 8
		),
		JobChain.make(
			&"garage_4", &"dock_road_garage", 4, "Short notice",
			"A named car, tonight, and they are already paid for it.",
			[vehicle, theft], 70, 70, 2.2, 10
		),

		# The broker: contracts.
		JobChain.make(
			&"broker_1", &"the_broker", 1, "Errands",
			"Small work for people who do not know you.", [goods, multi], 20, 0, 1.0, 5
		),
		JobChain.make(
			&"broker_2", &"the_broker", 2, "Contracts",
			"Named jobs with a clock and a number.", [robbery, theft, multi],
			35, 20, 1.35, 7
		),
		JobChain.make(
			&"broker_3", &"the_broker", 3, "The list",
			"Work they would not put in front of most people.",
			[robbery, theft, stash], 55, 45, 1.8, 9
		),
		JobChain.make(
			&"broker_4", &"the_broker", 4, "Principals only",
			"They stop calling you and start asking you.",
			[robbery, theft, vehicle], 80, 70, 2.4, 12
		),
	]


static func for_contact(id: StringName) -> Array[JobChain]:
	var found: Array[JobChain] = []
	for chain in catalogue():
		if chain.contact_id == id:
			found.append(chain)
	return found


## The best rung this player has earned with this contact, or null if they have
## not earned the first one yet.
static func current(id: StringName, reputation: int, trust: int) -> JobChain:
	var best: JobChain = null
	for chain in for_contact(id):
		if not chain.is_open(reputation, trust):
			continue
		if best == null or chain.tier > best.tier:
			best = chain
	return best


## The rung after the current one, so a screen can say what is next and what it
## would take. Null at the top of the ladder.
static func next(id: StringName, reputation: int, trust: int) -> JobChain:
	var here := current(id, reputation, trust)
	var rung := 0 if here == null else here.tier
	for chain in for_contact(id):
		if chain.tier == rung + 1:
			return chain
	return null
