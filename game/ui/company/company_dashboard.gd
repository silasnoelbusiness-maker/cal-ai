class_name CompanyDashboard
extends Control
## Everything the player owns, seen as one company.
##
## The business dashboard answers "how is this shop doing". This answers "how is
## the company doing", which is a different question the moment there are three
## of them: which brand, which location, which of forty people, and which of the
## nine things going wrong right now is the one worth driving across the city
## for.
##
## Every figure is read from CompanyManager rather than added up here, so this
## file is layout and nothing else.

signal opened()
signal closed()
signal schedule_requested(worker: EmployeeData)
signal manager_requested(business: BusinessInstance)

enum Page { OVERVIEW, BRANDS, LOCATIONS, EMPLOYEES, OPERATIONS, FINANCE, MILESTONES }

const PAGE_NAMES := {
	Page.OVERVIEW: "OVERVIEW",
	Page.BRANDS: "BRANDS",
	Page.LOCATIONS: "LOCATIONS",
	Page.EMPLOYEES: "EMPLOYEES",
	Page.OPERATIONS: "OPERATIONS",
	Page.FINANCE: "FINANCE",
	Page.MILESTONES: "MILESTONES",
}

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _tabs: HBoxContainer = null
var _page: Page = Page.OVERVIEW
## Staff filters, which is the whole of what §55 asks for.
var _staff_business: StringName = &""
var _staff_role: int = -1
var _staff_on_shift_only: bool = false
var _naming: bool = false


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(940, 660))
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 6)
	_parts["body"].add_child(_tabs)
	_body = ScreenKit.scroller(_parts["body"])
	CompanyManager.company_changed.connect(_on_company_changed)
	BusinessManager.business_changed.connect(_on_business_changed)


func is_open() -> bool:
	return visible


func open(page: Page = Page.OVERVIEW) -> void:
	_page = page
	_naming = false
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
	_naming = false
	_rebuild()


# --- Chrome --------------------------------------------------------------

func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _tabs.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	var summary := CompanyManager.company_summary()
	_parts["title"].text = String(summary["name"]).to_upper()
	_parts["subtitle"].text = "%d locations  ·  %d brands  ·  %d staff  ·  company value %s" % [
		int(summary["locations"]), int(summary["brands"]), int(summary["employees"]),
		ScreenKit.money(int(summary["company_value"])),
	]
	_parts["status"].text = ""

	for page: Page in PAGE_NAMES:
		var button := BusinessUIKit.button(String(PAGE_NAMES[page]), 104.0)
		button.toggle_mode = true
		button.button_pressed = _page == page
		button.pressed.connect(show_tab.bind(page))
		_tabs.add_child(button)

	match _page:
		Page.BRANDS:
			_build_brands()
		Page.LOCATIONS:
			_build_locations()
		Page.EMPLOYEES:
			_build_employees()
		Page.OPERATIONS:
			_build_operations()
		Page.FINANCE:
			_build_finance(summary)
		Page.MILESTONES:
			_build_milestones()
		_:
			_build_overview(summary)

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


# --- Overview ------------------------------------------------------------

func _build_overview(summary: Dictionary) -> void:
	if _naming:
		_build_name_field()
		return

	_body.add_child(ScreenKit.row("Company", String(summary["name"]), true))
	_body.add_child(ScreenKit.row("Locations", "%d in %d districts" % [
		int(summary["locations"]), int(summary["districts"])
	]))
	_body.add_child(ScreenKit.row("Brands", str(int(summary["brands"]))))
	_body.add_child(ScreenKit.row("Employees", str(int(summary["employees"]))))
	_body.add_child(ScreenKit.spacer(8))

	_body.add_child(ScreenKit.heading("TODAY"))
	_body.add_child(ScreenKit.row("Revenue", ScreenKit.money(int(summary["revenue_today"]))))
	var profit := int(summary["profit_today"])
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Profit", 14, ScreenKit.MUTED),
		BusinessUIKit.value_label(
			ScreenKit.money(profit), 15, ScreenKit.GOOD if profit >= 0 else ScreenKit.BAD
		),
	]))

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("WORTH"))
	_body.add_child(ScreenKit.row(
		"Company value", ScreenKit.money(int(summary["company_value"])), true
	))
	_body.add_child(ScreenKit.row("Brand premium", ScreenKit.money(int(summary["brand_premium"]))))
	_body.add_child(ScreenKit.row("Business cash", ScreenKit.money(int(summary["business_cash"]))))
	_body.add_child(ScreenKit.row("Business debt", ScreenKit.money(int(summary["business_debt"]))))
	_body.add_child(ScreenKit.row(
		"Property equity", ScreenKit.money(int(summary["property_equity"]))
	))
	_body.add_child(ScreenKit.row("Your net worth", ScreenKit.money(int(summary["net_worth"]))))
	_body.add_child(BusinessUIKit.label(
		"Company value is the operating business only — no house, no cars, no "
		+ "personal cash. Net worth is everything, and lives on the profile screen.",
		13, ScreenKit.MUTED
	))

	var rename := BusinessUIKit.button("NAME COMPANY", 170.0)
	rename.pressed.connect(func() -> void:
		_naming = true
		AudioManager.play_ui(&"ui_click")
		_rebuild()
	)
	_parts["actions"].add_child(rename)


