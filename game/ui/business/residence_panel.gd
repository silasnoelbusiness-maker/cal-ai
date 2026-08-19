extends Control
## The letting details for somewhere to live.
##
## The same shape as the commercial property screen, because it is the same
## errand with different consequences: sign for it, and then decide whether it is
## where you sleep.

signal opened()
signal closed()

@onready var _title: Label = %ResidenceTitle
@onready var _subtitle: Label = %ResidenceSubtitle
@onready var _rows: VBoxContainer = %ResidenceRows
@onready var _status: Label = %ResidenceStatus
@onready var _actions: HBoxContainer = %ResidenceActions

var _residence: ResidenceProperty = null


func _ready() -> void:
	visible = false
	EconomyManager.cash_changed.connect(_on_cash_changed)


func is_open() -> bool:
	return visible


func open(residence: ResidenceProperty) -> void:
	if residence == null:
		return
	_residence = residence
	_status.text = ""
	_rebuild()
	visible = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_residence = null
	closed.emit()


func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for child in _actions.get_children():
		child.queue_free()

	_title.text = _residence.display_name.to_upper()
	_subtitle.text = _residence.address

	_add_row("Size", _residence.size_label)
	_add_row("Amenities", _residence.amenities)
	_add_row("Rent", "$%d every %d days" % [_residence.rent_amount, _residence.rent_interval_days])
	_add_row("Deposit", "$%d" % _residence.deposit)
	if not _residence.is_leased_by_player():
		_add_row("Move-in cost", "$%d" % _residence.move_in_cost(), true)
	_add_row("Your cash", EconomyManager.get_cash_string())
	_add_row(
		"Status",
		"YOUR HOME" if _residence.is_current_home()
		else ("Leased" if _residence.is_leased_by_player() else "To let")
	)

	if not _residence.is_leased_by_player():
		var rent := BusinessUIKit.button("RENT", 150.0)
		rent.disabled = not EconomyManager.can_afford(_residence.move_in_cost())
		rent.pressed.connect(_on_rent_pressed)
		_actions.add_child(rent)
		if rent.disabled:
			_note("You need $%d to sign for this." % _residence.move_in_cost(), BusinessUIKit.BAD)
	else:
		if not _residence.is_current_home():
			var home := BusinessUIKit.button("SET AS HOME", 170.0)
			home.pressed.connect(_on_set_home)
			_actions.add_child(home)
		var end := BusinessUIKit.button("END LEASE", 150.0)
		end.disabled = _residence.is_current_home()
		end.pressed.connect(_on_end_lease)
		_actions.add_child(end)
		if end.disabled:
			_note("Move somewhere else before giving this up.", BusinessUIKit.MUTED)

	var cancel := BusinessUIKit.button("CLOSE", 120.0)
	cancel.pressed.connect(func() -> void: GameManager.close_menus())
	_actions.add_child(cancel)


func _add_row(name: String, value: String, emphasis: bool = false) -> void:
	_rows.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(name, 14, BusinessUIKit.MUTED),
		BusinessUIKit.value_label(
			value, 15 if emphasis else 14,
			BusinessUIKit.ACCENT if emphasis else BusinessUIKit.TEXT
		),
	]))


func _note(text: String, colour: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", colour)


func _on_rent_pressed() -> void:
	if not PropertyManager.lease_residence(_residence):
		_note("That did not go through.", BusinessUIKit.BAD)
		return
	_rebuild()


func _on_set_home() -> void:
	_residence.set_as_home()
	GameManager.notify("HOME SET\n%s" % _residence.address.to_upper(), GameManager.Tone.GOOD)
	_rebuild()


func _on_end_lease() -> void:
	_residence.end_lease()
	GameManager.notify("LEASE ENDED\n%s" % _residence.address.to_upper(), GameManager.Tone.INFO)
	_rebuild()


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible:
		_rebuild()
