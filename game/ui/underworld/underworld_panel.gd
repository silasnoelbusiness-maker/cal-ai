class_name UnderworldPanel
extends Control
## The criminal side of the player's life, on its own screen.
##
## §92 asks for this to be kept out of the company UI, and it is: nothing here
## knows a business exists. Four tabs answering the four questions a criminal
## career raises — what am I worth, who do I know, what is going, and what has
## all this actually earned.

signal opened()
signal closed()

enum Page { STANDING, CONTACTS, JOBS, EARNINGS }

const PAGE_NAMES := {
	Page.STANDING: "STANDING",
	Page.CONTACTS: "CONTACTS",
	Page.JOBS: "JOBS",
	Page.EARNINGS: "EARNINGS",
}

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _tabs: HBoxContainer = null
var _page: Page = Page.STANDING


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(920, 640))
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 6)
	_parts["body"].add_child(_tabs)
	_body = ScreenKit.scroller(_parts["body"])
	Underworld.reputation_changed.connect(_on_changed)
	Underworld.job_completed.connect(_on_job_changed)
	Underworld.job_failed.connect(_on_job_failed)


func is_open() -> bool:
	return visible


func open(page: Page = Page.STANDING) -> void:
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


func _on_changed(_value: int = 0, _tier: int = 0) -> void:
	if visible:
		_rebuild()


func _on_job_changed(_job: IllegalJobData) -> void:
	if visible:
		_rebuild()


func _on_job_failed(_job: IllegalJobData, _reason: String) -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _tabs.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	_parts["title"].text = "UNDERWORLD"
	_parts["subtitle"].text = "%s  ·  %d contacts  ·  %s earned" % [
		Underworld.tier_name(), Underworld.contacts().size(),
		ScreenKit.money(Underworld.total_illegal_income()),
	]
	_parts["status"].text = ""

	for page: Page in PAGE_NAMES:
		var button := BusinessUIKit.button(String(PAGE_NAMES[page]), 116.0)
		button.disabled = page == _page
		button.pressed.connect(func() -> void: show_tab(page))
		_tabs.add_child(button)

	match _page:
		Page.CONTACTS:
			_build_contacts()
		Page.JOBS:
			_build_jobs()
		Page.EARNINGS:
			_build_earnings()
		_:
			_build_standing()

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


# --- Standing ------------------------------------------------------------

func _build_standing() -> void:
	_body.add_child(ScreenKit.heading("CRIMINAL REPUTATION"))
	_body.add_child(ScreenKit.stat_bar(
		Underworld.tier_name(), Underworld.reputation,
		Underworld.tier() >= CriminalReputation.Tier.CONNECTED
	))
	var next := CriminalReputation.next_threshold(Underworld.reputation)
	_body.add_child(BusinessUIKit.label(
		"%d to %s." % [
			next - Underworld.reputation,
			CriminalReputation.tier_name(
				CriminalReputation.tier_for(next) as CriminalReputation.Tier
			),
		] if next >= 0 else "Nobody on these streets has not heard of you.",
		13, ScreenKit.MUTED
	))

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("WHAT IT BUYS"))
	_body.add_child(ScreenKit.row(
		"Fence pays", "%d%% of value"
		% int(round(CriminalReputation.fence_rate(Underworld.reputation) * 100.0))
	))
	_body.add_child(ScreenKit.row(
		"Buyer pays", "%d%% of a car's value" % int(round((
			Underworld.CHOP_BASE_RATE + Underworld.CHOP_REPUTATION_BONUS * (
				float(Underworld.reputation) / float(CriminalReputation.MAX_REPUTATION)
			)
		) * 100.0))
	))

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("RECORD"))
	_body.add_child(ScreenKit.row(
		"Highest wanted level",
		"%d star%s" % [
			CrimeManager.get_statistic(&"highest_wanted_level"),
			"" if CrimeManager.get_statistic(&"highest_wanted_level") == 1 else "s",
		]
	))
	_body.add_child(ScreenKit.row(
		"Times busted", str(CrimeManager.get_statistic(&"times_busted"))
	))
	_body.add_child(ScreenKit.row(
		"Got away", str(CrimeManager.get_statistic(&"times_escaped"))
	))
	_body.add_child(ScreenKit.row("Jobs done", str(Underworld.jobs_completed)))
	_body.add_child(ScreenKit.row("Jobs failed", str(Underworld.jobs_failed)))


