extends Node
## Runs the opening sequence, and gets out of the way.
##
## §74 — skippable at any time, and skipping is permanent for that save.
## §75 — a player who has already done the thing is not made to do it again;
## a step whose condition is already satisfied when it comes up is marked done
## and passed straight through, so loading an established save does not reopen
## the tutorial.
## §77 — nothing here gates anything. The city is fully open on the first
## frame; these are suggestions with a banner.

signal step_changed(step: OnboardingStep)
signal step_completed(step: OnboardingStep)
signal finished()
signal skipped()

## How long a player may sit on one step before the hint appears (§78), in
## real seconds.
const HINT_AFTER := 45.0

## Flags reported more than once do nothing, so a shop visit on day forty
## cannot advance a step the player is nowhere near.
const CHECK_INTERVAL := 0.5

@export var save_id: StringName = &"onboarding"
@export var reset_on_missing_save: bool = true

var _steps: Array[OnboardingStep] = []
var _index: int = 0
var _done: bool = false
var _skipped: bool = false
var _hint_timer: float = 0.0
var _tick: float = 0.0
## Flags seen since the current step began. Cleared on every advance so a step
## is never satisfied by something that happened before it was asked for.
var _flags: Dictionary = {}
var _quiet: bool = false


func _ready() -> void:
	add_to_group(&"saveable")
	_steps = OnboardingChain.steps()
	set_process(true)
	# Settling has to wait until every other entity has been restored, because
	# it asks questions about the player's shifts and businesses and those are
	# loaded by their own owners in an order this file must not depend on.
	SaveManager.game_loaded.connect(_on_game_loaded)
	# Watched rather than reported, so the progression side never has to know
	# this file exists.
	Progression.pinned_changed.connect(_on_pinned_changed)


func _process(delta: float) -> void:
	if not is_running():
		return
	_hint_timer += delta
	_tick += delta
	if _tick < CHECK_INTERVAL:
		return
	_tick = 0.0
	_evaluate()


func _on_game_loaded(_slot: int) -> void:
	settle()


func _on_pinned_changed() -> void:
	if not Progression.pinned().is_empty():
		report(&"goal_pinned")


# --- State ---------------------------------------------------------------

func is_running() -> bool:
	return not _done and not _skipped and _index < _steps.size()


func is_finished() -> bool:
	return _done


func was_skipped() -> bool:
	return _skipped


func current() -> OnboardingStep:
	if not is_running():
		return null
	return _steps[_index]


func step_number() -> int:
	return _index + 1


func step_count() -> int:
	return _steps.size()


## The hint, once the player has been on this step long enough to want it.
func visible_hint() -> String:
	var step := current()
	if step == null or _hint_timer < HINT_AFTER:
		return ""
	return step.hint


func all_steps() -> Array[OnboardingStep]:
	return _steps.duplicate()


func is_step_done(id: StringName) -> bool:
	for i in _steps.size():
		if _steps[i].step_id == id:
			return _done or _skipped or i < _index
	return false


# --- Driving it ----------------------------------------------------------

## One line at the place the thing happens. Unknown names are harmless.
func report(flag: StringName) -> void:
	if not is_running():
		return
	_flags[flag] = true
	_evaluate()


func skip() -> void:
	if _done or _skipped:
		return
	_skipped = true
	skipped.emit()
	if not _quiet:
		GameManager.notify("GUIDE DISMISSED\nGoals are on the profile screen", GameManager.Tone.INFO)


## Brings the tutorial back for a player who dismissed it by accident. It
## resumes where it stopped rather than starting over.
func resume() -> void:
	if _done:
		return
	_skipped = false
	_hint_timer = 0.0
	step_changed.emit(current())


func _satisfied(step: OnboardingStep) -> bool:
	if step.trigger == OnboardingStep.Trigger.METRIC:
		return Progression.value_for(step.key) >= step.target
	return bool(_flags.get(step.key, false))


## True if this step is already true the moment it comes up — §75. A flag step
## only counts as already-done when it says it may.
func _already_done(step: OnboardingStep) -> bool:
	if not step.can_be_already_done:
		return false
	if step.trigger == OnboardingStep.Trigger.METRIC:
		return Progression.value_for(step.key) >= step.target
	return false


func _evaluate() -> void:
	# Loops because passing one step can reveal another that is also already
	# satisfied, which is what makes loading a rich save fall straight through
	# to the end instead of stopping on step two.
	var guard := 0
	while is_running() and guard < _steps.size() + 1:
		guard += 1
		var step := _steps[_index]
		if not _satisfied(step):
			return
		_advance(step)


func _advance(step: OnboardingStep) -> void:
	step_completed.emit(step)
	if not _quiet:
		GameManager.notify("DONE\n%s" % step.title.to_upper(), GameManager.Tone.GOOD)
	_index += 1
	_flags.clear()
	_hint_timer = 0.0
	if _index >= _steps.size():
		_done = true
		if not _quiet:
			GameManager.notify(
				"YOU KNOW ENOUGH\nThe city is yours", GameManager.Tone.GOOD
			)
		finished.emit()
		return
	step_changed.emit(_steps[_index])


## Passes over any leading steps the player has plainly already done, without
## announcing them. Used on load and when a new game starts from a debug state.
##
## §165 — a save written before the guide existed carries no record of it, and
## its player may have been running a company for a fortnight. Somebody who has
## already worked or founded something is not shown a tutorial at all; anybody
## else only skips the steps that are provably behind them.
func settle() -> void:
	if _done or _skipped:
		return
	if Progression.value_for(&"shifts_worked") >= 1.0 \
			or Progression.value_for(&"businesses") >= 1.0:
		_index = _steps.size()
		_done = true
		step_changed.emit(null)
		return
	_quiet = true
	while is_running() and _already_done(_steps[_index]):
		_index += 1
		_flags.clear()
	if _index >= _steps.size():
		_done = true
	_quiet = false
	_hint_timer = 0.0
	step_changed.emit(current())


# --- Save ----------------------------------------------------------------

func clear() -> void:
	_index = 0
	_done = false
	_skipped = false
	_flags.clear()
	_hint_timer = 0.0
	step_changed.emit(current())


func save_state() -> Dictionary:
	return {"index": _index, "done": _done, "skipped": _skipped}


func load_state(state: Dictionary) -> void:
	_index = clampi(int(state.get("index", 0)), 0, _steps.size())
	_done = bool(state.get("done", false))
	_skipped = bool(state.get("skipped", false))
	_flags.clear()
	_hint_timer = 0.0
	if _index >= _steps.size():
		_done = true
	# Settling happens on `game_loaded`, once every other entity is restored.
