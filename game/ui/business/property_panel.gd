extends Control
## The letting details for a commercial unit, and the form that turns one into a
## business.
##
## Two pages rather than two screens, because they are two steps of one errand:
## the player signs for the unit and then names what they are opening in it. The
## door decides which page it opens on.

signal opened()
signal closed()

enum Page { LETTING, CREATE }

@onready var _title: Label = %PropertyTitle
@onready var _subtitle: Label = %PropertySubtitle
@onready var _rows: VBoxContainer = %PropertyRows
@onready var _status: Label = %PropertyStatus
@onready var _actions: HBoxContainer = %PropertyActions

var _property: CommercialProperty = null
var _page: Page = Page.LETTING
var _name_field: LineEdit = null


func _ready() -> void:
	visible = false
	EconomyManager.cash_changed.connect(_on_cash_changed)


func is_open() -> bool:
	return visible


func open(property: CommercialProperty) -> void:
	if property == null:
		return
	_property = property
	_page = Page.LETTING if property.is_vacant() else Page.CREATE
	_status.text = ""
	_rebuild()
	visible = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_property = null
	_name_field = null
	closed.emit()


# --- Pages ---------------------------------------------------------------

func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for child in _actions.get_children():
		child.queue_free()

	if _page == Page.LETTING:
		_build_letting()
	else:
		_build_create()


func _build_letting() -> void:
	_title.text = "AVAILABLE FOR RENT"
	_subtitle.text = _property.address

	_add_row("Property", _property.property_type)
	_add_row("Size", "%s · %d m²" % [_property.size_label, _property.floor_area])
	_add_row("Rent", "%s every %d days" % [
		BusinessUIKit.money(_property.rent_amount), _property.rent_interval_days
	])
	_add_row("Deposit", BusinessUIKit.money(_property.deposit))
	_add_row("Move-in cost", BusinessUIKit.money(_property.move_in_cost()), true)
	_add_row("Status", "Vacant")
	_add_row("Your cash", EconomyManager.get_cash_string())

	var rent := BusinessUIKit.button("RENT PROPERTY", 170.0)
	rent.disabled = not PropertyManager.can_afford(_property)
	rent.pressed.connect(_on_rent_pressed)
	_actions.add_child(rent)

	var cancel := BusinessUIKit.button("CANCEL", 120.0)
	cancel.pressed.connect(func() -> void: GameManager.close_menus())
	_actions.add_child(cancel)

	if not PropertyManager.can_afford(_property):
		_status.text = "You need %s to sign for this unit." % BusinessUIKit.money(
			_property.move_in_cost()
		)
		_status.add_theme_color_override("font_color", BusinessUIKit.BAD)


func _build_create() -> void:
	_title.text = "CREATE BUSINESS"
	_subtitle.text = _property.address

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.add_child(BusinessUIKit.label("Business name", 14, BusinessUIKit.MUTED))
	_name_field = LineEdit.new()
	_name_field.text = "Silas Market"
	_name_field.custom_minimum_size = Vector2(260, 32)
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_field)
	_rows.add_child(name_row)

	# One type today. The list is the extension point, so it is built from the
	# catalogue rather than hard-coded to it.
	_rows.add_child(BusinessUIKit.heading("Business type"))
	for definition in BusinessCatalogue.TYPES:
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(definition.display_name.to_upper(), 15),
			BusinessUIKit.label(definition.description, 12, BusinessUIKit.MUTED),
		]))

	var create := BusinessUIKit.button("CREATE BUSINESS", 190.0)
	create.pressed.connect(_on_create_pressed)
	_actions.add_child(create)

	var cancel := BusinessUIKit.button("CANCEL", 120.0)
	cancel.pressed.connect(func() -> void: GameManager.close_menus())
	_actions.add_child(cancel)

	_status.text = "Creating a business costs nothing. You fund it yourself afterwards."
	_status.add_theme_color_override("font_color", BusinessUIKit.MUTED)


func _add_row(name: String, value: String, emphasis: bool = false) -> void:
	_rows.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(name, 14, BusinessUIKit.MUTED),
		BusinessUIKit.value_label(
			value, 15 if emphasis else 14,
			BusinessUIKit.ACCENT if emphasis else BusinessUIKit.TEXT
		),
	]))


# --- Actions -------------------------------------------------------------

func _on_rent_pressed() -> void:
	var result := PropertyManager.lease(_property)
	if result != PropertyManager.LeaseResult.OK:
		_status.text = PropertyManager.describe(result)
		_status.add_theme_color_override("font_color", BusinessUIKit.BAD)
		return
	# Straight on to naming it: signing a lease and opening a business are one
	# errand as far as the player is concerned.
	_page = Page.CREATE
	_status.text = ""
	_rebuild()


func _on_create_pressed() -> void:
	var business := BusinessManager.create_business(
		_name_field.text if _name_field != null else "", BusinessCatalogue.first().type_id, _property
	)
	if business == null:
		_status.text = "Could not create the business."
		_status.add_theme_color_override("font_color", BusinessUIKit.BAD)
		return
	GameManager.close_menus()
	GameManager.request_screen(&"business", null, null)


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible and _page == Page.LETTING:
		_rebuild()
