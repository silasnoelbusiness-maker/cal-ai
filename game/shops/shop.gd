class_name Shop
extends Interactable
## A counter the player can buy from.
##
## Stock is a list of ItemData resources, so a new shop is a new stock list and
## a pair of opening hours — nothing about the convenience store is hard-coded.
## Restaurants, car dealers and player-owned businesses later reuse this by
## swapping the stock and overriding `get_price`.

signal purchase_made(item: ItemData, price: int)
signal purchase_failed(item: ItemData, result: Result)
signal robbery_started(robber: Node)
signal robbery_finished(takings: int)
signal robbery_failed(reason: RobberyResult)

enum Result { OK, CLOSED, NOT_ENOUGH_CASH, INVENTORY_FULL, NO_BUYER }
enum RobberyResult { OK, NOT_ROBBABLE, CLOSED, ON_COOLDOWN, ALREADY_RUNNING, NO_ROBBER }

@export var shop_name: String = "Shop"
## Stable id for the save file. The robbery cooldown has to survive a save, or
## sleeping through it would be a way to reset a shop that has just been done.
@export var save_id: StringName = &""
@export var stock: Array[ItemData] = []
@export_group("Opening hours")
@export_range(0, 23) var opens_hour: int = 6
@export_range(0, 24) var closes_hour: int = 23
## Multiplies the item's base price. Lets a later premium shop charge more
## without duplicating the item catalogue.
@export var price_multiplier: float = 1.0

@export_group("Robbery")
@export var robbable: bool = false
## Seconds of tension before the till is handed over. The window in which a
## witness can call it in, the police can arrive, or the player can walk out.
@export var robbery_seconds: Vector2 = Vector2(3.0, 6.0)
## Range the till pays out, in whole dollars. Set against the warehouse shift's
## $120: worth doing, not worth doing instead of everything else.
@export var robbery_reward: Vector2i = Vector2i(150, 500)
## In-game days before the same shop can be robbed again. Data, not code — a
## bigger shop later just carries a longer number.
@export var robbery_cooldown_days: int = 3
## The cashier. Set by whoever builds the shop; a shop with none can still be
## robbed, it just has nobody to be frightened.
@export var employee_path: NodePath

var recently_robbed: bool = false

var _robbed_on_day: int = -9999
var _robbery_running: bool = false
## Which robbery is the current one. A robbery that was walked out on still has
## a timer running somewhere; without this, that timer wakes up during the *next*
## robbery, sees one in progress, and pays out the abandoned one's money instead.
var _robbery_id: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if save_id != &"":
		add_to_group(&"saveable")
	add_to_group(&"shop")
	TimeManager.hour_passed.connect(_on_hour_passed)
	TimeManager.day_passed.connect(_on_day_passed)
	TimeManager.clock_synced.connect(_refresh_open_state)
	TimeManager.clock_synced.connect(_refresh_robbery_state)
	_refresh_open_state()


func is_open() -> bool:
	var hour := TimeManager.hour
	if opens_hour == closes_hour:
		return true
	if opens_hour < closes_hour:
		return hour >= opens_hour and hour < closes_hour
	# Wraps past midnight.
	return hour >= opens_hour or hour < closes_hour


# --- Robbery -------------------------------------------------------------

func can_be_robbed() -> RobberyResult:
	if not robbable:
		return RobberyResult.NOT_ROBBABLE
	if _robbery_running:
		return RobberyResult.ALREADY_RUNNING
	if recently_robbed:
		return RobberyResult.ON_COOLDOWN
	if not is_open():
		return RobberyResult.CLOSED
	return RobberyResult.OK


func is_being_robbed() -> bool:
	return _robbery_running


func get_employee() -> Node3D:
	if employee_path.is_empty():
		return null
	return get_node_or_null(employee_path) as Node3D


