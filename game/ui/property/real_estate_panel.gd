class_name RealEstatePanel
extends Control
## The landlord's screen: what is owned, what is owed, what it earns.
##
## Three tabs and one detail view. The tabs answer the three questions a
## landlord actually has — what have I got, what do I owe on it, and did any
## of this make money — and the detail view is where the decisions are: set a
## rent, take a tenant, do the place up, or sell it.
##
## Deliberately its own screen rather than a tab bolted onto the business
## dashboard. Property is a second business with a different shape, and burying
## nine buildings inside a shop's management screen would make both worse.

signal opened()
signal closed()

enum Tab { PORTFOLIO, MORTGAGES, INCOME }

const TABS: Array[String] = ["PORTFOLIO", "MORTGAGES", "INCOME"]

var _parts: Dictionary = {}
var _list: VBoxContainer = null
var _tab_bar: TabBar = null
var _tab: Tab = Tab.PORTFOLIO
## The property being looked at in detail, by id. Held as an id rather than a
## record because a sale frees the record out from under the screen.
var _focus_id: StringName = &""
## Set while the tab bar is being brought into line with `_tab` in code, so its
## tab_changed does not read as the player having pressed a tab — which would
## clear the property being looked at and send them back to the list.
var _syncing: bool = false

func _ready() -> void:
	# Tall enough for the summary and the first property card together: a
	# landlord opening this screen is looking for their buildings, and a card
	# below the fold is a building they have to go and find.
	_parts = ScreenKit.build_frame(self, Vector2(900, 770))
	_build()
	EconomyManager.cash_changed.connect(_on_cash_changed)
	RealEstate.portfolio_changed.connect(_on_portfolio_changed)


func is_open() -> bool:
	return visible


## Opens on the portfolio, or straight into a property if one is named — which
## is what the door of a building the player owns asks for.
func open(property_id: StringName = &"") -> void:
	_focus_id = property_id if RealEstate.owns(property_id) else &""
	_tab = Tab.PORTFOLIO
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_focus_id = &""
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _build() -> void:
	var body: VBoxContainer = _parts["body"]

	_tab_bar = TabBar.new()
	for tab in TABS:
		_tab_bar.add_tab(tab)
	_tab_bar.tab_changed.connect(_on_tab_changed)
	body.add_child(_tab_bar)

	_list = ScreenKit.scroller(body)


func _on_tab_changed(index: int) -> void:
	if _syncing:
		return
	_tab = index as Tab
	_focus_id = &""
	AudioManager.play_ui(&"ui_click")
	_rebuild()


func _focus() -> PropertyRecord:
	return RealEstate.record_for(_focus_id) if _focus_id != &"" else null


func _rebuild() -> void:
	if not is_instance_valid(_list):
		return
	_empty(_list)
	_empty(_parts["actions"])

	var summary := RealEstate.portfolio_summary()
	_parts["title"].text = "PROPERTY PORTFOLIO"
	_parts["subtitle"].text = "%d owned  ·  Equity %s  ·  Your cash: %s" % [
		int(summary["properties"]), ScreenKit.money(int(summary["equity"])),
		EconomyManager.get_cash_string()
	]
	_parts["status"].text = ""
	_tab_bar.visible = _focus_id == &""
	# The bar follows the tab rather than the other way round, so a tab opened
	# in code is the tab that looks selected.
	if _tab_bar.current_tab != int(_tab):
		_syncing = true
		_tab_bar.current_tab = int(_tab)
		_syncing = false

	var held := _focus()
	if held != null:
		_build_detail(held)
	else:
		match _tab:
			Tab.MORTGAGES:
				_build_mortgages()
			Tab.INCOME:
				_build_income(summary)
			_:
				_build_portfolio(summary)
		_add_close()


# --- The portfolio tab ----------------------------------------------------

