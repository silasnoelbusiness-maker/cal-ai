class_name BranchFinancePanel
extends Control
## One branch's money, and what to do when there is not enough of it.
##
## Everything §96 lists as a way out, in one place and in the order a player in
## trouble would try them: put money in, stop the bleeding, or wind it up. The
## screen deliberately shows what each choice costs before it is made —
## liquidation in particular is irreversible, and a player should see the
## recovery rates before they agree to them rather than afterwards.

signal opened()
signal closed()

enum Page { MONEY, CLOSE, LIQUIDATE }

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _business: BusinessInstance = null
var _page: Page = Page.MONEY
var _amount: int = 500


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(820, 640))
	_body = ScreenKit.scroller(_parts["body"])
	EconomyManager.cash_changed.connect(_on_cash_changed)


func is_open() -> bool:
	return visible


func open(business: BusinessInstance) -> void:
	if business == null:
		return
	_business = business
	_page = Page.MONEY
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_business = null
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()
	if _business == null:
		return

	_parts["title"].text = _business.business_name.to_upper()
	_parts["subtitle"].text = "%s  ·  %s in the till  ·  your cash %s" % [
		_business.distress_label(), ScreenKit.money(_business.cash_balance),
		EconomyManager.get_cash_string(),
	]
	_parts["status"].text = ""

	match _page:
		Page.CLOSE:
			_build_close()
		Page.LIQUIDATE:
			_build_liquidate()
		_:
			_build_money()

	var close_button := BusinessUIKit.button("CLOSE", 120.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


# --- Money ---------------------------------------------------------------

func _build_money() -> void:
	var arrears := _business.total_arrears()
	if arrears > 0:
		_body.add_child(ScreenKit.heading("WHAT IT OWES"))
		for worker in _business.employees:
			if worker.wage_arrears > 0:
				_body.add_child(BusinessUIKit.row([
					BusinessUIKit.stretch_label(worker.employee_name, 14, ScreenKit.TEXT),
					BusinessUIKit.value_label(
						ScreenKit.money(worker.wage_arrears), 14, ScreenKit.BAD
					),
					BusinessUIKit.value_label(
						"not turning up" if not worker.will_work() else "", 12, ScreenKit.BAD
					),
				]))
		var unit := _business.property()
		if unit != null and unit.has_landlord() and unit.arrears > 0:
			_body.add_child(ScreenKit.row(
				"Rent overdue", ScreenKit.money(unit.arrears)
			))
		_body.add_child(ScreenKit.row("Total overdue", ScreenKit.money(arrears), true))

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("WHAT IS COMING"))
	for entry in FinanceManager.obligations_for(_business):
		_body.add_child(ScreenKit.row(
			"%s  ·  %s" % [entry.kind_name(), entry.label],
			"%s%s" % [
				ScreenKit.money(entry.amount),
				"  ·  %s late" % ScreenKit.money(entry.overdue) if entry.is_overdue() else "",
			]
		))

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("PUT MONEY IN"))
	var spin := BusinessUIKit.spin(50, 100000, float(_amount), 50)
	spin.value_changed.connect(func(value: float) -> void: _amount = int(value))
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Amount", 14, ScreenKit.MUTED), spin,
	]))
	_body.add_child(BusinessUIKit.label(
		"Your own money into the business. It is recorded on both ledgers, so "
		+ "your net worth does not change — the money simply moves.",
		12, ScreenKit.MUTED
	))

	var inject := BusinessUIKit.button("INJECT CAPITAL", 170.0)
	inject.pressed.connect(func() -> void:
		if FinanceManager.inject_capital(_business, _amount):
			_rebuild()
		else:
			AudioManager.play_ui(&"ui_error")
	)
	_parts["actions"].add_child(inject)

	if arrears > 0:
		var settle := BusinessUIKit.button("PAY ARREARS", 150.0)
		settle.disabled = _business.cash_balance <= 0
		settle.pressed.connect(func() -> void:
			FinanceManager.pay_arrears(_business)
			_rebuild()
		)
		_parts["actions"].add_child(settle)

	if _business.is_closed():
		var reopen := BusinessUIKit.button("REOPEN", 130.0)
		reopen.pressed.connect(func() -> void:
			BusinessManager.reopen_business(_business)
			_rebuild()
		)
		_parts["actions"].add_child(reopen)
	else:
		var shut := BusinessUIKit.button("CLOSE BRANCH", 150.0)
		shut.pressed.connect(func() -> void:
			_page = Page.CLOSE
			_rebuild()
		)
		_parts["actions"].add_child(shut)

	var wind_up := BusinessUIKit.button("LIQUIDATE", 130.0)
	wind_up.pressed.connect(func() -> void:
		_page = Page.LIQUIDATE
		_rebuild()
	)
	_parts["actions"].add_child(wind_up)


