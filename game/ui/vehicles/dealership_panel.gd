class_name DealershipPanel
extends Control
## The sales desk at Northline Motors.
##
## Three lists in one screen: what is new, what is on the used lot, and what the
## player already owns. Buying, part-exchanging and selling all happen here, and
## selling only happens here — a car has to be brought in, which is what stops
## the fleet being manageable from the far side of the city.

signal opened()
signal closed()

enum Tab { NEW, USED, MINE }

const TABS: Array[String] = ["NEW", "USED", "MY VEHICLES"]

var _parts: Dictionary = {}
var _tab_bar: TabBar = null
var _list: VBoxContainer = null
var _tab: Tab = Tab.NEW
## The two models being compared, as ids. Cleared when the screen closes.
var _compare: Array[StringName] = []
## Set when a purchase should take a car in part exchange.
var _trade: OwnedVehicle = null


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(900, 640))
	_build()
	EconomyManager.cash_changed.connect(_on_cash_changed)
	VehicleRegistry.fleet_changed.connect(_on_fleet_changed)


func is_open() -> bool:
	return visible


func open(tab: Tab = Tab.NEW) -> void:
	_tab = tab
	_compare.clear()
	_trade = null
	_tab_bar.current_tab = int(tab)
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_compare.clear()
	_trade = null
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _build() -> void:
	var body: VBoxContainer = _parts["body"]

	_tab_bar = TabBar.new()
	for tab in TABS:
		_tab_bar.add_tab(tab)
	_tab_bar.tab_changed.connect(_on_tab_changed)
	body.add_child(_tab_bar)

	_list = ScreenKit.scroller(body)

	var actions: HBoxContainer = _parts["actions"]
	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	actions.add_child(close_button)


func _on_tab_changed(index: int) -> void:
	_tab = index as Tab
	_compare.clear()
	_rebuild()


func _stock() -> Dealership:
	return get_tree().get_first_node_in_group(&"dealership_stock") as Dealership


func _rebuild() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()

	_parts["title"].text = "NORTHLINE MOTORS"
	_parts["subtitle"].text = "Riverside Drive  ·  Your cash: %s" % EconomyManager.get_cash_string()
	_parts["status"].text = ""

	# The comparison goes at the top rather than the bottom. A player who has
	# just pressed COMPARE wants to see the answer, not scroll past the list
	# they pressed it in to find it.
	if not _compare.is_empty():
		_build_comparison()

	match _tab:
		Tab.USED:
			_build_used()
		Tab.MINE:
			_build_mine()
		_:
			_build_new()


# --- The range -----------------------------------------------------------

func _build_new() -> void:
	if _trade != null:
		_list.add_child(ScreenKit.heading(
			"PART EXCHANGE: %s  ·  %s allowed" % [
				_trade.display_name().to_upper(), ScreenKit.money(_trade.dealer_offer())
			]
		))
	for model_id in VehicleCatalogue.purchasable_ids():
		_list.add_child(_model_row(model_id))


## One line per model: what it is, what it costs, and the two buttons that
## matter. The stats live behind COMPARE rather than being flattened into the
## row, because five numbers per row across ten rows is a spreadsheet.
func _model_row(model_id: StringName) -> PanelContainer:
	var definition := VehicleCatalogue.data_for(model_id)
	var price := definition.price_new
	var due := price - (_trade.dealer_offer() if _trade != null else 0)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(definition.display_name, 16, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(VehicleCatalogue.subtitle(model_id), 12, ScreenKit.MUTED))
	line.add_child(text)

	var money := VBoxContainer.new()
	money.add_child(BusinessUIKit.value_label(ScreenKit.money(price), 16, ScreenKit.TEXT))
	if _trade != null:
		money.add_child(BusinessUIKit.value_label(
			"due %s" % ScreenKit.money(maxi(due, 0)), 12,
			ScreenKit.GOOD if due <= 0 else ScreenKit.MUTED
		))
	line.add_child(money)

	var compare := BusinessUIKit.button(
		"COMPARING" if _compare.has(model_id) else "COMPARE", 130.0
	)
	compare.pressed.connect(func() -> void: _toggle_compare(model_id))
	line.add_child(compare)

	var buy := BusinessUIKit.button("BUY", 110.0)
	var payable := maxi(due, 0)
	buy.disabled = not EconomyManager.can_afford(payable)
	buy.pressed.connect(func() -> void: _confirm_buy_new(model_id, price))
	line.add_child(buy)
	return frame