func _build_portfolio(summary: Dictionary) -> void:
	# The buildings first and the totals under them. The totals are already
	# summarised in one line under the title, and what a player opens this
	# screen for is the list of what they own.
	_list.add_child(ScreenKit.heading("WHAT YOU OWN"))
	var holdings := RealEstate.portfolio()
	if holdings.is_empty():
		_list.add_child(BusinessUIKit.label(
			"Nothing yet. Boards go up outside anything on the market — stand at "
			+ "one to see the asking price.",
			14, ScreenKit.MUTED
		))
	for record in holdings:
		_list.add_child(_property_card(record))

	_list.add_child(ScreenKit.spacer(10))
	_list.add_child(ScreenKit.heading("THE BOOKS"))
	_list.add_child(ScreenKit.row("Properties owned", str(int(summary["properties"]))))
	_list.add_child(ScreenKit.row("Market value", ScreenKit.money(int(summary["market_value"]))))
	_list.add_child(ScreenKit.row("Mortgage debt", ScreenKit.money(int(summary["debt"]))))
	_list.add_child(ScreenKit.row("Equity", ScreenKit.money(int(summary["equity"])), true))

	_list.add_child(ScreenKit.spacer(8))
	_list.add_child(ScreenKit.heading("EVERY 7 DAYS"))
	_list.add_child(ScreenKit.row("Rental income", "+%s" % ScreenKit.money(int(summary["rent"]))))
	_list.add_child(ScreenKit.row("Maintenance", "-%s" % ScreenKit.money(int(summary["maintenance"]))))
	_list.add_child(ScreenKit.row(
		"Mortgage payments", "-%s" % ScreenKit.money(int(summary["mortgage_payments"]))
	))
	_list.add_child(_flow_row("Net cash flow", int(summary["cash_flow"])))
	_list.add_child(ScreenKit.row("Occupancy", _occupancy_label(summary)))


func _occupancy_label(summary: Dictionary) -> String:
	var rentable := int(summary["rentable"])
	if rentable <= 0:
		return "Nothing to let"
	return "%d%%  ·  %d of %d let" % [
		roundi(float(summary["occupancy"]) * 100.0), int(summary["occupied"]), rentable
	]


## One building, as the list shows it: what it is, what it is worth, what it is
## doing and what it earns. Everything else is behind MANAGE.
func _property_card(record: PropertyRecord) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(record.address, 16, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  %s  ·  %s" % [
			record.kind_label(), record.use_label(), record.condition_label()
		], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	var loan := RealEstate.mortgage_for(record.property_id)
	var money := VBoxContainer.new()
	money.add_child(BusinessUIKit.value_label(ScreenKit.money(record.market_value), 16, ScreenKit.TEXT))
	money.add_child(BusinessUIKit.value_label(
		"equity %s" % ScreenKit.money(RealEstate.equity_of(record)), 12,
		ScreenKit.MUTED if loan == null else ScreenKit.ACCENT
	))
	line.add_child(money)

	var rent := 0
	for tenant in RealEstate.tenants_in(record.property_id):
		rent += tenant.rent_amount
	var earning := VBoxContainer.new()
	earning.add_child(BusinessUIKit.value_label(
		"+%s" % ScreenKit.money(rent), 15, ScreenKit.GOOD if rent > 0 else ScreenKit.MUTED
	))
	earning.add_child(BusinessUIKit.value_label("per 7 days", 12, ScreenKit.MUTED))
	line.add_child(earning)

	var manage := BusinessUIKit.button("MANAGE", 130.0)
	manage.pressed.connect(func() -> void:
		_focus_id = record.property_id
		AudioManager.play_ui(&"ui_click")
		_rebuild()
	)
	line.add_child(manage)
	return frame


# --- One property ---------------------------------------------------------

