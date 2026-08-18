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

enum State { PLAYING, PAUSED }
enum Tone { INFO, GOOD, BAD }

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


func _ready() -> void:
	# The manager has to keep running while the tree is paused, otherwise it
	# could never unpause itself.
	process_mode = Node.PROCESS_MODE_ALWAYS


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
func notify(message: String, tone: Tone = Tone.INFO) -> void:
	notification_posted.emit(message, tone)
