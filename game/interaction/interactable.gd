class_name Interactable
extends Area3D
## A thing the player can walk up to and use.
##
## This is the ONE contract between the player and the world. Doors, shop
## counters, job markers, beds and vehicles all attach an Interactable (or a
## subclass of it) and never touch the player script. Behaviour is supplied
## either by extending this class and overriding _perform(), or by connecting
## to the `interacted` signal from a sibling node.

signal interacted(interactor: Node3D)
signal availability_changed(available: bool)

## Verb shown in the prompt, e.g. "Enter Apartment" -> "E — Enter Apartment".
@export var prompt_action: String = "Interact"
## Key hint shown before the em dash. Vehicles use "F", everything else "E".
@export var input_action: String = "interact"
@export var key_hint: String = "E"
## Optional second line, e.g. "Larkspur Apartments".
@export var prompt_subtitle: String = ""
## When several interactables overlap, the highest value wins ties. Named
## focus_priority because Area3D already has an unrelated `priority`.
@export var focus_priority: int = 0
@export var available: bool = true:
	set(value):
		if available == value:
			return
		available = value
		availability_changed.emit(available)
## Shown instead of the normal prompt while unavailable. Empty hides the prompt.
@export var unavailable_prompt: String = ""


## Defaults are applied in _init so a scene can still override them: property
## values stored in a .tscn are applied after _init and before _ready.
func _init() -> void:
	# Interactables live on the "interactable" physics layer (3) and detect
	# nothing themselves; the player's detector does the querying.
	collision_layer = 1 << 2
	collision_mask = 0
	monitoring = false
	monitorable = true


func get_prompt_text() -> String:
	if not available:
		return unavailable_prompt
	return "%s — %s" % [key_hint, prompt_action]


func can_interact(_interactor: Node3D) -> bool:
	return available


## Called by the interaction controller. Subclasses override _perform().
func interact(interactor: Node3D) -> void:
	if not can_interact(interactor):
		return
	_perform(interactor)
	interacted.emit(interactor)


## Override point for subclasses.
func _perform(_interactor: Node3D) -> void:
	pass