func _build_name_field() -> void:
	_body.add_child(ScreenKit.heading("WHAT IS THE COMPANY CALLED?"))
	var field := LineEdit.new()
	field.text = CompanyManager.get_company_name()
	field.max_length = 40
	field.custom_minimum_size = Vector2(420, 34)
	field.caret_blink = true
	_body.add_child(field)
	field.grab_focus()
	field.select_all()
	_body.add_child(BusinessUIKit.label(
		"Anything you like. It goes on the profile, the company screen and the "
		+ "sign in your office.", 13, ScreenKit.MUTED
	))

	var save := BusinessUIKit.button("SAVE", 150.0)
	save.pressed.connect(func() -> void:
		if CompanyManager.set_company_name(field.text):
			AudioManager.play_ui(&"ui_confirm")
			_naming = false
			_rebuild()
		else:
			_note("A company needs a name.", ScreenKit.BAD)
	)
	_parts["actions"].add_child(save)
	field.text_submitted.connect(func(_value: String) -> void: save.pressed.emit())

	var cancel := BusinessUIKit.button("BACK", 120.0)
	cancel.pressed.connect(func() -> void:
		_naming = false
		AudioManager.play_ui(&"ui_back")
		_rebuild()
	)
	_parts["actions"].add_child(cancel)


# --- Brands --------------------------------------------------------------

func _build_brands() -> void:
	var brands := CompanyManager.brands()
	if brands.is_empty():
		_body.add_child(BusinessUIKit.label(
			"No brands yet. Found a business and it becomes one.", 14, ScreenKit.MUTED
		))
		return
	for brand in brands:
		var figures := CompanyManager.brand_summary(brand)
		_body.add_child(_brand_card(brand, figures))
		_body.add_child(ScreenKit.spacer(6))


func _brand_card(brand: BrandData, figures: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)

	# A swatch of the brand's colour beside its name: two chains of the same
	# kind of shop are told apart by colour on the map and on the sign.
	var swatch := ColorRect.new()
	swatch.color = brand.brand_color
	swatch.custom_minimum_size = Vector2(16, 16)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_child(BusinessUIKit.row([
		swatch,
		BusinessUIKit.stretch_label(brand.brand_name.to_upper(), 16, ScreenKit.TEXT),
		BusinessUIKit.value_label(
			"%d branch%s" % [
				int(figures["branches"]), "" if int(figures["branches"]) == 1 else "es"
			], 13, ScreenKit.MUTED
		),
	]))
	column.add_child(ScreenKit.row(
		"Revenue today", ScreenKit.money(int(figures["revenue_today"]))
	))
	var profit := int(figures["profit_today"])
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Profit today", 14, ScreenKit.MUTED),
		BusinessUIKit.value_label(
			ScreenKit.money(profit), 14, ScreenKit.GOOD if profit >= 0 else ScreenKit.BAD
		),
	]))
	column.add_child(ScreenKit.row(
		"Brand reputation", "%d  ·  %s" % [int(figures["reputation"]), brand.reputation_label()]
	))
	if not String(figures["best_branch"]).is_empty():
		column.add_child(ScreenKit.row("Best branch", String(figures["best_branch"])))
	return card


# --- Locations -----------------------------------------------------------

func _build_locations() -> void:
	var rows := CompanyManager.location_rows()
	if rows.is_empty():
		_body.add_child(BusinessUIKit.label("Nothing trading yet.", 14, ScreenKit.MUTED))
		return
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("LOCATION", 12, ScreenKit.MUTED),
		BusinessUIKit.value_label("REVENUE", 12, ScreenKit.MUTED),
		BusinessUIKit.value_label("PROFIT", 12, ScreenKit.MUTED),
		BusinessUIKit.value_label("CUSTOMERS", 12, ScreenKit.MUTED),
	]))
	for row in rows:
		_body.add_child(_location_row(row))


