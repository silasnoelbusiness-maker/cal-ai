class_name PropertySalePanel
extends Control
## The details of a property that is for sale.
##
## Two ways to buy and one screen for both. Cash is simple and rarely
## affordable; the mortgage view is where the interesting decision is, because
## it shows the deposit against the debt and the payment against the rent, and
## those three numbers are the whole of property investment.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _property_id: StringName = &""
## Set while the mortgage terms are being shown rather than the summary.
var _showing_mortgage: bool = false


func _ready() -> void:
	# Tall enough that the mortgage view fits without scrolling. The cash-flow
	# line under IF IT IS LET is the number the whole screen exists for, and a
	# number below the fold is a number nobody reads.
	_parts = ScreenKit.build_frame(self, Vector2(780, 730))
	_body = ScreenKit.scroller(_parts["body"])
	EconomyManager.cash_changed.connect(_on_cash_changed)


func is_open() -> bool:
	return visible


func open(property_id: StringName) -> void:
	if RealEstate.listing_for(property_id) == null:
		return
	_property_id = property_id
	_showing_mortgage = false
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _listing() -> PropertyListing:
	return RealEstate.listing_for(_property_id)


func _rebuild() -> void:
	_empty(_body)
	_empty(_parts["actions"])

	var offer := _listing()
	if offer == null:
		# Bought, or taken off the market while the screen was open.
		_parts["title"].text = "NO LONGER FOR SALE"
		_parts["subtitle"].text = ""
		_add_close()
		return

	_parts["title"].text = offer.address.to_upper()
	_parts["subtitle"].text = "%s  ·  Your cash: %s" % [
		offer.kind_label(), EconomyManager.get_cash_string()
	]
	_parts["status"].text = ""

	if _showing_mortgage:
		_build_mortgage(offer)
	else:
		_build_summary(offer)


func _build_summary(offer: PropertyListing) -> void:
	_body.add_child(ScreenKit.row("Asking price", ScreenKit.money(offer.asking_price), true))
	_body.add_child(ScreenKit.row("Type", offer.kind_label()))
	_body.add_child(ScreenKit.row("Size", "%s  ·  %d m²" % [offer.size_label, offer.floor_area]))
	_body.add_child(ScreenKit.row(
		"Condition", "%s  ·  %d%%" % [offer.condition_label(), roundi(offer.condition)]
	))
	_body.add_child(ScreenKit.row("Location", offer.location_label()))
	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("WHAT IT WOULD EARN"))
	_body.add_child(ScreenKit.row("Estimated rent", "%s every 7 days" % ScreenKit.money(offer.estimated_rent)))
	_body.add_child(ScreenKit.row("Upkeep", "%s every 7 days" % ScreenKit.money(offer.base_maintenance)))
	_body.add_child(ScreenKit.row("Gross yield", offer.yield_label(), true))
	if offer.kind == PropertyRecord.Kind.MULTI_UNIT:
		_body.add_child(BusinessUIKit.label(
			"Four flats under one roof. Each is let separately, so the rent above "
			+ "is what it earns full — and it will not always be full.",
			13, ScreenKit.MUTED
		))

	var actions: HBoxContainer = _parts["actions"]

	var cash := BusinessUIKit.button("BUY WITH CASH", 190.0)
	cash.disabled = not EconomyManager.can_afford(offer.asking_price)
	cash.pressed.connect(func() -> void: _confirm_cash(offer))
	actions.add_child(cash)

	var mortgage := BusinessUIKit.button("VIEW MORTGAGE", 190.0)
	mortgage.disabled = not offer.mortgage_available
	mortgage.pressed.connect(func() -> void:
		_showing_mortgage = true
		AudioManager.play_ui(&"ui_click")
		_rebuild()
	)
	actions.add_child(mortgage)

	_add_close()
	if cash.disabled:
		_note(
			"Not enough for the full price. A mortgage needs %s down."
			% ScreenKit.money(offer.required_down_payment()),
			ScreenKit.MUTED
		)


