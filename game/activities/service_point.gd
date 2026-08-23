class_name ServicePoint
extends Interactable
## A counter you can order from: a cafe, a diner, a gym, a bar.
##
## The city already had places the player walked past. This is what makes them
## somewhere to go.
##
## A venue the player happens to own is the same counter with a different till:
## the money moves from their pocket into the business rather than out of the
## world, and it is never revenue, because selling yourself a coffee is not
## trade. A quiet shop must not be made to look busy by eating in it.

signal service_taken(service: VenueService, paid: int)

enum Result { OK, CLOSED, NOT_ENOUGH_CASH, NO_BUYER }

@export var venue_name: String = "Counter"
@export var venue_kind: ServiceCatalogue.Kind = ServiceCatalogue.Kind.CAFE
@export_range(0, 23) var opens_hour: int = 7
@export_range(0, 24) var closes_hour: int = 22
## Multiplies every price here, for a venue dearer than the standard.
@export var price_multiplier: float = 1.0
## Set when this counter belongs to one of the player's own businesses. Looked
## up by id each time rather than held, so selling the business cannot leave a
## counter paying into a company that no longer exists.
@export var business_id: StringName = &""


func _init() -> void:
	super()
	prompt_action = "Order"
	focus_priority = 1


func _ready() -> void:
	prompt_subtitle = venue_name
	TimeManager.hour_passed.connect(_on_hour_passed)
	_refresh()


func _on_hour_passed(_hour: int) -> void:
	_refresh()


func _refresh() -> void:
	if is_open():
		available = true
		unavailable_prompt = ""
		return
	unavailable_prompt = "%s — CLOSED\nOpen %02d:00 – %02d:00" % [
		venue_name.to_upper(), opens_hour, closes_hour
	]
	available = false


func is_open() -> bool:
	var hour := TimeManager.hour
	if closes_hour > opens_hour:
		return hour >= opens_hour and hour < closes_hour
	# A bar that shuts at three in the morning is open across midnight.
	return hour >= opens_hour or hour < closes_hour


func services() -> Array[VenueService]:
	return ServiceCatalogue.for_kind(venue_kind)


func price_of(service: VenueService) -> int:
	return maxi(1, int(round(float(service.price) * price_multiplier)))


## The player's own business behind this counter, or null.
func owning_business() -> BusinessInstance:
	if business_id == &"":
		return null
	return BusinessManager.by_id(business_id)


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"venue", self, interactor)


## Takes an order. Returns what happened so the screen can say something
## specific rather than merely failing.
func order(service: VenueService, buyer: Node) -> Result:
	if service == null or buyer == null or not buyer.has_method("get_stats"):
		return Result.NO_BUYER
	if not is_open():
		return Result.CLOSED
	var price := price_of(service)
	if not EconomyManager.can_afford(price):
		return Result.NOT_ENOUGH_CASH

	var business := owning_business()
	if not EconomyManager.spend(price, "%s — %s" % [venue_name, service.label]):
		return Result.NOT_ENOUGH_CASH
	if business != null:
		# Straight across, not takings. The daily report must never show the
		# owner's lunch as trade.
		business.credit(price, "Owner's order — %s" % service.label, &"owner_funds")

	# The clock moves before the needs do, so the drain for the time spent is
	# charged against the state the player walked in with.
	if service.minutes > 0:
		TimeManager.advance_minutes(service.minutes)

	var stats: PlayerStats = buyer.call("get_stats")
	if stats != null:
		stats.add_hunger(service.hunger)
		stats.add_energy(service.energy)
		stats.add_health(service.health)

	_count(service)
	service_taken.emit(service, price)
	GameManager.notify(
		"%s\n%s  −$%d" % [venue_name.to_upper(), service.label, price],
		GameManager.Tone.INFO
	)
	return Result.OK


## Pushed from here rather than pulled by the counters file, which names
## nothing. See the note at the top of life_stats.gd for why that matters.
func _count(service: VenueService) -> void:
	if service.hunger >= 20.0:
		LifeStats.add(&"meals_eaten")
		Onboarding.report(&"food_bought")
	if venue_kind == ServiceCatalogue.Kind.CAFE and service.energy > 0.0:
		LifeStats.add(&"coffees_drunk")
	if venue_kind == ServiceCatalogue.Kind.GYM and service.health > 4.0:
		LifeStats.add(&"gym_sessions")


static func describe_result(result: Result) -> String:
	match result:
		Result.CLOSED:
			return "THEY ARE CLOSED"
		Result.NOT_ENOUGH_CASH:
			return "NOT ENOUGH CASH"
		Result.NO_BUYER:
			return "NOBODY TO SERVE"
	return ""