func _build_detail(record: PropertyRecord) -> void:
	_parts["title"].text = record.address.to_upper()
	_parts["subtitle"].text = "%s  ·  %s  ·  Your cash: %s" % [
		record.kind_label(), record.use_label(), EconomyManager.get_cash_string()
	]

	var loan := RealEstate.mortgage_for(record.property_id)
	# What it is worth, what of it is theirs, and what state it is in. The rest
	# of the figures are worth having but they are not what the player opened
	# the building for — the letting decision is, so that comes next and the
	# arithmetic goes under it.
	_list.add_child(ScreenKit.row("Market value", ScreenKit.money(record.market_value), true))
	_list.add_child(ScreenKit.row("Equity", ScreenKit.money(RealEstate.equity_of(record))))
	_list.add_child(ScreenKit.stat_bar("Condition", roundi(record.condition)))

	_list.add_child(ScreenKit.spacer(8))
	if record.is_multi_unit():
		_list.add_child(ScreenKit.heading("THE FLATS"))
		for i in record.unit_count():
			_list.add_child(_unit_block(record, i))
	else:
		_list.add_child(ScreenKit.heading("LETTING"))
		_list.add_child(_unit_block(record, -1))

	_list.add_child(ScreenKit.spacer(10))
	_list.add_child(ScreenKit.heading("THE NUMBERS"))
	_list.add_child(ScreenKit.row("Paid", ScreenKit.money(record.purchase_price)))
	var gain := record.market_value - record.purchase_price
	_list.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Since you bought it", 14, ScreenKit.MUTED),
		BusinessUIKit.value_label(
			"%s%s" % ["+" if gain >= 0 else "-", ScreenKit.money(absi(gain))], 14,
			ScreenKit.GOOD if gain >= 0 else ScreenKit.BAD
		),
	]))
	if loan != null:
		_list.add_child(ScreenKit.row("Owed", ScreenKit.money(loan.remaining_principal)))
	_list.add_child(ScreenKit.row("Size", "%s  ·  %d m²" % [record.size_label, record.floor_area]))
	_list.add_child(ScreenKit.row("Location", record.location_label()))
	_list.add_child(ScreenKit.row(
		"Upkeep", "%s every %d days" % [
			ScreenKit.money(record.maintenance_cost()), RealEstate.RENT_INTERVAL_DAYS
		]
	))
	_list.add_child(ScreenKit.row(
		"Yield on value", "%.1f%% a year" % (RealEstate.yield_of(record) * 100.0)
	))

	_build_works(record)

	var back := BusinessUIKit.button("BACK", 130.0)
	back.pressed.connect(func() -> void:
		_focus_id = &""
		AudioManager.play_ui(&"ui_back")
		_rebuild()
	)
	_parts["actions"].add_child(back)

	var sell := BusinessUIKit.button("SELL", 130.0)
	var blocked := RealEstate.sale_blocked_reason(record)
	sell.disabled = not blocked.is_empty()
	sell.pressed.connect(func() -> void: _confirm_sale(record))
	_parts["actions"].add_child(sell)
	_add_close()
	if not blocked.is_empty():
		_note(blocked, ScreenKit.BAD)


## The letting state of one unit — or of the whole property, when the index is
## -1. The same four cases either way, which is why a block of flats needed no
## second screen.
func _unit_block(record: PropertyRecord, unit_index: int) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.add_child(column)

	var use := record.use
	if unit_index >= 0:
		use = record.unit_uses[unit_index] as PropertyRecord.Use
		column.add_child(BusinessUIKit.label("Flat %d" % (unit_index + 1), 15, ScreenKit.TEXT))

	match use:
		PropertyRecord.Use.OWNER_OCCUPIED:
			column.add_child(BusinessUIKit.label(
				"You live here. Move out before letting it.", 14, ScreenKit.MUTED
			))
		PropertyRecord.Use.BUSINESS_OCCUPIED:
			column.add_child(BusinessUIKit.label(
				"Your own business trades from here, so there is no rent to collect "
				+ "and none to pay.", 14, ScreenKit.MUTED
			))
		PropertyRecord.Use.TENANTED:
			_build_tenancy(column, record, unit_index)
		PropertyRecord.Use.LISTED_FOR_RENT:
			_build_listing(column, record, unit_index)
		_:
			_build_vacant(column, record, unit_index)
	return frame


