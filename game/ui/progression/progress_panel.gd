class_name ProgressPanel
extends Control
## Where the player is going, where they have been, and how to work the game.
##
## §95 asks that goals be shown a few at a time rather than forty; §97 that
## milestones be unified where practical; §98 for a journey the player can look
## back over; §157 for statistics; §84 for a guide. Those are four readings of
## one question — "how am I doing?" — so they are four tabs of one screen
## rather than four screens the player has to learn.
##
## Nothing on here changes the game except pinning, and pinning changes only
## what the HUD shows.

signal opened()
signal closed()

enum Page { GOALS, JOURNAL, STATISTICS, GUIDE }

const PAGE_NAMES := {
	Page.GOALS: "GOALS",
	Page.JOURNAL: "JOURNEY",
	Page.STATISTICS: "STATISTICS",
	Page.GUIDE: "GUIDE",
}

## How many goals one tier shows before it is collapsed to a count. Keeps the
## list honest without turning it into a wall.
const GOALS_PER_TIER := 6

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _tabs: HBoxContainer = null
var _page: Page = Page.GOALS
## Which track the goals tab is showing. Both exist at once (§94), so this is a
## filter on one list and never a choice the player is locked into.
var _track: int = Goal.Track.LEGAL


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(920, 660))
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 6)
	_parts["body"].add_child(_tabs)
	_body = ScreenKit.scroller(_parts["body"])
	Progression.goals_changed.connect(_on_changed)
	Progression.pinned_changed.connect(_on_changed)


func is_open() -> bool:
	return visible


func open(page: Page = Page.GOALS) -> void:
	_page = page
	Progression.evaluate()
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


func _on_changed() -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _tabs.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	_parts["title"].text = "PROGRESS"
	_parts["subtitle"].text = "%s  ·  %s" % [
		Goal.tier_name(Goal.Track.LEGAL, Progression.tier_on(Goal.Track.LEGAL)),
		Goal.tier_name(Goal.Track.CRIMINAL, Progression.tier_on(Goal.Track.CRIMINAL)),
	]
	_parts["status"].text = "%d of %d goals reached" % [
		Progression.completed_count(), Progression.all_goals().size()
	]

	for page: Page in PAGE_NAMES:
		var button := BusinessUIKit.button(String(PAGE_NAMES[page]), 118.0)
		button.disabled = page == _page
		button.pressed.connect(func() -> void: show_tab(page))
		_tabs.add_child(button)

	match _page:
		Page.JOURNAL:
			_build_journal()
		Page.STATISTICS:
			_build_statistics()
		Page.GUIDE:
			_build_guide()
		_:
			_build_goals()

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


# --- Goals ---------------------------------------------------------------

func _build_goals() -> void:
	_body.add_child(ScreenKit.heading("PINNED"))
	var pinned := Progression.pinned()
	if pinned.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Nothing pinned. Pin up to three and they show on the HUD.",
			13, BusinessUIKit.MUTED
		))
	for goal in pinned:
		_body.add_child(_goal_row(goal))

	_body.add_child(ScreenKit.spacer(10))
	var switcher := HBoxContainer.new()
	switcher.add_theme_constant_override("separation", 6)
	for track: int in [Goal.Track.LEGAL, Goal.Track.CRIMINAL]:
		var button := BusinessUIKit.button(
			"LEGAL" if track == Goal.Track.LEGAL else "CRIMINAL", 130.0
		)
		button.disabled = track == _track
		button.pressed.connect(func() -> void:
			_track = track
			_rebuild()
		)
		switcher.add_child(button)
	_body.add_child(switcher)

	for tier: int in [
		Goal.Tier.STARTING, Goal.Tier.ENTREPRENEUR, Goal.Tier.OWNER,
		Goal.Tier.CEO, Goal.Tier.TYCOON, Goal.Tier.MOGUL,
	]:
		var in_tier: Array[Goal] = []
		for goal in Progression.all_goals():
			if goal.track == _track and goal.tier == tier:
				in_tier.append(goal)
		if in_tier.is_empty():
			continue
		var done := 0
		for goal in in_tier:
			if Progression.is_complete(goal.goal_id):
				done += 1
		_body.add_child(ScreenKit.heading("%s  —  %d/%d" % [
			Goal.tier_name(_track, tier).to_upper(), done, in_tier.size()
		]))
		var shown := 0
		for goal in in_tier:
			if shown >= GOALS_PER_TIER:
				_body.add_child(BusinessUIKit.label(
					"and %d more" % (in_tier.size() - shown), 12, BusinessUIKit.MUTED
				))
				break
			_body.add_child(_goal_row(goal))
			shown += 1


func _goal_row(goal: Goal) -> PanelContainer:
	# Asked of the manager rather than taken from which list this row is in.
	# The pinned section also shows the game's own suggestions, and those had
	# an UNPIN button on them for something the player had never pinned.
	var is_pinned := Progression.is_pinned(goal.goal_id)
	var complete := Progression.is_complete(goal.goal_id)
	var value := Progression.value_for(goal.metric)
	var text := "DONE" if complete else _progress_text(goal, value)
	var colour := BusinessUIKit.GOOD if complete else BusinessUIKit.TEXT

	var children: Array = [
		BusinessUIKit.stretch_label(goal.label, 14, colour),
		BusinessUIKit.value_label(text, 13, BusinessUIKit.MUTED),
	]
	if not complete:
		var button := BusinessUIKit.button("UNPIN" if is_pinned else "PIN", 84.0)
		# The suggested list is not pinned, so its rows offer PIN even while
		# they are on screen — pressing it is what makes the choice the
		# player's and stops the list rearranging itself.
		# A full list still lets you take one off; it only refuses another on.
		button.disabled = not is_pinned and _pinned_by_player() >= Progression.MAX_PINNED
		button.pressed.connect(func() -> void:
			if Progression.is_pinned(goal.goal_id):
				Progression.unpin(goal.goal_id)
			else:
				Progression.pin(goal.goal_id)
		)
		children.append(button)
	return BusinessUIKit.row(children)


