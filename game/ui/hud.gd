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
@onready var _property_panel: Control = %PropertyPanel
@onready var _business_dashboard: Control = %BusinessDashboard
@onready var _city_map: Control = %CityMap
@onready var _residence_panel: Control = %ResidencePanel
@onready var _destination_label: Label = %DestinationLabel
@onready var _empire_dashboard: Control = %EmpireDashboard

## Built in _build_phase_m_screens rather than instanced from the scene.
var _dealership_panel: DealershipPanel = null
var _vehicle_detail_panel: VehicleDetailPanel = null
var _repair_panel: RepairPanel = null
var _garage_panel: GaragePanel = null
var _furniture_store_panel: FurnitureStorePanel = null
var _furnishing_panel: FurnishingPanel = null
var _home_storage_panel: HomeStoragePanel = null
var _profile_panel: ProfilePanel = null
## Phase O: the company, one person's week, and one branch's manager.
var _company_dashboard: CompanyDashboard = null
var _staff_schedule_panel: StaffSchedulePanel = null
var _manager_panel: ManagerPanel = null
## Phase P: the company's distribution.
var _logistics_panel: LogisticsPanel = null
var _branch_finance_panel: BranchFinancePanel = null
var _property_sale_panel: PropertySalePanel = null
var _real_estate_panel: RealEstatePanel = null
@onready var _store_panel: PanelContainer = %StorePanel
@onready var _store_name: Label = %StoreName
@onready var _store_status: Label = %StoreStatus
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
	# One theme for every Control in the game, set at the window root so each
	# screen inherits it instead of styling itself.
	get_tree().root.theme = UITheme.get_theme()
	GameManager.screen_requested.connect(_on_screen_requested)
	GameManager.menus_close_requested.connect(close_screens)
	GameManager.player_teleported.connect(_on_player_teleported)
	SaveManager.autosave_started.connect(_on_autosave_started)
	SaveManager.autosave_finished.connect(_on_autosave_finished)

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
	_property_panel.opened.connect(_on_screen_visibility_changed)
	_property_panel.closed.connect(_on_screen_visibility_changed)
	_business_dashboard.opened.connect(_on_screen_visibility_changed)
	_business_dashboard.closed.connect(_on_screen_visibility_changed)
	_city_map.opened.connect(_on_screen_visibility_changed)
	_city_map.closed.connect(_on_screen_visibility_changed)
	_residence_panel.opened.connect(_on_screen_visibility_changed)
	_residence_panel.closed.connect(_on_screen_visibility_changed)

	MapManager.destination_changed.connect(_on_destination_changed)
	_business_dashboard.empire_requested.connect(_on_empire_requested)
	_empire_dashboard.opened.connect(_on_screen_visibility_changed)
	_empire_dashboard.closed.connect(_on_screen_visibility_changed)
	_empire_dashboard.business_selected.connect(_on_business_selected)

	BusinessManager.business_changed.connect(_on_owned_business_changed)
	BusinessManager.business_opened.connect(_on_owned_business_changed)
	BusinessManager.business_closed.connect(_on_owned_business_changed)

	_style_hud()
	_prompt_panel.visible = false
	_toast_panel.modulate.a = 0.0
	_pause_overlay.visible = false
	_build_pause_menu()
	_build_phase_m_screens()
	_speed_panel.visible = false
	_wanted_label.visible = false
	_escape_label.visible = false
	_busted_overlay.visible = false
	_store_panel.visible = false
	_destination_label.visible = false
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
	_refresh_destination()
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
## How far it is to wherever the player said they were going. One line, only when
## there is somewhere to go — the map is where the detail lives.
func _on_destination_changed(marker: MapMarker) -> void:
	_destination_label.visible = marker != null
	if marker != null:
		_destination_label.text = marker.label.to_upper()
	_update_process_need()


func _refresh_destination() -> void:
	if not _destination_label.visible:
		return
	var marker := MapManager.get_destination()
	if marker == null:
		_destination_label.visible = false
		return
	var distance := MapManager.distance_to_destination()
	_destination_label.text = "%s\n%s" % [
		marker.label.to_upper(),
		"%d m" % roundi(distance) if distance < 1000.0 else "%.1f km" % (distance / 1000.0),
	]


