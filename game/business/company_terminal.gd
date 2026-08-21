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
	prompt_subtitle = "%s  ·  %d locations" % [
		CompanyManager.get_company_name(), BusinessManager.owned_count()
	]
	return super.get_prompt_text()


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"company", self, interactor)
