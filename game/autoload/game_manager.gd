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

enum State { PLAYING, PAUSED }
enum Tone { INFO, GOOD, BAD }

var state: State = State.PLAYING:
	set(value):
		if state == value:
			return
		state = value
		get_tree().paused = state == State.PAUSED
		state_changed.emit(state)

## The currently controlled player. Registered by the player itself so that
## nothing has to hard-code a scene path to it.
var player: Node3D = null


func _ready() -> void:
	# The manager has to keep running while the tree is paused, otherwise it
	# could never unpause itself.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	state = State.PLAYING if state == State.PAUSED else State.PAUSED


func is_paused() -> bool:
	return state == State.PAUSED


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
