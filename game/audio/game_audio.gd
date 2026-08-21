extends Node
## Connects the game's existing signals to sounds.
##
## Deliberately one listener rather than an `AudioManager.play` sprinkled through
## thirty files. Everything in here is a connection to something the game
## already announced — a sale, a crime report, a lease — so adding sound needed
## no new events, and muting a whole category is a line in one place.
##
## The rule for money sounds (§40 of the brief, and good sense) is that they
## mark moments the player caused and is present for. A shop selling a bottle of
## water in another district is a number on a report, not a till in your ear.

## Sales are only audible when the player is near the shop that made them.
const SALE_EARSHOT := 22.0

var _last_wanted_level: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	GameManager.notification_posted.connect(_on_notification)
	GameManager.screen_requested.connect(_on_screen_requested)

	WantedManager.level_changed.connect(_on_wanted_level_changed)
	WantedManager.escaping_started.connect(_on_escaping_started)
	WantedManager.wanted_cleared.connect(_on_wanted_cleared)
	WantedManager.bust_finished.connect(_on_bust_finished)

	# A sale is announced by the business, not the manager, so this follows
	# every business as it is created rather than connecting once at boot.
	BusinessManager.business_created.connect(_on_business_created)
	for business in BusinessManager.get_businesses():
		_on_business_created(business)
	BusinessManager.order_delivered.connect(_on_order_delivered)

	TimeManager.time_skipped.connect(_on_time_skipped)

	# Logistics and money trouble. Same rule as sales: a van pulling up
	# somewhere the player is standing is a sound, a van pulling up across the
	# city is a line on a screen.
	LogisticsManager.transfer_dispatched.connect(_on_transfer_dispatched)
	LogisticsManager.transfer_delivered.connect(_on_transfer_delivered)
	LogisticsManager.transfer_failed.connect(_on_transfer_failed)
	FinanceManager.distress_changed.connect(_on_distress_changed)
	FinanceManager.business_closed_by_distress.connect(_on_closed_by_distress)


# --- Interface -------------------------------------------------------------

## Notifications are the game's main voice, and their tone already says whether
## something went well. Mapping tone to sound means every future notification
## is audible without anybody remembering to make it so.
func _on_notification(_message: String, tone: int) -> void:
	match tone:
		GameManager.Tone.GOOD:
			AudioManager.play_ui(&"ui_notify", -4.0)
		GameManager.Tone.BAD:
			AudioManager.play_ui(&"ui_error", -5.0)
		_:
			AudioManager.play_ui(&"ui_click", -9.0)


func _on_screen_requested(_screen_id: StringName, _context: Node, _requester: Node) -> void:
	AudioManager.play_ui(&"ui_confirm", -6.0)


# --- Crime and police ------------------------------------------------------

func _on_wanted_level_changed(level: int) -> void:
	# Rising heat gets an alert; falling heat does not, so clearing a star is
	# not congratulated with the same sound that warned about earning it.
	if level > _last_wanted_level:
		AudioManager.play(&"alert", AudioBuses.SFX, -6.0)
	_last_wanted_level = level


func _on_escaping_started(_seconds: float) -> void:
	AudioManager.play(&"ui_notify", AudioBuses.SFX, -8.0)


func _on_wanted_cleared() -> void:
	_last_wanted_level = 0
	AudioManager.play(&"money", AudioBuses.SFX, -10.0)


func _on_bust_finished(_fine_paid: int) -> void:
	AudioManager.play(&"busted", AudioBuses.SFX, -3.0)


# --- Business --------------------------------------------------------------

## A till, heard only if the player is standing in the shop that rang it. Far
## businesses report their takings on the dashboard instead.
func _on_business_created(business: BusinessInstance) -> void:
	if business == null or business.sale_made.is_connected(_on_sale_made):
		return
	business.sale_made.connect(_on_sale_made.bind(business))


func _on_sale_made(
	_item: ItemData, _quantity: int, _revenue: int, business: BusinessInstance
) -> void:
	var player := GameManager.player
	if player == null or business == null:
		return
	var unit := RetailUnit.for_business(business, get_tree())
	if unit == null:
		return
	if unit.global_position.distance_to(player.global_position) > SALE_EARSHOT:
		return
	AudioManager.play_at(
		&"register", unit.global_position, AudioBuses.SFX, -12.0, 1.0, 0.12
	)


func _on_order_delivered(order: PurchaseOrder) -> void:
	var player := GameManager.player
	if player == null or order == null:
		return
	var business := BusinessManager.by_id(order.business_id)
	if business == null:
		return
	var unit := RetailUnit.for_business(business, get_tree())
	if unit == null:
		return
	# Near enough to see the delivery arrive: a sound. Otherwise the
	# notification on its own is the whole event.
	if unit.global_position.distance_to(player.global_position) > SALE_EARSHOT * 2.0:
		return
	AudioManager.play_at(&"delivery", unit.global_position, AudioBuses.SFX, -10.0)


# --- Logistics and money ---------------------------------------------------

## §119 — a van loading up. Heard at the depot it leaves, not everywhere.
func _on_transfer_dispatched(order: TransferOrder) -> void:
	_play_at_place(
		&"shipment_out", order.source_kind, order.source_id, -11.0
	)


## §120 — a shipment landing, at the place it landed.
func _on_transfer_delivered(order: TransferOrder) -> void:
	_play_at_place(
		&"shipment_in", order.destination_kind, order.destination_id, -9.0
	)


func _on_transfer_failed(order: TransferOrder) -> void:
	_play_at_place(&"warning", order.destination_kind, order.destination_id, -12.0)


## §121 — a business sliding into trouble. Only on the way down: recovering is
## already announced, and a chime every time a shop crosses back over the line
## would train the player to ignore it.
func _on_distress_changed(_business: BusinessInstance, state: int) -> void:
	if state == DistressState.State.DISTRESSED or state == DistressState.State.CRITICAL:
		AudioManager.play(&"warning", AudioBuses.SFX, -7.0)


## A shutter coming down. Loud enough to be the end of something.
func _on_closed_by_distress(_business: BusinessInstance) -> void:
	AudioManager.play(&"shutter", AudioBuses.SFX, -5.0)


## Plays a sound at one end of a transfer, if the player is near enough to be
## standing there. Distance is the same rule the till uses.
func _play_at_place(
	id: StringName, kind: TransferOrder.Place, place_id: StringName, volume_db: float
) -> void:
	var player := GameManager.player
	if player == null:
		return
	var where := LogisticsManager.place_position(kind, place_id)
	if where == Vector3.ZERO:
		return
	if where.distance_to(player.global_position) > SALE_EARSHOT * 2.0:
		return
	AudioManager.play_at(id, where, AudioBuses.SFX, volume_db)


# --- Time ------------------------------------------------------------------

## Sleeping and working a shift both skip the clock forward. A soft fall marks
## the transition, so waking up is an event rather than a jump cut.
func _on_time_skipped(minutes: int) -> void:
	if minutes >= 120:
		AudioManager.play(&"sleep", AudioBuses.SFX, -8.0)
