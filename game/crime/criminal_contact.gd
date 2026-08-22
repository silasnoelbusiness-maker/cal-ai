class_name CriminalContactData
extends RefCounted

## Somebody who will do business with a criminal.
##
## Three kinds in Phase Q and no more (§77): a fence who buys goods, a buyer
## who takes vehicles, and a broker who hands out work. §186 rules out criminal
## organisations, territory and everything that comes with them, so a contact
## here is one person at one address with a phone that is sometimes engaged.
##
## Everything about them is fictional and generic on purpose. No contact,
## location or job in this file refers to anything real.

enum Kind { FENCE, VEHICLE_BUYER, BROKER }

const KIND_NAMES := {
	Kind.FENCE: "FENCE",
	Kind.VEHICLE_BUYER: "VEHICLE BUYER",
	Kind.BROKER: "BROKER",
}

var contact_id: StringName = &""
var display_name: String = "Contact"
var kind: Kind = Kind.FENCE
## Criminal reputation before they will deal with the player at all.
var reputation_required: int = 0
## Which job types this one offers. Empty for a contact who only trades.
var job_types: Array[StringName] = []
## In-game minutes before they have something new to offer. §91.
var cooldown_minutes: float = 240.0
## The property or marker their place is at, for the map and the world.
var location_id: StringName = &""
## What they say when the player has not earned their time yet.
var closed_line: String = "They do not know you."


static func make(
	id: StringName, name: String, contact_kind: Kind, needs: int,
	where: StringName, jobs: Array[StringName] = [],
	cooldown: float = 240.0, closed: String = "They do not know you."
) -> CriminalContactData:
	var contact := CriminalContactData.new()
	contact.contact_id = id
	contact.display_name = name
	contact.kind = contact_kind
	contact.reputation_required = needs
	contact.location_id = where
	contact.job_types = jobs
	contact.cooldown_minutes = cooldown
	contact.closed_line = closed
	return contact


static func kind_name(contact_kind: Kind) -> String:
	return String(KIND_NAMES.get(contact_kind, "CONTACT"))


func kind_label() -> String:
	return kind_name(kind)


## The starter contact is the one §125 asks for: discoverable, low level, and
## not forced on anybody. The other two want a name behind you first.
static var _table: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty():
		_table = {
			&"quayside_fence": make(
				&"quayside_fence", "The Quayside Buyer", Kind.FENCE, 0,
				&"fence_quayside", [], 180.0,
				"They are not interested in strangers today."
			),
			&"dock_road_garage": make(
				&"dock_road_garage", "Dock Road Motors", Kind.VEHICLE_BUYER, 10,
				&"chop_shop_dock", [&"vehicle_delivery"], 240.0,
				"They only take cars from people they have heard of."
			),
			&"the_broker": make(
				&"the_broker", "The Broker", Kind.BROKER, 20,
				&"broker_backstreet",
				[&"stolen_goods_run", &"robbery_contract", &"high_risk_theft"],
				300.0, "Come back when somebody can vouch for you."
			),
		}
	return _table


static func all() -> Array[CriminalContactData]:
	var found: Array[CriminalContactData] = []
	for id: StringName in table():
		found.append(table()[id])
	return found


static func by_id(id: StringName) -> CriminalContactData:
	return table().get(id)
