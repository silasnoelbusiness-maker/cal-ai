class_name ContactPanel
extends Control
## Standing in somebody's back room, doing business.
##
## One screen for all three kinds of contact, because they are all the same
## conversation with a different subject: here is what I have, here is what you
## will give me, yes or no. §89 sets the shape of the job offer — what, how
## risky, what it pays, how long — and the fence and the buyer are the same
## thing with the haggling already done.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _contact: CriminalContactData = null


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(820, 560))
	_body = ScreenKit.scroller(_parts["body"])


func is_open() -> bool:
	return visible


func open(contact: CriminalContactData) -> void:
	if contact == null:
		return
	_contact = contact
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_contact = null
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func contact() -> CriminalContactData:
	return _contact


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()
	if _contact == null:
		return

	_parts["title"].text = _contact.display_name.to_upper()
	_parts["subtitle"].text = "%s  ·  you are %s" % [
		_contact.kind_label(), Underworld.tier_name()
	]
	_parts["status"].text = ""

	if not Underworld.will_deal(_contact):
		_body.add_child(BusinessUIKit.label(_contact.closed_line, 15, ScreenKit.BAD))
		_body.add_child(BusinessUIKit.label(
			"They want %d reputation. You have %d." % [
				_contact.reputation_required, Underworld.reputation
			], 13, ScreenKit.MUTED
		))
	else:
		match _contact.kind:
			CriminalContactData.Kind.FENCE:
				_build_fence()
			CriminalContactData.Kind.VEHICLE_BUYER:
				_build_buyer()
			_:
				_build_broker()

	var leave := BusinessUIKit.button("LEAVE", 130.0)
	leave.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(leave)


# --- Fence ---------------------------------------------------------------

func _build_fence() -> void:
	var inventory := _inventory()
	var quote := Underworld.fence_quote(inventory)
	_build_request_block()
	_body.add_child(ScreenKit.heading("WHAT YOU ARE CARRYING"))
	if int(quote["units"]) <= 0:
		_body.add_child(BusinessUIKit.label(
			"Nothing they would touch. They deal in things that are not yours.",
			14, ScreenKit.MUTED
		))
		return
	for entry in inventory.call("stolen_stacks"):
		var item: ItemData = entry["item"]
		_body.add_child(ScreenKit.row(
			item.display_name, "x%d" % int(entry["quantity"])
		))
	_body.add_child(ScreenKit.spacer(6))
	_body.add_child(ScreenKit.row("Worth", ScreenKit.money(int(quote["value"]))))
	_body.add_child(ScreenKit.row(
		"They pay", "%d%%" % int(round(float(quote["rate"]) * 100.0))
	))
	_body.add_child(ScreenKit.row("You get", ScreenKit.money(int(quote["payout"])), true))
	_body.add_child(BusinessUIKit.label(
		"Better standing gets a better price. Nothing else does.",
		12, ScreenKit.MUTED
	))

	var sell := BusinessUIKit.button("SELL IT ALL", 170.0)
	sell.pressed.connect(func() -> void:
		Underworld.sell_to_fence(_inventory())
		_rebuild()
	)
	_parts["actions"].add_child(sell)


## What this contact has asked for, if anything, and how close the player is to
## having it. §62 and §65 — an order is a reason to go and get one thing rather
## than to bring in whatever is lying about.
func _build_request_block() -> void:
	var request := Underworld.request_from(_contact.contact_id)
	if request == null:
		# Asking is what posts one. A contact with nothing outstanding will
		# name something the next time the player walks in.
		request = Underworld.post_request(_contact)
	if request == null:
		return
	_body.add_child(ScreenKit.heading("WHAT THEY WANT"))
	_body.add_child(ScreenKit.row("Asking for", request.headline(), true))
	_body.add_child(ScreenKit.row(
		"Pays", "+%d%% over the usual" % roundi(request.bonus * 100.0)
	))
	if request.minimum_condition > 0.0:
		_body.add_child(ScreenKit.row("Condition", request.condition_label()))
	_body.add_child(ScreenKit.row("Their trust", "+%d" % request.trust_reward))
	var days := request.days_left(TimeManager.day_index)
	_body.add_child(ScreenKit.row(
		"Stands for", "%d day%s" % [days, "" if days == 1 else "s"]
	))
	if request.kind == ContactRequest.Kind.GOODS:
		var carried := Underworld._count_stolen(_inventory(), request.target_id)
		_body.add_child(ScreenKit.row(
			"You have", "%d of %d" % [carried, request.quantity],
			carried >= request.quantity
		))


func _inventory() -> Node:
	var player := GameManager.player
	if player == null or not player.has_method("get_inventory"):
		return null
	return player.call("get_inventory")


# --- Vehicle buyer -------------------------------------------------------

