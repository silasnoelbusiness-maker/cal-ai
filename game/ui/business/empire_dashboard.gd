extends Control
## Everything the player owns, in one place.
##
## The per-business dashboard answers "how is this shop doing"; this answers "how
## am I doing". They are deliberately separate screens: once there is more than
## one business, the questions stop having the same answer, and a portfolio view
## that is really just the first shop's numbers is worse than useless.

signal opened()
signal closed()
signal business_selected(business: BusinessInstance)

enum Page { EMPIRE, BUSINESSES, EMPLOYEES, FINANCE, LOANS }

const PAGE_NAMES := {
	Page.EMPIRE: "EMPIRE",
	Page.BUSINESSES: "BUSINESSES",
	Page.EMPLOYEES: "EMPLOYEES",
	Page.FINANCE: "FINANCE",
	Page.LOANS: "LOANS",
}

@onready var _title: Label = %EmpireTitle
@onready var _subtitle: Label = %EmpireSubtitle
@onready var _tabs: HBoxContainer = %EmpireTabs
@onready var _rows: VBoxContainer = %EmpireRows
@onready var _status: Label = %EmpireStatus

var _page: Page = Page.EMPIRE
## Which business the loan tab is acting on.
var _selected: BusinessInstance = null


func _ready() -> void:
	visible = false
	BusinessManager.business_changed.connect(_on_changed)
	BusinessManager.business_sold.connect(_on_sold)
	EconomyManager.cash_changed.connect(_on_cash_changed)


func is_open() -> bool:
	return visible


func open() -> void:
	_selected = _selected if _selected != null else BusinessManager.primary_business()
	_status.text = ""
	_build_tabs()
	_rebuild()
	visible = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# --- Chrome --------------------------------------------------------------

func _build_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for page in PAGE_NAMES:
		var button := BusinessUIKit.button(PAGE_NAMES[page], 118.0)
		button.toggle_mode = true
		button.button_pressed = _page == page
		button.pressed.connect(_show_page.bind(page))
		_tabs.add_child(button)


## Switches tab from outside — used by the screenshot tool.
func show_tab(page: Page) -> void:
	_show_page(page)


func _show_page(page: Page) -> void:
	_page = page
	_status.text = ""
	_build_tabs()
	_rebuild()


func _rebuild() -> void:
	var summary := BusinessManager.portfolio_summary()
	_title.text = String(summary["company"]).to_upper()
	_subtitle.text = "%d business%s · %d staff · net worth %s" % [
		int(summary["businesses"]), "" if int(summary["businesses"]) == 1 else "es",
		int(summary["employees"]), BusinessUIKit.money(int(summary["net_worth"])),
	]

	for child in _rows.get_children():
		child.queue_free()

	match _page:
		Page.EMPIRE: _build_empire(summary)
		Page.BUSINESSES: _build_businesses()
		Page.EMPLOYEES: _build_employees()
		Page.FINANCE: _build_finance(summary)
		Page.LOANS: _build_loans()


func _pair(name: String, value: String, colour: Color = BusinessUIKit.TEXT) -> void:
	_rows.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(name, 14, BusinessUIKit.MUTED),
		BusinessUIKit.value_label(value, 14, colour),
	]))


# --- Empire --------------------------------------------------------------

func _build_empire(summary: Dictionary) -> void:
	var worth := int(summary["net_worth"])
	_pair("Net worth", BusinessUIKit.money(worth), BusinessUIKit.tone_for(worth))
	_pair("Personal cash", BusinessUIKit.money(int(summary["personal_cash"])))
	_pair("Business cash", BusinessUIKit.money(int(summary["business_cash"])))
	_pair("Business value", BusinessUIKit.money(int(summary["business_value"])))
	_pair("Vehicles", BusinessUIKit.money(int(summary["vehicles"])))
	_pair("Property equity", BusinessUIKit.money(int(summary["property_equity"])))
	_pair(
		"Debt", BusinessUIKit.money(-int(summary["debt"])),
		BusinessUIKit.BAD if int(summary["debt"]) > 0 else BusinessUIKit.TEXT
	)
	_rows.add_child(BusinessUIKit.heading("Today"))
	_pair("Businesses owned", str(int(summary["businesses"])))
	_pair("Employees", str(int(summary["employees"])))
	_pair("Customers", str(int(summary["customers_today"])))
	_pair("Revenue", BusinessUIKit.money(int(summary["revenue_today"])))
	_pair("Expenses", BusinessUIKit.money(-int(summary["expenses_today"])))
	_pair(
		"Profit", BusinessUIKit.money(int(summary["profit_today"])),
		BusinessUIKit.tone_for(int(summary["profit_today"]))
	)

	var reached := BusinessManager.reached_milestones()
	if not reached.is_empty():
		_rows.add_child(BusinessUIKit.heading("Milestones (%d)" % reached.size()))
		for entry in BusinessManager.MILESTONES:
			if not reached.has(entry[0]):
				continue
			_rows.add_child(BusinessUIKit.row([
				BusinessUIKit.stretch_label(String(entry[1]), 14, BusinessUIKit.GOOD),
				BusinessUIKit.label(String(entry[2]), 12, BusinessUIKit.MUTED),
			]))