func _confirm_buy_new(model_id: StringName, price: int) -> void:
	var definition := VehicleCatalogue.data_for(model_id)
	var allowance := _trade.dealer_offer() if _trade != null else 0
	var due := maxi(price - allowance, 0)
	var detail := "%s  ·  %s" % [VehicleCatalogue.subtitle(model_id), definition.vehicle_class]
	if _trade != null:
		detail = "%s traded at %s  ·  you pay %s" % [
			_trade.display_name(), ScreenKit.money(allowance), ScreenKit.money(due)
		]
	ScreenKit.confirm(
		self,
		"BUY %s FOR %s?" % [definition.display_name.to_upper(), ScreenKit.money(due)],
		detail,
		func() -> void: _do_buy(model_id, price, 0.0, 100.0, null)
	)


# --- The used lot --------------------------------------------------------

func _build_used() -> void:
	var stock := _stock()
	if stock == null or stock.listings().is_empty():
		_list.add_child(BusinessUIKit.label("Nothing on the lot today.", 14, ScreenKit.MUTED))
		return
	_list.add_child(BusinessUIKit.label(
		"Second hand. Sold as seen, and priced on what they have been through.",
		13, ScreenKit.MUTED
	))
	for listing in stock.listings():
		_list.add_child(_listing_row(listing))


func _listing_row(listing: UsedListing) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(listing.display_name(), 16, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  %s  ·  %s" % [
			VehicleCatalogue.subtitle(listing.model_id), listing.mileage_label(),
			listing.condition_label()
		], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	line.add_child(BusinessUIKit.value_label(ScreenKit.money(listing.price), 16, ScreenKit.TEXT))

	var compare := BusinessUIKit.button(
		"COMPARING" if _compare.has(listing.model_id) else "COMPARE", 130.0
	)
	compare.pressed.connect(func() -> void: _toggle_compare(listing.model_id))
	line.add_child(compare)

	var buy := BusinessUIKit.button("BUY", 110.0)
	buy.disabled = not EconomyManager.can_afford(listing.price)
	buy.pressed.connect(func() -> void:
		ScreenKit.confirm(
			self,
			"BUY %s FOR %s?" % [listing.display_name().to_upper(), ScreenKit.money(listing.price)],
			"%s  ·  condition %s" % [listing.mileage_label(), listing.condition_label()],
			func() -> void: _do_buy(
				listing.model_id, listing.price, listing.mileage_km, listing.condition, listing
			)
		)
	)
	line.add_child(buy)
	return frame


# --- What the player owns ------------------------------------------------

func _build_mine() -> void:
	var fleet := VehicleRegistry.get_fleet()
	if fleet.is_empty():
		_list.add_child(BusinessUIKit.label("You do not own a vehicle yet.", 14, ScreenKit.MUTED))
		return
	_list.add_child(ScreenKit.row(
		"Fleet value", ScreenKit.money(VehicleRegistry.total_value()), true
	))
	for record in fleet:
		_list.add_child(_owned_row(record))


func _owned_row(record: OwnedVehicle) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	frame.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(BusinessUIKit.label(record.display_name(), 16, ScreenKit.TEXT))
	text.add_child(BusinessUIKit.label(
		"%s  ·  %s  ·  condition %d%%  ·  %s" % [
			record.mileage_label(), record.condition_label(), roundi(record.condition),
			_where(record)
		], 12, ScreenKit.MUTED
	))
	line.add_child(text)

	var money := VBoxContainer.new()
	money.add_child(BusinessUIKit.value_label(ScreenKit.money(record.market_value()), 16, ScreenKit.TEXT))
	money.add_child(BusinessUIKit.value_label(
		"offer %s" % ScreenKit.money(record.dealer_offer()), 12, ScreenKit.MUTED
	))
	line.add_child(money)

	var trade := BusinessUIKit.button("TRADE IN" if _trade != record else "TRADING", 130.0)
	trade.pressed.connect(func() -> void:
		_trade = null if _trade == record else record
		_tab = Tab.NEW
		_tab_bar.current_tab = int(Tab.NEW)
		_rebuild()
	)
	line.add_child(trade)

	var sell := BusinessUIKit.button("SELL", 110.0)
	sell.pressed.connect(func() -> void:
		ScreenKit.confirm(
			self,
			"SELL %s FOR %s?" % [
				record.display_name().to_upper(), ScreenKit.money(record.dealer_offer())
			],
			"%s  ·  %s" % [record.mileage_label(), record.condition_label()],
			func() -> void: _do_sell(record)
		)
	)
	line.add_child(sell)
	return frame


