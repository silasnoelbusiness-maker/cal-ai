class_name LegalPanel
extends Control
## Everything the city has on the player, on one screen.
##
## §31 asks for overview, cases, record and money owed. §125 asks that it feel
## related to the underworld screen and distinct from it — same frame, same
## kit, but this one is a civic document rather than a back room, so it states
## figures plainly and never uses the underworld's language.
##
## §34 is the discipline here: this shows what happened, not the machinery.
## Nothing on this screen exposes pressure scores or outcome rolls.

signal opened()
signal closed()

enum Page { OVERVIEW, CASES, RECORD, MONEY, SERVICES }

const PAGE_NAMES := {
	Page.OVERVIEW: "OVERVIEW",
	Page.CASES: "CASES",
	Page.RECORD: "RECORD",
	Page.MONEY: "FINES",
	Page.SERVICES: "COUNSEL",
}

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _tabs: HBoxContainer = null
var _page: Page = Page.OVERVIEW


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(920, 640))
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 6)
	_parts["body"].add_child(_tabs)
	_body = ScreenKit.scroller(_parts["body"])
	LegalManager.case_opened.connect(_on_changed)
	LegalManager.case_resolved.connect(_on_changed)
	LegalManager.case_missed.connect(_on_changed)
	LegalManager.arrest_recorded.connect(_on_changed)
	LegalManager.legal_debt_changed.connect(_on_debt_changed)


func is_open() -> bool:
	return visible


func open(page: Page = Page.OVERVIEW) -> void:
	_page = page
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


func show_tab(page: Page) -> void:
	_page = page
	_rebuild()


func _on_changed(_a: Variant = null) -> void:
	if visible:
		_rebuild()


func _on_debt_changed(_amount: int) -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _tabs.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	var record := LegalManager.record
	_parts["title"].text = "LEGAL"
	_parts["subtitle"].text = "%s  ·  %d arrest%s  ·  %d open case%s" % [
		LegalManager.tier_name(), record.arrest_count(),
		"" if record.arrest_count() == 1 else "s",
		LegalManager.open_cases().size(),
		"" if LegalManager.open_cases().size() == 1 else "s",
	]
	_parts["status"].text = (
		"LEGAL MATTER OUTSTANDING" if LegalManager.has_outstanding_matter() else ""
	)

	for page: Page in PAGE_NAMES:
		var button := BusinessUIKit.button(String(PAGE_NAMES[page]), 110.0)
		button.disabled = page == _page
		button.pressed.connect(func() -> void: show_tab(page))
		_tabs.add_child(button)

	match _page:
		Page.CASES:
			_build_cases()
		Page.RECORD:
			_build_record()
		Page.MONEY:
			_build_money()
		Page.SERVICES:
			_build_services()
		_:
			_build_overview()

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


# --- Overview ------------------------------------------------------------

func _build_overview() -> void:
	var record := LegalManager.record
	_body.add_child(ScreenKit.heading("WHERE YOU STAND"))
	_body.add_child(ScreenKit.row("Record", LegalManager.tier_name()))
	_body.add_child(ScreenKit.row("Arrests", "%d" % record.arrest_count()))
	_body.add_child(ScreenKit.row(
		"Worst offence", LegalSeverity.name_of(record.highest_severity()).capitalize()
	))
	_body.add_child(ScreenKit.row("Open cases", "%d" % LegalManager.open_cases().size()))
	_body.add_child(ScreenKit.row("Missed hearings", "%d" % record.missed_court_events))

	var next_case := LegalManager.next_case()
	_body.add_child(ScreenKit.heading("NEXT COURT DATE"))
	if next_case == null:
		_body.add_child(BusinessUIKit.label(
			"Nothing listed. Keep it that way.", 14, ScreenKit.MUTED
		))
	else:
		var days := next_case.days_until(TimeManager.day_index)
		_body.add_child(ScreenKit.row("Case", next_case.title))
		_body.add_child(ScreenKit.row(
			"When",
			"Today at %s" % next_case.court_time_label() if days <= 0
			else "In %d day%s at %s" % [
				days, "" if days == 1 else "s", next_case.court_time_label()
			]
		))
		_body.add_child(ScreenKit.row("Counsel", LegalService.by_id(next_case.counsel_id).display_name))
		_body.add_child(BusinessUIKit.label(
			"The Civic Court is on Harbour Row. Turning up is worth more than "
			+ "any lawyer.", 12, ScreenKit.MUTED
		))

	_body.add_child(ScreenKit.heading("MONEY"))
	_body.add_child(ScreenKit.row("Outstanding balance", ScreenKit.money(LegalManager.legal_debt)))
	_body.add_child(ScreenKit.row("Fines paid", ScreenKit.money(record.total_fines_paid)))
	_body.add_child(ScreenKit.row("Legal costs", ScreenKit.money(record.total_legal_costs)))


# --- Cases ---------------------------------------------------------------

func _build_cases() -> void:
	var open := LegalManager.open_cases()
	if open.is_empty():
		_body.add_child(BusinessUIKit.label(
			"No case is waiting on you.", 14, ScreenKit.MUTED
		))
	else:
		_body.add_child(ScreenKit.heading("WAITING ON YOU"))
		for case in open:
			_body.add_child(_case_card(case, true))

	var settled: Array[LegalCase] = []
	for case in LegalManager.record.cases:
		if not case.is_open():
			settled.append(case)
	if settled.is_empty():
		return
	_body.add_child(ScreenKit.heading("HEARD"))
	for case in settled:
		_body.add_child(_case_card(case, false))


