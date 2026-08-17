extends CanvasLayer
## Minimal heads-up display.
##
## The HUD is a pure listener: it connects to the managers and to whatever the
## player registers, and never reaches into gameplay state itself. Panels that
## have no system behind them yet (wanted stars) are deliberately absent rather
## than faked; the speedometer only exists while the player is in a vehicle.

const TOAST_HOLD_SECONDS := 2.6
const TOAST_FADE_SECONDS := 0.6

## Indexed by GameManager.Tone: INFO, GOOD, BAD.
const TONE_COLORS: Array[Color] = [
	Color(0.898, 0.925, 0.961),
	Color(0.596, 0.918, 0.639),
	Color(0.965, 0.549, 0.502),
]

@onready var _day_label: Label = %DayLabel
@onready var _time_label: Label = %TimeLabel
@onready var _cash_label: Label = %CashLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _energy_bar: ProgressBar = %EnergyBar
@onready var _hunger_bar: ProgressBar = %HungerBar
@onready var _prompt_panel: PanelContainer = %PromptPanel
@onready var _prompt_label: Label = %PromptLabel
@onready var _toast_panel: PanelContainer = %ToastPanel
@onready var _toast_label: Label = %ToastLabel
@onready var _pause_overlay: Control = %PauseOverlay
@onready var _screen_fade: ColorRect = %ScreenFade
@onready var _inventory_panel: Control = %InventoryPanel
@onready var _shop_panel: Control = %ShopPanel
@onready var _speed_panel: PanelContainer = %SpeedPanel
@onready var _speed_label: Label = %SpeedLabel
@onready var _vehicle_name: Label = %VehicleName
@onready var _vehicle_health_bar: ProgressBar = %VehicleHealthBar
@onready var _wanted_label: Label = %WantedLabel
@onready var _escape_label: Label = %EscapeLabel
@onready var _busted_overlay: Control = %BustedOverlay
@onready var _busted_text: Label = %BustedText
@onready var _equipped_label: Label = %EquippedLabel
@onready var _equipped_swatch: ColorRect = %EquippedSwatch

var _player: Node3D = null
var _stats: PlayerStats = null
var _inventory: Inventory = null
var _interaction: InteractionController = null
var _combat: CombatController = null
var _toast_tween: Tween = null
var _fade_tween: Tween = null
## The vehicle currently being driven, if any. The speedometer polls it rather
## than the vehicle pushing every frame.
var _vehicle: Vehicle = null


func _ready() -> void:
	TimeManager.minute_passed.connect(_on_minute_passed)
	TimeManager.clock_synced.connect(_refresh_clock)
	EconomyManager.cash_changed.connect(_on_cash_changed)
	EconomyManager.purchase_failed.connect(_on_purchase_failed)
	GameManager.notification_posted.connect(_on_notification_posted)
	GameManager.state_changed.connect(_on_game_state_changed)
	GameManager.player_registered.connect(_bind_player)
	GameManager.player_unregistered.connect(_unbind_player)
	GameManager.screen_requested.connect(_on_screen_requested)
	GameManager.menus_close_requested.connect(close_screens)
	GameManager.player_teleported.connect(_on_player_teleported)

	WantedManager.level_changed.connect(_on_wanted_level_changed)
	WantedManager.escaping_started.connect(_on_escaping_started)
	WantedManager.escaping_cancelled.connect(_on_escaping_cancelled)
	WantedManager.wanted_cleared.connect(_on_wanted_cleared)
	WantedManager.bust_started.connect(_on_bust_started)
	WantedManager.bust_finished.connect(_on_bust_finished)

	_inventory_panel.opened.connect(_on_screen_visibility_changed)
	_inventory_panel.closed.connect(_on_screen_visibility_changed)
	_shop_panel.opened.connect(_on_screen_visibility_changed)
	_shop_panel.closed.connect(_on_screen_visibility_changed)

	_prompt_panel.visible = false
	_toast_panel.modulate.a = 0.0
	_pause_overlay.visible = false
	_speed_panel.visible = false
	_wanted_label.visible = false
	_escape_label.visible = false
	_busted_overlay.visible = false
	set_process(false)

	_refresh_clock()
	_cash_label.text = EconomyManager.get_cash_string()

	# The player may already exist by the time the HUD is ready.
	if GameManager.player != null:
		_bind_player(GameManager.player)