func _where(record: OwnedVehicle) -> String:
	if record.is_stored():
		var garage := PropertyManager.garage_by_id(record.garage_id)
		return garage.display_name if garage != null else "In storage"
	var district := WorldManager.by_id(record.district_id)
	return district.display_name if district != null else "In the city"


# --- Comparison ----------------------------------------------------------

func _toggle_compare(model_id: StringName) -> void:
	if _compare.has(model_id):
		_compare.erase(model_id)
	else:
		# Two at a time. A third pushes the oldest out rather than refusing,
		# which is what a player clicking down a list actually wants.
		_compare.append(model_id)
		while _compare.size() > 2:
			_compare.pop_front()
	AudioManager.play_ui(&"ui_click")
	_rebuild()


## The two cars side by side, as bars. Five rows, not a spreadsheet.
func _build_comparison() -> void:
	_list.add_child(ScreenKit.heading("COMPARE"))

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(BusinessUIKit.stretch_label("", 13, ScreenKit.MUTED))
	for model_id in _compare:
		var name_label := BusinessUIKit.value_label(
			VehicleCatalogue.display_name(model_id), 14, ScreenKit.TEXT
		)
		name_label.custom_minimum_size = Vector2(220, 0)
		header.add_child(name_label)
	_list.add_child(header)

	_list.add_child(_compare_line("Price", _compare.map(
		func(id: StringName) -> String: return ScreenKit.money(VehicleCatalogue.price_new(id))
	)))

	for stat in ["Top speed", "Acceleration", "Handling", "Durability", "Prestige"]:
		var values: Array[String] = []
		for model_id in _compare:
			values.append(str(int(VehicleCatalogue.data_for(model_id).showroom_ratings()[stat])))
		_list.add_child(_compare_line(stat, values))
	_list.add_child(ScreenKit.spacer(12))


func _compare_line(name: String, values: Array) -> PanelContainer:
	var children: Array = [BusinessUIKit.stretch_label(name, 13, ScreenKit.MUTED)]
	for value in values:
		var node := BusinessUIKit.value_label(String(value), 14, ScreenKit.TEXT)
		node.custom_minimum_size = Vector2(220, 0)
		children.append(node)
	return BusinessUIKit.row(children)


# --- Doing the deal ------------------------------------------------------

func _do_buy(
	model_id: StringName, price: int, mileage: float, condition: float, listing: UsedListing
) -> void:
	var stock := _stock()
	var at := stock.collection_transform() if stock != null else Transform3D.IDENTITY
	var result: int
	if _trade != null:
		result = VehicleRegistry.trade_in(model_id, at, price, _trade, mileage, condition)
		_trade = null
	else:
		result = VehicleRegistry.buy(model_id, at, price, mileage, condition)

	if result != VehicleRegistry.BuyResult.OK:
		_note(_buy_failure(result), ScreenKit.BAD)
		AudioManager.play_ui(&"ui_error")
		return
	if listing != null and stock != null:
		stock.remove_listing(listing)
	AudioManager.play_ui(&"money")
	_note("Collect it from the bay outside.", ScreenKit.GOOD)
	_rebuild()


func _do_sell(record: OwnedVehicle) -> void:
	var paid := VehicleRegistry.sell(record)
	if paid <= 0:
		_note("That sale did not go through.", ScreenKit.BAD)
		return
	AudioManager.play_ui(&"money")
	_note("Sold for %s." % ScreenKit.money(paid), ScreenKit.GOOD)
	_rebuild()


func _buy_failure(result: int) -> String:
	match result:
		VehicleRegistry.BuyResult.CANNOT_AFFORD:
			return "You cannot afford that."
		VehicleRegistry.BuyResult.NOT_FOR_SALE:
			return "That one is not for sale."
		VehicleRegistry.BuyResult.NO_SUCH_MODEL:
			return "We do not have that."
		_:
			return "That did not go through."


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible:
		_parts["subtitle"].text = (
			"Riverside Drive  ·  Your cash: %s" % EconomyManager.get_cash_string()
		)


func _on_fleet_changed() -> void:
	if visible:
		_rebuild()
