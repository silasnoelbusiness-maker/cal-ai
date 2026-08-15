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

var _stats: PlayerStats = null
var _interaction: InteractionController = null
var _toast_tween: Tween = null


func _ready() -> void:
	TimeManager.minute_passed.connect(_on_minute_passed)
	EconomyManager.cash_changed.connect(_on_cash_changed)
	EconomyManager.purchase_failed.connect(_on_purchase_failed)
	GameManager.notification_posted.connect(_on_notification_posted)
	GameManager.state_changed.connect(_on_game_state_changed)
	GameManager.player_registered.connect(_bind_player)
	GameManager.player_unregistered.connect(_unbind_player)

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
	if _interaction != null:
		_interaction.focus_changed.disconnect(_on_focus_changed)
		_interaction = null
	_on_focus_changed(null)


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