func _build_buyer() -> void:
	_build_request_block()
	_body.add_child(ScreenKit.heading("THE CAR OUTSIDE"))
	var record := _current_vehicle_record()
	if record == null:
		_body.add_child(BusinessUIKit.label(
			"Turn up in something. They are not going to come and find it.",
			14, ScreenKit.MUTED
		))
		return
	var quote := Underworld.chop_quote(record)
	_body.add_child(ScreenKit.row("Vehicle", record.display_name()))
	_body.add_child(ScreenKit.row("Condition", "%d%%" % int(record.condition)))
	if not bool(quote.get("eligible", false)):
		_body.add_child(BusinessUIKit.label(
			String(quote.get("reason", "They will not take it.")), 14, ScreenKit.BAD
		))
		_body.add_child(BusinessUIKit.label(
			"A car you bought is yours. Sell that through a dealership.",
			12, ScreenKit.MUTED
		))
		return
	_body.add_child(ScreenKit.row("Worth", ScreenKit.money(int(quote["base"]))))
	_body.add_child(ScreenKit.row(
		"They pay", "%d%%" % int(round(float(quote["rate"]) * 100.0))
	))
	if float(quote.get("falloff", 1.0)) < 0.99:
		_body.add_child(ScreenKit.row(
			"Recently supplied",
			"-%d%%" % int(round((1.0 - float(quote["falloff"])) * 100.0))
		))
	_body.add_child(ScreenKit.row("You get", ScreenKit.money(int(quote["payout"])), true))

	var deliver := BusinessUIKit.button("HAND IT OVER", 190.0)
	deliver.disabled = not bool(quote.get("ready", true))
	deliver.pressed.connect(func() -> void:
		Underworld.deliver_to_chop_shop(_current_vehicle_record())
		_rebuild()
	)
	if not bool(quote.get("ready", true)):
		_body.add_child(BusinessUIKit.label(
			"They cannot move another one for %.0f hours."
			% (Underworld.chop_minutes_left() / 60.0),
			12, ScreenKit.BAD
		))
	_parts["actions"].add_child(deliver)


## The car the player arrived in, as a registry record. Deliberately the one
## they are sitting in or standing beside — §71 is a delivery, so the car has
## to actually be here.
func _current_vehicle_record() -> OwnedVehicle:
	var player := GameManager.player
	if player == null:
		return null
	var car: Node3D = null
	if player.has_method("get_vehicle"):
		car = player.call("get_vehicle") as Node3D
	if car == null:
		var nearest := INF
		for node in get_tree().get_nodes_in_group(&"vehicle"):
			var candidate := node as Node3D
			if candidate == null:
				continue
			var distance := candidate.global_position.distance_to(player.global_position)
			if distance < nearest and distance < 12.0:
				nearest = distance
				car = candidate
	if car == null:
		return null
	if car is Vehicle:
		return VehicleRegistry.record_for(car as Vehicle)
	var id: Variant = car.get("instance_id")
	return VehicleRegistry.by_id(StringName(id)) if id != null else null


# --- Broker --------------------------------------------------------------

func _build_broker() -> void:
	_body.add_child(ScreenKit.heading("WORK"))
	var running := Underworld.active_job()
	if running != null:
		_body.add_child(BusinessUIKit.label(
			"Finish what you took on first.", 14, ScreenKit.MUTED
		))
		_body.add_child(ScreenKit.row(running.objective_label(), running.target_name))
		return
	# §69 — a small rotating board rather than one job at a time. What is on it
	# comes off the rung of this contact's ladder the player has earned, so
	# better standing shows different work rather than the same work priced up.
	var chain := Underworld.chain_for(_contact.contact_id)
	if chain != null:
		_body.add_child(ScreenKit.row("They put you on", chain.display_name))
		_body.add_child(BusinessUIKit.label(chain.blurb, 12, ScreenKit.MUTED))
	var board := Underworld.refresh_board(_contact)
	if board.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Nothing today. Try again later." if Underworld.contact_ready(_contact)
				else "They have nothing new yet.",
			14, ScreenKit.MUTED
		))
		return
	for job in board:
		_body.add_child(_offer_card(job))
	var next_rung := Underworld.next_chain_for(_contact.contact_id)
	if next_rung != null:
		_body.add_child(BusinessUIKit.label(
			"Better work — %s — wants %d reputation and %d trust. You have %d and %d."
			% [
				next_rung.display_name, next_rung.reputation_required,
				next_rung.trust_required, Underworld.reputation,
				Underworld.trust_in(_contact.contact_id),
			], 12, ScreenKit.MUTED
		))


## One offer on the board, with its own accept and decline.
func _offer_card(job: IllegalJobData) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(job.objective_label(), 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(job.risk_label(), 13, ScreenKit.BAD),
	]))
	column.add_child(BusinessUIKit.label(job.target_name, 13, ScreenKit.MUTED))
	column.add_child(ScreenKit.row("Reward", ScreenKit.money(job.reward), true))
	column.add_child(ScreenKit.row("Time", "%dh" % job.time_limit_hours))
	column.add_child(ScreenKit.row("Reputation", "+%d" % job.reputation_reward))
	var chain := Underworld.chain_for(job.contact_id)
	column.add_child(ScreenKit.row(
		"Their trust", "+%d" % (chain.trust_reward if chain != null else 5)
	))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var accept := BusinessUIKit.button("ACCEPT", 140.0)
	accept.pressed.connect(func() -> void:
		Underworld.accept_job(job)
		_rebuild()
	)
	var decline := BusinessUIKit.button("PASS", 110.0)
	decline.pressed.connect(func() -> void:
		Underworld.decline_job(job)
		_rebuild()
	)
	buttons.add_child(accept)
	buttons.add_child(decline)
	column.add_child(buttons)
	return card