func _update_process_need() -> void:
	# A visible prompt is a third reason to tick: what an interactable offers can
	# change while the player stands still in front of it.
	set_process(
		_vehicle != null or _escape_label.visible or _prompt_panel.visible
		or _destination_label.visible
	)


# --- Screens -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("city_map"):
		if _city_map.is_open():
			_city_map.close()
		else:
			close_screens()
			_city_map.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("profile"):
		if _profile_panel.is_open():
			close_screens()
		else:
			close_screens()
			_profile_panel.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("real_estate"):
		if _real_estate_panel.is_open():
			close_screens()
		else:
			close_screens()
			_real_estate_panel.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("logistics"):
		if _logistics_panel.is_open():
			close_screens()
		else:
			close_screens()
			_logistics_panel.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("company"):
		if _company_dashboard.is_open():
			close_screens()
		else:
			close_screens()
			_company_dashboard.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("business_menu"):
		# One key, and it opens whichever answer the player is standing in front
		# of: the shop they are inside, or the company as a whole.
		if _business_dashboard.is_open() or _empire_dashboard.is_open():
			close_screens()
		elif _business_in_reach() != null:
			_business_dashboard.open(_business_in_reach())
		else:
			_empire_dashboard.open()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("inventory"):
		return
	# The bag is reachable from the shop counter too, so only the inventory
	# screen itself toggles off.
	if _inventory_panel.is_open():
		_inventory_panel.close()
	else:
		_inventory_panel.open(GameManager.player)
	get_viewport().set_input_as_handled()


## The HUD's own look. Kept here rather than in the scene so the whole
## interface — panels, prompts, needs — is styled from the one palette, and a
## colour change is a single edit instead of eight scene properties.
func _style_hud() -> void:
	var backdrop := UITheme.slab(Palette.UI_BACKDROP, Color(1, 1, 1, 0.10), 8, 10)
	_prompt_panel.add_theme_stylebox_override("panel", backdrop)
	_toast_panel.add_theme_stylebox_override("panel", backdrop)
	var store_panel: PanelContainer = %StorePanel
	store_panel.add_theme_stylebox_override(
		"panel", UITheme.slab(Palette.UI_BACKDROP, Color(1, 1, 1, 0.10), 8, 10)
	)

	# Needs bars: a dark track and a fill in the colour of the need, so the
	# three are told apart by hue rather than by reading the labels.
	for pair in [
		[_health_bar, Palette.DANGER], [_energy_bar, Palette.CALM],
		[_hunger_bar, Palette.WARNING],
	]:
		_style_bar(pair[0] as ProgressBar, pair[1] as Color)
	_style_bar(_vehicle_health_bar, Palette.MONEY)

	%CashLabel.add_theme_color_override("font_color", Palette.MONEY)
	%WantedLabel.add_theme_color_override("font_color", Palette.WARNING)
	%EscapeLabel.add_theme_color_override("font_color", Palette.DANGER)
	%DestinationLabel.add_theme_color_override("font_color", Palette.CALM)
	%DayLabel.add_theme_color_override("font_color", Palette.UI_MUTED)
	%TimeLabel.add_theme_color_override("font_color", Palette.UI_TEXT)


func _style_bar(bar: ProgressBar, colour: Color) -> void:
	if bar == null:
		return
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.043, 0.051, 0.075, 0.85)
	track.set_corner_radius_all(5)
	track.set_border_width_all(1)
	track.border_color = Color(1, 1, 1, 0.08)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)