func _location_row(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	var profit := int(row["profit_today"])
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(String(row["name"]), 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(ScreenKit.money(int(row["revenue_today"])), 14, ScreenKit.TEXT),
		BusinessUIKit.value_label(
			ScreenKit.money(profit), 14, ScreenKit.GOOD if profit >= 0 else ScreenKit.BAD
		),
		BusinessUIKit.value_label(str(int(row["customers_today"])), 14, ScreenKit.MUTED),
	]))
	column.add_child(BusinessUIKit.label(
		"%s  ·  %s  ·  %s  ·  %d staff  ·  %s" % [
			String(row["brand"]), String(row["type"]), String(row["district"]),
			int(row["staff"]), String(row["status"]),
		], 12, ScreenKit.MUTED
	))

	var business: BusinessInstance = row["business"]
	var manage := BusinessUIKit.button("MANAGER", 110.0)
	manage.pressed.connect(func() -> void: manager_requested.emit(business))
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("", 12, ScreenKit.MUTED), manage,
	]))
	return card


# --- Employees -----------------------------------------------------------

func _build_employees() -> void:
	_build_staff_filters()
	var rows := CompanyManager.staff_rows()
	var shown := 0
	for row in rows:
		if _staff_business != &"" and StringName(row["business_id"]) != _staff_business:
			continue
		if _staff_role >= 0 and int(row["role"]) != _staff_role:
			continue
		if _staff_on_shift_only and not bool(row["on_shift"]):
			continue
		shown += 1
		_body.add_child(_staff_row(row))
	if shown == 0:
		_body.add_child(BusinessUIKit.label("Nobody matches that.", 14, ScreenKit.MUTED))


func _build_staff_filters() -> void:
	var by_business := OptionButton.new()
	by_business.add_item("All locations", -1)
	var index := 0
	var ids: Array[StringName] = [&""]
	for business in BusinessManager.get_businesses():
		index += 1
		by_business.add_item(business.business_name, index)
		ids.append(business.business_id)
		if business.business_id == _staff_business:
			by_business.selected = index
	by_business.item_selected.connect(func(chosen: int) -> void:
		_staff_business = ids[chosen] if chosen < ids.size() else &""
		_rebuild()
	)

	var by_role := OptionButton.new()
	by_role.add_item("All roles", -1)
	var roles: Array[int] = [-1]
	var role_index := 0
	for role: int in EmployeeData.ROLE_NAMES:
		role_index += 1
		by_role.add_item(String(EmployeeData.ROLE_NAMES[role]), role_index)
		roles.append(role)
		if role == _staff_role:
			by_role.selected = role_index
	by_role.item_selected.connect(func(chosen: int) -> void:
		_staff_role = roles[chosen] if chosen < roles.size() else -1
		_rebuild()
	)

	var on_shift := BusinessUIKit.button("ON SHIFT", 110.0)
	on_shift.toggle_mode = true
	on_shift.button_pressed = _staff_on_shift_only
	on_shift.pressed.connect(func() -> void:
		_staff_on_shift_only = not _staff_on_shift_only
		_rebuild()
	)

	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("FILTER", 12, ScreenKit.MUTED),
		by_business, by_role, on_shift,
	]))


func _staff_row(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	var worker: EmployeeData = row["employee"]
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(String(row["name"]), 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(String(row["role_name"]), 13, ScreenKit.ACCENT),
		BusinessUIKit.value_label(
			"ON SHIFT" if bool(row["on_shift"]) else "OFF", 12,
			ScreenKit.GOOD if bool(row["on_shift"]) else ScreenKit.MUTED
		),
	]))
	column.add_child(BusinessUIKit.label(
		"%s  ·  %s  ·  $%d/hr  ·  skill %d" % [
			String(row["business_name"]), String(row["shift"]),
			int(row["wage"]), int(row["skill"]),
		], 12, ScreenKit.MUTED
	))
	var problems := CompanyManager.schedule_problems(worker)
	if not problems.is_empty():
		column.add_child(BusinessUIKit.label(problems[0], 12, ScreenKit.BAD))

	var rota := BusinessUIKit.button("SCHEDULE", 120.0)
	rota.pressed.connect(func() -> void: schedule_requested.emit(worker))
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("", 12, ScreenKit.MUTED), rota,
	]))
	return card


# --- Operations ----------------------------------------------------------