func _build_tenancy(column: VBoxContainer, record: PropertyRecord, unit_index: int) -> void:
	var tenant := RealEstate.tenant_for(record.property_id, unit_index)
	if tenant == null:
		column.add_child(BusinessUIKit.label("Let.", 14, ScreenKit.MUTED))
		return
	column.add_child(ScreenKit.row("Tenant", tenant.tenant_name, true))
	column.add_child(ScreenKit.row(
		"Rent", "%s every %d days" % [
			ScreenKit.money(tenant.rent_amount), RealEstate.RENT_INTERVAL_DAYS
		]
	))
	column.add_child(ScreenKit.row("Reliability", tenant.reliability_label()))
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Payments", 14, ScreenKit.MUTED),
		BusinessUIKit.value_label(
			tenant.payment_label(), 14,
			ScreenKit.BAD if tenant.payment_state != TenantData.PaymentState.CURRENT
			else ScreenKit.GOOD
		),
	]))
	column.add_child(ScreenKit.row(
		"Lease", "%d days left" % tenant.lease_days_left(TimeManager.day_index)
	))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	var evict := BusinessUIKit.button("END TENANCY", 160.0)
	evict.pressed.connect(func() -> void:
		ScreenKit.confirm(
			self, "END %s'S TENANCY?" % tenant.tenant_name.to_upper(),
			"The unit goes empty and earns nothing until it is let again.",
			func() -> void:
				RealEstate.end_tenancy(tenant)
				_rebuild()
		)
	)
	buttons.add_child(evict)
	column.add_child(buttons)


func _build_listing(column: VBoxContainer, record: PropertyRecord, unit_index: int) -> void:
	var asking := record.asking_rent if unit_index < 0 else record.unit_rents[unit_index]
	column.add_child(ScreenKit.row("Listed at", ScreenKit.money(asking), true))
	column.add_child(ScreenKit.row("Going rate", ScreenKit.money(RealEstate.unit_market_rent(record))))
	column.add_child(ScreenKit.row("Empty for", "%d days" % record.days_vacant))
	column.add_child(ScreenKit.row(
		"Interest", "%d%% chance of an enquiry a day"
		% roundi(RealEstate.demand_chance(record, asking) * 100.0)
	))

	var waiting := RealEstate.candidates_for(record, unit_index)
	if waiting.is_empty():
		column.add_child(BusinessUIKit.label("Nobody has applied yet.", 13, ScreenKit.MUTED))
	else:
		column.add_child(ScreenKit.heading("APPLICANTS"))
		for entry in waiting:
			column.add_child(_applicant_row(record, entry as TenantData, unit_index))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	var stop := BusinessUIKit.button("STOP LISTING", 160.0)
	stop.pressed.connect(func() -> void:
		RealEstate.stop_listing(record, unit_index)
		AudioManager.play_ui(&"ui_back")
		_rebuild()
	)
	buttons.add_child(stop)
	column.add_child(buttons)


func _applicant_row(record: PropertyRecord, tenant: TenantData, unit_index: int) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(tenant.tenant_name, 15, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  reliability %s  ·  can pay up to %s" % [
			"Business" if tenant.is_commercial() else "Private",
			tenant.reliability_label(), ScreenKit.money(tenant.rent_budget)
		], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	var accept := BusinessUIKit.button("ACCEPT", 120.0)
	accept.pressed.connect(func() -> void:
		if RealEstate.accept_tenant(record, tenant, unit_index):
			_rebuild()
		else:
			_note("That tenancy could not be signed.", ScreenKit.BAD)
	)
	line.add_child(accept)

	var decline := BusinessUIKit.button("DECLINE", 120.0)
	decline.pressed.connect(func() -> void:
		var waiting: Array = RealEstate.candidates_for(record, unit_index)
		waiting.erase(tenant)
		AudioManager.play_ui(&"ui_back")
		_rebuild()
	)
	line.add_child(decline)
	return frame


