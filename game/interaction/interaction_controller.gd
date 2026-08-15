class_name InteractionController
extends Area3D
## Finds the best nearby Interactable and routes the interact input to it.
##
## Lives as a child of the player so the player script never needs to know what
## it is standing next to. Anything that can interact (an NPC later, or the
## player inside a vehicle) can reuse this node as-is.

signal focus_changed(interactable: Interactable)

## Node passed to Interactable.interact(). Defaults to the parent node.
@export var interactor_path: NodePath
## How often the best candidate is re-evaluated, in seconds. Overlap counts are
## tiny, but this keeps the work off the per-frame path as the city grows.
@export var refresh_interval: float = 0.1

var _candidates: Array[Interactable] = []
var _current: Interactable = null
var _interactor: Node3D = null
var _refresh_accumulator: float = 0.0


func _init() -> void:
	# Detect the "interactable" layer (3); occupy no layer of our own.
	collision_layer = 0
	collision_mask = 1 << 2
	monitoring = true
	monitorable = false


func _ready() -> void:
	_interactor = get_node_or_null(interactor_path) as Node3D
	if _interactor == null:
		_interactor = get_parent() as Node3D
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _process(delta: float) -> void:
	_refresh_accumulator += delta
	if _refresh_accumulator < refresh_interval:
		return
	_refresh_accumulator = 0.0
	_update_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _current == null or _interactor == null:
		return
	if not event.is_action_pressed(_current.input_action):
		return
	if not _current.can_interact(_interactor):
		return
	_current.interact(_interactor)
	get_viewport().set_input_as_handled()


func get_focused() -> Interactable:
	return _current


func _on_area_entered(area: Area3D) -> void:
	var target := area as Interactable
	if target == null or _candidates.has(target):
		return
	_candidates.append(target)
	_update_focus()


func _on_area_exited(area: Area3D) -> void:
	var target := area as Interactable
	if target == null:
		return
	_candidates.erase(target)
	_update_focus()


## Picks the closest available candidate, breaking ties by priority.
func _update_focus() -> void:
	var best: Interactable = null
	var best_score := INF
	var origin := global_position if _interactor == null else _interactor.global_position

	for candidate in _candidates:
		if not is_instance_valid(candidate):
			continue
		if not candidate.can_interact(_interactor) and candidate.unavailable_prompt.is_empty():
			continue
		# Distance minus a priority bonus, so a high-priority target a little
		# further away still wins.
		var score := origin.distance_to(candidate.global_position) - float(candidate.focus_priority)
		if score < best_score:
			best_score = score
			best = candidate

	_candidates = _candidates.filter(func(c: Interactable) -> bool: return is_instance_valid(c))

	if best == _current:
		return
	_current = best
	focus_changed.emit(_current)
