extends Node
## Save and load.
##
## Nothing here knows what a player or a car is. Any node that wants persisting
## joins the "saveable" group, exposes a `save_id`, and implements
## `save_state() -> Dictionary` and `load_state(Dictionary)`. Global managers
## (clock, money) are written alongside as their own sections. Adding a system
## to the save is therefore two methods on that system and nothing here.
##
## Files are JSON so a broken save can be read by a human during development.
## Every read is defensive: a missing or unknown key falls back to the live
## value rather than throwing, so an older save still loads after new fields
## are added.

signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(reason: String)

const SAVE_VERSION := 1
const SAVE_PATH := "user://meridian_save_%d.json"
const SAVEABLE_GROUP := &"saveable"


func _ready() -> void:
	# Must keep running while the tree is paused so saving from a menu works.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		save_to_slot(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		load_from_slot(1)
		get_viewport().set_input_as_handled()


func get_slot_path(slot: int) -> String:
	return SAVE_PATH % slot


func has_save(slot: int = 1) -> bool:
	return FileAccess.file_exists(get_slot_path(slot))


func save_to_slot(slot: int = 1) -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"clock": {"total_minutes": TimeManager.total_minutes},
		"economy": {
			"cash": EconomyManager.cash,
			"income": EconomyManager.total_income,
			"expenses": EconomyManager.total_expenses,
		},
		"entities": _collect_entities(),
	}

	var file := FileAccess.open(get_slot_path(slot), FileAccess.WRITE)
	if file == null:
		var reason := "Could not open %s for writing." % get_slot_path(slot)
		push_error(reason)
		save_failed.emit(reason)
		GameManager.notify("SAVE FAILED", GameManager.Tone.BAD)
		return false

	file.store_string(JSON.stringify(payload, "  "))
	file.close()

	game_saved.emit(slot)
	GameManager.notify("GAME SAVED", GameManager.Tone.GOOD)
	return true


func load_from_slot(slot: int = 1) -> bool:
	if not has_save(slot):
		GameManager.notify("NO SAVE TO LOAD", GameManager.Tone.BAD)
		return false

	var file := FileAccess.open(get_slot_path(slot), FileAccess.READ)
	if file == null:
		save_failed.emit("Could not read %s." % get_slot_path(slot))
		GameManager.notify("LOAD FAILED", GameManager.Tone.BAD)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		save_failed.emit("Save file is not valid JSON.")
		GameManager.notify("LOAD FAILED", GameManager.Tone.BAD)
		return false

	var payload: Dictionary = parsed
	var version := int(payload.get("version", 0))
	if version > SAVE_VERSION:
		# Newer than this build understands. Refuse rather than half-apply it.
		save_failed.emit("Save is version %d, this build reads %d." % [version, SAVE_VERSION])
		GameManager.notify("SAVE IS FROM A NEWER BUILD", GameManager.Tone.BAD)
		return false

	_apply_payload(payload)
	game_loaded.emit(slot)
	GameManager.notify("GAME LOADED", GameManager.Tone.GOOD)
	return true


func delete_slot(slot: int = 1) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(get_slot_path(slot))


# --- Internals -----------------------------------------------------------

func _collect_entities() -> Dictionary:
	var entities := {}
	for node in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		var id := _save_id_of(node)
		if id == "":
			push_warning("Saveable node '%s' has no save_id; skipping." % node.name)
			continue
		if not node.has_method("save_state"):
			push_warning("Saveable node '%s' has no save_state(); skipping." % node.name)
			continue
		entities[id] = node.call("save_state")
	return entities


func _apply_payload(payload: Dictionary) -> void:
	# Get the player out of any car first: the save records where they stood,
	# not which seat they were in, and restoring position while driving would
	# fight the vehicle for control of their transform.
	_eject_driver()

	var clock: Dictionary = payload.get("clock", {})
	TimeManager.set_total_minutes(float(clock.get("total_minutes", TimeManager.total_minutes)))

	var economy: Dictionary = payload.get("economy", {})
	EconomyManager.restore(
		int(economy.get("cash", EconomyManager.cash)),
		int(economy.get("income", EconomyManager.total_income)),
		int(economy.get("expenses", EconomyManager.total_expenses))
	)

	var entities: Dictionary = payload.get("entities", {})
	for node in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		var id := _save_id_of(node)
		# A save written before this entity existed simply leaves it as it is.
		if id == "" or not entities.has(id) or not node.has_method("load_state"):
			continue
		node.call("load_state", entities[id])


func _eject_driver() -> void:
	var player := GameManager.player
	if player == null or not player.has_method("get_vehicle"):
		return
	var vehicle = player.call("get_vehicle")
	if vehicle != null and vehicle.has_method("exit_driver"):
		vehicle.call("exit_driver", true)


func _save_id_of(node: Node) -> String:
	var id: Variant = node.get("save_id")
	return "" if id == null else String(id)
