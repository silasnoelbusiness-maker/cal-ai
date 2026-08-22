class_name CourtDoor
extends Interactable

## The door of the Civic Court.
##
## §21 and §22 prefer the player to attend physically rather than settle a case
## from a menu, and that is what this is: a building on a street they have to
## drive to, at an hour that is listed, while everything else in their life
## carries on. §126 — it is built from the modular city kit, not a new art pass.
##
## Attending is not a formality. §24 makes turning up one of the things that
## decides how a hearing goes, and it is the largest single term in it, so this
## door is worth the journey.

func _ready() -> void:
	add_to_group(&"civic_court")
	focus_priority = 3
	_refresh()


func get_prompt_text() -> String:
	_refresh()
	return super.get_prompt_text()


func _refresh() -> void:
	prompt_action = "Civic Court"
	var due := LegalManager.case_ready_now()
	if due != null:
		prompt_action = "Attend the hearing"
		prompt_subtitle = due.title
		return
	var next_case := LegalManager.next_case()
	if next_case == null:
		prompt_subtitle = "Nothing listed for you"
		return
	var days := next_case.days_until(TimeManager.day_index)
	if days <= 0:
		prompt_subtitle = "Listed today at %s" % next_case.court_time_label()
	else:
		prompt_subtitle = "Listed in %d day%s" % [days, "" if days == 1 else "s"]


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"court", self, interactor)
