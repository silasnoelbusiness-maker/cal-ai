class_name ContactRelationship
extends RefCounted

## How much one particular person trusts the player.
##
## §54 is the distinction the whole underworld half of Phase R turns on.
## Criminal reputation is how *known* somebody is — one number, shared, and
## already built in Phase Q. Trust is how a *named* contact feels about them,
## and it is earned and lost with that contact alone. Doing three jobs for the
## fence teaches the vehicle buyer nothing.
##
## §61 then uses both: better work needs a reputation that says you are somebody
## and a trust that says this person will hand you something that matters. That
## is what stops the career being one stat farmed in one place.

enum Tier { NEW, RELIABLE, TRUSTED, PREFERRED, INNER_CIRCLE }

const TIER_NAMES := {
	Tier.NEW: "New",
	Tier.RELIABLE: "Reliable",
	Tier.TRUSTED: "Trusted",
	Tier.PREFERRED: "Preferred",
	Tier.INNER_CIRCLE: "Inner circle",
}

const MAX_TRUST := 100
const TIER_THRESHOLDS := [0, 20, 45, 70, 90]

## §57 — one bad night is not a divorce. Abandoning work costs more than
## failing it, because failing is bad luck and abandoning is a decision.
const FAILURE_LOSS := 6
const ABANDON_LOSS := 10

var contact_id: StringName = &""
var trust: int = 0
var jobs_done: int = 0
var jobs_failed: int = 0
var requests_filled: int = 0
## How far up this contact's own ladder the player has climbed. §59.
var chain_tier: int = 1
var total_paid: int = 0


static func make(id: StringName) -> ContactRelationship:
	var link := ContactRelationship.new()
	link.contact_id = id
	return link


func tier() -> Tier:
	var reached := Tier.NEW
	for candidate in range(TIER_THRESHOLDS.size()):
		if trust >= int(TIER_THRESHOLDS[candidate]):
			reached = candidate as Tier
	return reached


func tier_name() -> String:
	return String(TIER_NAMES.get(tier(), "New"))


static func name_of(value: Tier) -> String:
	return String(TIER_NAMES.get(value, "New"))


## Trust needed for the next rung, or -1 at the top.
func next_threshold() -> int:
	var here := int(tier())
	if here >= TIER_THRESHOLDS.size() - 1:
		return -1
	return int(TIER_THRESHOLDS[here + 1])


func gain(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := trust
	trust = clampi(trust + amount, 0, MAX_TRUST)
	return trust - before


func lose(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := trust
	trust = clampi(trust - amount, 0, MAX_TRUST)
	return before - trust


func to_dict() -> Dictionary:
	return {
		"id": String(contact_id),
		"trust": trust,
		"done": jobs_done,
		"failed": jobs_failed,
		"requests": requests_filled,
		"chain": chain_tier,
		"paid": total_paid,
	}


static func from_dict(state: Dictionary) -> ContactRelationship:
	var link := ContactRelationship.new()
	link.contact_id = StringName(state.get("id", ""))
	link.trust = int(state.get("trust", 0))
	link.jobs_done = int(state.get("done", 0))
	link.jobs_failed = int(state.get("failed", 0))
	link.requests_filled = int(state.get("requests", 0))
	link.chain_tier = int(state.get("chain", 1))
	link.total_paid = int(state.get("paid", 0))
	return link