func _build_mortgage(offer: PropertyListing) -> void:
	var deposit := offer.required_down_payment()
	var financed := offer.financed_amount()
	var payment := MortgageData.level_payment(
		financed, RealEstate.MORTGAGE_RATE / 52.0, RealEstate.MORTGAGE_TERM_PAYMENTS
	)

	_body.add_child(ScreenKit.heading("MORTGAGE OFFER"))
	_body.add_child(ScreenKit.row("Property price", ScreenKit.money(offer.asking_price)))
	_body.add_child(ScreenKit.row(
		"Down payment", "%s  ·  %d%%" % [
			ScreenKit.money(deposit), roundi(offer.down_payment_fraction() * 100.0)
		], true
	))
	_body.add_child(ScreenKit.row("Loan", ScreenKit.money(financed)))
	_body.add_child(ScreenKit.row("Interest", "%d%% a year" % roundi(RealEstate.MORTGAGE_RATE * 100.0)))
	_body.add_child(ScreenKit.row(
		"Payment", "%s every %d days" % [
			ScreenKit.money(payment), RealEstate.MORTGAGE_INTERVAL_DAYS
		]
	))
	_body.add_child(ScreenKit.row("Term", "%d payments" % RealEstate.MORTGAGE_TERM_PAYMENTS))

	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("IF IT IS LET"))
	var flow := offer.estimated_rent - offer.base_maintenance - payment
	_body.add_child(ScreenKit.row("Rent", "+%s" % ScreenKit.money(offer.estimated_rent)))
	_body.add_child(ScreenKit.row("Upkeep", "-%s" % ScreenKit.money(offer.base_maintenance)))
	_body.add_child(ScreenKit.row("Mortgage", "-%s" % ScreenKit.money(payment)))
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Cash flow every 7 days", 14, ScreenKit.MUTED),
		BusinessUIKit.value_label(
			"%s%s" % ["+" if flow >= 0 else "-", ScreenKit.money(absi(flow))], 15,
			ScreenKit.GOOD if flow >= 0 else ScreenKit.BAD
		),
	]))
	_body.add_child(BusinessUIKit.label(
		"Vacant, the upkeep and the mortgage carry on without the rent.",
		13, ScreenKit.MUTED
	))

	var actions: HBoxContainer = _parts["actions"]
	var take := BusinessUIKit.button("TAKE MORTGAGE", 190.0)
	var eligible := RealEstate.is_credit_eligible()
	take.disabled = not eligible or not EconomyManager.can_afford(deposit)
	take.pressed.connect(func() -> void: _confirm_mortgage(offer, deposit, payment))
	actions.add_child(take)

	var back := BusinessUIKit.button("BACK", 130.0)
	back.pressed.connect(func() -> void:
		_showing_mortgage = false
		AudioManager.play_ui(&"ui_back")
		_rebuild()
	)
	actions.add_child(back)
	_add_close()

	if not eligible:
		_note(RealEstate.credit_refusal_reason(), ScreenKit.BAD)
	elif take.disabled:
		_note("You need %s for the deposit." % ScreenKit.money(deposit), ScreenKit.BAD)


## Takes the old contents out of the tree at once rather than waiting on
## queue_free, which is deferred: a rebuild triggered twice in one frame would
## otherwise leave two sets of buttons on screen.
func _empty(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()


func _add_close() -> void:
	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func _confirm_cash(offer: PropertyListing) -> void:
	ScreenKit.confirm(
		self,
		"BUY %s FOR %s?" % [offer.address.to_upper(), ScreenKit.money(offer.asking_price)],
		"This purchase uses your personal funds.",
		func() -> void:
			var result := RealEstate.buy_with_cash(offer.property_id)
			if result == RealEstate.BuyResult.OK:
				GameManager.close_menus()
			else:
				AudioManager.play_ui(&"ui_error")
				_note(_failure(result), ScreenKit.BAD)
	)


func _confirm_mortgage(offer: PropertyListing, deposit: int, payment: int) -> void:
	ScreenKit.confirm(
		self,
		"TAKE A MORTGAGE ON %s?" % offer.address.to_upper(),
		"%s down now, then %s every %d days for %d payments." % [
			ScreenKit.money(deposit), ScreenKit.money(payment),
			RealEstate.MORTGAGE_INTERVAL_DAYS, RealEstate.MORTGAGE_TERM_PAYMENTS
		],
		func() -> void:
			var result := RealEstate.buy_with_mortgage(offer.property_id)
			if result == RealEstate.BuyResult.OK:
				GameManager.close_menus()
			else:
				AudioManager.play_ui(&"ui_error")
				_note(_failure(result), ScreenKit.BAD)
	)


func _failure(result: int) -> String:
	match result:
		RealEstate.BuyResult.CANNOT_AFFORD:
			return "You cannot afford that."
		RealEstate.BuyResult.ALREADY_OWNED:
			return "You already own it."
		RealEstate.BuyResult.NOT_ELIGIBLE:
			return RealEstate.credit_refusal_reason()
		RealEstate.BuyResult.NO_MORTGAGE_OFFERED:
			return "No lender will finance this one."
		RealEstate.BuyResult.NOT_DISCOVERED:
			return "You have not seen this property yet."
		_:
			return "That did not go through."


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible:
		_rebuild()