func _on_screen_requested(screen_id: StringName, context: Node, requester: Node) -> void:
	match screen_id:
		&"shop":
			var buyer := requester if requester != null else GameManager.player
			_shop_panel.open(context as Shop, buyer)
		&"property":
			_property_panel.open(context as CommercialProperty)
		&"business":
			var equipment := context as BusinessEquipment
			_business_dashboard.open(
				equipment.business if equipment != null else _business_in_reach()
			)
		&"empire":
			_empire_dashboard.open()
		&"shelf":
			_business_dashboard.open_shelf(context as BusinessEquipment)
		&"residence":
			_residence_panel.open(context as ResidenceProperty)
		&"map":
			_city_map.open()
		&"dealership":
			_dealership_panel.open()
		&"dealership_vehicle":
			var stand := context as DealershipDisplay
			if stand != null:
				_vehicle_detail_panel.open(stand.model_id)
		&"repair":
			_repair_panel.open(context as RepairShop)
		&"garage":
			_garage_panel.open(context as GarageProperty)
		&"furniture_store":
			_furniture_store_panel.open()
		&"furnishing":
			var spot := context as FurnishingPoint
			if spot != null:
				_furnishing_panel.open(spot.residence_id)
		&"home_storage":
			var cupboard := context as HomeStoragePoint
			if cupboard != null:
				_home_storage_panel.open(cupboard.residence_id)
		&"profile":
			_profile_panel.open()
		&"company":
			_company_dashboard.open()
		&"logistics":
			_logistics_panel.open()
		&"company_staff":
			_company_dashboard.open(CompanyDashboard.Page.EMPLOYEES)
		&"manager":
			var equipment := context as BusinessEquipment
			var branch := (
				equipment.business if equipment != null else _business_in_reach()
			)
			if branch != null:
				_manager_panel.open(branch)
		&"property_sale":
			_property_sale_panel.open(_property_id_of(context))
		&"real_estate":
			_real_estate_panel.open(_property_id_of(context))
		_:
			push_warning("HUD has no screen for '%s'." % screen_id)


func close_screens() -> void:
	_inventory_panel.close()
	_shop_panel.close()
	_property_panel.close()
	_business_dashboard.close()
	_residence_panel.close()
	_city_map.close()
	_empire_dashboard.close()
	for screen in _phase_m_screens():
		screen.close()


## The business the management key should open: the one the player is standing
## in if they are in one, otherwise the first they founded.
func _business_in_reach() -> BusinessInstance:
	for node in get_tree().get_nodes_in_group(&"retail_unit"):
		var unit := node as RetailUnit
		if unit != null and unit.is_player_inside() and unit.get_business() != null:
			return unit.get_business()
	return null


## A screen being up freezes the world, so the manager has to know.
func _on_screen_visibility_changed() -> void:
	var phase_m_open := false
	for screen in _phase_m_screens():
		phase_m_open = phase_m_open or screen.is_open()
	GameManager.menu_open = (
		_inventory_panel.is_open() or _shop_panel.is_open()
		or _property_panel.is_open() or _business_dashboard.is_open()
		or _empire_dashboard.is_open() or phase_m_open
	)


## The two dashboards hand off to each other rather than stacking.
func _on_empire_requested() -> void:
	_business_dashboard.close()
	_empire_dashboard.open()


func _on_business_selected(business: BusinessInstance) -> void:
	_empire_dashboard.close()
	_business_dashboard.open(business)


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


# --- Owned business ------------------------------------------------------

## A three-line reminder while the player is stood in their own shop. Everything
## else about the business lives in the dashboard; the HUD stays the HUD.
func _on_owned_business_changed(business: BusinessInstance) -> void:
	var here := _business_in_reach()
	if here == null or here != business:
		if here == null:
			_store_panel.visible = false
		return
	_store_name.text = business.business_name.to_upper()
	var spawner_count := 0
	var unit := RetailUnit.for_business(business, get_tree())
	if unit != null:
		var spawner := unit.get_spawner()
		if spawner != null:
			spawner_count = spawner.active_customers().size()
	_store_status.text = "%s  ·  customers %d  ·  %s today" % [
		business.status_text(), spawner_count,
		"$%d" % business.revenue_today,
	]
	_store_panel.visible = unit != null and unit.is_player_inside()


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


## A quiet line in the corner while the game saves itself. Deliberately a toast
## rather than anything modal: an autosave the player has to acknowledge is
## worse than no autosave.
func _on_autosave_started(_reason: String) -> void:
	_show_toast("SAVING…", GameManager.Tone.INFO)


func _on_autosave_finished(succeeded: bool) -> void:
	if not succeeded:
		_show_toast("AUTOSAVE FAILED", GameManager.Tone.BAD)


