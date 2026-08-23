extends Node
## Top-level session state for Meridian City.
##
## Deliberately small: it owns the run state (playing / paused), keeps a weak
## registry of "who is the player right now", and provides a single place for
## systems to push short player-facing notifications to whatever UI is
## listening. Gameplay rules live in their own systems, never here.

signal state_changed(new_state: State)
signal player_registered(player: Node3D)
signal player_unregistered()
signal notification_posted(message: String, tone: Tone)
## A system is asking the UI to open a screen. `screen_id` keeps this generic:
## the manager never needs to know what a shop or a job is.
signal screen_requested(screen_id: StringName, context: Node, requester: Node)
## Something asked for every open screen to close (Esc, or a teleport).
signal menus_close_requested()
signal player_teleported(destination: Transform3D)
## Emitted the moment a message is accepted — shown now or queued to be shown
## shortly. A message that is deduped or dropped for backlog does not emit,
## because the player genuinely never sees one of those.
signal notification_accepted(message: String, tone: int, priority: int)

enum State { PLAYING, PAUSED }
enum Tone { INFO, GOOD, BAD }

## How much a message deserves the player's attention.
##
## Before this existed every notification simply replaced the one before it, so
## a busy moment — a shop closing, a wage run, a delivery landing and the
## police arriving, all in the same second — showed the player whichever
## happened to be last. Now the police arriving wins, and the wage run waits
## its turn rather than being lost.
##
##   LOW    — pleasant to know, and repeats: low stock, rent landing, an
##            enquiry. Dropped when there is a queue. Nothing the player
##            deliberately paid for and waited on belongs here — a delivery
##            arriving is not chatter, however often it happens.
##   NORMAL — the default. Queued in order.
##   HIGH   — the player must see this: arrests, court, foreclosure, death.
enum Priority { LOW, NORMAL, HIGH }

## Seconds a message holds the corner before the next one is allowed up. Just
## under the toast's own hold, so the queue never runs dry mid-fade.
const NOTIFY_DWELL := 2.2
## The same message inside this many seconds is the same message. Stops a
## per-frame condition shouting the same line forty times.
const NOTIFY_DEDUPE := 6.0
## Beyond this many waiting, LOW messages are dropped rather than queued.
const NOTIFY_BACKLOG := 3

var state: State = State.PLAYING:
	set(value):
		if state == value:
			return
		state = value
		_apply_pause()
		state_changed.emit(state)

## True while a full-screen UI (inventory, shop) is up. Freezes the world like
## a pause but without the pause overlay, so the two cannot fight over
## `get_tree().paused`.
var menu_open: bool = false:
	set(value):
		if menu_open == value:
			return
		menu_open = value
		_apply_pause()

## True while a scripted beat owns the screen — the arrest, for now. Freezes the
## world like a pause, but Esc cannot dismiss it and no overlay competes with it.
var cutscene_active: bool = false:
	set(value):
		if cutscene_active == value:
			return
		cutscene_active = value
		_apply_pause()

## True while the player is placing a piece of business equipment. The world
## keeps running — placement is a mode, not a menu — so this exists to tell the
## handful of things that share those inputs (the left button, R) to stand down
## rather than to freeze anything.
var placement_active: bool = false

## The currently controlled player. Registered by the player itself so that
## nothing has to hard-code a scene path to it.
var player: Node3D = null

## Messages waiting for the corner, and when each was last said.
var _notify_queue: Array[Dictionary] = []
var _notify_recent: Dictionary = {}
var _notify_shown_at: float = 0.0


func _ready() -> void:
	# The manager has to keep running while the tree is paused, otherwise it
	# could never unpause itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	_drain_notifications()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		if cutscene_active:
			get_viewport().set_input_as_handled()
			return
		# Esc backs out of an open screen first, and only then pauses.
		if menu_open:
			close_menus()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	state = State.PLAYING if state == State.PAUSED else State.PAUSED


func is_paused() -> bool:
	return state == State.PAUSED


func _apply_pause() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = state == State.PAUSED or menu_open or cutscene_active


## Asks whatever UI is listening to open a screen. `context` is the thing the
## screen is about (a Shop, say); `requester` is who asked (usually the player).
func request_screen(screen_id: StringName, context: Node = null, requester: Node = null) -> void:
	screen_requested.emit(screen_id, context, requester)


func close_menus() -> void:
	menus_close_requested.emit()


## Moves the player somewhere else in the world. Central so that the camera and
## the HUD can react to a cut without every door having to know about them.
func teleport_player(destination: Transform3D) -> void:
	if player == null:
		return
	close_menus()
	player.global_position = destination.origin
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	player_teleported.emit(destination)


func register_player(new_player: Node3D) -> void:
	player = new_player
	player_registered.emit(new_player)


func unregister_player(old_player: Node3D) -> void:
	if player != old_player:
		return
	player = null
	player_unregistered.emit()


## Push a transient message to the HUD ("SHIFT COMPLETE", "CRIME REPORTED", ...).
## Posts a message to the corner of the screen.
##
## The signal is emitted when the message is actually due to be shown, not when
## it is posted, so everything downstream — the toast, the sound — stays as
## simple as it was and the ordering lives in one place.
func notify(
	message: String, tone: Tone = Tone.INFO, priority: Priority = Priority.NORMAL
) -> void:
	if message.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _recently_said(message, now):
		return
	var entry := {"message": message, "tone": int(tone), "priority": int(priority), "at": now}

	# Nothing showing: straight up, whatever it is.
	if now - _notify_shown_at >= NOTIFY_DWELL and _notify_queue.is_empty():
		notification_accepted.emit(message, int(tone), int(priority))
		_say(entry, now)
		return

	if priority == Priority.HIGH:
		# Something the player must see does not wait behind a wage run.
		notification_accepted.emit(message, int(tone), int(priority))
		_notify_queue.push_front(entry)
		_say(_notify_queue.pop_front(), now)
		return
	if priority == Priority.LOW and _notify_queue.size() >= NOTIFY_BACKLOG:
		return
	notification_accepted.emit(message, int(tone), int(priority))
	_notify_queue.append(entry)


func _say(entry: Dictionary, now: float) -> void:
	_notify_shown_at = now
	_notify_recent[String(entry["message"])] = now
	notification_posted.emit(String(entry["message"]), int(entry["tone"]))


func _recently_said(message: String, now: float) -> bool:
	if _notify_recent.has(message) and now - float(_notify_recent[message]) < NOTIFY_DEDUPE:
		return true
	for entry in _notify_queue:
		if String(entry["message"]) == message:
			return true
	return false


## Drains the queue. Runs on the always-process clock, so messages keep coming
## through while a screen is up.
func _drain_notifications() -> void:
	if _notify_queue.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _notify_shown_at < NOTIFY_DWELL:
		return
	# Highest priority first, oldest first within a priority.
	var best := 0
	for i in _notify_queue.size():
		var entry: Dictionary = _notify_queue[i]
		if int(entry["priority"]) > int(_notify_queue[best]["priority"]):
			best = i
	_say(_notify_queue.pop_at(best), now)


## How many messages are waiting. For the debug overlay and the tests.
func pending_notifications() -> int:
	return _notify_queue.size()


func clear_notifications() -> void:
	_notify_queue.clear()
	_notify_recent.clear()
	_notify_shown_at = 0.0
