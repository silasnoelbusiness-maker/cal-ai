class_name CriminalContactPoint
extends Interactable

## The door the player knocks on.
##
## One of these stands at each of the three fictional addresses Phase Q adds.
## Walking up to it is how a contact is discovered (§126) — no cutscene, no
## quest marker, just somebody who is there if you find them. The starter fence
## introduces themselves to anybody; the other two want a name first, and say
## so rather than pretending not to exist.

## Which contact this is the door of.
@export var contact_id: StringName = &"quayside_fence"


func _ready() -> void:
	add_to_group(&"criminal_contact")
	focus_priority = 3
	_refresh()


func contact() -> CriminalContactData:
	return CriminalContactData.by_id(contact_id)


func get_prompt_text() -> String:
	_refresh()
	return super.get_prompt_text()


func _refresh() -> void:
	var data := contact()
	if data == null:
		prompt_action = "Knock"
		prompt_subtitle = ""
		return
	if not Underworld.is_unlocked(contact_id):
		prompt_action = "Knock"
		prompt_subtitle = "Somebody works out of here"
		return
	prompt_action = "Talk to %s" % data.display_name
	if not Underworld.will_deal(data):
		prompt_subtitle = data.closed_line
		return
	match data.kind:
		CriminalContactData.Kind.FENCE:
			var carried := _stolen_carried()
			prompt_subtitle = (
				"%d item%s to sell" % [carried, "" if carried == 1 else "s"]
				if carried > 0 else "Buys what you should not have"
			)
		CriminalContactData.Kind.VEHICLE_BUYER:
			prompt_subtitle = (
				"Takes cars that are not yours" if Underworld.chop_ready()
				else "Cannot move another one yet"
			)
		_:
			prompt_subtitle = "Has work, sometimes"


func _stolen_carried() -> int:
	var player := GameManager.player
	if player == null or not player.has_method("get_inventory"):
		return 0
	var inventory = player.call("get_inventory")
	return int(inventory.call("stolen_count")) if inventory != null else 0


func _perform(interactor: Node3D) -> void:
	var data := contact()
	if data == null:
		return
	# Finding them is meeting them. The reputation gate is about whether they
	# will deal, not about whether they exist. §126.
	if not Underworld.is_unlocked(contact_id):
		Underworld.unlock(contact_id)
	GameManager.request_screen(&"underworld_contact", self, interactor)
