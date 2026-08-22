class_name ContactRequest
extends RefCounted

## Something a contact has actually asked for.
##
## §62 and §65. Selling the fence whatever you happen to be carrying always
## works and always pays the standing rate; a *request* is the contact naming a
## category and paying over the odds for it, with trust attached. Same for the
## vehicle buyer naming a class and a condition.
##
## §64 and §75 are the boundary this keeps: a request names an abstract
## category from the game's own item and vehicle data. It never describes how to
## obtain anything, because that is not something a game needs to say.

enum Kind { GOODS, VEHICLE }

var request_id: StringName = &""
var contact_id: StringName = &""
var kind: Kind = Kind.GOODS
## For goods: an ItemData category. For vehicles: a class id, or a specific
## model id when the contact wants one particular fictional car.
var target_id: StringName = &""
var target_name: String = "Goods"
var quantity: int = 1
## Fraction over the ordinary rate this pays.
var bonus: float = 0.25
## Vehicle requests only: the contact will not take a wreck. §68 — the reason
## not to destroy the car on the way.
var minimum_condition: float = 0.0
var trust_reward: int = 6
var reputation_reward: int = 2
## Day the request stops standing. §67 — requests expire and refresh so nothing
## can be farmed forever.
var expires_on_day: int = 0
var filled: bool = false


static func make(
	id: StringName, contact: StringName, sort: Kind,
	target: StringName, name: String, amount: int, day: int
) -> ContactRequest:
	var request := ContactRequest.new()
	request.request_id = id
	request.contact_id = contact
	request.kind = sort
	request.target_id = target
	request.target_name = name
	request.quantity = amount
	request.expires_on_day = day
	return request


func is_open(today: int) -> bool:
	return not filled and today <= expires_on_day


func days_left(today: int) -> int:
	return maxi(expires_on_day - today, 0)


func headline() -> String:
	if kind == Kind.VEHICLE:
		return target_name
	return "%s x%d" % [target_name, quantity]


func condition_label() -> String:
	if minimum_condition <= 0.0:
		return "Any condition"
	return "Condition %d%% or better" % roundi(minimum_condition)


func to_dict() -> Dictionary:
	return {
		"id": String(request_id),
		"contact": String(contact_id),
		"kind": int(kind),
		"target": String(target_id),
		"name": target_name,
		"quantity": quantity,
		"bonus": bonus,
		"condition": minimum_condition,
		"trust": trust_reward,
		"reputation": reputation_reward,
		"expires": expires_on_day,
		"filled": filled,
	}


static func from_dict(state: Dictionary) -> ContactRequest:
	var request := ContactRequest.new()
	request.request_id = StringName(state.get("id", ""))
	request.contact_id = StringName(state.get("contact", ""))
	request.kind = int(state.get("kind", 0)) as Kind
	request.target_id = StringName(state.get("target", ""))
	request.target_name = String(state.get("name", "Goods"))
	request.quantity = int(state.get("quantity", 1))
	request.bonus = float(state.get("bonus", 0.25))
	request.minimum_condition = float(state.get("condition", 0.0))
	request.trust_reward = int(state.get("trust", 6))
	request.reputation_reward = int(state.get("reputation", 2))
	request.expires_on_day = int(state.get("expires", 0))
	request.filled = bool(state.get("filled", false))
	return request