func _build_vacant(column: VBoxContainer, record: PropertyRecord, unit_index: int) -> void:
	var going := RealEstate.unit_market_rent(record)
	column.add_child(ScreenKit.row("Empty", "earning nothing"))
	column.add_child(ScreenKit.row("Going rate", ScreenKit.money(going), true))

	var box := BusinessUIKit.spin(1.0, float(maxi(going * 4, 100)), float(going), 5.0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.add_child(BusinessUIKit.stretch_label("Ask for", 14, ScreenKit.MUTED))
	line.add_child(box)

	var let_it := BusinessUIKit.button("LIST TO LET", 160.0)
	let_it.pressed.connect(func() -> void:
		var asking := roundi(box.value)
		if RealEstate.list_for_rent(record, asking, unit_index):
			AudioManager.play_ui(&"ui_confirm")
			_rebuild()
		else:
			_note("That could not be listed.", ScreenKit.BAD)
	)
	line.add_child(let_it)
	column.add_child(line)
	column.add_child(BusinessUIKit.label(
		"Ask above the going rate and it sits empty longer. Ask below and it lets "
		+ "quickly for less.", 13, ScreenKit.MUTED
	))


func _build_works(record: PropertyRecord) -> void:
	_list.add_child(ScreenKit.spacer(10))
	_list.add_child(ScreenKit.heading("REPAIRS AND RENOVATION"))
	var blocked := RealEstate.renovation_blocked_reason(record)
	if not blocked.is_empty():
		_list.add_child(BusinessUIKit.label(blocked, 13, ScreenKit.MUTED))

	for tier: StringName in RealEstate.RENOVATIONS:
		var spec: Array = RealEstate.RENOVATIONS[tier]
		var cost := RealEstate.renovation_quote(record, tier)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		frame.add_child(line)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(BusinessUIKit.label(String(spec[0]), 15, ScreenKit.TEXT))
		text.add_child(BusinessUIKit.label(
			"up to %d%% condition  ·  %d day%s of work" % [
				roundi(float(spec[1])), int(spec[3]), "" if int(spec[3]) == 1 else "s"
			], 12, ScreenKit.MUTED
		))
		line.add_child(text)
		line.add_child(BusinessUIKit.value_label(
			ScreenKit.money(cost) if cost > 0 else "Not needed", 15,
			ScreenKit.TEXT if cost > 0 else ScreenKit.MUTED
		))

		var button := BusinessUIKit.button("START WORK", 150.0)
		button.disabled = (
			cost <= 0 or not blocked.is_empty() or not EconomyManager.can_afford(cost)
		)
		button.pressed.connect(func() -> void: _confirm_works(record, tier, String(spec[0]), cost))
		line.add_child(button)
		_list.add_child(frame)


func _confirm_works(record: PropertyRecord, tier: StringName, title: String, cost: int) -> void:
	ScreenKit.confirm(
		self, "%s FOR %s?" % [title.to_upper(), ScreenKit.money(cost)],
		"The work takes %d day%s, and the days pass while it is done." % [
			RealEstate.renovation_days(tier),
			"" if RealEstate.renovation_days(tier) == 1 else "s"
		],
		func() -> void:
			if RealEstate.renovate(record, tier):
				_rebuild()
			else:
				_note("The work could not be started.", ScreenKit.BAD)
	)


func _confirm_sale(record: PropertyRecord) -> void:
	var price := RealEstate.sale_price(record)
	var fees := RealEstate.selling_cost(record)
	var loan := RealEstate.mortgage_for(record.property_id)
	var owed := loan.remaining_principal if loan != null else 0
	var proceeds := RealEstate.net_proceeds(record)

	var detail := "%s less %s in fees" % [ScreenKit.money(price), ScreenKit.money(fees)]
	if owed > 0:
		detail += ", less %s still owed" % ScreenKit.money(owed)
	detail += ". Any tenancy ends with the sale."
	if proceeds < 0:
		detail += "\nYou would have to find %s to clear the debt." % ScreenKit.money(-proceeds)

	ScreenKit.confirm(
		self,
		"SELL %s FOR %s?" % [
			record.address.to_upper(),
			"%s%s" % ["-" if proceeds < 0 else "", ScreenKit.money(absi(proceeds))]
		],
		detail,
		func() -> void:
			var result := RealEstate.sell(record)
			if result == RealEstate.SellResult.OK:
				_focus_id = &""
				_rebuild()
			else:
				AudioManager.play_ui(&"ui_error")
				_note("That sale did not go through.", ScreenKit.BAD)
	)


# --- The mortgage tab -----------------------------------------------------

func _build_mortgages() -> void:
	var loans := RealEstate.mortgages()
	_list.add_child(ScreenKit.row("Total owed", ScreenKit.money(RealEstate.total_mortgage_debt()), true))
	_list.add_child(ScreenKit.spacer(6))
	if loans.is_empty():
		_list.add_child(BusinessUIKit.label(
			"No mortgages. Everything you own, you own outright.", 14, ScreenKit.MUTED
		))
		return
	for loan in loans:
		_list.add_child(_mortgage_card(loan))
	_list.add_child(BusinessUIKit.label(
		"Every payment is interest first and principal second, so paying extra "
		+ "early takes the most off the total.", 13, ScreenKit.MUTED
	))


func _mortgage_card(loan: MortgageData) -> PanelContainer:
	var record := RealEstate.record_for(loan.property_id)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	frame.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(BusinessUIKit.stretch_label(
		record.address if record != null else String(loan.property_id), 16, ScreenKit.TEXT
	))
	header.add_child(BusinessUIKit.status_chip(
		loan.status_label(),
		ScreenKit.GOOD if loan.status == MortgageData.Status.ACTIVE else ScreenKit.BAD
	))
	column.add_child(header)

	column.add_child(ScreenKit.row("Balance", ScreenKit.money(loan.remaining_principal), true))
	column.add_child(ScreenKit.row("Borrowed", ScreenKit.money(loan.original_principal)))
	column.add_child(ScreenKit.row("Interest", "%.0f%% a year" % (loan.interest_rate * 100.0)))
	column.add_child(ScreenKit.row(
		"Payment", "%s every %d days" % [
			ScreenKit.money(loan.payment_amount), loan.payment_interval_days
		]
	))
	column.add_child(ScreenKit.row(
		"Next due", "day %d  ·  in %d days" % [
			loan.next_payment_day, maxi(loan.next_payment_day - TimeManager.day_index, 0)
		]
	))
	column.add_child(ScreenKit.row(
		"Progress", "%d of %d payments" % [loan.payments_made, loan.term_payments]
	))
	column.add_child(ScreenKit.row("Interest paid", ScreenKit.money(loan.interest_paid)))
	column.add_child(ScreenKit.row("Principal paid", ScreenKit.money(loan.principal_paid)))
	if loan.missed_payments > 0:
		column.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("Missed", 14, ScreenKit.MUTED),
			BusinessUIKit.value_label(str(loan.missed_payments), 14, ScreenKit.BAD),
		]))

	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_END
	line.add_theme_constant_override("separation", 8)
	var box := BusinessUIKit.spin(
		1.0, float(maxi(loan.remaining_principal, 1)),
		float(mini(loan.payment_amount, maxi(loan.remaining_principal, 1))), 25.0
	)
	line.add_child(box)

	var extra := BusinessUIKit.button("PAY EXTRA", 150.0)
	extra.disabled = loan.is_settled()
	extra.pressed.connect(func() -> void: _confirm_extra(loan, roundi(box.value)))
	line.add_child(extra)

	var off := BusinessUIKit.button("PAY OFF", 130.0)
	off.disabled = loan.is_settled() or not EconomyManager.can_afford(loan.payoff_amount())
	off.pressed.connect(func() -> void: _confirm_payoff(loan))
	line.add_child(off)
	column.add_child(line)
	return frame


