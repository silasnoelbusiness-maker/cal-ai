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


func _inventory() -> Node:
	var player := GameManager.player
	if player == null or not player.has_method("get_inventory"):
		return null
	return player.call("get_inventory")


# --- Vehicle buyer -------------------------------------------------------

func _build_buyer() -> void:
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
	var job := Underworld.offer_job(_contact)
	if job == null:
		_body.add_child(BusinessUIKit.label(
			"Nothing today. Try again later." if Underworld.contact_ready(_contact)
				else "They have nothing new yet.",
			14, ScreenKit.MUTED
		))
		return

	_body.add_child(ScreenKit.row("Job", job.objective_label(), true))
	_body.add_child(ScreenKit.row("Target", job.target_name))
	_body.add_child(ScreenKit.row("Reward", ScreenKit.money(job.reward), true))
	_body.add_child(ScreenKit.row("Risk", job.risk_label()))
	_body.add_child(ScreenKit.row("Time", "%dh" % job.time_limit_hours))
	_body.add_child(ScreenKit.row("Reputation", "+%d" % job.reputation_reward))

	var accept := BusinessUIKit.button("ACCEPT", 150.0)
	accept.pressed.connect(func() -> void:
		Underworld.accept_job(job)
		_rebuild()
	)
	var decline := BusinessUIKit.button("DECLINE", 150.0)
	decline.pressed.connect(func() -> void:
		Underworld.decline_job(job)
		_rebuild()
	)
	_parts["actions"].add_child(accept)
	_parts["actions"].add_child(decline)
