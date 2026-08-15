class_name MessagePoint
extends Interactable
## Shows a HUD message when used.
##
## Used for the notice board, and to mark the doors of venues whose interiors
## and systems arrive in later phases (apartment, store, restaurant, job,
## police station). The location, prompt and detection volume are all real —
## only what is behind the door is still to come, so swapping this script for
## the real one later is a one-line change per door.

@export_multiline var message: String = ""
## Matches GameManager.Tone. Kept as an int so the export does not depend on an
## autoload's type being resolvable at parse time.
@export_enum("Info", "Good", "Bad") var tone: int = 0


func _perform(_interactor: Node3D) -> void:
	if message.is_empty():
		return
	GameManager.notify(message, tone)