# --- Businesses ----------------------------------------------------------

func _build_businesses() -> void:
	if BusinessManager.owned_count() == 0:
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(
				"You do not own a business yet. Find a vacant unit on the street.",
				13, BusinessUIKit.MUTED
			)
		]))
		return

	for business in BusinessManager.get_businesses():
		var unit := business.property()
		var profit := business.profit_today()
		var open := BusinessUIKit.button("MANAGE", 110.0)
		open.pressed.connect(_on_manage_pressed.bind(business))

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		header.add_child(BusinessUIKit.stretch_label(business.business_name.to_upper(), 16))
		header.add_child(BusinessUIKit.label(
			business.status_text(), 13,
			BusinessUIKit.GOOD if business.is_open() else BusinessUIKit.MUTED
		))
		header.add_child(open)
		card.add_child(header)
		card.add_child(BusinessUIKit.label(
			"%s · %s · level %d" % [
				BusinessCatalogue.by_id(business.type_id).display_name,
				unit.address if unit != null else "no premises", business.level(),
			], 12, BusinessUIKit.MUTED
		))
		card.add_child(BusinessUIKit.label(
			"today  revenue %s · profit %s · margin %d%% · customers %d" % [
				BusinessUIKit.money(business.revenue_today), BusinessUIKit.money(profit),
				roundi(business.profit_margin() * 100.0), business.customer_count_today,
			], 13, BusinessUIKit.tone_for(profit)
		))
		card.add_child(BusinessUIKit.label(
			"value %s · cash %s · reputation %d%% · staff %d" % [
				BusinessUIKit.money(business.estimated_value()),
				BusinessUIKit.money(business.cash_balance),
				roundi(business.reputation), business.employees.size(),
			], 12, BusinessUIKit.MUTED
		))

		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
		frame.add_child(card)
		_rows.add_child(frame)


func _on_manage_pressed(business: BusinessInstance) -> void:
	_selected = business
	business_selected.emit(business)


# --- Employees -----------------------------------------------------------

func _build_employees() -> void:
	var staff := BusinessManager.all_employees()
	_rows.add_child(BusinessUIKit.heading("Everybody on the payroll (%d)" % staff.size()))
	if staff.is_empty():
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("Nobody yet.", 13, BusinessUIKit.MUTED)
		]))
		return

	var hourly := 0
	for business in BusinessManager.get_businesses():
		for worker in business.employees:
			hourly += worker.hourly_wage
			_rows.add_child(BusinessUIKit.row([
				BusinessUIKit.stretch_label(worker.employee_name, 14),
				BusinessUIKit.label(worker.get_role_name(), 13, BusinessUIKit.MUTED),
				BusinessUIKit.label(business.business_name, 12, BusinessUIKit.MUTED),
				BusinessUIKit.label(worker.schedule_text(), 12, BusinessUIKit.MUTED),
				BusinessUIKit.label("skill %d" % worker.relevant_skill(), 12, BusinessUIKit.MUTED),
				BusinessUIKit.value_label("$%d/h" % worker.hourly_wage, 13),
			]))
	_pair("Wage bill, per hour worked", BusinessUIKit.money(-hourly), BusinessUIKit.BAD)


# --- Finance -------------------------------------------------------------

func _build_finance(summary: Dictionary) -> void:
	_rows.add_child(BusinessUIKit.heading("Today, across everything"))
	_pair("Revenue", BusinessUIKit.money(int(summary["revenue_today"])), BusinessUIKit.GOOD)
	_pair("Expenses", BusinessUIKit.money(-int(summary["expenses_today"])))
	_pair(
		"Profit", BusinessUIKit.money(int(summary["profit_today"])),
		BusinessUIKit.tone_for(int(summary["profit_today"]))
	)

	_rows.add_child(BusinessUIKit.heading("This week, per business"))
	for business in BusinessManager.get_businesses():
		var week := business.weekly_report()
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(business.business_name, 14),
			BusinessUIKit.label("%d days" % int(week["days"]), 12, BusinessUIKit.MUTED),
			BusinessUIKit.label("rev %s" % BusinessUIKit.money(int(week["revenue"])), 12, BusinessUIKit.MUTED),
			BusinessUIKit.label("wages %s" % BusinessUIKit.money(-int(week["wages"])), 12, BusinessUIKit.MUTED),
			BusinessUIKit.label("rent %s" % BusinessUIKit.money(-int(week["rent"])), 12, BusinessUIKit.MUTED),
			BusinessUIKit.value_label(
				"%s  %d%%" % [
					BusinessUIKit.money(int(week["profit"])), roundi(float(week["margin"]) * 100.0)
				],
				13, BusinessUIKit.tone_for(int(week["profit"]))
			),
		]))

	_rows.add_child(BusinessUIKit.heading("Personal finances"))
	_pair("Cash", BusinessUIKit.money(int(summary["personal_cash"])))
	_pair("Business equity", BusinessUIKit.money(int(summary["business_value"])))
	_pair("Vehicles", BusinessUIKit.money(int(summary["vehicles"])))
	_pair("Property, at market", BusinessUIKit.money(int(summary["property_value"])))
	_pair("Mortgages", BusinessUIKit.money(-int(summary["mortgage_debt"])))
	_pair("Debt", BusinessUIKit.money(-int(summary["debt"])))
	_pair(
		"NET WORTH", BusinessUIKit.money(int(summary["net_worth"])),
		BusinessUIKit.tone_for(int(summary["net_worth"]))
	)


