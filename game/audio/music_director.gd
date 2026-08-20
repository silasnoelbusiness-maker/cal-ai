extends Node
## The music system, with no music in it.
##
## STREET CAPITAL ships without a soundtrack: inventing one would mean either
## licensed audio this project does not have or synthesised loops that would
## wear out in ten minutes of a game meant to be played for hours. So this is
## the architecture and the state machine, wired to the real events, with
## silence in every slot — and the day a track exists it is one line in
## `TRACKS` rather than a system to design under deadline.
##
## The states are the ones the game already distinguishes. The transitions
## crossfade, so nothing about adding audio later requires touching callers.

signal state_changed(state: State)

enum State { NONE, MENU, DAY, NIGHT, WANTED }

## Track per state. Empty means silence, which is the current shipping answer
## for everything except the menu — and the menu's is the ambience bed rather
## than a composed cue, so the title screen is not silent.
const TRACKS := {
	State.NONE: &"",
	State.MENU: &"",
	State.DAY: &"",
	State.NIGHT: &"",
	State.WANTED: &"",
}

const FADE := 2.0
const TRACK_DB := -12.0

var _state: State = State.NONE
var _player: AudioStreamPlayer = null
var _target_db: float = -80.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure_layout()
	_player = AudioStreamPlayer.new()
	_player.name = "Track"
	_player.bus = String(AudioBuses.MUSIC)
	_player.volume_db = -80.0
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)

	WantedManager.level_changed.connect(_on_wanted_level_changed)
	WantedManager.wanted_cleared.connect(_on_wanted_cleared)
	TimeManager.hour_passed.connect(_on_hour_passed)


func get_state() -> State:
	return _state


## Moves to a state. Crossfades rather than cutting, and does nothing at all
## when the state has not changed — the day/night check calls this hourly.
func set_state(state: State) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(state)

	var track: StringName = TRACKS.get(state, &"")
	if track == &"":
		# Silence is a legitimate state, not a failure to find a file.
		_target_db = -80.0
		return
	_player.stream = ToneBank.get_stream(track)
	_player.play()
	_target_db = TRACK_DB


## What the world should be playing right now, ignoring the menu.
func refresh_world_state() -> void:
	if WantedManager.is_wanted():
		set_state(State.WANTED)
		return
	set_state(
		State.NIGHT if TimeManager.get_phase() == TimeManager.Phase.NIGHT else State.DAY
	)


func _process(delta: float) -> void:
	if _player == null:
		return
	var step := delta / FADE * 60.0
	_player.volume_db = move_toward(_player.volume_db, _target_db, step)
	if _player.volume_db <= -79.0 and _player.playing and _target_db <= -79.0:
		_player.stop()


func _on_wanted_level_changed(level: int) -> void:
	if _state == State.MENU:
		return
	if level > 0:
		set_state(State.WANTED)
	else:
		refresh_world_state()


func _on_wanted_cleared() -> void:
	if _state != State.MENU:
		refresh_world_state()


func _on_hour_passed(_hour: int) -> void:
	if _state != State.MENU and not WantedManager.is_wanted():
		refresh_world_state()
