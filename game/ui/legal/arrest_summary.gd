class_name ArrestSummary
extends Control
## What the arrest came to, shown once, immediately after it.
##
## §14 and §15. Phase Q ended an arrest with a fine and a fade; this is the
## beat in between that tells the player what just happened to them and what it
## is going to keep costing. It is a statement rather than a decision — the
## release has already been taken by the time this appears, because §16's
## release is a cost and not a menu, and §17 means it can never be refused for
## want of money.
##
## §100 asks that a large time skip be announced. The hours are on the card.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _body: VBoxContainer = null


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(780, 780))
	_body = ScreenKit.scroller(_parts["body"])
	visible = false


func is_open() -> bool:
	return visible


## Called by the HUD when WantedManager finishes an arrest.
func show_arrest(arrest: ArrestRecord, hours_lost: int) -> void:
	if arrest == null:
		return
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	_parts["title"].text = "ARRESTED"
	_parts["subtitle"].text = "Day %d  ·  %s" % [arrest.day, arrest.stars()]
	_parts["status"].text = ""

	_body.add_child(ScreenKit.heading("WHAT THEY TOOK YOU IN FOR"))
	for offence in arrest.offences:
		_body.add_child(BusinessUIKit.label(offence, 16, ScreenKit.TEXT))
	_body.add_child(ScreenKit.row("Seriousness", arrest.severity_name().capitalize()))
	_body.add_child(ScreenKit.row("Wanted level", arrest.stars()))

	_body.add_child(ScreenKit.heading("WHAT IT COST"))
	_body.add_child(ScreenKit.row("Fine", ScreenKit.money(arrest.fine_paid)))
	if arrest.fine_charged > arrest.fine_paid:
		_body.add_child(ScreenKit.row(
			"Left owing", ScreenKit.money(arrest.fine_charged - arrest.fine_paid)
		))
	if arrest.release_cost > 0:
		_body.add_child(ScreenKit.row("Release", ScreenKit.money(arrest.release_cost)))
	if arrest.goods_confiscated > 0:
		_body.add_child(ScreenKit.row("Seized", "%d item%s" % [
			arrest.goods_confiscated, "" if arrest.goods_confiscated == 1 else "s"
		]))
	if arrest.stolen_vehicle_recovered:
		_body.add_child(ScreenKit.row("Vehicle", "Recovered — it was not yours"))
	_body.add_child(ScreenKit.row("Time lost", "%d hour%s" % [
		hours_lost, "" if hours_lost == 1 else "s"
	]))
	if LegalManager.legal_debt > 0:
		_body.add_child(BusinessUIKit.label(
			"You owe %s. It does not grow, and nobody is coming for your things."
			% ScreenKit.money(LegalManager.legal_debt), 12, ScreenKit.MUTED
		))

	_body.add_child(ScreenKit.heading("COURT"))
	var case := LegalManager.case_by_id(arrest.case_id) if arrest.has_case() else null
	if case == null:
		_body.add_child(BusinessUIKit.label(
			"Not required. Dealt with on the spot.", 14, ScreenKit.MUTED
		))
	else:
		_body.add_child(ScreenKit.row("Case", case.title))
		_body.add_child(ScreenKit.row("Listed", "Day %d at %s" % [
			case.court_day, case.court_time_label()
		]))
		_body.add_child(ScreenKit.row(
			"Counsel", LegalService.by_id(case.counsel_id).display_name
		))
		_body.add_child(BusinessUIKit.label(
			"The Civic Court is by the Civic Hall. Turning up counts for more "
			+ "than anything else you can do about this.", 12, ScreenKit.MUTED
		))

	_body.add_child(ScreenKit.heading("RECORD"))
	_body.add_child(ScreenKit.row("Where you stand", LegalManager.tier_name()))
	_body.add_child(BusinessUIKit.label(
		"Your businesses, your properties and your vehicles are untouched.",
		12, ScreenKit.MUTED
	))

	var done := BusinessUIKit.button("CARRY ON", 180.0)
	done.pressed.connect(func() -> void: close())
	_parts["actions"].add_child(done)

	visible = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	AudioManager.play_ui(&"ui_back")
	closed.emit()
