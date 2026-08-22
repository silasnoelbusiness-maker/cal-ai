class_name UnderworldDebug
extends RefCounted

## Development-only pokes for the Phase Q crime and police systems.
##
## §145 lists what a developer needs to be able to force, and this is that list
## made callable. Everything here drives the real systems rather than setting
## flags behind their backs — forcing a search runs the same code a broken line
## of sight does — so a test that passes here is a test of the game rather than
## of the tool.
##
## Nothing in this file is reachable from play. It is called by the smoke test,
## by the screenshot tool, and from the debug overlay.

# --- Wanted and police ---------------------------------------------------

## Sets the wanted level outright, as if the player had earned it.
static func set_wanted(level: int) -> void:
	WantedManager.set_level(clampi(level, 0, WantedManager.MAX_LEVEL))


## Files a crime and puts it straight in front of the police, skipping the
## witness system. What "somebody saw that" would have produced.
static func force_report(
	type: int = CrimeManager.CrimeType.VEHICLE_THEFT, at: Vector3 = Vector3.INF
) -> Dictionary:
	var player := GameManager.player
	var position := at
	if position == Vector3.INF:
		position = player.global_position if player != null else Vector3.ZERO
	var record := CrimeManager.report_crime(type, position, player, null)
	CrimeManager.mark_witnessed(record, player)
	CrimeManager.mark_reported(record)
	WantedManager.on_crime_reported(record)
	return record


## Puts eyes on the player right now.
##
## Goes through WantedManager, which is the door every police unit in the game
## uses — it is what cancels the escape countdown, tells the player they have
## been SPOTTED and marks the car they are sitting in. Calling the response
## manager directly reached the state machine but left the countdown running,
## which is the second time in this phase a debug helper has taken a shortcut
## and produced a state the game itself never reaches.
static func force_pursuit() -> void:
	var player := GameManager.player
	if player == null:
		return
	WantedManager.notify_player_seen(player.global_position)


## Nobody can see the player any more. The honest way to test escaping without
## having to drive round a corner.
static func break_line_of_sight() -> void:
	PoliceMemory.seconds_since_seen = 999.0


## Opens a search around wherever the police last had eyes.
##
## Drives the real path rather than opening the zone behind everybody's back.
## The first version called SearchManager.begin() directly, which left
## WantedManager not escaping and the response manager still in PURSUIT — a
## search nothing else in the game agreed was happening, and one that being
## spotted therefore could not end.
static func start_search() -> void:
	break_line_of_sight()
	if not WantedManager.is_wanted():
		return
	WantedManager.call("_begin_escaping")
	PoliceResponseManager.call("_set_state", PoliceResponseManager.State.SEARCHING)


static func clear_wanted() -> void:
	WantedManager.clear_wanted("WANTED LEVEL CLEARED")


## §28 — makes the police look for a particular car.
static func mark_vehicle_known(vehicle: Node) -> void:
	PoliceMemory.mark_vehicle_known(vehicle)


## §30 — the police lose their description, as if the player had swapped cars
## somewhere nobody was watching.
static func lose_identity() -> void:
	PoliceMemory.lose_player_identity()


## Puts a roadblock on the road, bypassing the wanted-level gate.
static func spawn_roadblock() -> bool:
	return bool(RoadblockManager.call("_place_one"))


# --- Underworld ----------------------------------------------------------

static func unlock_all_contacts() -> void:
	for contact in CriminalContactData.all():
		Underworld.unlock(contact.contact_id)


static func set_reputation(value: int) -> void:
	Underworld.add_reputation(
		clampi(value, 0, CriminalReputation.MAX_REPUTATION) - Underworld.reputation
	)


## Puts work on the table from a named contact, ready to be accepted.
static func create_job(contact_id: StringName = &"the_broker") -> IllegalJobData:
	var contact := CriminalContactData.by_id(contact_id)
	if contact == null:
		return null
	Underworld.unlock(contact_id)
	if not Underworld.will_deal(contact):
		set_reputation(contact.reputation_required)
	# Clear the cooldown so a test does not have to wait five hours.
	var cooldowns: Dictionary = Underworld.get("_cooldowns")
	cooldowns.erase(contact_id)
	return Underworld.offer_job(contact)


## Puts stolen goods in the player's bag, which is what a fence buys.
static func give_stolen_goods(item_id: StringName, quantity: int = 5) -> int:
	var player := GameManager.player
	if player == null or not player.has_method("get_inventory"):
		return 0
	var item := ItemCatalogue.by_id(item_id)
	if item == null:
		return 0
	var inventory = player.call("get_inventory")
	return int(inventory.call("add", item, quantity, true))


## Marks a vehicle as not the player's, which is what a buyer takes.
static func mark_vehicle_stolen(record: OwnedVehicle) -> void:
	if record != null:
		record.stolen = true


## Hands a car over without having to drive it there.
static func force_chop_delivery(record: OwnedVehicle) -> int:
	if record == null:
		return 0
	Underworld.set("_chop_ready_minute", 0.0)
	return Underworld.deliver_to_chop_shop(record)
