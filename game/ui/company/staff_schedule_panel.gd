class_name StaffSchedulePanel
extends Control
## One person's week, and where they work it.
##
## Phase H gave everybody one shift and a pair of spin boxes. A company with a
## restaurant that opens for lunch and dinner needs more than that, and the
## moment somebody can work at two branches it needs checking as well as
## setting — hence the warnings under the rota rather than a silent accept.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _worker: EmployeeData = null
## The shift being added, held while the player fills it in.
var _draft_day: int = ShiftSlot.EVERY_DAY
var _draft_start: int = 9
var _draft_end: int = 17
var _draft_role: int = 0
var _transferring: bool = false


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(820, 620))
	_body = ScreenKit.scroller(_parts["body"])


func is_open() -> bool:
	return visible


func open(worker: EmployeeData) -> void:
	if worker == null:
		return
	_worker = worker
	_draft_role = int(worker.role)
	_transferring = false
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_worker = null
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()
	if _worker == null:
		return

	var home := BusinessManager.by_id(_worker.assigned_business)
	_parts["title"].text = _worker.employee_name.to_upper()
	_parts["subtitle"].text = "%s  ·  %s  ·  $%d/hr  ·  %.0f hours a week" % [
		_worker.get_role_name(),
		home.business_name if home != null else "Unassigned",
		_worker.hourly_wage, _worker.weekly_hours(),
	]
	_parts["status"].text = ""

	if _transferring:
		_build_transfer(home)
		return

	_build_week()
	_build_new_shift(home)

	var problems := CompanyManager.schedule_problems(_worker)
	if not problems.is_empty():
		_body.add_child(ScreenKit.spacer(8))
		_body.add_child(ScreenKit.heading("PROBLEMS WITH THIS ROTA"))
		for line in problems:
			_body.add_child(BusinessUIKit.label(line, 13, ScreenKit.BAD))

	if home != null:
		var gaps := CompanyManager.staffing_gaps(home)
		if not gaps.is_empty():
			_body.add_child(ScreenKit.spacer(8))
			_body.add_child(ScreenKit.heading("GAPS AT %s" % home.business_name.to_upper()))
			for line in gaps:
				_body.add_child(BusinessUIKit.label(line, 13, ScreenKit.BAD))

	var transfer := BusinessUIKit.button("TRANSFER", 150.0)
	transfer.disabled = BusinessManager.owned_count() < 2
	transfer.pressed.connect(func() -> void:
		_transferring = true
		AudioManager.play_ui(&"ui_click")
		_rebuild()
	)
	_parts["actions"].add_child(transfer)
	_add_close()


func _build_week() -> void:
	_body.add_child(ScreenKit.heading("THE WEEK"))
	var rota := _worker.weekly_shifts()
	if rota.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Not scheduled. They are on the payroll and never at work.", 14, ScreenKit.BAD
		))
		return
	for i in rota.size():
		var slot: ShiftSlot = rota[i]
		var at := BusinessManager.by_id(
			slot.business_id if slot.business_id != &"" else _worker.assigned_business
		)
		var remove := BusinessUIKit.button("REMOVE", 100.0)
		var index := i
		remove.pressed.connect(func() -> void:
			if _worker.remove_shift(index):
				AudioManager.play_ui(&"ui_back")
				BusinessManager.business_changed.emit(BusinessManager.by_id(
					_worker.assigned_business
				))
				_rebuild()
		)
		_body.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(slot.day_name(), 14, ScreenKit.TEXT),
			BusinessUIKit.value_label(slot.time_text(), 14, ScreenKit.ACCENT),
			BusinessUIKit.value_label(
				EmployeeData.name_of_role(slot.role), 13, ScreenKit.MUTED
			),
			BusinessUIKit.value_label(
				at.business_name if at != null else "—", 13, ScreenKit.MUTED
			),
			remove,
		]))


