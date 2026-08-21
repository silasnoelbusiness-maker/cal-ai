class_name CompanyTerminal
extends Interactable
## The computer in the company office.
##
## Opens the same company screen the pause key does, from a desk in a room the
## player leased. That is deliberate: §93 asks for a physical place to manage
## the company from, and is equally clear that nobody should have to drive
## across the city to look at their own figures. So this is a shortcut with a
## chair, not a gate.

func _ready() -> void:
	add_to_group(&"company_terminal")
	prompt_action = "Open Company"
	focus_priority = 2


func get_prompt_text() -> String:
	# §113 — the desk says whether it is worth sitting down at. A count of
	# locations alone never changes; a count of locations in trouble is the
	# reason a player walks into their own office.
	var troubled := 0
	for business in BusinessManager.get_businesses():
		if DistressState.is_alarming(business.distress):
			troubled += 1
	prompt_subtitle = "%s  ·  %d locations%s" % [
		CompanyManager.get_company_name(), BusinessManager.owned_count(),
		"  ·  %d in trouble" % troubled if troubled > 0 else "",
	]
	return super.get_prompt_text()


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"company", self, interactor)
