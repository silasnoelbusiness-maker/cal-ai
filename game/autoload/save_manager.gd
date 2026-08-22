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

## Emitted around an autosave so the HUD can show that it happened without the
## save system knowing anything about the HUD.
signal autosave_started(reason: String)
signal autosave_finished(succeeded: bool)

const SAVE_VERSION := 1
const SAVE_PATH := "user://meridian_save_%d.json"
const SAVEABLE_GROUP := &"saveable"

## Entity ids present in the save most recently loaded. See save_contained().
var _loaded_entity_ids: PackedStringArray = PackedStringArray()


func _ready() -> void:
	# Must keep running while the tree is paused so saving from a menu works.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	# Quick-load retired with Phase L: loading is a considered choice made from
	# the pause menu against a named slot, not a keystroke that silently throws
	# away everything since the last save.
	if event.is_action_pressed("quick_save"):
		save_to_slot(1)
		get_viewport().set_input_as_handled()


func get_slot_path(slot: int) -> String:
	return SAVE_PATH % slot


## Slots the front end offers. Three manual, plus one the game writes itself.
const MANUAL_SLOTS: Array[int] = [1, 2, 3]
const AUTOSAVE_SLOT := 0


## What is in a slot, without loading it: the summary written at save time plus
## the file's own timestamp. Returns an empty dictionary for an empty slot, and
## for a corrupt one — a slot that cannot be described is a slot the player
## should not be offered.
func describe_slot(slot: int) -> Dictionary:
	var path := get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = parsed
	if int(payload.get("version", 0)) > SAVE_VERSION:
		return {}
	var summary: Dictionary = payload.get("summary", {})
	summary["slot"] = slot
	summary["saved_at"] = payload.get("saved_at", "")
	summary["autosave"] = slot == AUTOSAVE_SLOT
	return summary


## Every slot with something readable in it, newest first. What CONTINUE picks
## from, and what the load screen lists.
func list_saves() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for slot in ([AUTOSAVE_SLOT] + MANUAL_SLOTS):
		var summary := describe_slot(slot)
		if not summary.is_empty():
			found.append(summary)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("saved_at", "")) > String(b.get("saved_at", ""))
	)
	return found


## The slot CONTINUE should load, or -1 when there is nothing valid to continue.
func most_recent_slot() -> int:
	var saves := list_saves()
	return int(saves[0].get("slot", -1)) if not saves.is_empty() else -1


func has_any_save() -> bool:
	return most_recent_slot() >= 0


## A one-line description of the game as it stands, stored with the save.
func _describe_current_game() -> Dictionary:
	var district := WorldManager.player_district()
	return {
		"cash": EconomyManager.cash,
		"day": TimeManager.day_index + 1,
		"time": TimeManager.get_time_string(),
		"district": district.display_name if district != null else "Harbour Row",
		"businesses": BusinessManager.owned_count(),
		"net_worth": BusinessManager.net_worth(),
	}


func has_save(slot: int = 1) -> bool:
	return FileAccess.file_exists(get_slot_path(slot))


func save_to_slot(slot: int = 1) -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		# A summary the load screen reads without restoring anything: enough to
		# tell one slot from another at a glance.
		"summary": _describe_current_game(),
		"clock": {"total_minutes": TimeManager.total_minutes},
		"economy": {
			"cash": EconomyManager.cash,
			"income": EconomyManager.total_income,
			"expenses": EconomyManager.total_expenses,
			"illegal": EconomyManager.illegal_income,
			"lifetime": EconomyManager.lifetime_for_save(),
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
	# The lifetime split is Phase R's; a save without it simply has none, and
	# the figures start from whatever this session earns.
	EconomyManager.restore_lifetime(
		economy.get("lifetime", {}), int(economy.get("illegal", 0))
	)

	var entities: Dictionary = payload.get("entities", {})
	_loaded_entity_ids.clear()
	for key in entities:
		_loaded_entity_ids.append(String(key))
	for node in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		var id := _save_id_of(node)
		if id == "" or not node.has_method("load_state"):
			continue
		if not entities.has(id):
			# Most entities are simply left as they are: an older save saying
			# nothing about them is not the same as saying they are empty.
			# A few are the other way round — a depot or a shipment from the
			# session before must not survive into a save that never had one —
			# and those ask to be emptied instead.
			if node.get("reset_on_missing_save") == true:
				node.call("load_state", {})
			continue
		node.call("load_state", entities[id])


## Whether the save just loaded actually carried a block for this entity.
## The difference matters to anything that keeps its records somewhere else:
## an absent block means "there were none", not "leave what you have".
func save_contained(id: StringName) -> bool:
	return _loaded_entity_ids.has(String(id))


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


# --- Autosave --------------------------------------------------------------

## The game saving itself, at moments that are already a natural break.
##
## Deliberately event-driven rather than on a timer: a save every five minutes
## lands mid-chase as often as not, and a save when the player goes to bed or
## signs a lease is one they would have made themselves. The cooldown stops a
## flurry of events becoming a flurry of writes.
const AUTOSAVE_COOLDOWN := 90.0

var _last_autosave: float = -999.0


func autosave(reason: String = "") -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_autosave < AUTOSAVE_COOLDOWN:
		return false
	_last_autosave = now
	autosave_started.emit(reason)
	var saved := save_to_slot(AUTOSAVE_SLOT)
	autosave_finished.emit(saved)
	return saved