func _build_new_shift(home: BusinessInstance) -> void:
	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("ADD A SHIFT"))

	var day := OptionButton.new()
	day.add_item("Every day", 0)
	for i in 7:
		day.add_item(TimeManager.DAY_NAMES[i].capitalize(), i + 1)
	day.selected = 0 if _draft_day == ShiftSlot.EVERY_DAY else _draft_day + 1
	day.item_selected.connect(func(chosen: int) -> void:
		_draft_day = ShiftSlot.EVERY_DAY if chosen == 0 else chosen - 1
	)

	var start := BusinessUIKit.spin(0, 23, float(_draft_start), 1)
	start.value_changed.connect(func(value: float) -> void: _draft_start = int(value))
	var finish := BusinessUIKit.spin(0, 24, float(_draft_end), 1)
	finish.value_changed.connect(func(value: float) -> void: _draft_end = int(value))

	var role := OptionButton.new()
	var roles: Array[int] = []
	var definition := home.type_data() if home != null else null
	var index := 0
	for value: int in EmployeeData.ROLE_NAMES:
		if definition != null and not definition.uses_role(value):
			continue
		role.add_item(String(EmployeeData.ROLE_NAMES[value]), index)
		roles.append(value)
		if value == _draft_role:
			role.selected = index
		index += 1
	role.item_selected.connect(func(chosen: int) -> void:
		_draft_role = roles[chosen] if chosen < roles.size() else int(_worker.role)
	)

	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Day", 13, ScreenKit.MUTED), day,
	]))
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("From / to", 13, ScreenKit.MUTED), start, finish,
	]))
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Doing", 13, ScreenKit.MUTED), role,
	]))

	var add := BusinessUIKit.button("ADD SHIFT", 150.0)
	add.pressed.connect(_add_shift)
	_parts["actions"].add_child(add)


func _add_shift() -> void:
	var slot := ShiftSlot.make(
		_draft_start, _draft_end, _draft_role, _draft_day, _worker.assigned_business
	)
	if not slot.is_valid():
		_note("A shift needs to start and end at different times.", ScreenKit.BAD)
		AudioManager.play_ui(&"ui_error")
		return
	# Checked before anything is written, so a clashing rota is refused rather
	# than saved and complained about afterwards.
	if not CompanyManager.can_add_shift(_worker, slot):
		_note("That overlaps a shift they already work.", ScreenKit.BAD)
		AudioManager.play_ui(&"ui_error")
		return
	_worker.add_shift(slot)
	AudioManager.play_ui(&"ui_confirm")
	BusinessManager.business_changed.emit(BusinessManager.by_id(_worker.assigned_business))
	_rebuild()


func _build_transfer(home: BusinessInstance) -> void:
	_body.add_child(ScreenKit.heading("MOVE THEM WHERE?"))
	_body.add_child(BusinessUIKit.label(
		"The same person arrives — their skills, their history and their rota go "
		+ "with them, and %s stops having them." % (
			home.business_name if home != null else "the old branch"
		), 13, ScreenKit.MUTED
	))
	_body.add_child(ScreenKit.spacer(6))

	var offered := 0
	for business in BusinessManager.get_businesses():
		if home != null and business.business_id == home.business_id:
			continue
		var definition := business.type_data()
		var welcome := definition == null or definition.uses_role(int(_worker.role))
		var button := BusinessUIKit.button("TRANSFER", 130.0)
		button.disabled = not welcome
		button.pressed.connect(func() -> void: _do_transfer(business))
		_body.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(business.business_name, 14, ScreenKit.TEXT),
			BusinessUIKit.value_label(
				definition.display_name if definition != null else "", 13, ScreenKit.MUTED
			),
			BusinessUIKit.value_label(
				"" if welcome else "no use for a %s" % _worker.get_role_name().to_lower(),
				12, ScreenKit.BAD
			),
			button,
		]))
		offered += 1
	if offered == 0:
		_body.add_child(BusinessUIKit.label("Nowhere else to send them.", 14, ScreenKit.MUTED))

	var back := BusinessUIKit.button("BACK", 120.0)
	back.pressed.connect(func() -> void:
		_transferring = false
		AudioManager.play_ui(&"ui_back")
		_rebuild()
	)
	_parts["actions"].add_child(back)
	_add_close()


func _do_transfer(target: BusinessInstance) -> void:
	var result := CompanyManager.transfer_employee(_worker, target)
	if result != CompanyManager.TransferResult.OK:
		AudioManager.play_ui(&"ui_error")
		_note(CompanyManager.describe_transfer(result), ScreenKit.BAD)
		return
	AudioManager.play_ui(&"ui_confirm")
	_transferring = false
	_rebuild()


func _add_close() -> void:
	var close_button := BusinessUIKit.button("CLOSE", 120.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)