func _confirm_extra(loan: MortgageData, amount: int) -> void:
	if not EconomyManager.can_afford(amount):
		_note("You do not have %s spare." % ScreenKit.money(amount), ScreenKit.BAD)
		return
	ScreenKit.confirm(
		self, "PAY %s OFF THE BALANCE?" % ScreenKit.money(amount),
		"It comes straight off the principal, so every payment after it is more "
		+ "principal and less interest.",
		func() -> void:
			if RealEstate.pay_extra(loan, amount) > 0:
				AudioManager.play_ui(&"money")
				_rebuild()
			else:
				_note("That payment did not go through.", ScreenKit.BAD)
	)


func _confirm_payoff(loan: MortgageData) -> void:
	var owed := loan.payoff_amount()
	var record := RealEstate.record_for(loan.property_id)
	ScreenKit.confirm(
		self, "CLEAR THE MORTGAGE FOR %s?" % ScreenKit.money(owed),
		"%s would be yours outright." % (record.address if record != null else "The property"),
		func() -> void:
			if RealEstate.pay_off(loan) > 0:
				AudioManager.play_ui(&"money")
				_rebuild()
			else:
				_note("That payment did not go through.", ScreenKit.BAD)
	)


# --- The income tab -------------------------------------------------------

func _build_income(summary: Dictionary) -> void:
	var report := RealEstate.income_report()
	_list.add_child(ScreenKit.heading("SINCE YOU STARTED"))
	_list.add_child(ScreenKit.row(
		"Gross rent", "+%s" % ScreenKit.money(int(report["rent_collected"]))
	))
	_list.add_child(ScreenKit.row(
		"Vacancy loss", "-%s" % ScreenKit.money(int(report["vacancy_lost"]))
	))
	_list.add_child(ScreenKit.row(
		"Maintenance", "-%s" % ScreenKit.money(int(report["maintenance_paid"]))
	))
	_list.add_child(ScreenKit.row(
		"Mortgage interest", "-%s" % ScreenKit.money(int(report["interest_paid"]))
	))
	_list.add_child(ScreenKit.row(
		"Mortgage principal", "-%s" % ScreenKit.money(int(report["principal_paid"]))
	))
	_list.add_child(_flow_row("Net cash flow", int(report["net_cash"])))
	_list.add_child(BusinessUIKit.label(
		"Principal is not a loss — it buys equity, and equity is in the portfolio "
		+ "figure rather than this one.", 13, ScreenKit.MUTED
	))

	_list.add_child(ScreenKit.spacer(10))
	_list.add_child(ScreenKit.heading("AS THINGS STAND"))
	_list.add_child(ScreenKit.row("Rent booked", "+%s" % ScreenKit.money(int(summary["rent"]))))
	_list.add_child(ScreenKit.row("Upkeep", "-%s" % ScreenKit.money(int(summary["maintenance"]))))
	_list.add_child(ScreenKit.row(
		"Mortgages", "-%s" % ScreenKit.money(int(summary["mortgage_payments"]))
	))
	_list.add_child(_flow_row("Every 7 days", int(summary["cash_flow"])))
	_list.add_child(ScreenKit.row("Occupancy", _occupancy_label(summary)))


# --- Shared ---------------------------------------------------------------

## Takes the old contents out of the tree at once rather than waiting on
## queue_free, which is deferred — two rebuilds in one frame would otherwise
## show both sets of buttons.
func _empty(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()


func _flow_row(name: String, amount: int) -> PanelContainer:
	return BusinessUIKit.row([
		BusinessUIKit.stretch_label(name, 14, ScreenKit.MUTED),
		BusinessUIKit.value_label(
			"%s%s" % ["+" if amount >= 0 else "-", ScreenKit.money(absi(amount))], 15,
			ScreenKit.GOOD if amount >= 0 else ScreenKit.BAD
		),
	])


func _add_close() -> void:
	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible:
		_rebuild()


func _on_portfolio_changed() -> void:
	if visible:
		_rebuild()
