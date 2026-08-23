class_name VenuePanel
extends Control
## Ordering at a counter.
##
## One screen, one list, and the effect of each line stated plainly. The player
## should be able to decide what to order without knowing a single number about
## how needs work.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _point: ServicePoint = null
var _buyer: Node = null


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(760, 520))
	_body = ScreenKit.scroller(_parts["body"])


func is_open() -> bool:
	return visible


func open(point: ServicePoint, buyer: Node = null) -> void:
	if point == null:
		return
	_point = point
	_buyer = buyer if buyer != null else GameManager.player
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_point = null
	_buyer = null
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()
	if _point == null:
		return

	_parts["title"].text = _point.venue_name.to_upper()
	_parts["subtitle"].text = "%s  ·  open %02d:00 – %02d:00  ·  %s" % [
		ServiceCatalogue.kind_name(_point.venue_kind),
		_point.opens_hour, _point.closes_hour,
		ScreenKit.money(EconomyManager.cash),
	]

	if _point.owning_business() != null:
		# Said out loud, because it is the one place in the game where spending
		# money does not leave the player worse off.
		_parts["status"].text = "YOUR OWN — what you spend here goes into the till"
	elif not _point.is_open():
		_parts["status"].text = "CLOSED"
	else:
		_parts["status"].text = ""

	for service in _point.services():
		_body.add_child(_service_row(service))

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func _service_row(service: VenueService) -> PanelContainer:
	var price := _point.price_of(service)
	var button := BusinessUIKit.button(ScreenKit.money(price), 96.0)
	button.disabled = not _point.is_open() or not EconomyManager.can_afford(price)
	button.pressed.connect(func() -> void: _order(service))

	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 0)
	lines.add_child(BusinessUIKit.stretch_label(service.label, 15, BusinessUIKit.TEXT))
	if not service.detail.is_empty():
		lines.add_child(
			BusinessUIKit.stretch_label(service.detail, 12, BusinessUIKit.MUTED)
		)
	lines.add_child(
		BusinessUIKit.stretch_label(service.effect_line(), 12, BusinessUIKit.ACCENT)
	)
	return BusinessUIKit.row([lines, button])


func _order(service: VenueService) -> void:
	var result := _point.order(service, _buyer)
	if result != ServicePoint.Result.OK:
		_parts["status"].text = ServicePoint.describe_result(result)
		AudioManager.play_ui(&"ui_back")
		return
	AudioManager.play_ui(&"ui_confirm")
	# The clock has moved and the counter may have shut behind them, so the
	# screen is rebuilt rather than merely repriced.
	_rebuild()