func _bind_player(player: Node3D) -> void:
	_unbind_player()
	_player = player

	if player.has_method("get_stats"):
		_stats = player.call("get_stats")
	if _stats != null:
		_stats.health_changed.connect(_on_health_changed)
		_stats.energy_changed.connect(_on_energy_changed)
		_stats.hunger_changed.connect(_on_hunger_changed)
		_on_health_changed(_stats.health, PlayerStats.MAX_VALUE)
		_on_energy_changed(_stats.energy, PlayerStats.MAX_VALUE)
		_on_hunger_changed(_stats.hunger, PlayerStats.MAX_VALUE)

	if player.has_method("get_inventory"):
		_inventory = player.call("get_inventory")
	if _inventory != null:
		_inventory.item_used.connect(_on_item_used)
		_inventory.add_rejected.connect(_on_add_rejected)

	if player.has_signal("vehicle_changed"):
		player.connect("vehicle_changed", _on_vehicle_changed)
		if player.has_method("get_vehicle"):
			_on_vehicle_changed(player.call("get_vehicle"))

	_interaction = player.get_node_or_null("InteractionController") as InteractionController
	if _interaction != null:
		_interaction.focus_changed.connect(_on_focus_changed)
		_on_focus_changed(_interaction.get_focused())

	_combat = player.get_node_or_null("Combat") as CombatController
	if _combat != null:
		_combat.equipped_changed.connect(_on_equipped_changed)
	_on_equipped_changed(_combat.get_equipped_item() if _combat != null else null)


func _unbind_player(_old_player: Node3D = null) -> void:
	if _stats != null:
		_stats.health_changed.disconnect(_on_health_changed)
		_stats.energy_changed.disconnect(_on_energy_changed)
		_stats.hunger_changed.disconnect(_on_hunger_changed)
		_stats = null
	if _inventory != null:
		_inventory.item_used.disconnect(_on_item_used)
		_inventory.add_rejected.disconnect(_on_add_rejected)
		_inventory = null
	if _interaction != null:
		_interaction.focus_changed.disconnect(_on_focus_changed)
		_interaction = null
	if _combat != null:
		_combat.equipped_changed.disconnect(_on_equipped_changed)
		_combat = null
	_on_equipped_changed(null)
	if _player != null and _player.has_signal("vehicle_changed"):
		if _player.is_connected("vehicle_changed", _on_vehicle_changed):
			_player.disconnect("vehicle_changed", _on_vehicle_changed)
	_player = null
	_on_vehicle_changed(null)
	_on_focus_changed(null)


# --- Speedometer ---------------------------------------------------------

## Shown only while driving, per the brief. Polled rather than pushed: one label
## update per frame beats a signal per physics tick.
func _on_vehicle_changed(vehicle: Node3D) -> void:
	if _vehicle != null and _vehicle.health_changed.is_connected(_on_vehicle_health_changed):
		_vehicle.health_changed.disconnect(_on_vehicle_health_changed)

	_vehicle = vehicle as Vehicle
	_speed_panel.visible = _vehicle != null
	_update_process_need()

	if _vehicle == null:
		return
	_vehicle_name.text = _vehicle.get_display_name().to_upper()
	_vehicle.health_changed.connect(_on_vehicle_health_changed)
	_on_vehicle_health_changed(_vehicle.health, _vehicle.data.max_health)
	_refresh_speed()


func _process(_delta: float) -> void:
	_refresh_speed()
	# Prompts are re-read rather than cached: what a thing offers can change
	# while the player stands in front of it — a car slowing to a stop becomes
	# carjackable, a shop that has just been robbed stops offering the till.
	if _prompt_panel.visible and _interaction != null:
		_on_focus_changed(_interaction.get_focused())
	if _escape_label.visible:
		_escape_label.text = "ESCAPING...  %.0f" % ceilf(
			WantedManager.get_escape_seconds_left()
		)


func _refresh_speed() -> void:
	if _vehicle == null or not is_instance_valid(_vehicle):
		return
	_speed_label.text = "%d km/h" % roundi(_vehicle.get_speed_kmh())


func _on_vehicle_health_changed(value: float, max_value: float) -> void:
	_vehicle_health_bar.max_value = max_value
	_vehicle_health_bar.value = value


# --- Wanted level --------------------------------------------------------

## Stars only appear when there is heat, per the brief. The escape countdown
## sits under them so both read as one block.
func _on_wanted_level_changed(level: int) -> void:
	_wanted_label.visible = level > 0
	if level > 0:
		_wanted_label.text = (
			"★".repeat(level) + "☆".repeat(WantedManager.MAX_LEVEL - level)
		)
	else:
		_escape_label.visible = false
	_update_process_need()


func _on_escaping_started(_seconds: float) -> void:
	_escape_label.visible = true
	_update_process_need()


func _on_escaping_cancelled() -> void:
	_escape_label.visible = false
	_update_process_need()


func _on_wanted_cleared() -> void:
	_wanted_label.visible = false
	_escape_label.visible = false
	_update_process_need()


func _on_bust_started() -> void:
	_busted_text.text = "BUSTED"
	_busted_overlay.visible = true


