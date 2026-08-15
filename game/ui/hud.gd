extends CanvasLayer
## Minimal heads-up display.
##
## The HUD is a pure listener: it connects to the managers and to whatever the
## player registers, and never reaches into gameplay state itself. Panels that
## have no system behind them yet (wanted stars, speedometer) are deliberately
## absent rather than faked.

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

var _stats: PlayerStats = null
var _inventory: Inventory = null
var _interaction: InteractionController = null
var _toast_tween: Tween = null
var _fade_tween: Tween = null


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

	_inventory_panel.opened.connect(_on_screen_visibility_changed)
	_inventory_panel.closed.connect(_on_screen_visibility_changed)
	_shop_panel.opened.connect(_on_screen_visibility_changed)
	_shop_panel.closed.connect(_on_screen_visibility_changed)

	_prompt_panel.visible = false
	_toast_panel.modulate.a = 0.0
	_pause_overlay.visible = false

	_refresh_clock()
	_cash_label.text = EconomyManager.get_cash_string()

	# The player may already exist by the time the HUD is ready.
	if GameManager.player != null:
		_bind_player(GameManager.player)


func _bind_player(player: Node3D) -> void:
	_unbind_player()

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

	_interaction = player.get_node_or_null("InteractionController") as InteractionController
	if _interaction != null:
		_interaction.focus_changed.connect(_on_focus_changed)
		_on_focus_changed(_interaction.get_focused())


func _unbind_player(_player: Node3D = null) -> void:
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
	_on_focus_changed(null)


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


# --- Interaction prompt --------------------------------------------------

func _on_focus_changed(interactable: Interactable) -> void:
	if interactable == null:
		_prompt_panel.visible = false
		return
	var text := interactable.get_prompt_text()
	if text.is_empty():
		_prompt_panel.visible = false
		return
	if not interactable.prompt_subtitle.is_empty():
		text += "\n" + interactable.prompt_subtitle
	_prompt_label.text = text
	_prompt_panel.visible = true


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