## How many the player has chosen, as against how many the game is suggesting.
func _pinned_by_player() -> int:
	var total := 0
	for goal in Progression.all_goals():
		if Progression.is_pinned(goal.goal_id):
			total += 1
	return total


func _progress_text(goal: Goal, value: float) -> String:
	if goal.is_money:
		return "%s / %s" % [
			BusinessUIKit.money(int(value)), BusinessUIKit.money(int(goal.target))
		]
	return "%d / %d" % [int(value), int(goal.target)]


# --- Journey -------------------------------------------------------------

func _build_journal() -> void:
	var entries := Progression.recent(60)
	if entries.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Nothing worth remembering yet.", 13, BusinessUIKit.MUTED
		))
		return
	_body.add_child(ScreenKit.heading("HOW YOU GOT HERE"))
	for entry in entries:
		var kind := int(entry.get("kind", 0))
		var colour := _colour_for(kind)
		var when := "Day %d, %02d:00" % [int(entry.get("day", 0)) + 1, int(entry.get("hour", 0))]
		var detail := String(entry.get("detail", ""))
		_body.add_child(BusinessUIKit.row([
			BusinessUIKit.label(when, 12, BusinessUIKit.MUTED),
			BusinessUIKit.stretch_label(String(entry.get("title", "")), 14, colour),
			BusinessUIKit.value_label(detail, 12, BusinessUIKit.MUTED),
		]))


## Colours the timeline by what kind of thing happened. A function rather than
## a table because the enum lives on an autoload, which a const cannot reach.
func _colour_for(kind: int) -> Color:
	match kind:
		Progression.Kind.GOAL:
			return Palette.MONEY
		Progression.Kind.MILESTONE, Progression.Kind.BUSINESS:
			return Palette.UI_ACCENT
		Progression.Kind.LEGAL, Progression.Kind.CRIMINAL:
			return Palette.LOSS
		Progression.Kind.LIFE:
			return Palette.UI_MUTED
	return Palette.UI_TEXT


# --- Statistics ----------------------------------------------------------

func _build_statistics() -> void:
	for group: StringName in LifeStats.COUNTERS:
		_body.add_child(ScreenKit.heading(
			String(LifeStats.GROUP_NAMES.get(group, "Life")).to_upper()
		))
		for entry in LifeStats.COUNTERS[group]:
			var key: StringName = entry[0]
			var value := LifeStats.get_counter(key)
			var text := (
				BusinessUIKit.money(value) if key == &"shift_income" else str(value)
			)
			_body.add_child(ScreenKit.row(String(entry[1]), text))

	_body.add_child(ScreenKit.heading("MONEY"))
	_body.add_child(ScreenKit.row("Earned, all told", ScreenKit.money(EconomyManager.total_income)))
	_body.add_child(ScreenKit.row("Of that, illegally", ScreenKit.money(EconomyManager.illegal_income)))
	_body.add_child(ScreenKit.row("Net worth", ScreenKit.money(BusinessManager.net_worth()), true))

	_body.add_child(ScreenKit.heading("BUSINESS"))
	for key: StringName in BusinessManager.STATISTIC_KEYS:
		_body.add_child(ScreenKit.row(
			String(key).capitalize(), str(BusinessManager.get_statistic(key))
		))

	_body.add_child(ScreenKit.heading("THE OTHER SIDE"))
	for key: StringName in CrimeManager.STATISTIC_KEYS:
		_body.add_child(ScreenKit.row(
			String(key).capitalize(), str(CrimeManager.get_statistic(key))
		))


# --- Guide ---------------------------------------------------------------

func _build_guide() -> void:
	if Onboarding.is_running():
		var step: OnboardingStep = Onboarding.current()
		_body.add_child(ScreenKit.heading("RIGHT NOW"))
		_body.add_child(ScreenKit.row(step.title, step.instruction))
		if not step.hint.is_empty():
			_body.add_child(BusinessUIKit.label(step.hint, 12, BusinessUIKit.MUTED))
		var skip := BusinessUIKit.button("SKIP THE GUIDE", 170.0)
		skip.pressed.connect(func() -> void:
			Onboarding.skip()
			_rebuild()
		)
		_body.add_child(skip)
	elif Onboarding.was_skipped():
		var resume := BusinessUIKit.button("BRING THE GUIDE BACK", 220.0)
		resume.pressed.connect(func() -> void:
			Onboarding.resume()
			_rebuild()
		)
		_body.add_child(resume)

	for section in HelpTopics.sections():
		_body.add_child(ScreenKit.heading(String(section["title"]).to_upper()))
		for line in section["lines"]:
			_body.add_child(BusinessUIKit.label(String(line), 13, BusinessUIKit.MUTED))
		_body.add_child(ScreenKit.spacer(6))
