class_name ObjectiveBanner
extends VBoxContainer
## The short list in the corner: what the game is suggesting right now.
##
## §95 — a few, never forty. §96 — it is the same list whether it is coming
## from the opening guide or from the goals screen, because to the player they
## are the same thing: the next thing worth doing.
##
## The guide takes precedence while it is running, and once it is done the
## pinned goals take the space over. There is never a moment where both are
## shown, and never a moment where the corner is arguing with itself.

## Refreshed on a timer as well as on signals, because most of what it shows
## is a live number rather than an event.
const REFRESH_INTERVAL := 1.0

var _title: Label = null
var _rows: VBoxContainer = null
var _timer: float = 0.0


func _ready() -> void:
	name = "ObjectiveBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	alignment = BoxContainer.ALIGNMENT_BEGIN

	_title = BusinessUIKit.label("", 12, Palette.UI_ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 1)
	add_child(_rows)

	Progression.pinned_changed.connect(_refresh)
	Progression.goals_changed.connect(_refresh)
	Onboarding.step_changed.connect(_on_step_changed)
	Onboarding.finished.connect(_refresh)
	Onboarding.skipped.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	_refresh()


func _on_step_changed(_step: OnboardingStep) -> void:
	_refresh()


func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	if Onboarding.is_running():
		_show_guide()
	else:
		_show_goals()
	visible = not _rows.get_child_count() == 0


func _show_guide() -> void:
	var step: OnboardingStep = Onboarding.current()
	if step == null:
		return
	_title.text = "GETTING STARTED  %d/%d" % [
		Onboarding.step_number(), Onboarding.step_count()
	]
	_add_line(step.instruction, Palette.UI_TEXT)
	var hint := Onboarding.visible_hint()
	if not hint.is_empty():
		_add_line(hint, Palette.UI_MUTED)


func _show_goals() -> void:
	var goals := Progression.pinned()
	if goals.is_empty():
		_title.text = ""
		return
	_title.text = "GOALS"
	for goal in goals:
		var value := Progression.value_for(goal.metric)
		var text := goal.label
		# The number is only shown where it means something. A goal counted in
		# ones reads worse with "0 / 1" after it than without.
		if goal.target > 1.0:
			text += "   %s" % _amount(goal, value)
		_add_line(text, Palette.UI_TEXT)


func _amount(goal: Goal, value: float) -> String:
	if goal.is_money:
		return "%s/%s" % [
			BusinessUIKit.money(int(value)), BusinessUIKit.money(int(goal.target))
		]
	return "%d/%d" % [int(value), int(goal.target)]


func _add_line(text: String, colour: Color) -> void:
	var label := BusinessUIKit.label(text, 12, colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300.0, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(label)


## What the banner is saying, as text. The tests read this rather than walking
## the labels, so a change to the layout does not break them.
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _rows.get_children():
		var label := child as Label
		if label != null:
			out.append(label.text)
	return out


func heading() -> String:
	return _title.text