func _on_bust_finished(fine_paid: int) -> void:
	_busted_overlay.visible = false
	_show_toast("BUSTED\n-$%d fine" % fine_paid, GameManager.Tone.BAD)


## The HUD only needs a per-frame tick while something on it is live.
func _update_process_need() -> void:
	# A visible prompt is a third reason to tick: what an interactable offers can
	# change while the player stands still in front of it.
	set_process(_vehicle != null or _escape_label.visible or _prompt_panel.visible)


# --- Screens -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("inventory"):
		return
	# The bag is reachable from the shop counter too, so only the inventory
	# screen itself toggles off.
	if _inventory_panel.is_open():
		_inventory_panel.close()
	else:
		_inventory_panel.open(GameManager.player)
	get_viewport().set_input_as_handled()


func _on_screen_requested(screen_id: StringName, context: Node, requester: Node) -> void:
	match screen_id:
		&"shop":
			var buyer := requester if requester != null else GameManager.player
			_shop_panel.open(context as Shop, buyer)
		_:
			push_warning("HUD has no screen for '%s'." % screen_id)


func close_screens() -> void:
	_inventory_panel.close()
	_shop_panel.close()


## A screen being up freezes the world, so the manager has to know.
func _on_screen_visibility_changed() -> void:
	GameManager.menu_open = _inventory_panel.is_open() or _shop_panel.is_open()


func _on_item_used(item: ItemData) -> void:
	_show_toast(item.get_use_summary(), GameManager.Tone.GOOD)


func _on_add_rejected(item: ItemData, _quantity: int) -> void:
	_show_toast("NO ROOM FOR %s" % item.display_name.to_upper(), GameManager.Tone.BAD)


## Teleports are cuts. A quick fade up from black hides the pop and reads as a
## door opening rather than a glitch.
func _on_player_teleported(_destination: Transform3D) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_screen_fade.modulate.a = 1.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_screen_fade, "modulate:a", 0.0, 0.45)


# --- Clock / money -------------------------------------------------------

func _on_minute_passed(_hour: int, _minute: int) -> void:
	_refresh_clock()


func _refresh_clock() -> void:
	_day_label.text = TimeManager.get_day_name()
	_time_label.text = TimeManager.get_time_string()


func _on_cash_changed(_balance: int, delta: int) -> void:
	_cash_label.text = EconomyManager.get_cash_string()
	if delta != 0:
		var sign_text := "+" if delta > 0 else "-"
		var tone: int = GameManager.Tone.GOOD if delta > 0 else GameManager.Tone.BAD
		_show_toast("%s$%d" % [sign_text, absi(delta)], tone)


func _on_purchase_failed(amount: int, _reason: String) -> void:
	_show_toast("NOT ENOUGH CASH  ($%d short)" % (amount - EconomyManager.cash), GameManager.Tone.BAD)


# --- Needs ---------------------------------------------------------------

func _on_health_changed(value: float, max_value: float) -> void:
	_set_bar(_health_bar, value, max_value)


func _on_energy_changed(value: float, max_value: float) -> void:
	_set_bar(_energy_bar, value, max_value)


func _on_hunger_changed(value: float, max_value: float) -> void:
	_set_bar(_hunger_bar, value, max_value)


func _set_bar(bar: ProgressBar, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value = value


# --- Equipment -----------------------------------------------------------

## Always shown, because empty hands are a state the player needs to be able to
## read as clearly as a weapon in them.
func _on_equipped_changed(item: ItemData) -> void:
	if item == null:
		_equipped_label.text = "FISTS"
		_equipped_swatch.color = CombatController.FISTS.icon_color
		return
	_equipped_label.text = item.display_name.to_upper()
	_equipped_swatch.color = item.icon_color


# --- Interaction prompt --------------------------------------------------

func _on_focus_changed(interactable: Interactable) -> void:
	if interactable == null:
		_prompt_panel.visible = false
		_update_process_need()
		return
	var text := interactable.get_prompt_text()
	if text.is_empty():
		_prompt_panel.visible = false
		_update_process_need()
		return
	if not interactable.prompt_subtitle.is_empty():
		text += "\n" + interactable.prompt_subtitle
	_prompt_label.text = text
	_prompt_panel.visible = true
	_update_process_need()


# --- Toasts / pause ------------------------------------------------------

func _on_notification_posted(message: String, tone: int) -> void:
	_show_toast(message, tone)


func _show_toast(message: String, tone: int) -> void:
	_toast_label.text = message
	_toast_label.modulate = TONE_COLORS[clampi(tone, 0, TONE_COLORS.size() - 1)]

	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_panel.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD_SECONDS)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, TOAST_FADE_SECONDS)


func _on_game_state_changed(state: int) -> void:
	_pause_overlay.visible = state == GameManager.State.PAUSED