## Robs the till.
##
## Deliberately not instant. The cashier is frightened straight away and the
## crime is filed straight away — so a witness can call it in, and the police can
## already be moving — but the money only arrives at the end of the tension
## window. That window is the whole risk: leave early and there is nothing to
## show for it, stay and the response may already be outside.
func rob(robber: Node) -> RobberyResult:
	if robber == null:
		robbery_failed.emit(RobberyResult.NO_ROBBER)
		return RobberyResult.NO_ROBBER
	var verdict := can_be_robbed()
	if verdict != RobberyResult.OK:
		robbery_failed.emit(verdict)
		GameManager.notify(describe_robbery_result(verdict), GameManager.Tone.BAD)
		return verdict

	_robbery_running = true
	_robbery_id += 1
	var this_robbery := _robbery_id
	robbery_started.emit(robber)
	GameManager.notify("ROBBING %s
HOLD ON..." % shop_name.to_upper(), GameManager.Tone.BAD)

	var employee := get_employee()
	var wait := _rng.randf_range(robbery_seconds.x, robbery_seconds.y)
	if employee != null and employee.has_method("enter_fear"):
		# Frightened for the whole window and a moment longer, so they are still
		# visibly shaken when the player turns to leave.
		employee.call("enter_fear", robber.global_position, wait + 3.0)

	# Filed now, not at the payout: the crime is the threat, and the police
	# should be able to arrive *during* it.
	var takings := _rng.randi_range(robbery_reward.x, robbery_reward.y)
	CrimeManager.report_crime(
		CrimeManager.CrimeType.STORE_ROBBERY,
		global_position,
		robber,
		self,
		false,
		{"reward_value": takings, "victim": employee, "shop_name": shop_name}
	)
	_frighten_bystanders(robber)

	await get_tree().create_timer(wait).timeout

	# Walking out mid-robbery is allowed, and costs the money. The crime stands.
	if not _robbery_running or this_robbery != _robbery_id:
		return RobberyResult.OK

	_robbery_running = false
	_mark_robbed()
	EconomyManager.deposit(takings, "%s — robbery" % shop_name, EconomyManager.Source.CRIME)
	GameManager.notify("STORE ROBBERY
+$%d" % takings, GameManager.Tone.BAD)
	robbery_finished.emit(takings)
	return RobberyResult.OK


## Abandons a robbery in progress. The crime has already been filed; only the
## payout is lost.
func abandon_robbery() -> void:
	if not _robbery_running:
		return
	_robbery_running = false
	_mark_robbed()
	GameManager.notify("YOU LEFT EMPTY HANDED", GameManager.Tone.INFO)


static func describe_robbery_result(result: RobberyResult) -> String:
	match result:
		RobberyResult.ON_COOLDOWN:
			return "THE TILL IS EMPTY"
		RobberyResult.CLOSED:
			return "THE SHOP IS CLOSED"
		RobberyResult.ALREADY_RUNNING:
			return ""
		RobberyResult.NOT_ROBBABLE:
			return "NOTHING WORTH TAKING"
		_:
			return "CANNOT ROB THAT"


## Everyone nearby who can see it gets a fright. Distance-filtered rather than
## broadcast, so a robbery in a shop does not empty the street outside.
func _frighten_bystanders(robber: Node) -> void:
	for civilian in get_tree().get_nodes_in_group(&"pedestrian"):
		if civilian == robber or not (civilian is Node3D):
			continue
		if civilian.global_position.distance_to(global_position) > 14.0:
			continue
		if civilian.has_method("enter_fear"):
			civilian.call("enter_fear", global_position)


func _mark_robbed() -> void:
	recently_robbed = true
	_robbed_on_day = TimeManager.day_index
	_refresh_open_state()


func _refresh_robbery_state() -> void:
	if not recently_robbed:
		return
	if TimeManager.day_index - _robbed_on_day >= robbery_cooldown_days:
		recently_robbed = false
	_refresh_open_state()


func _on_day_passed(_day: int) -> void:
	_refresh_robbery_state()


# --- Trading -------------------------------------------------------------

func get_price(item: ItemData) -> int:
	if item == null:
		return 0
	return maxi(1, roundi(float(item.price) * price_multiplier))


## Runs a purchase end to end: checks, payment, delivery. Returns why it failed
## so the UI can say something specific.
func buy(item: ItemData, buyer: Node) -> Result:
	if not is_open():
		purchase_failed.emit(item, Result.CLOSED)
		return Result.CLOSED
	if item == null or buyer == null or not buyer.has_method("get_inventory"):
		purchase_failed.emit(item, Result.NO_BUYER)
		return Result.NO_BUYER

	var inventory: Inventory = buyer.call("get_inventory")
	if inventory == null:
		purchase_failed.emit(item, Result.NO_BUYER)
		return Result.NO_BUYER

	var price := get_price(item)
	if not EconomyManager.can_afford(price):
		purchase_failed.emit(item, Result.NOT_ENOUGH_CASH)
		return Result.NOT_ENOUGH_CASH
	# Check room before taking the money, so a full bag never costs the player.
	if not inventory.can_add(item, 1):
		purchase_failed.emit(item, Result.INVENTORY_FULL)
		return Result.INVENTORY_FULL

	if not EconomyManager.spend(price, "%s — %s" % [shop_name, item.display_name]):
		purchase_failed.emit(item, Result.NOT_ENOUGH_CASH)
		return Result.NOT_ENOUGH_CASH

	inventory.add(item, 1)
	purchase_made.emit(item, price)
	return Result.OK


static func describe_result(result: Result) -> String:
	match result:
		Result.OK:
			return ""
		Result.CLOSED:
			return "THE SHOP IS CLOSED"
		Result.NOT_ENOUGH_CASH:
			return "NOT ENOUGH CASH"
		Result.INVENTORY_FULL:
			return "NO ROOM IN YOUR BAG"
		_:
			return "CANNOT BUY THAT"


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"shop", self, interactor)


## Robbery is a second verb on the same counter, so it listens for its own key
## rather than being a second interactable competing for focus. It only fires
## while this counter is the focused one, which is exactly the "player is stood
## at the till" test the normal prompt already does.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("rob") or not robbable:
		return
	if not _is_focused_by_player():
		return
	get_viewport().set_input_as_handled()
	rob(GameManager.player)


func _is_focused_by_player() -> bool:
	var player := GameManager.player
	if player == null:
		return false
	var controller = player.get("interaction")
	if controller == null or not controller.has_method("get_focused"):
		return false
	return controller.call("get_focused") == self


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	return {"recently_robbed": recently_robbed, "robbed_on_day": _robbed_on_day}


func load_state(state: Dictionary) -> void:
	recently_robbed = bool(state.get("recently_robbed", false))
	_robbed_on_day = int(state.get("robbed_on_day", -9999))
	_refresh_robbery_state()


func _on_hour_passed(_hour: int) -> void:
	_refresh_open_state()


func _refresh_open_state() -> void:
	available = is_open()
	unavailable_prompt = "CLOSED · opens %02d:00" % opens_hour


func get_prompt_text() -> String:
	var base := super.get_prompt_text()
	# The robbery lives on the same prompt rather than on a second interactable,
	# because only one interactable can hold focus and two overlapping counters
	# would mean the player could only ever see one of the two things they can do
	# at a till.
	if available and robbable and can_be_robbed() == RobberyResult.OK:
		return "%s\nG — Rob the till" % base
	return base
