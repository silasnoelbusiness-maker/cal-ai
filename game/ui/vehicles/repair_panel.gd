class_name RepairPanel
extends Control
## The mechanic's quote.
##
## Two jobs, priced separately and honestly: putting the damage right, and
## putting the years right. The first is cheap and takes the car back to full
## health; the second is dear, takes hours, and never quite gets a car back to
## new — which is what makes condition worth protecting rather than something to
## buy back whenever it dips.

signal opened()
signal closed()

## In-game hours each job takes. A morning, not a week.
const REPAIR_HOURS := 1
const RESTORE_HOURS := 3

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _shop: RepairShop = null
var _record: OwnedVehicle = null


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(720, 580))
	_body = ScreenKit.scroller(_parts["body"])


func is_open() -> bool:
	return visible


func open(shop: RepairShop) -> void:
	if shop == null:
		return
	_shop = shop
	_record = shop.vehicle_in_bay()
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_shop = null
	_record = null
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	_parts["title"].text = _shop.shop_name.to_upper()
	_parts["subtitle"].text = "Your cash: %s" % EconomyManager.get_cash_string()
	_parts["status"].text = ""

	if _record == null:
		_body.add_child(BusinessUIKit.label(
			"Nothing of yours in the bay. Drive a vehicle you own onto the marked "
			+ "area outside and try again.", 14, ScreenKit.MUTED
		))
		_add_close()
		return

	_body.add_child(ScreenKit.heading(_record.display_name().to_upper()))
	_body.add_child(ScreenKit.row("Mileage", _record.mileage_label()))
	_body.add_child(ScreenKit.stat_bar("Health", roundi(_record.health_fraction() * 100.0)))
	_body.add_child(ScreenKit.stat_bar("Condition", roundi(_record.condition), true))
	_body.add_child(ScreenKit.row("Value", ScreenKit.money(_record.market_value()), true))
	_body.add_child(ScreenKit.spacer(8))

	var repair_cost := VehicleRegistry.repair_quote(_record)
	var restore_cost := VehicleRegistry.restore_quote(_record)
	var restored := VehicleRegistry.restored_condition(_record)

	_body.add_child(ScreenKit.heading("WORK"))
	_body.add_child(ScreenKit.row(
		"Basic repair — health to 100%%, %d hour" % REPAIR_HOURS,
		ScreenKit.money(repair_cost) if repair_cost > 0 else "nothing to do"
	))
	_body.add_child(ScreenKit.row(
		"Full service — condition to %d%%, %d hours" % [roundi(restored), RESTORE_HOURS],
		ScreenKit.money(repair_cost + restore_cost) if restore_cost > 0 else "nothing to do"
	))

	var actions: HBoxContainer = _parts["actions"]

	var basic := BusinessUIKit.button("BASIC REPAIR", 170.0)
	basic.disabled = repair_cost <= 0 or not EconomyManager.can_afford(repair_cost)
	basic.pressed.connect(func() -> void: _confirm(false, repair_cost))
	actions.add_child(basic)

	var full := BusinessUIKit.button("FULL REPAIR", 170.0)
	var full_cost := repair_cost + restore_cost
	full.disabled = full_cost <= 0 or not EconomyManager.can_afford(full_cost)
	full.pressed.connect(func() -> void: _confirm(true, full_cost))
	actions.add_child(full)

	_add_close()
	if repair_cost <= 0 and restore_cost <= 0:
		_note("Nothing wrong with it.", ScreenKit.GOOD)


func _add_close() -> void:
	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func _confirm(restore: bool, cost: int) -> void:
	ScreenKit.confirm(
		self,
		"%s FOR %s?" % ["FULL REPAIR" if restore else "BASIC REPAIR", ScreenKit.money(cost)],
		"%d hour%s in the workshop." % [
			RESTORE_HOURS if restore else REPAIR_HOURS,
			"s" if (RESTORE_HOURS if restore else REPAIR_HOURS) != 1 else ""
		],
		func() -> void: _do_repair(restore)
	)


func _do_repair(restore: bool) -> void:
	var paid := VehicleRegistry.repair(_record, restore)
	if paid <= 0:
		_note("That did not go through.", ScreenKit.BAD)
		AudioManager.play_ui(&"ui_error")
		return
	# The work takes time, which is the other half of what it costs.
	TimeManager.advance_minutes((RESTORE_HOURS if restore else REPAIR_HOURS) * 60)
	AudioManager.play(&"purchase", AudioBuses.SFX, -6.0)
	GameManager.notify(
		"VEHICLE SERVICED\n%s  -%s" % [_record.display_name().to_upper(), ScreenKit.money(paid)],
		GameManager.Tone.GOOD
	)
	_rebuild()
	_note("Done. %s." % ("Serviced and repaired" if restore else "Repaired"), ScreenKit.GOOD)


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)