# --- Loans ---------------------------------------------------------------

func _build_loans() -> void:
	if BusinessManager.owned_count() == 0:
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("The bank lends to businesses, not to people.", 13, BusinessUIKit.MUTED)
		]))
		return

	_rows.add_child(BusinessUIKit.heading("Borrowing against"))
	for business in BusinessManager.get_businesses():
		var pick := BusinessUIKit.button(
			"SELECTED" if business == _selected else "SELECT", 120.0
		)
		pick.disabled = business == _selected
		pick.pressed.connect(func() -> void:
			_selected = business
			_rebuild()
		)
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(business.business_name, 14),
			BusinessUIKit.label(
				"reputation %d%%  ·  %d days trading" % [
					roundi(business.reputation), TimeManager.day_index - business.founded_on_day
				], 12, BusinessUIKit.MUTED
			),
			pick,
		]))

	_rows.add_child(BusinessUIKit.heading("Outstanding"))
	var any := false
	for business in BusinessManager.get_businesses():
		for loan in business.loans:
			any = true
			var actions := HBoxContainer.new()
			actions.add_theme_constant_override("separation", 6)
			if loan.is_active():
				var extra := BusinessUIKit.button("PAY $500", 110.0)
				extra.pressed.connect(_on_repay.bind(business, loan, 500))
				var settle := BusinessUIKit.button("PAY OFF", 110.0)
				settle.pressed.connect(_on_repay.bind(business, loan, loan.remaining_balance))
				actions.add_child(extra)
				actions.add_child(settle)
			_rows.add_child(BusinessUIKit.row([
				BusinessUIKit.stretch_label(
					"%s  ·  %s" % [loan.display_name, business.business_name], 14
				),
				BusinessUIKit.label(
					"borrowed %s" % BusinessUIKit.money(loan.principal), 12, BusinessUIKit.MUTED
				),
				BusinessUIKit.label(
					"%s left" % BusinessUIKit.money(loan.remaining_balance), 13,
					BusinessUIKit.BAD if loan.is_active() else BusinessUIKit.GOOD
				),
				BusinessUIKit.label(
					"%s every %d days" % [
						BusinessUIKit.money(loan.payment_amount), loan.payment_interval_days
					], 12, BusinessUIKit.MUTED
				),
				BusinessUIKit.label(loan.status_text(), 12, BusinessUIKit.MUTED),
				actions,
			]))
	if not any:
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("Nothing borrowed.", 13, BusinessUIKit.MUTED)
		]))

	if _selected == null:
		return
	_rows.add_child(BusinessUIKit.heading("Available to %s" % _selected.business_name))
	for offer in BusinessManager.loan_offers():
		var take := BusinessUIKit.button("BORROW", 110.0)
		var eligible := BusinessManager.is_eligible(_selected, offer)
		take.disabled = not eligible
		take.pressed.connect(_on_borrow.bind(offer))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(offer.display_name, 14),
			BusinessUIKit.label(BusinessUIKit.money(offer.amount), 14),
			BusinessUIKit.label("%d%% interest" % roundi(offer.interest_rate * 100.0), 12, BusinessUIKit.MUTED),
			BusinessUIKit.label(
				"%s every %d days" % [
					BusinessUIKit.money(offer.payment_amount), offer.payment_interval_days
				], 12, BusinessUIKit.MUTED
			),
			BusinessUIKit.label(
				"repay %s" % BusinessUIKit.money(offer.total_repayable()), 12, BusinessUIKit.MUTED
			),
			take,
		]))


func _on_borrow(offer: LoanOffer) -> void:
	var result := BusinessManager.take_loan(_selected, offer.offer_id)
	if result == BusinessManager.LoanResult.OK:
		_note("Borrowed %s." % BusinessUIKit.money(offer.amount), BusinessUIKit.GOOD)
	else:
		_note(BusinessManager.describe_loan(result), BusinessUIKit.BAD)
	_rebuild()


func _on_repay(business: BusinessInstance, loan: Loan, amount: int) -> void:
	var paid := BusinessManager.repay_loan(business, loan.loan_id, amount)
	if paid <= 0:
		_note("The business cannot cover that.", BusinessUIKit.BAD)
	else:
		_note("Paid %s off %s." % [BusinessUIKit.money(paid), loan.display_name], BusinessUIKit.GOOD)
	_rebuild()


# --- Plumbing ------------------------------------------------------------

func _note(text: String, colour: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", colour)


func _on_changed(_business: BusinessInstance) -> void:
	if visible:
		_rebuild()


func _on_sold(_name: String, _proceeds: int) -> void:
	_selected = BusinessManager.primary_business()
	if visible:
		_rebuild()


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible:
		_rebuild()
