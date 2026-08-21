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
## What is being opened here, and under whose name. Null brand means a new one.
var _chosen_type: StringName = &""
var _chosen_brand: BrandData = null


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
	_add_row("Size", "%s · %d m²" % [_property.size_label(), _property.floor_area])
	_add_row("Location", "%s · up to %d customers" % [
		_property.location_label(), _property.customer_capacity
	])
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

	# What this unit is zoned for decides what may open in it. A nightclub does
	# not go in a corner shop, and the player is told that here rather than
	# refused after they have typed a name.
	var allowed := _property.allowed_business_types()
	if allowed.is_empty():
		_rows.add_child(BusinessUIKit.label(
			"Nothing you can open trades from a unit like this one.",
			14, BusinessUIKit.BAD
		))
		var back := BusinessUIKit.button("CLOSE", 120.0)
		back.pressed.connect(func() -> void: GameManager.close_menus())
		_actions.add_child(back)
		return
	if _chosen_type == &"" or not _type_allowed(allowed, _chosen_type):
		_chosen_type = allowed[0].type_id
		_chosen_brand = null

	_rows.add_child(BusinessUIKit.heading("Business type"))
	for definition in allowed:
		var pick := BusinessUIKit.button(
			"OPEN" if definition.type_id != _chosen_type else "CHOSEN", 100.0
		)
		pick.disabled = definition.type_id == _chosen_type
		var id := definition.type_id
		pick.pressed.connect(func() -> void:
			_chosen_type = id
			_chosen_brand = null
			_rebuild()
		)
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(definition.display_name.to_upper(), 15),
			BusinessUIKit.value_label(
				"needs %s" % BusinessUIKit.money(definition.startup_cost),
				13, BusinessUIKit.MUTED
			),
			pick,
		]))
		_rows.add_child(BusinessUIKit.label(
			definition.description, 12, BusinessUIKit.MUTED
		))

	var chosen := BusinessCatalogue.by_id(_chosen_type)
	_build_brand_choice(chosen)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.add_child(BusinessUIKit.label(
		"Business name" if _chosen_brand == null else "Trading as",
		14, BusinessUIKit.MUTED
	))
	_name_field = LineEdit.new()
	_name_field.text = (
		_chosen_brand.branch_name(_property.address) if _chosen_brand != null
		else _default_name(chosen)
	)
	_name_field.editable = _chosen_brand == null
	_name_field.custom_minimum_size = Vector2(300, 32)
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_field)
	_rows.add_child(name_row)

	var create := BusinessUIKit.button("CREATE BUSINESS", 190.0)
	create.disabled = chosen != null and not EconomyManager.can_afford(chosen.startup_cost)
	create.pressed.connect(_on_create_pressed)
	_actions.add_child(create)

	var cancel := BusinessUIKit.button("CANCEL", 120.0)
	cancel.pressed.connect(func() -> void: GameManager.close_menus())
	_actions.add_child(cancel)

	if create.disabled and chosen != null:
		_status.text = "A %s needs %s behind it before you open the doors." % [
			chosen.display_name.to_lower(), BusinessUIKit.money(chosen.startup_cost)
		]
		_status.add_theme_color_override("font_color", BusinessUIKit.BAD)
		return
	_status.text = "Creating a business costs nothing. You fund it yourself afterwards."
	_status.add_theme_color_override("font_color", BusinessUIKit.MUTED)


## Whether an existing chain of this kind can take another branch, and which.
func _build_brand_choice(definition: BusinessTypeData) -> void:
	if definition == null:
		return
	var options := CompanyManager.brands_of_type(definition.type_id)
	if options.is_empty():
		return
	_rows.add_child(BusinessUIKit.heading("Under which name"))

	var fresh := BusinessUIKit.button(
		"CHOSEN" if _chosen_brand == null else "NEW BRAND", 130.0
	)
	fresh.disabled = _chosen_brand == null
	fresh.pressed.connect(func() -> void:
		_chosen_brand = null
		_rebuild()
	)
	_rows.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("A new brand", 15),
		BusinessUIKit.value_label("its own name and reputation", 12, BusinessUIKit.MUTED),
		fresh,
	]))

	for brand in options:
		var join := BusinessUIKit.button(
			"CHOSEN" if _chosen_brand == brand else "BRANCH OF", 130.0
		)
		join.disabled = _chosen_brand == brand
		var picked := brand
		join.pressed.connect(func() -> void:
			_chosen_brand = picked
			_rebuild()
		)
		var swatch := ColorRect.new()
		swatch.color = brand.brand_color
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_rows.add_child(BusinessUIKit.row([
			swatch,
			BusinessUIKit.stretch_label(brand.brand_name, 15),
			BusinessUIKit.value_label(
				"%d branch%s  ·  reputation %d" % [
					brand.branch_count(), "" if brand.branch_count() == 1 else "es",
					roundi(brand.brand_reputation)
				], 12, BusinessUIKit.MUTED
			),
			join,
		]))


func _type_allowed(allowed: Array[BusinessTypeData], type_id: StringName) -> bool:
	for definition in allowed:
		if definition.type_id == type_id:
			return true
	return false


func _default_name(definition: BusinessTypeData) -> String:
	return definition.display_name if definition != null else "Business"


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
	var definition := BusinessCatalogue.by_id(_chosen_type)
	if definition == null:
		return
	if not EconomyManager.can_afford(definition.startup_cost):
		_status.text = "You need %s to open a %s." % [
			BusinessUIKit.money(definition.startup_cost), definition.display_name.to_lower()
		]
		_status.add_theme_color_override("font_color", BusinessUIKit.BAD)
		return
	var business := CompanyManager.found_business(
		_name_field.text if _name_field != null else "", _chosen_type, _property, _chosen_brand
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