# --- Closing -------------------------------------------------------------

func _build_close() -> void:
	_body.add_child(ScreenKit.heading("CLOSE THE DOORS?"))
	_body.add_child(BusinessUIKit.label(
		"Trading stops. Nobody is served, no wages accrue and the utilities go "
		+ "quiet.\n\nYou keep the stock, the fittings and the lease — and you "
		+ "keep paying the rent, the mortgage and anything you already owe. "
		+ "This is a way to stop the bleeding while you sort something out, "
		+ "not a way to walk away.",
		14, ScreenKit.MUTED
	))
	_body.add_child(ScreenKit.spacer(6))
	_body.add_child(ScreenKit.row("Stock held", "%d units" % _business.storage_used()))
	_body.add_child(ScreenKit.row("Fittings", "%d" % _business.equipment.size()))
	_body.add_child(ScreenKit.row("Staff", "%d" % _business.employees.size()))

	var confirm := BusinessUIKit.button("CLOSE IT", 150.0)
	confirm.pressed.connect(func() -> void:
		ScreenKit.confirm(
			self, "CLOSE %s?" % _business.business_name.to_upper(),
			"You can reopen it whenever you like.",
			func() -> void:
				BusinessManager.close_business(_business, "closed by you")
				_page = Page.MONEY
				_rebuild()
		)
	)
	_parts["actions"].add_child(confirm)
	_add_back()


# --- Liquidation ---------------------------------------------------------

func _build_liquidate() -> void:
	var quote := Liquidation.quote(_business)
	_body.add_child(ScreenKit.heading("WIND IT UP?"))
	_body.add_child(BusinessUIKit.label(
		"Everything is sold, what is owed is paid out of the proceeds, the "
		+ "lease ends and the branch comes off the books. This cannot be "
		+ "undone.",
		14, ScreenKit.MUTED
	))
	_body.add_child(ScreenKit.spacer(6))
	_body.add_child(ScreenKit.row(
		"Stock", "%s → %s" % [
			ScreenKit.money(int(quote["stock_value"])),
			ScreenKit.money(int(quote["stock_recovered"])),
		]
	))
	_body.add_child(ScreenKit.row(
		"Fittings", "%s → %s" % [
			ScreenKit.money(int(quote["equipment_value"])),
			ScreenKit.money(int(quote["equipment_recovered"])),
		]
	))
	_body.add_child(ScreenKit.row("In the till", ScreenKit.money(int(quote["cash"]))))
	_body.add_child(ScreenKit.row("Raised", ScreenKit.money(int(quote["raised"])), true))
	_body.add_child(ScreenKit.row("Owed", ScreenKit.money(int(quote["owed"]))))
	var left := int(quote["left_over"])
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("You would keep", 14, ScreenKit.MUTED),
		BusinessUIKit.value_label(
			ScreenKit.money(maxi(left, 0)), 15,
			ScreenKit.GOOD if left >= 0 else ScreenKit.BAD
		),
	]))
	if left < 0:
		_body.add_child(BusinessUIKit.label(
			"It owes more than it is worth. Winding it up clears what it can "
			+ "and the rest simply goes unpaid.", 12, ScreenKit.BAD
		))
	_body.add_child(BusinessUIKit.label(
		"%d people would be released to the company pool rather than dismissed."
			% int(quote["employees"]),
		12, ScreenKit.MUTED
	))

	# The better option, offered beside the worse one.
	var warehouse := LogisticsManager.primary_warehouse()
	if warehouse != null and _business.storage_used() > 0:
		var move := BusinessUIKit.button("STOCK TO DEPOT", 170.0)
		move.pressed.connect(func() -> void:
			var moved := Liquidation.move_stock_to_warehouse(_business, warehouse)
			_note(
				"Moved %d units to %s." % [moved, warehouse.display_name], ScreenKit.GOOD
			)
			_rebuild()
		)
		_parts["actions"].add_child(move)

	var confirm := BusinessUIKit.button("LIQUIDATE", 150.0)
	confirm.pressed.connect(func() -> void:
		ScreenKit.confirm(
			self, "WIND UP %s?" % _business.business_name.to_upper(),
			"This cannot be undone.",
			func() -> void:
				BusinessManager.liquidate_business(_business)
				GameManager.close_menus()
		)
	)
	_parts["actions"].add_child(confirm)
	_add_back()


func _add_back() -> void:
	var back := BusinessUIKit.button("BACK", 110.0)
	back.pressed.connect(func() -> void:
		_page = Page.MONEY
		AudioManager.play_ui(&"ui_back")
		_rebuild()
	)
	_parts["actions"].add_child(back)


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible:
		_rebuild()
