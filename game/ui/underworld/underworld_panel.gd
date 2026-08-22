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

## Phase R adds REQUESTS and CAREER (§87). Six tabs is the limit of what this
## frame reads comfortably, which is why the career tab holds the paths rather
## than each getting one of its own.
enum Page { STANDING, CONTACTS, JOBS, REQUESTS, CAREER, EARNINGS }

const PAGE_NAMES := {
	Page.STANDING: "STANDING",
	Page.CONTACTS: "CONTACTS",
	Page.JOBS: "JOBS",
	Page.REQUESTS: "REQUESTS",
	Page.CAREER: "CAREER",
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
		var button := BusinessUIKit.button(String(PAGE_NAMES[page]), 96.0)
		button.disabled = page == _page
		button.pressed.connect(func() -> void: show_tab(page))
		_tabs.add_child(button)

	match _page:
		Page.CONTACTS:
			_build_contacts()
		Page.JOBS:
			_build_jobs()
		Page.REQUESTS:
			_build_requests()
		Page.CAREER:
			_build_career()
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
	if not dealing:
		column.add_child(BusinessUIKit.label(contact.closed_line, 12, ScreenKit.MUTED))
		column.add_child(BusinessUIKit.label(
			"Needs %d reputation  ·  you have %d" % [
				contact.reputation_required, Underworld.reputation
			], 12, ScreenKit.MUTED
		))
		return card

	# §89 — what this particular person makes of you, which is not the same as
	# what the street does.
	var link := Underworld.relationship(contact.contact_id)
	column.add_child(ScreenKit.stat_bar("Trust", link.trust))
	column.add_child(ScreenKit.row(
		"Standing with them",
		"%d / %d  ·  %s" % [
			link.trust, ContactRelationship.MAX_TRUST, link.tier_name().to_upper()
		]
	))
	var chain := Underworld.chain_for(contact.contact_id)
	column.add_child(ScreenKit.row(
		"Work offered", chain.display_name if chain != null else "Nothing yet"
	))
	var offers := Underworld.jobs_from(contact.contact_id).size()
	column.add_child(ScreenKit.row("On the table", "%d" % offers))
	var request := Underworld.request_from(contact.contact_id)
	if request != null:
		column.add_child(ScreenKit.row("Asking for", request.headline()))
	var next_rung := Underworld.next_chain_for(contact.contact_id)
	if next_rung != null:
		column.add_child(BusinessUIKit.label(
			"Next: %s — needs %d reputation and %d trust." % [
				next_rung.display_name, next_rung.reputation_required,
				next_rung.trust_required
			], 12, ScreenKit.MUTED
		))
	if link.jobs_done > 0 or link.jobs_failed > 0:
		column.add_child(BusinessUIKit.label(
			"%d done, %d gone wrong, %s paid out." % [
				link.jobs_done, link.jobs_failed, ScreenKit.money(link.total_paid)
			], 12, ScreenKit.MUTED
		))
	return card


# --- Requests ------------------------------------------------------------

func _build_requests() -> void:
	var asks := Underworld.requests()
	if asks.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Nobody has asked you for anything. Go and see them — work does not "
			+ "come to you.", 14, ScreenKit.MUTED
		))
		return
	_body.add_child(ScreenKit.heading("WANTED"))
	for request in asks:
		_body.add_child(_request_card(request))


func _request_card(request: ContactRequest) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	var contact := Underworld.contact_by_id(request.contact_id)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(request.headline(), 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(
			contact.display_name if contact != null else "", 13, ScreenKit.ACCENT
		),
	]))
	column.add_child(ScreenKit.row("Pays", "+%d%% over the usual" % roundi(request.bonus * 100.0)))
	if request.minimum_condition > 0.0:
		column.add_child(ScreenKit.row("Condition", request.condition_label()))
	column.add_child(ScreenKit.row(
		"Stands for", "%d day%s" % [
			request.days_left(TimeManager.day_index),
			"" if request.days_left(TimeManager.day_index) == 1 else "s"
		]
	))
	column.add_child(ScreenKit.row("Trust", "+%d" % request.trust_reward))
	return card


# --- Career --------------------------------------------------------------

func _build_career() -> void:
	var career := Underworld.career
	_body.add_child(ScreenKit.heading("WHAT YOU ARE KNOWN FOR"))
	var speciality := career.speciality()
	_body.add_child(ScreenKit.row(
		"Speciality", CriminalCareer.path_name(speciality)
	))
	_body.add_child(BusinessUIKit.label(
		"Nothing is chosen here. It is whatever you have actually done most of.",
		12, ScreenKit.MUTED
	))

	_body.add_child(ScreenKit.heading("PATHS"))
	for path in [
		CriminalCareer.Path.GOODS, CriminalCareer.Path.VEHICLE,
		CriminalCareer.Path.CONTRACT,
	]:
		_body.add_child(_path_card(career, path))

	_body.add_child(ScreenKit.heading("RECORD OF WORK"))
	_body.add_child(ScreenKit.row("Jobs finished", "%d" % career.total_jobs()))
	_body.add_child(ScreenKit.row("Orders filled", "%d" % career.requests_filled))
	_body.add_child(ScreenKit.row("Gone wrong", "%d" % career.jobs_failed))
	_body.add_child(ScreenKit.row("Walked away from", "%d" % career.jobs_abandoned))
	_body.add_child(ScreenKit.row("Best single payout", ScreenKit.money(career.best_single_payout)))


func _path_card(career: CriminalCareer, path: CriminalCareer.Path) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(
			CriminalCareer.path_name(path), 15, ScreenKit.TEXT
		),
		BusinessUIKit.value_label(career.rank_name(path), 13, ScreenKit.ACCENT),
	]))
	column.add_child(ScreenKit.row("Jobs", "%d" % career.count_of(path)))
	var togo := career.to_next_rank(path)
	column.add_child(BusinessUIKit.label(
		"As high as it goes." if togo < 0 else "%d more for the next step." % togo,
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