# --- Contacts ------------------------------------------------------------

func _build_contacts() -> void:
	var known := Underworld.contacts()
	if known.is_empty():
		_body.add_child(BusinessUIKit.label(
			"You do not know anybody. That is not the worst way to live.",
			14, ScreenKit.MUTED
		))
		return
	for contact in known:
		_body.add_child(_contact_card(contact))


func _contact_card(contact: CriminalContactData) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	var dealing := Underworld.will_deal(contact)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(contact.display_name, 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(contact.kind_label(), 13, ScreenKit.ACCENT),
		BusinessUIKit.value_label(
			"OPEN" if dealing else "CLOSED", 12,
			ScreenKit.GOOD if dealing else ScreenKit.MUTED
		),
	]))
	column.add_child(BusinessUIKit.label(
		contact.closed_line if not dealing
			else "Needs %d reputation  ·  you have %d" % [
				contact.reputation_required, Underworld.reputation
			],
		12, ScreenKit.MUTED
	))
	return card


# --- Jobs ----------------------------------------------------------------

func _build_jobs() -> void:
	var running := Underworld.active_job()
	_body.add_child(ScreenKit.heading("ON NOW"))
	if running == null:
		_body.add_child(BusinessUIKit.label("Nothing.", 14, ScreenKit.MUTED))
	else:
		_body.add_child(_job_card(running, true))

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("OFFERED"))
	var offers := Underworld.offered_jobs()
	if offers.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Go and see somebody. Work does not come to you.", 14, ScreenKit.MUTED
		))
	for job in offers:
		_body.add_child(_job_card(job, false))


func _job_card(job: IllegalJobData, running: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(job.objective_label(), 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(job.risk_label(), 13, _risk_colour(job.risk)),
		BusinessUIKit.value_label(ScreenKit.money(job.reward), 14, ScreenKit.GOOD),
	]))
	column.add_child(BusinessUIKit.label(
		"%s  ·  %s  ·  +%d reputation" % [
			job.target_name, job.time_text(), job.reputation_reward
		], 12, ScreenKit.MUTED
	))
	if running and job.target_quantity > 1:
		column.add_child(ScreenKit.stat_bar(
			"Progress",
			int(round(100.0 * float(job.progress) / float(job.target_quantity)))
		))
	if running:
		var give_up := BusinessUIKit.button("GIVE IT UP", 140.0)
		give_up.pressed.connect(func() -> void:
			Underworld.abandon_job(job)
			_rebuild()
		)
		column.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("", 12, ScreenKit.MUTED), give_up,
		]))
	return card


func _risk_colour(risk: IllegalJobData.Risk) -> Color:
	match risk:
		IllegalJobData.Risk.LOW:
			return ScreenKit.MUTED
		IllegalJobData.Risk.MEDIUM:
			return ScreenKit.TEXT
		IllegalJobData.Risk.HIGH:
			return Color(0.933, 0.702, 0.318)
		_:
			return ScreenKit.BAD


# --- Earnings ------------------------------------------------------------

func _build_earnings() -> void:
	_body.add_child(ScreenKit.heading("ILLEGAL EARNINGS"))
	var total := Underworld.total_illegal_income()
	if total <= 0:
		_body.add_child(BusinessUIKit.label(
			"Nothing yet. Everything you have, you earned.", 14, ScreenKit.MUTED
		))
	for category: CrimeData.Income in CrimeData.INCOME_NAMES:
		if category == CrimeData.Income.NONE:
			continue
		var amount := Underworld.earnings_of(category)
		if amount <= 0:
			continue
		_body.add_child(ScreenKit.row(
			CrimeData.income_name(category), ScreenKit.money(amount)
		))
	_body.add_child(ScreenKit.row("Total", ScreenKit.money(total), true))

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("AND THE LEGITIMATE SIDE"))
	# §93 — the two figures side by side is the whole point of tracking them
	# separately, and the comparison is the player's own business.
	var legal := maxi(EconomyManager.total_income - total, 0)
	_body.add_child(ScreenKit.row("Legal income", ScreenKit.money(legal)))
	_body.add_child(ScreenKit.row("Illegal income", ScreenKit.money(total)))
	_body.add_child(BusinessUIKit.label(
		"Both spend the same. Only one of them is safe.", 12, ScreenKit.MUTED
	))