func _case_card(case: LegalCase, live: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(case.title, 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(
			case.severity_name(), 13,
			ScreenKit.BAD if int(case.severity) >= int(CrimeData.Severity.SEVERE)
			else ScreenKit.ACCENT
		),
	]))
	column.add_child(ScreenKit.row("Status", case.status_name()))
	if live:
		var days := case.days_until(TimeManager.day_index)
		column.add_child(ScreenKit.row(
			"Court",
			"Today at %s" % case.court_time_label() if days <= 0
			else "In %d day%s at %s" % [
				days, "" if days == 1 else "s", case.court_time_label()
			]
		))
		column.add_child(ScreenKit.row(
			"Counsel", LegalService.by_id(case.counsel_id).display_name
		))
		column.add_child(BusinessUIKit.label(
			"Expected: a fine and a line on the record.", 12, ScreenKit.MUTED
		))
	else:
		column.add_child(ScreenKit.row("Outcome", case.outcome_name()))
		if case.fine_applied > 0:
			column.add_child(ScreenKit.row("Fine", ScreenKit.money(case.fine_applied)))
		if case.costs_applied > 0:
			column.add_child(ScreenKit.row("Costs", ScreenKit.money(case.costs_applied)))
		column.add_child(BusinessUIKit.label(
			"You appeared." if case.attended else "You did not appear.",
			12, ScreenKit.MUTED
		))
	return card


# --- Record --------------------------------------------------------------

func _build_record() -> void:
	var arrests := LegalManager.record.arrests
	if arrests.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Nothing on you at all. Most people manage this without trying.",
			14, ScreenKit.MUTED
		))
		return
	_body.add_child(ScreenKit.heading("WHAT THEY HAVE ON YOU"))
	# Newest first: what happened lately is what matters.
	for index in range(arrests.size() - 1, -1, -1):
		_body.add_child(_arrest_card(arrests[index]))


func _arrest_card(arrest: ArrestRecord) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("DAY %d" % arrest.day, 13, ScreenKit.MUTED),
		BusinessUIKit.value_label(arrest.stars(), 13, ScreenKit.BAD),
	]))
	for offence in arrest.offences:
		column.add_child(BusinessUIKit.label(offence.capitalize(), 15, ScreenKit.TEXT))
	column.add_child(ScreenKit.row("Seriousness", arrest.severity_name().capitalize()))
	if arrest.fine_paid > 0:
		column.add_child(ScreenKit.row("Fine", ScreenKit.money(arrest.fine_paid)))
	if arrest.release_cost > 0:
		column.add_child(ScreenKit.row("Release", ScreenKit.money(arrest.release_cost)))
	if arrest.goods_confiscated > 0:
		column.add_child(ScreenKit.row("Seized", "%d item%s" % [
			arrest.goods_confiscated, "" if arrest.goods_confiscated == 1 else "s"
		]))
	var case := LegalManager.case_by_id(arrest.case_id) if arrest.has_case() else null
	column.add_child(BusinessUIKit.label(
		"Dealt with on the spot." if case == null else "Outcome: %s" % case.outcome_name(),
		12, ScreenKit.MUTED
	))
	return card


# --- Money ---------------------------------------------------------------

func _build_money() -> void:
	var owed := LegalManager.legal_debt
	_body.add_child(ScreenKit.heading("WHAT YOU OWE"))
	_body.add_child(ScreenKit.row("Outstanding balance", ScreenKit.money(owed)))
	if owed <= 0:
		_body.add_child(BusinessUIKit.label(
			"Nothing outstanding. Fines and costs come straight out of your "
			+ "pocket; what you cannot cover waits here until you can.",
			13, ScreenKit.MUTED
		))
	else:
		_body.add_child(BusinessUIKit.label(
			"This does not grow, and nobody forecloses on it. It sits there "
			+ "until it is paid, and lenders can see it.",
			13, ScreenKit.MUTED
		))
		var pay_all := BusinessUIKit.button("PAY IT OFF", 160.0)
		pay_all.disabled = EconomyManager.cash <= 0
		pay_all.pressed.connect(func() -> void:
			LegalManager.pay_legal_debt(owed)
			_rebuild()
		)
		_parts["actions"].add_child(pay_all)

	_body.add_child(ScreenKit.heading("LIFETIME"))
	_body.add_child(ScreenKit.row("Fines paid", ScreenKit.money(LegalManager.record.total_fines_paid)))
	_body.add_child(ScreenKit.row("Legal costs", ScreenKit.money(LegalManager.record.total_legal_costs)))


# --- Counsel -------------------------------------------------------------

func _build_services() -> void:
	_body.add_child(ScreenKit.heading("REPRESENTATION"))
	_body.add_child(BusinessUIKit.label(
		"Retained for whatever is listed next. Better counsel improves the odds "
		+ "and reduces a fine. None of it buys an acquittal, and none of it can "
		+ "be changed once a case has been heard.",
		13, ScreenKit.MUTED
	))
	for service in LegalService.catalogue():
		_body.add_child(_service_card(service))


func _service_card(service: LegalService) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	var retained := LegalManager.counsel_id == service.service_id
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(service.display_name, 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(
			"RETAINED" if retained else ScreenKit.money(service.cost), 13,
			ScreenKit.GOOD if retained else ScreenKit.ACCENT
		),
	]))
	column.add_child(BusinessUIKit.label(service.blurb, 12, ScreenKit.MUTED))
	if service.outcome_bonus > 0.0:
		column.add_child(ScreenKit.row(
			"Fine reduced by", "%d%%" % roundi(service.fine_relief * 100.0)
		))
	if not retained:
		var hire := BusinessUIKit.button("RETAIN", 140.0)
		hire.disabled = service.cost > 0 and not EconomyManager.can_afford(service.cost)
		hire.pressed.connect(func() -> void:
			LegalManager.retain(service.service_id)
			_rebuild()
		)
		column.add_child(hire)
	return card