## The ownership screens: the dealership, the mechanic, the garage, the
## furniture shop, the furnishing list, the cupboard, the profile and the two
## property screens.
##
## Built in code and parented here for the same reason the pause menu is —
## their contents are lists whose length depends on what the player owns, so
## there is nothing to lay out in a scene file that the code would not
## immediately replace.
func _build_phase_m_screens() -> void:
	var root := get_node_or_null("Root")
	var host: Node = root if root != null else self

	_dealership_panel = DealershipPanel.new()
	_dealership_panel.name = "DealershipPanel"
	_vehicle_detail_panel = VehicleDetailPanel.new()
	_vehicle_detail_panel.name = "VehicleDetailPanel"
	_repair_panel = RepairPanel.new()
	_repair_panel.name = "RepairPanel"
	_garage_panel = GaragePanel.new()
	_garage_panel.name = "GaragePanel"
	_furniture_store_panel = FurnitureStorePanel.new()
	_furniture_store_panel.name = "FurnitureStorePanel"
	_furnishing_panel = FurnishingPanel.new()
	_furnishing_panel.name = "FurnishingPanel"
	_home_storage_panel = HomeStoragePanel.new()
	_home_storage_panel.name = "HomeStoragePanel"
	_profile_panel = ProfilePanel.new()
	_profile_panel.name = "ProfilePanel"
	_company_dashboard = CompanyDashboard.new()
	_company_dashboard.name = "CompanyDashboard"
	_staff_schedule_panel = StaffSchedulePanel.new()
	_staff_schedule_panel.name = "StaffSchedulePanel"
	_manager_panel = ManagerPanel.new()
	_manager_panel.name = "ManagerPanel"
	_logistics_panel = LogisticsPanel.new()
	_logistics_panel.name = "LogisticsPanel"
	_branch_finance_panel = BranchFinancePanel.new()
	_branch_finance_panel.name = "BranchFinancePanel"
	_property_sale_panel = PropertySalePanel.new()
	_property_sale_panel.name = "PropertySalePanel"
	_real_estate_panel = RealEstatePanel.new()
	_real_estate_panel.name = "RealEstatePanel"

	for screen in _phase_m_screens():
		host.add_child(screen)
		screen.opened.connect(_on_screen_visibility_changed)
		screen.closed.connect(_on_screen_visibility_changed)

	# The stand beside a car offers COMPARE, and comparing is something the
	# sales desk screen does, so the two hand off rather than stacking.
	_vehicle_detail_panel.compare_requested.connect(_on_compare_requested)
	# The company screen hands off to the two screens that edit one thing: a
	# person's week, and a branch's manager. Same pattern, same reason.
	_company_dashboard.schedule_requested.connect(_on_schedule_requested)
	_company_dashboard.manager_requested.connect(_on_manager_requested)
	_company_dashboard.finance_requested.connect(_on_finance_requested)


func _phase_m_screens() -> Array:
	return [
		_dealership_panel, _vehicle_detail_panel, _repair_panel, _garage_panel,
		_furniture_store_panel, _furnishing_panel, _home_storage_panel, _profile_panel,
		_property_sale_panel, _real_estate_panel,
		_company_dashboard, _staff_schedule_panel, _manager_panel, _logistics_panel,
		_branch_finance_panel,
	]


## Which property a screen request is about. A for-sale board carries the id of
## the address it stands outside; a block of flats is its own id.
func _property_id_of(context: Node) -> StringName:
	var board := context as PropertySign
	if board != null:
		return board.property_id
	var block := context as MultiUnitBuilding
	if block != null:
		return block.building_id
	return &""


func _on_schedule_requested(worker: EmployeeData) -> void:
	_company_dashboard.close()
	_staff_schedule_panel.open(worker)


func _on_finance_requested(business: BusinessInstance) -> void:
	_company_dashboard.close()
	_branch_finance_panel.open(business)


func _on_manager_requested(business: BusinessInstance) -> void:
	_company_dashboard.close()
	_manager_panel.open(business)


func _on_compare_requested(_model_id: StringName) -> void:
	_vehicle_detail_panel.close()
	_dealership_panel.open(DealershipPanel.Tab.NEW)


## The pause menu, added to the HUD rather than given its own scene: pausing
## should not cost a scene change, and everything it needs is already here.
func _build_pause_menu() -> void:
	if get_node_or_null("Root/PauseMenu") != null:
		return
	var menu := PauseMenu.new()
	menu.name = "PauseMenu"
	var root := get_node_or_null("Root")
	if root == null:
		add_child(menu)
	else:
		root.add_child(menu)


func _on_game_state_changed(_state: int) -> void:
	# The old overlay was a dim and the word PAUSED. The pause menu replaces it,
	# and manages its own visibility from the same signal.
	_pause_overlay.visible = false
