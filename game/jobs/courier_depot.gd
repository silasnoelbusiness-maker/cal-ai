class_name CourierDepot
extends Interactable
## The counter where delivery work is handed out.
##
## The courier job is the first thing in the game that needs the city to be
## bigger than one street: a run is a real drive across two districts, guided by
## the map, paid on arrival. Everything it does is assembled from parts that
## already exist — the destination pool is the city's own venues, the guidance is
## the map's destination, and the money is the ordinary economy.

func _init() -> void:
	super()
	prompt_action = "Start deliveries"


func _ready() -> void:
	add_to_group(&"courier_depot")


func can_interact(interactor: Node3D) -> bool:
	return super.can_interact(interactor)


func get_prompt_text() -> String:
	if not available:
		return unavailable_prompt
	if CourierJob.has_active_run():
		return "%s — Delivery in progress" % key_hint
	return super.get_prompt_text()


func _perform(_interactor: Node3D) -> void:
	if CourierJob.has_active_run():
		GameManager.notify(
			"FINISH THE RUN YOU HAVE\n%s" % CourierJob.active_destination_name(),
			GameManager.Tone.BAD
		)
		return
	CourierJob.offer_run()