func _build_operations() -> void:
	_body.add_child(ScreenKit.heading("TODAY'S ISSUES"))
	var issues := CompanyManager.bottleneck_report()
	if issues.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Nothing is holding anything up right now.", 14, ScreenKit.GOOD
		))
	for i in issues.size():
		var issue: Dictionary = issues[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		card.add_child(column)
		column.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(
				"%d. %s" % [i + 1, String(issue["headline"])], 15,
				ScreenKit.BAD if float(issue["severity"]) > 0.6 else ScreenKit.TEXT
			),
			BusinessUIKit.value_label(String(issue["business_name"]), 13, ScreenKit.MUTED),
		]))
		column.add_child(BusinessUIKit.label(String(issue["detail"]), 12, ScreenKit.MUTED))
		_body.add_child(card)

	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("HOW HARD THINGS ARE WORKING"))
	var any := false
	for business in BusinessManager.get_businesses():
		var rows := CompanyManager.utilisation_rows(business)
		if rows.is_empty():
			continue
		any = true
		_body.add_child(BusinessUIKit.label(business.business_name.to_upper(), 13, ScreenKit.ACCENT))
		for row in rows:
			_body.add_child(ScreenKit.stat_bar(
				String(row["label"]), roundi(float(row["load"]) * 100.0),
				float(row["load"]) > 0.9
			))
	if not any:
		_body.add_child(BusinessUIKit.label(
			"Nothing has traded yet today.", 13, ScreenKit.MUTED
		))

	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("ON ORDER"))
	var purchasing := BusinessManager.purchasing_overview()
	var pending: Array = purchasing["pending"]
	if pending.is_empty():
		_body.add_child(BusinessUIKit.label("Nothing on its way.", 13, ScreenKit.MUTED))
	for order in pending:
		_body.add_child(ScreenKit.row(
			"%s  ·  %s" % [String(order["business"]), String(order["summary"])],
			String(order["arrives"])
		))
	var low: Array = purchasing["low_stock"]
	if not low.is_empty():
		_body.add_child(ScreenKit.spacer(6))
		_body.add_child(ScreenKit.heading("RUNNING SHORT"))
		for entry in low.slice(0, 8):
			_body.add_child(ScreenKit.row(
				"%s  ·  %s" % [String(entry["business"]), String(entry["item"])],
				"%d held, %d coming" % [int(entry["held"]), int(entry["incoming"])]
			))


# --- Finance -------------------------------------------------------------

func _build_finance(summary: Dictionary) -> void:
	_body.add_child(ScreenKit.heading("THE COMPANY TODAY"))
	_body.add_child(ScreenKit.row("Revenue", ScreenKit.money(int(summary["revenue_today"]))))
	var profit := int(summary["profit_today"])
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Profit", 14, ScreenKit.MUTED),
		BusinessUIKit.value_label(
			ScreenKit.money(profit), 15, ScreenKit.GOOD if profit >= 0 else ScreenKit.BAD
		),
	]))
	_body.add_child(ScreenKit.row("Cash in the businesses", ScreenKit.money(
		int(summary["business_cash"])
	)))
	_body.add_child(ScreenKit.row("Business debt", ScreenKit.money(int(summary["business_debt"]))))

	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("BY LOCATION"))
	for row in CompanyManager.location_rows():
		var business: BusinessInstance = row["business"]
		var line := ScreenKit.row(
			String(row["name"]),
			"%s in  ·  %s out  ·  %s" % [
				ScreenKit.money(business.revenue_today),
				ScreenKit.money(business.expenses_today()),
				ScreenKit.money(business.profit_today()),
			]
		)
		_body.add_child(line)

	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("WHY CUSTOMERS LEFT"))
	var totals := {}
	for business in BusinessManager.get_businesses():
		for entry in business.lost_reason_breakdown():
			totals[entry["label"]] = int(totals.get(entry["label"], 0)) + int(entry["count"])
	if totals.is_empty():
		_body.add_child(BusinessUIKit.label("Nobody walked out today.", 13, ScreenKit.MUTED))
	for label: String in totals:
		_body.add_child(ScreenKit.row(label, str(int(totals[label]))))


# --- Milestones ----------------------------------------------------------

func _build_milestones() -> void:
	for entry in CompanyManager.MILESTONES:
		var id: StringName = entry[0]
		var done := CompanyManager.has_milestone(id)
		_body.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(String(entry[1]), 14,
				ScreenKit.TEXT if done else ScreenKit.MUTED),
			BusinessUIKit.value_label(
				"REACHED" if done else "—", 13,
				ScreenKit.GOOD if done else ScreenKit.MUTED
			),
		]))


# --- Plumbing ------------------------------------------------------------

func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_company_changed() -> void:
	if visible and not _naming:
		_rebuild()


func _on_business_changed(_business: BusinessInstance) -> void:
	if visible and not _naming:
		_rebuild()
