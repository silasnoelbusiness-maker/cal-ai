extends Node
## Buying the city rather than renting it.
##
## The layer above the doors. Every address in the game is already a node that
## knows how to be leased — a CommercialProperty or a ResidenceProperty — and
## this does not replace any of that. It adds the other relationship you can
## have with a building: owning it, owing money on it, and letting it to
## somebody else. Both are keyed to the same `property_id`, which is what lets a
## player rent a unit, trade from it for a fortnight and then buy the building
## without anything inside the shop noticing.
##
## Everything here is data. A portfolio of nine let units is nine records and no
## extra nodes, no tenants walking about and nothing simulated per minute; the
## day tick does the work, which is also what makes sleeping through a week
## behave exactly like living through one.

signal portfolio_changed()
signal property_bought(record: PropertyRecord)
signal property_sold(record: PropertyRecord, proceeds: int)
signal mortgage_opened(loan: MortgageData)
signal mortgage_settled(loan: MortgageData)
signal mortgage_payment_made(loan: MortgageData, interest: int, principal: int)
signal mortgage_missed(loan: MortgageData)
signal tenant_signed(record: PropertyRecord, tenant: TenantData)
signal tenant_left(record: PropertyRecord, tenant: TenantData)
signal rent_received(record: PropertyRecord, amount: int)
signal listing_discovered(listing: PropertyListing)
signal foreclosure_started(loan: MortgageData)
signal foreclosure_cured(loan: MortgageData)
signal foreclosure_completed(loan: MortgageData, recovered: int)

enum BuyResult {
	OK, NO_LISTING, ALREADY_OWNED, CANNOT_AFFORD, NOT_DISCOVERED,
	NO_MORTGAGE_OFFERED, NOT_ELIGIBLE,
}
enum SellResult { OK, NOT_OWNED, BUSINESS_OCCUPIES }

var save_id: StringName = &"real_estate"

# --- Valuation ------------------------------------------------------------
#
# An authored floor area and pitch, run through the same short formula for
# every building, rather than a price per address. It means a renovated
# property is worth more for a reason the player can follow, and it means the
# market can move everything at once without touching a table.

## Value per square metre before anything is taken into account.
const RATE_BY_KIND := {
	PropertyRecord.Kind.RESIDENTIAL: 1150.0,
	PropertyRecord.Kind.COMMERCIAL: 3300.0,
	PropertyRecord.Kind.MULTI_UNIT: 1050.0,
}
## Central is dearer than Harbour Row, which is the difference the districts
## were built to have.
const DISTRICT_MULTIPLIER := {
	&"harbour_row": 1.0,
	&"central": 1.25,
}

## Rent for one period, as a fraction of what the property is worth, and upkeep
## as a fraction of the same.
##
## Rent is then tilted by the pitch: a fringe flat lets for proportionally more
## than a prime one, which is both how the real market behaves and the only way
## the yield figure means anything. A flat fraction of value would give every
## listing in the city the same yield and make the number decorative.
const RENT_FRACTION := 0.0075
const MAINTENANCE_FRACTION := 0.0014
const YIELD_TILT_FRINGE := 1.25
const YIELD_TILT_PRIME := 0.72

## How far the whole market can drift, and how fast. Slow on purpose: this is a
## game about running things, not about trading houses.
const TREND_FLOOR := 0.92
const TREND_CEILING := 1.12
const TREND_STEP := 0.004

## Condition falls by this much a day for an empty building. A tenant adds
## their own wear on top. A hundred days of neglect costs about eight points.
const IDLE_WEAR_PER_DAY := 0.08

## How long a tenancy runs, and how often rent is charged.
const LEASE_DAYS := 28
const RENT_INTERVAL_DAYS := 7
const MORTGAGE_INTERVAL_DAYS := 7
const MORTGAGE_TERM_PAYMENTS := 200
const MORTGAGE_RATE := 0.06

## What the player has to have behind them before a lender will look at them,
## on top of the deposit.
const MIN_NET_WORTH_FOR_CREDIT := 12000

## Selling costs this fraction of the price. Enough that buying and selling the
## same building back and forth loses money, which is the point of it.
const SELLING_COST_FRACTION := 0.04
## What a forced sale fetches against the open market. A lender in a hurry does
## not get the best price, and the player wears the difference.
const FORECLOSURE_SALE_FRACTION := 0.82

## What a renovation costs and buys. Each entry: label, condition floor it
## lifts to, cost per point of condition gained, days it takes.
const RENOVATIONS := {
	&"repair": ["Basic repair", 88.0, 240.0, 1],
	&"renovation": ["Full renovation", 96.0, 420.0, 2],
	&"premium": ["Premium finish", 100.0, 760.0, 3],
}

var _listings: Array[PropertyListing] = []
var _records: Array[PropertyRecord] = []
var _mortgages: Array[MortgageData] = []
## Tenants in place, and the applicants waiting on a listed property.
var _tenants: Array[TenantData] = []
var _candidates: Dictionary = {}
var _market_trend: float = 1.0
var _next_number: int = 1
var _rng := RandomNumberGenerator.new()

## Running totals for the income report, since the shared ledger has no
## property category of its own.
var _rent_collected: int = 0
var _maintenance_paid: int = 0
var _interest_paid: int = 0
var _principal_paid: int = 0
var _vacancy_lost: int = 0
## Rent banked during the current day's tick, so the arrival of it is announced
## once rather than once per tenant.
var _rent_today: int = 0

var _built: bool = false


func _ready() -> void:
	add_to_group(&"saveable")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	TimeManager.day_passed.connect(_on_day_passed)
	# The world has to exist before its addresses can be listed.
	call_deferred("build_market")


# --- The market ----------------------------------------------------------

## Reads the city's own doors and puts some of them up for sale.
##
## Which addresses are on the market is authored here rather than on the nodes:
## it is a market decision, it changes between phases, and a district script
## should not have to know what a mortgage is.
func build_market() -> void:
	if _built:
		return
	_built = true
	_listings.clear()

	for home in PropertyManager.get_residences():
		var listing := _listing_for_residence(home)
		if listing != null:
			_listings.append(listing)
	for unit in PropertyManager.get_properties():
		var listing := _listing_for_commercial(unit)
		if listing != null:
			_listings.append(listing)
	for node in get_tree().get_nodes_in_group(&"multi_unit_building"):
		var block := node as MultiUnitBuilding
		if block != null:
			_listings.append(_listing_for_block(block))

	_listings.sort_custom(
		func(a: PropertyListing, b: PropertyListing) -> bool:
			return a.asking_price < b.asking_price
	)
	_refresh_signage()
	portfolio_changed.emit()


## A board outside everything on the market, and none outside anything that is
## not. Rebuilt wholesale rather than patched: the listings are the truth and
## the signs are a view of them, which is the same arrangement the cars and the
## furniture use.
func _refresh_signage() -> void:
	for node in get_tree().get_nodes_in_group(&"property_sign"):
		var sign := node as PropertySign
		if sign == null:
			continue
		if listing_for(sign.property_id) == null:
			sign.remove()

	for listing in _listings:
		if _sign_exists(listing.property_id):
			continue
		var anchor := door_for(listing.property_id)
		if anchor == null:
			continue
		var at := anchor.global_position
		# Out of the doorway and well to one side of it, facing the same way the
		# door does so the board reads from the street. Sideways along the door's
		# own right rather than along world x, because half the doors in the city
		# face across it and a fixed offset would stand the board in a doorway
		# the player uses every day.
		var facing := anchor.global_transform.basis.z
		var beside := anchor.global_transform.basis.x
		PropertySign.build(
			anchor.get_parent(), listing.property_id,
			at + facing * 1.7 + beside * 2.8 + Vector3(0.0, -0.9, 0.0),
			# The board reads off its local -Z, so it has to be turned to face
			# back down the door's own forward — half a turn from the door.
			rad_to_deg(atan2(-facing.x, -facing.z))
		)


func _sign_exists(property_id: StringName) -> bool:
	for node in get_tree().get_nodes_in_group(&"property_sign"):
		var sign := node as PropertySign
		if sign != null and sign.property_id == property_id:
			return true
	return false


## The node in the world that stands for an address. Public because the map
## needs somewhere to put a marker, and a door is where an address is.
func door_for(property_id: StringName) -> Node3D:
	var unit := PropertyManager.by_id(property_id)
	if unit != null:
		return unit
	var home := PropertyManager.residence_by_id(property_id)
	if home != null:
		return home
	return _block_for(property_id)


## Floor area and pitch for the three flats, since a residence node describes
## how it is let rather than how much of it there is.
const RESIDENCE_FACTS := {
	&"larkspur": [34, 42],
	&"meridian": [58, 70],
	&"central_heights": [110, 92],
}


func _listing_for_residence(home: ResidenceProperty) -> PropertyListing:
	var facts: Array = RESIDENCE_FACTS.get(home.residence_id, [40, 50])
	var listing := PropertyListing.new()
	listing.property_id = home.residence_id
	listing.address = home.address
	listing.district_id = home.district_id
	listing.kind = PropertyRecord.Kind.RESIDENTIAL
	listing.size_label = home.size_label
	listing.floor_area = int(facts[0])
	listing.location_quality = int(facts[1])
	listing.condition = 86.0
	listing.market_value = value_of(
		listing.kind, listing.floor_area, listing.location_quality,
		listing.district_id, listing.condition
	)
	listing.asking_price = listing.market_value
	listing.estimated_rent = rent_for_value(listing.market_value, listing.location_quality)
	listing.base_maintenance = maintenance_for_value(listing.market_value)
	return listing


func _listing_for_commercial(unit: CommercialProperty) -> PropertyListing:
	var listing := PropertyListing.new()
	listing.property_id = unit.property_id
	listing.address = unit.address
	listing.district_id = unit.district_id
	listing.kind = PropertyRecord.Kind.COMMERCIAL
	listing.size_label = unit.size_label()
	listing.floor_area = unit.floor_area
	# The pitch the unit already claims to have, on the same 0-100 scale.
	listing.location_quality = clampi(
		roundi((unit.location_demand_modifier - 0.5) / 1.5 * 100.0), 5, 98
	)
	listing.condition = 84.0
	listing.market_value = value_of(
		listing.kind, listing.floor_area, listing.location_quality,
		listing.district_id, listing.condition
	)
	listing.asking_price = listing.market_value
	listing.estimated_rent = rent_for_value(listing.market_value, listing.location_quality)
	listing.base_maintenance = maintenance_for_value(listing.market_value)
	return listing


func _listing_for_block(block: MultiUnitBuilding) -> PropertyListing:
	var listing := PropertyListing.new()
	listing.property_id = block.building_id
	listing.address = block.address
	listing.district_id = block.district_id
	listing.kind = PropertyRecord.Kind.MULTI_UNIT
	listing.size_label = "%d units" % block.unit_count
	listing.floor_area = block.floor_area
	listing.location_quality = block.location_quality
	listing.condition = block.condition
	listing.market_value = value_of(
		listing.kind, listing.floor_area, listing.location_quality,
		listing.district_id, listing.condition
	)
	listing.asking_price = listing.market_value
	# Four units, each earning its share.
	listing.estimated_rent = rent_for_value(listing.market_value, listing.location_quality)
	listing.base_maintenance = maintenance_for_value(listing.market_value)
	return listing


## The valuation, in one place. Size, pitch, district, type and condition, all
## against the same market trend.
func value_of(
	kind: PropertyRecord.Kind, floor_area: int, location_quality: int,
	district_id: StringName, condition: float
) -> int:
	var rate: float = RATE_BY_KIND.get(kind, 1150.0)
	var pitch := lerpf(0.75, 1.35, clampf(float(location_quality) / 100.0, 0.0, 1.0))
	var district: float = DISTRICT_MULTIPLIER.get(district_id, 1.0)
	var repair := lerpf(0.72, 1.08, clampf(condition / 100.0, 0.0, 1.0))
	return maxi(roundi(float(floor_area) * rate * pitch * district * repair * _market_trend), 1)


## What a property of this value on this pitch lets for, per period.
func rent_for_value(value: int, location_quality: int = 50) -> int:
	var tilt := lerpf(
		YIELD_TILT_FRINGE, YIELD_TILT_PRIME,
		clampf(float(location_quality) / 100.0, 0.0, 1.0)
	)
	return maxi(roundi(float(value) * RENT_FRACTION * tilt), 1)


func maintenance_for_value(value: int) -> int:
	return maxi(roundi(float(value) * MAINTENANCE_FRACTION), 1)


func market_trend() -> float:
	return _market_trend


func listings() -> Array[PropertyListing]:
	return _listings.duplicate()


## What the market screen shows: only what the player has actually stood in
## front of. The city is meant to be driven around, not browsed.
func discovered_listings() -> Array[PropertyListing]:
	var found: Array[PropertyListing] = []
	for listing in _listings:
		if listing.discovered:
			found.append(listing)
	return found


func listing_for(property_id: StringName) -> PropertyListing:
	for listing in _listings:
		if listing.property_id == property_id:
			return listing
	return null


func is_for_sale(property_id: StringName) -> bool:
	return listing_for(property_id) != null


## Called when the player looks at a property in the world.
func discover(property_id: StringName) -> void:
	var listing := listing_for(property_id)
	if listing == null or listing.discovered:
		return
	listing.discovered = true
	listing_discovered.emit(listing)
	portfolio_changed.emit()


# --- Ownership -----------------------------------------------------------

func portfolio() -> Array[PropertyRecord]:
	return _records.duplicate()


func owns(property_id: StringName) -> bool:
	return record_for(property_id) != null


func record_for(property_id: StringName) -> PropertyRecord:
	for record in _records:
		if record.property_id == property_id:
			return record
	return null


func count() -> int:
	return _records.size()


## Whether a lender would deal with this player at all. Deliberately shallow —
## enough money down, nothing badly overdue, and something behind them.
func is_credit_eligible() -> bool:
	if BusinessManager.net_worth() < MIN_NET_WORTH_FOR_CREDIT:
		return false
	for loan in _mortgages:
		if loan.status == MortgageData.Status.AT_RISK or loan.is_foreclosing():
			return false
	# §41 and §144 — a fresh application asks; the mortgages already running do
	# not, and nothing here can foreclose on one because of a record.
	return bool(LegalManager.lender_view()["accepted"])


func credit_refusal_reason() -> String:
	var view := LegalManager.lender_view()
	if not bool(view["accepted"]):
		return String(view["reason"])
	if BusinessManager.net_worth() < MIN_NET_WORTH_FOR_CREDIT:
		return "A lender wants to see $%s behind you first." % (
			EconomyManager.with_thousands_separator(MIN_NET_WORTH_FOR_CREDIT)
		)
	for loan in _mortgages:
		if loan.is_foreclosing():
			return "No lender will touch you while one of your properties is being taken."
		if loan.status == MortgageData.Status.AT_RISK:
			return "Settle the mortgage that is behind before taking another."
	return ""


## Cash purchase. The money leaves the player's own pocket once, the listing
## goes, and a record takes its place.
func buy_with_cash(property_id: StringName) -> BuyResult:
	# Ownership first. Buying something takes it off the market, so asking the
	# listing first would answer "no such address" for a building the player is
	# standing in.
	if owns(property_id):
		return BuyResult.ALREADY_OWNED
	var listing := listing_for(property_id)
	if listing == null:
		return BuyResult.NO_LISTING
	if not listing.discovered:
		return BuyResult.NOT_DISCOVERED
	if not EconomyManager.can_afford(listing.asking_price):
		return BuyResult.CANNOT_AFFORD
	if not EconomyManager.spend(listing.asking_price, "%s — property purchase" % listing.address):
		return BuyResult.CANNOT_AFFORD

	var record := _take_ownership(listing, listing.asking_price)
	GameManager.notify(
		"PROPERTY PURCHASED\n%s  -$%s" % [
			listing.address.to_upper(),
			EconomyManager.with_thousands_separator(listing.asking_price)
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"purchase", AudioBuses.SFX, -5.0)
	property_bought.emit(record)
	portfolio_changed.emit()
	SaveManager.autosave("bought a property")
	return BuyResult.OK


## Financed purchase. The deposit leaves now; the rest becomes a debt with a
## schedule against it.
func buy_with_mortgage(property_id: StringName) -> BuyResult:
	if owns(property_id):
		return BuyResult.ALREADY_OWNED
	var listing := listing_for(property_id)
	if listing == null:
		return BuyResult.NO_LISTING
	if not listing.discovered:
		return BuyResult.NOT_DISCOVERED
	if not listing.mortgage_available:
		return BuyResult.NO_MORTGAGE_OFFERED
	if not is_credit_eligible():
		return BuyResult.NOT_ELIGIBLE
	# §42 — a serious record does not close the door, it raises the bar: the
	# lender wants a larger share up front.
	var deposit := roundi(
		float(listing.required_down_payment())
		* float(LegalManager.lender_view()["deposit_multiplier"])
	)
	if not EconomyManager.can_afford(deposit):
		return BuyResult.CANNOT_AFFORD
	if not EconomyManager.spend(deposit, "%s — deposit" % listing.address):
		return BuyResult.CANNOT_AFFORD

	var record := _take_ownership(listing, listing.asking_price)
	var loan := _open_mortgage(record, listing.financed_amount(), deposit)
	GameManager.notify(
		"MORTGAGE APPROVED\n%s  ·  -$%s down" % [
			listing.address.to_upper(), EconomyManager.with_thousands_separator(deposit)
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"purchase", AudioBuses.SFX, -5.0)
	property_bought.emit(record)
	mortgage_opened.emit(loan)
	portfolio_changed.emit()
	SaveManager.autosave("bought a property")
	return BuyResult.OK


## Turns a listing into a holding. Also settles what the player was doing with
## the address before: a flat they rented becomes a flat they own, and the old
## lease ends without them having to remember to cancel it.
func _take_ownership(listing: PropertyListing, price: int) -> PropertyRecord:
	var record := PropertyRecord.new()
	record.property_id = listing.property_id
	record.address = listing.address
	record.district_id = listing.district_id
	record.kind = listing.kind
	record.size_label = listing.size_label
	record.floor_area = listing.floor_area
	record.condition = listing.condition
	record.location_quality = listing.location_quality
	record.purchase_price = price
	record.purchase_day = TimeManager.day_index
	record.market_value = listing.market_value
	record.market_rent = listing.estimated_rent
	record.asking_rent = listing.estimated_rent
	record.base_maintenance = listing.base_maintenance

	if record.is_multi_unit():
		var block := _block_for(record.property_id)
		var units := block.unit_count if block != null else PropertyRecord.MULTI_UNIT_COUNT
		var each := maxi(roundi(float(record.market_rent) / float(units)), 1)
		for i in units:
			record.unit_uses.append(int(PropertyRecord.Use.VACANT))
			record.unit_rents.append(each)

	_records.append(record)
	_listings.erase(listing)
	_settle_previous_relationship(record)
	_refresh_signage()
	return record


## What the player was doing here before they bought it.
##
## A home they were renting stays their home and stops costing rent. A unit
## their business trades from keeps the business exactly as it is and stops
## paying a landlord. Everything else starts empty.
func _settle_previous_relationship(record: PropertyRecord) -> void:
	match record.kind:
		PropertyRecord.Kind.RESIDENTIAL:
			var home := PropertyManager.residence_by_id(record.property_id)
			if home == null:
				return
			var was_home := home.is_current_home()
			if home.is_leased_by_player():
				# The lease ends because the landlord relationship has: there is
				# nobody to pay any more. The furniture, the storage and the
				# home marker are untouched — they belong to the flat, not to
				# the lease.
				home.end_lease()
			home.owned_by_player = true
			if was_home:
				home.set_as_home()
				record.use = PropertyRecord.Use.OWNER_OCCUPIED
			else:
				record.use = PropertyRecord.Use.VACANT
			home.refresh_state()
		PropertyRecord.Kind.COMMERCIAL:
			var unit := PropertyManager.by_id(record.property_id)
			if unit == null:
				return
			var business := BusinessManager.business_for_property(record.property_id)
			unit.owned_by_player = true
			# An empty unit the player has just bought is theirs to trade from
			# without signing anything, so the door stops being an agent's board
			# and becomes a door.
			unit.occupy_as_owner()
			if unit.is_leased_by_player():
				# Deliberately not ended: the business's occupancy of the unit
				# is what keeps its equipment, staff and signage in place. What
				# changes is who the landlord is, and the rent charge checks
				# that before billing anybody.
				pass
			record.use = (
				PropertyRecord.Use.BUSINESS_OCCUPIED if business != null
				else PropertyRecord.Use.VACANT
			)
			unit.refresh_state()
		_:
			record.use = PropertyRecord.Use.VACANT
			var block := _block_for(record.property_id)
			if block != null:
				block.owned_by_player = true
				block.refresh_state()


func _block_for(building_id: StringName) -> MultiUnitBuilding:
	for node in get_tree().get_nodes_in_group(&"multi_unit_building"):
		var block := node as MultiUnitBuilding
		if block != null and block.building_id == building_id:
			return block
	return null


# --- Mortgages -----------------------------------------------------------

func mortgages() -> Array[MortgageData]:
	return _mortgages.duplicate()


func mortgage_for(property_id: StringName) -> MortgageData:
	for loan in _mortgages:
		if loan.property_id == property_id and not loan.is_settled():
			return loan
	return null


func by_mortgage_id(mortgage_id: StringName) -> MortgageData:
	for loan in _mortgages:
		if loan.mortgage_id == mortgage_id:
			return loan
	return null


func total_mortgage_debt() -> int:
	var total := 0
	for loan in _mortgages:
		if not loan.is_settled():
			total += loan.remaining_principal
	return total


func _open_mortgage(record: PropertyRecord, principal: int, deposit: int) -> MortgageData:
	var loan := MortgageData.new()
	loan.mortgage_id = StringName("mortgage_%d" % _next_number)
	_next_number += 1
	loan.property_id = record.property_id
	loan.original_principal = principal
	loan.remaining_principal = principal
	loan.down_payment = deposit
	loan.interest_rate = MORTGAGE_RATE
	loan.payment_interval_days = MORTGAGE_INTERVAL_DAYS
	loan.term_payments = MORTGAGE_TERM_PAYMENTS
	loan.payment_amount = MortgageData.level_payment(
		principal, loan.period_rate(), MORTGAGE_TERM_PAYMENTS
	)
	loan.next_payment_day = TimeManager.day_index + MORTGAGE_INTERVAL_DAYS
	_mortgages.append(loan)
	record.mortgage_id = loan.mortgage_id
	return loan


## One scheduled payment: interest first, the rest off the balance. A payment
## that would overshoot the balance is trimmed, which is what stops a mortgage
## going negative on its last instalment.
func _charge_mortgage(loan: MortgageData) -> void:
	var record := record_for(loan.property_id)
	var interest := loan.period_interest()
	var due := mini(loan.payment_amount, loan.remaining_principal + interest)

	if not EconomyManager.spend(due, "%s — mortgage" % _address_of(loan.property_id)):
		loan.missed_payments += 1
		# The debt does not go away because it was not paid; it is owed again
		# next period, and past a point the lender starts taking the property.
		# Phase N stopped at AT_RISK; the two steps past it are Phase P's.
		if loan.missed_payments >= MortgageData.FORECLOSURE_MISSES:
			_begin_foreclosure(loan)
		elif loan.missed_payments >= MortgageData.AT_RISK_MISSES:
			loan.status = MortgageData.Status.AT_RISK
		else:
			loan.status = MortgageData.Status.OVERDUE
		loan.next_payment_day = TimeManager.day_index + loan.payment_interval_days
		if not loan.is_foreclosing():
			GameManager.notify(
				"MORTGAGE %s\n%s" % [
					"AT RISK" if loan.status == MortgageData.Status.AT_RISK
						else "PAYMENT MISSED",
					_address_of(loan.property_id).to_upper(),
				],
				GameManager.Tone.BAD
			)
		mortgage_missed.emit(loan)
		return

	var principal := maxi(due - interest, 0)
	loan.remaining_principal = maxi(loan.remaining_principal - principal, 0)
	loan.payments_made += 1
	loan.interest_paid += interest
	loan.principal_paid += principal
	loan.missed_payments = 0
	loan.status = MortgageData.Status.ACTIVE
	loan.next_payment_day = TimeManager.day_index + loan.payment_interval_days
	_interest_paid += interest
	_principal_paid += principal

	if loan.remaining_principal <= 0:
		_settle_mortgage(loan, record)
	mortgage_payment_made.emit(loan, interest, principal)


func _settle_mortgage(loan: MortgageData, record: PropertyRecord) -> void:
	loan.remaining_principal = 0
	loan.status = MortgageData.Status.PAID
	if record != null:
		record.mortgage_id = &""
	GameManager.notify(
		"MORTGAGE CLEARED\n%s" % _address_of(loan.property_id).to_upper(), GameManager.Tone.GOOD
	)
	AudioManager.play(&"money", AudioBuses.SFX, -6.0)
	mortgage_settled.emit(loan)
	portfolio_changed.emit()


## An extra payment straight off the balance. No interest is charged on it —
## that is the whole reason to make one.
func pay_extra(loan: MortgageData, amount: int) -> int:
	if loan == null or loan.is_settled():
		return 0
	var paying := clampi(amount, 0, loan.remaining_principal)
	if paying <= 0 or not EconomyManager.spend(
		paying, "%s — mortgage overpayment" % _address_of(loan.property_id)
	):
		return 0
	loan.remaining_principal -= paying
	loan.principal_paid += paying
	_principal_paid += paying
	if loan.remaining_principal <= 0:
		_settle_mortgage(loan, record_for(loan.property_id))
	portfolio_changed.emit()
	return paying


func pay_off(loan: MortgageData) -> int:
	return pay_extra(loan, loan.payoff_amount() if loan != null else 0)


# --- Equity and net worth -------------------------------------------------

func total_market_value() -> int:
	var total := 0
	for record in _records:
		total += record.market_value
	return total


## What the buildings are worth less what is owed on them. The number the
## profile screen calls property equity, and the one that belongs in net worth.
func total_equity() -> int:
	return total_market_value() - total_mortgage_debt()


func equity_of(record: PropertyRecord) -> int:
	if record == null:
		return 0
	var loan := mortgage_for(record.property_id)
	return record.market_value - (loan.remaining_principal if loan != null else 0)


# --- Tenants --------------------------------------------------------------

func tenants() -> Array[TenantData]:
	return _tenants.duplicate()


func tenant_for(property_id: StringName, unit_index: int = -1) -> TenantData:
	for tenant in _tenants:
		if tenant.property_id == property_id and tenant.unit_index == unit_index:
			return tenant
	return null


func tenants_in(property_id: StringName) -> Array[TenantData]:
	var found: Array[TenantData] = []
	for tenant in _tenants:
		if tenant.property_id == property_id:
			found.append(tenant)
	return found


## Puts a property, or one unit of a block, on the rental market at a chosen
## rent. Applicants arrive over the following days rather than at once.
func list_for_rent(record: PropertyRecord, asking_rent: int, unit_index: int = -1) -> bool:
	if record == null or not _records.has(record):
		return false
	if record.use == PropertyRecord.Use.BUSINESS_OCCUPIED:
		return false
	var rent := maxi(asking_rent, 1)
	if record.is_multi_unit():
		if unit_index < 0 or unit_index >= record.unit_uses.size():
			return false
		if record.unit_uses[unit_index] == int(PropertyRecord.Use.TENANTED):
			return false
		record.unit_uses[unit_index] = int(PropertyRecord.Use.LISTED_FOR_RENT)
		record.unit_rents[unit_index] = rent
	else:
		if record.use == PropertyRecord.Use.TENANTED:
			return false
		record.use = PropertyRecord.Use.LISTED_FOR_RENT
		record.asking_rent = rent
	record.days_vacant = 0
	portfolio_changed.emit()
	return true


func stop_listing(record: PropertyRecord, unit_index: int = -1) -> void:
	if record == null:
		return
	if record.is_multi_unit() and unit_index >= 0 and unit_index < record.unit_uses.size():
		if record.unit_uses[unit_index] == int(PropertyRecord.Use.LISTED_FOR_RENT):
			record.unit_uses[unit_index] = int(PropertyRecord.Use.VACANT)
	elif record.use == PropertyRecord.Use.LISTED_FOR_RENT:
		record.use = PropertyRecord.Use.VACANT
	_candidates.erase(_candidate_key(record.property_id, unit_index))
	portfolio_changed.emit()


func _candidate_key(property_id: StringName, unit_index: int) -> String:
	return "%s#%d" % [property_id, unit_index]


## Whoever has applied for a listed property, waiting on the player's answer.
func candidates_for(record: PropertyRecord, unit_index: int = -1) -> Array:
	if record == null:
		return []
	return _candidates.get(_candidate_key(record.property_id, unit_index), [])


## How likely an applicant is to turn up on any given day. Cheap places in good
## repair on a good pitch let quickly; an ambitious rent on a tired flat does
## not, and that is the risk the player is choosing to take.
func demand_chance(record: PropertyRecord, asking_rent: int) -> float:
	if record == null or record.market_rent <= 0:
		return 0.0
	var price_ratio := float(asking_rent) / float(record.market_rent)
	# At the going rate, a good chance; at half again, almost none.
	var by_price := clampf(1.6 - price_ratio, 0.02, 1.0)
	var by_condition := lerpf(0.45, 1.0, clampf(record.condition / 100.0, 0.0, 1.0))
	var by_pitch := lerpf(0.55, 1.0, clampf(float(record.location_quality) / 100.0, 0.0, 1.0))
	return clampf(by_price * by_condition * by_pitch * 0.55, 0.0, 0.9)


func _seek_tenants(record: PropertyRecord) -> void:
	if record.is_multi_unit():
		for i in record.unit_uses.size():
			if record.unit_uses[i] == int(PropertyRecord.Use.LISTED_FOR_RENT):
				_seek_one(record, i, record.unit_rents[i])
	elif record.use == PropertyRecord.Use.LISTED_FOR_RENT:
		_seek_one(record, -1, record.asking_rent)


func _seek_one(record: PropertyRecord, unit_index: int, asking_rent: int) -> void:
	record.days_vacant += 1
	var key := _candidate_key(record.property_id, unit_index)
	var waiting: Array = _candidates.get(key, [])
	# Two applicants at a time is a choice; a queue of ten is a spreadsheet.
	if waiting.size() >= 2:
		_candidates[key] = waiting
		return
	if _rng.randf() > demand_chance(record, asking_rent):
		return

	var kind := (
		TenantData.Kind.COMMERCIAL if record.kind == PropertyRecord.Kind.COMMERCIAL
		else TenantData.Kind.RESIDENTIAL
	)
	var market := record.market_rent
	if record.is_multi_unit():
		market = maxi(roundi(float(record.market_rent) / float(record.unit_count())), 1)
	var applicant := TenantData.generate(kind, market, _rng, _next_number)
	_next_number += 1
	# Somebody who cannot afford the asking rent does not apply for it.
	if not applicant.would_accept(asking_rent):
		return
	waiting.append(applicant)
	_candidates[key] = waiting
	GameManager.notify(
		"RENTAL ENQUIRY\n%s  ·  %s" % [record.address.to_upper(), applicant.tenant_name],
		GameManager.Tone.INFO
	)
	portfolio_changed.emit()


## Signs one of the applicants. The rent begins on the ordinary schedule.
func accept_tenant(record: PropertyRecord, tenant: TenantData, unit_index: int = -1) -> bool:
	if record == null or tenant == null or not _records.has(record):
		return false
	var asking := record.asking_rent
	if record.is_multi_unit():
		if unit_index < 0 or unit_index >= record.unit_uses.size():
			return false
		asking = record.unit_rents[unit_index]
		record.unit_uses[unit_index] = int(PropertyRecord.Use.TENANTED)
	else:
		record.use = PropertyRecord.Use.TENANTED

	tenant.property_id = record.property_id
	tenant.unit_index = unit_index
	tenant.rent_amount = asking
	tenant.lease_start_day = TimeManager.day_index
	tenant.lease_end_day = TimeManager.day_index + LEASE_DAYS
	tenant.next_rent_day = TimeManager.day_index + RENT_INTERVAL_DAYS
	_tenants.append(tenant)
	_candidates.erase(_candidate_key(record.property_id, unit_index))
	record.days_vacant = 0

	GameManager.notify(
		"TENANT SIGNED\n%s  ·  $%s" % [
			record.address.to_upper(), EconomyManager.with_thousands_separator(asking)
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play_ui(&"ui_confirm")
	tenant_signed.emit(record, tenant)
	portfolio_changed.emit()
	SaveManager.autosave("signed a tenant")
	return true


## Ends a tenancy. The player's decision, and confirmed before it gets here.
func end_tenancy(tenant: TenantData) -> void:
	if tenant == null or not _tenants.has(tenant):
		return
	var record := record_for(tenant.property_id)
	_tenants.erase(tenant)
	if record != null:
		if record.is_multi_unit() and tenant.unit_index >= 0:
			record.unit_uses[tenant.unit_index] = int(PropertyRecord.Use.VACANT)
		else:
			record.use = PropertyRecord.Use.VACANT
		record.days_vacant = 0
		tenant_left.emit(record, tenant)
	portfolio_changed.emit()


func _collect_rent(tenant: TenantData) -> void:
	var record := record_for(tenant.property_id)
	if record == null:
		return
	tenant.next_rent_day = TimeManager.day_index + RENT_INTERVAL_DAYS

	if _rng.randf() > tenant.payment_chance():
		tenant.missed_payments += 1
		tenant.payment_state = (
			TenantData.PaymentState.MISSED if tenant.missed_payments > 1
			else TenantData.PaymentState.LATE
		)
		tenant.satisfaction = maxi(tenant.satisfaction - 4, 0)
		GameManager.notify(
			"RENT %s\n%s  ·  %s" % [
				tenant.payment_label(), record.address.to_upper(), tenant.tenant_name
			],
			GameManager.Tone.BAD
		)
		return

	# A tenant who was late catches up: the arrears come with this period's rent.
	var owed := tenant.rent_amount * (1 + tenant.missed_payments)
	tenant.missed_payments = 0
	tenant.payment_state = TenantData.PaymentState.CURRENT
	EconomyManager.deposit(
		owed, "%s — rental income" % record.address,
		EconomyManager.Source.LEGAL, EconomyManager.Stream.RENTAL
	)
	_rent_collected += owed
	_rent_today += owed
	rent_received.emit(record, owed)
	# Deliberately quiet per tenant: rent arrives every week for every unit, and
	# a chime each time would become the sound of the game. The day's total is
	# announced once, in _on_day_passed.
	record.condition = maxf(record.condition - tenant.wear_per_period(), 0.0)


func _expire_leases() -> void:
	var today := TimeManager.day_index
	for tenant in _tenants.duplicate():
		if today < tenant.lease_end_day:
			continue
		var record := record_for(tenant.property_id)
		if record == null:
			_tenants.erase(tenant)
			continue
		# Renewal, decided once, on whether they are happy and the place is
		# decent. No negotiation — the rent is what it was.
		var happy: bool = tenant.satisfaction >= 45 and record.condition >= 40.0
		var fair: bool = tenant.rent_amount <= roundi(float(unit_market_rent(record)) * 1.15)
		if happy and fair and _rng.randf() < 0.65:
			tenant.lease_start_day = today
			tenant.lease_end_day = today + LEASE_DAYS
			continue
		GameManager.notify(
			"TENANCY ENDED\n%s  ·  %s" % [record.address.to_upper(), tenant.tenant_name],
			GameManager.Tone.INFO
		)
		end_tenancy(tenant)


## The going rate for one lettable unit: the whole property, or one flat of a
## block. What the rent box on the portfolio screen offers as a starting point.
func unit_market_rent(record: PropertyRecord) -> int:
	if record.is_multi_unit():
		return maxi(roundi(float(record.market_rent) / float(record.unit_count())), 1)
	return record.market_rent


# --- Condition, maintenance and works ------------------------------------

## What it would cost to bring a property up to a renovation's standard.
func renovation_quote(record: PropertyRecord, tier: StringName) -> int:
	if record == null or not RENOVATIONS.has(tier):
		return 0
	var spec: Array = RENOVATIONS[tier]
	var target: float = spec[1]
	if record.condition >= target:
		return 0
	# Scaled by what the building is worth as well as by how far it has to
	# come: a premium finish on a large block is not a flat's redecoration.
	var points := target - record.condition
	var scale := clampf(float(record.market_value) / 120000.0, 0.35, 3.0)
	return maxi(roundi(points * float(spec[2]) * scale), 1)


func renovation_days(tier: StringName) -> int:
	var spec: Array = RENOVATIONS.get(tier, [])
	return int(spec[3]) if spec.size() > 3 else 1


func renovation_target(tier: StringName) -> float:
	var spec: Array = RENOVATIONS.get(tier, [])
	return float(spec[1]) if spec.size() > 1 else 0.0


## Whether works can start. Anybody living or trading there has to be out
## first — simpler than modelling a refit around a tenant, and safer.
func renovation_blocked_reason(record: PropertyRecord) -> String:
	if record == null:
		return "No such property."
	if record.use == PropertyRecord.Use.TENANTED:
		return "The tenant has to leave before the work can start."
	if record.is_multi_unit() and record.occupied_units() > 0:
		return "Every unit has to be empty before the work can start."
	return ""


func renovate(record: PropertyRecord, tier: StringName) -> bool:
	if record == null or not _records.has(record):
		return false
	if not renovation_blocked_reason(record).is_empty():
		return false
	var cost := renovation_quote(record, tier)
	if cost <= 0:
		return false
	if not EconomyManager.spend(cost, "%s — %s" % [record.address, RENOVATIONS[tier][0]]):
		GameManager.notify("NOT ENOUGH CASH FOR THAT", GameManager.Tone.BAD)
		return false

	# The days pass first and the work lands at the end of them. Applying the
	# new condition and then advancing the clock let the building wear away a
	# fraction of what had just been paid for, so a finished renovation read as
	# a hair under the standard it was bought to reach.
	TimeManager.advance_minutes(renovation_days(tier) * 1440)
	record.condition = maxf(record.condition, renovation_target(tier))
	_revalue(record)
	GameManager.notify(
		"WORK COMPLETE\n%s  ·  condition %d%%" % [record.address.to_upper(), roundi(record.condition)],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"purchase", AudioBuses.SFX, -8.0)
	portfolio_changed.emit()
	return true


func _revalue(record: PropertyRecord) -> void:
	record.market_value = value_of(
		record.kind, record.floor_area, record.location_quality,
		record.district_id, record.condition
	)
	record.market_rent = rent_for_value(record.market_value, record.location_quality)
	record.base_maintenance = maintenance_for_value(record.market_value)


# --- Foreclosure ----------------------------------------------------------

## The lender gives notice. Nothing is taken today: the player is told what is
## owed and how long they have, and the property is theirs until the deadline
## passes uncured. §89.
func _begin_foreclosure(loan: MortgageData) -> void:
	if loan.is_foreclosing():
		return
	loan.status = MortgageData.Status.FORECLOSING
	loan.foreclosure_day = TimeManager.day_index + MortgageData.CURE_DAYS
	GameManager.notify(
		"FORECLOSURE NOTICE\n%s  ·  $%s to cure, %d days" % [
			_address_of(loan.property_id).to_upper(),
			EconomyManager.with_thousands_separator(loan.arrears_amount()),
			MortgageData.CURE_DAYS,
		],
		GameManager.Tone.BAD
	)
	AudioManager.play_ui(&"ui_error")
	foreclosure_started.emit(loan)
	SaveManager.autosave("foreclosure notice")


## Every mortgage under notice, for the screens that have to shout about them.
func foreclosing_mortgages() -> Array[MortgageData]:
	var found: Array[MortgageData] = []
	for loan in _mortgages:
		if loan.is_foreclosing():
			found.append(loan)
	return found


## What it costs to stop a foreclosure, and how long is left.
func cure_quote(loan: MortgageData) -> Dictionary:
	if loan == null:
		return {}
	return {
		"amount": loan.arrears_amount(),
		"days_left": loan.days_to_cure(TimeManager.day_index),
		"address": _address_of(loan.property_id),
		"affordable": EconomyManager.can_afford(loan.arrears_amount()),
	}


## Pays the arrears and puts the mortgage back in good standing. Not the whole
## balance — §90 — so curing is something a player in trouble can actually do.
func cure_foreclosure(loan: MortgageData) -> bool:
	if loan == null or not loan.is_foreclosing():
		return false
	var owed := loan.arrears_amount()
	if owed <= 0:
		return false
	if not EconomyManager.spend(owed, "%s — arrears" % _address_of(loan.property_id)):
		GameManager.notify(
			"YOU CANNOT COVER THE ARREARS", GameManager.Tone.BAD
		)
		return false
	loan.missed_payments = 0
	loan.status = MortgageData.Status.ACTIVE
	loan.foreclosure_day = -1
	GameManager.notify(
		"FORECLOSURE CANCELLED\n%s" % _address_of(loan.property_id).to_upper(),
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"money", AudioBuses.SFX, -8.0)
	foreclosure_cured.emit(loan)
	portfolio_changed.emit()
	SaveManager.autosave("cured a foreclosure")
	return true


## The deadline passed. The lender takes the property, clears the debt against
## it, and hands back whatever equity was left after their costs.
##
## Deliberately not punitive to the point of absurdity: §91 asks for a fair
## simplified formula rather than the value simply vanishing, so the player
## gets the sale price less the balance and a foreclosure fee.
func _complete_foreclosure(loan: MortgageData) -> void:
	var record := record_for(loan.property_id)
	var address := _address_of(loan.property_id)
	var recovered := 0
	if record != null:
		var price := roundi(float(record.market_value) * FORECLOSURE_SALE_FRACTION)
		recovered = maxi(price - loan.remaining_principal, 0)

	loan.status = MortgageData.Status.FORECLOSED
	loan.remaining_principal = 0
	loan.foreclosure_day = -1
	_mortgages.erase(loan)

	if record != null:
		_rehouse_after_foreclosure(record)
		_release_ownership(record)
		_records.erase(record)
	if recovered > 0:
		EconomyManager.deposit(recovered, "Foreclosure — %s" % address)
	FinanceManager.properties_foreclosed += 1
	GameManager.notify(
		"PROPERTY FORECLOSED\n%s%s" % [
			address.to_upper(),
			"  ·  $%s returned" % EconomyManager.with_thousands_separator(recovered)
				if recovered > 0 else "",
		],
		GameManager.Tone.BAD
	)
	AudioManager.play_ui(&"ui_error")
	foreclosure_completed.emit(loan, recovered)
	portfolio_changed.emit()
	SaveManager.autosave("a property was foreclosed")


## The two things a foreclosure can take out from under the player that a sale
## never could: the roof over their head, and the shop they trade from.
##
## Selling is blocked in both cases, so Phase N never had to think about it.
## Losing a property involuntarily has to, and the rule is that neither one is
## allowed to leave the game in a state the player cannot play out of. §92, §93.
func _rehouse_after_foreclosure(record: PropertyRecord) -> void:
	if record.use == PropertyRecord.Use.OWNER_OCCUPIED:
		var lost := PropertyManager.residence_by_id(record.property_id)
		if lost != null:
			lost.is_home = false
			lost.refresh_state()
		# Anywhere else the player can sleep, or the starter flat. Never
		# nowhere: a player with no bed cannot rest, and that is a soft lock.
		var fallback := PropertyManager.fallback_home(record.property_id)
		if fallback != null:
			PropertyManager.rehouse(fallback)

	var business := BusinessManager.business_for_property(record.property_id)
	if business != null:
		# The shop does not evaporate with the freehold. It closes, keeps
		# everything it owns, and the player decides what to do with it.
		BusinessManager.close_business(business, "the premises were foreclosed")
		GameManager.notify(
			"BUSINESS LOST ITS PREMISES\n%s" % business.business_name.to_upper(),
			GameManager.Tone.BAD
		)


## Checked once a day. A notice that has run out is acted on; one still inside
## its window nags instead.
func _advance_foreclosures() -> void:
	var today := TimeManager.day_index
	for loan in foreclosing_mortgages():
		var left := loan.days_to_cure(today)
		if left <= 0:
			_complete_foreclosure(loan)
			continue
		GameManager.notify(
			"FORECLOSURE IN %d DAY%s\n%s  ·  $%s to cure" % [
				left, "" if left == 1 else "S",
				_address_of(loan.property_id).to_upper(),
				EconomyManager.with_thousands_separator(loan.arrears_amount()),
			],
			GameManager.Tone.BAD
		)


# --- Selling --------------------------------------------------------------

## What stops a sale, in words the screen can show. Empty means it can go.
func sale_blocked_reason(record: PropertyRecord) -> String:
	if record == null or not _records.has(record):
		return "You do not own that."
	if record.use == PropertyRecord.Use.BUSINESS_OCCUPIED:
		return "BUSINESS MUST VACATE PROPERTY BEFORE SALE"
	return ""


func sale_price(record: PropertyRecord) -> int:
	return record.market_value if record != null else 0


func selling_cost(record: PropertyRecord) -> int:
	return roundi(float(sale_price(record)) * SELLING_COST_FRACTION)


## What the player actually walks away with: the price, less the fees, less
## whatever is still owed on it.
func net_proceeds(record: PropertyRecord) -> int:
	var loan := mortgage_for(record.property_id) if record != null else null
	var owed := loan.remaining_principal if loan != null else 0
	return sale_price(record) - selling_cost(record) - owed


func sell(record: PropertyRecord) -> SellResult:
	if record == null or not _records.has(record):
		return SellResult.NOT_OWNED
	if record.use == PropertyRecord.Use.BUSINESS_OCCUPIED:
		return SellResult.BUSINESS_OCCUPIES

	var price := sale_price(record)
	var fees := selling_cost(record)
	var loan := mortgage_for(record.property_id)
	var owed := loan.remaining_principal if loan != null else 0
	var proceeds := price - fees - owed

	# Whatever is owed is cleared out of the sale before the player sees a
	# penny, so a sold building never leaves a mortgage behind it.
	if loan != null:
		loan.remaining_principal = 0
		loan.status = MortgageData.Status.PAID
		_mortgages.erase(loan)
	# Any tenancy ends with the sale. The simple rule, stated plainly: the
	# tenant goes with the building rather than staying on the player's books.
	for tenant in tenants_in(record.property_id):
		_tenants.erase(tenant)
	_candidates.erase(_candidate_key(record.property_id, -1))

	_release_ownership(record)
	_records.erase(record)
	if proceeds > 0:
		EconomyManager.deposit(proceeds, "%s — property sale" % record.address)
	elif proceeds < 0:
		EconomyManager.spend(-proceeds, "%s — sale shortfall" % record.address)

	GameManager.notify(
		"PROPERTY SOLD\n%s  +$%s" % [
			record.address.to_upper(), EconomyManager.with_thousands_separator(maxi(proceeds, 0))
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"money", AudioBuses.SFX, -6.0)
	property_sold.emit(record, proceeds)
	portfolio_changed.emit()
	SaveManager.autosave("sold a property")
	return SellResult.OK


## Puts the address back on the market and hands the door back to whoever it
## belonged to before.
func _release_ownership(record: PropertyRecord) -> void:
	# Whoever was renting it is no longer renting it from us. Selling already
	# did this; foreclosure has to as well, or a property the bank took keeps
	# paying rent into the player's account. §94.
	for tenant in tenants_in(record.property_id):
		_tenants.erase(tenant)
	_candidates.erase(_candidate_key(record.property_id, -1))

	match record.kind:
		PropertyRecord.Kind.RESIDENTIAL:
			var home := PropertyManager.residence_by_id(record.property_id)
			if home != null:
				home.owned_by_player = false
				home.is_home = false
				home.refresh_state()
		PropertyRecord.Kind.COMMERCIAL:
			var unit := PropertyManager.by_id(record.property_id)
			if unit != null:
				unit.owned_by_player = false
				# Occupancy came with the freehold, so it goes with it. A unit
				# with a business in it never reaches here — that sale is
				# blocked — so nothing is turned out of its premises.
				if unit.is_leased_by_player():
					unit.end_lease()
				unit.refresh_state()
		_:
			var block := _block_for(record.property_id)
			if block != null:
				block.owned_by_player = false
				block.refresh_state()

	var listing := PropertyListing.new()
	listing.property_id = record.property_id
	listing.address = record.address
	listing.district_id = record.district_id
	listing.kind = record.kind
	listing.size_label = record.size_label
	listing.floor_area = record.floor_area
	listing.condition = record.condition
	listing.location_quality = record.location_quality
	listing.market_value = record.market_value
	listing.asking_price = record.market_value
	listing.estimated_rent = record.market_rent
	listing.base_maintenance = record.base_maintenance
	listing.discovered = true
	_listings.append(listing)
	_refresh_signage()


# --- The day --------------------------------------------------------------

func _on_day_passed(_day_index: int) -> void:
	_rent_today = 0
	_drift_market()
	for record in _records:
		_wear(record)
		_charge_maintenance(record)
		_seek_tenants(record)
		_revalue(record)
	for tenant in _tenants.duplicate():
		if TimeManager.day_index >= tenant.next_rent_day:
			_collect_rent(tenant)
	if _rent_today > 0:
		# One line and one quiet cue for the day's rent, however many units paid.
		GameManager.notify(
			"RENT RECEIVED\n+$%s" % EconomyManager.with_thousands_separator(_rent_today),
			GameManager.Tone.GOOD
		)
		AudioManager.play(&"money", AudioBuses.SFX, -10.0)
	_expire_leases()
	for loan in _mortgages.duplicate():
		if loan.is_due(TimeManager.day_index):
			_charge_mortgage(loan)
	portfolio_changed.emit()
	# Notices given, days counted, and anything past its deadline acted on.
	_advance_foreclosures()


## A slow wander around 1.0 rather than a random walk that can run away: the
## further the trend is from the middle, the more it is pulled back.
func _drift_market() -> void:
	var pull := (1.0 - _market_trend) * 0.08
	var wobble := _rng.randf_range(-TREND_STEP, TREND_STEP)
	_market_trend = clampf(_market_trend + pull + wobble, TREND_FLOOR, TREND_CEILING)


func _wear(record: PropertyRecord) -> void:
	# An empty building still ages. A tenanted one takes its wear when the rent
	# comes in, so a let property is not charged twice for the same week.
	if record.occupied_units() == 0:
		record.condition = maxf(record.condition - IDLE_WEAR_PER_DAY, 0.0)


func _charge_maintenance(record: PropertyRecord) -> void:
	# Charged on the same weekly cycle as everything else, on the day of the
	# week the property was bought.
	if (TimeManager.day_index - record.purchase_day) % RENT_INTERVAL_DAYS != 0:
		return
	if TimeManager.day_index == record.purchase_day:
		return
	var cost := record.maintenance_cost()
	if EconomyManager.spend(cost, "%s — property maintenance" % record.address):
		_maintenance_paid += cost
	else:
		# Deferred upkeep shows up as the building getting worse, which is a
		# more honest consequence than an unpayable bill.
		record.condition = maxf(record.condition - 1.5, 0.0)

	# A vacant property is money not earned, and the report says so.
	if record.rentable_units() > 0 and record.occupied_units() < record.rentable_units():
		var empty := record.rentable_units() - record.occupied_units()
		_vacancy_lost += unit_market_rent(record) * empty


# --- Reporting ------------------------------------------------------------

## Everything the portfolio screen shows, worked out once.
func portfolio_summary() -> Dictionary:
	var rent := 0
	var maintenance := 0
	var mortgage_due := 0
	var occupied := 0
	var rentable := 0
	for record in _records:
		maintenance += record.maintenance_cost()
		occupied += record.occupied_units()
		rentable += record.rentable_units()
	for tenant in _tenants:
		rent += tenant.rent_amount
	for loan in _mortgages:
		if not loan.is_settled():
			mortgage_due += loan.payment_amount

	return {
		"properties": _records.size(),
		"market_value": total_market_value(),
		"debt": total_mortgage_debt(),
		"equity": total_equity(),
		"rent": rent,
		"maintenance": maintenance,
		"mortgage_payments": mortgage_due,
		"cash_flow": rent - maintenance - mortgage_due,
		"occupied": occupied,
		"rentable": rentable,
		"occupancy": float(occupied) / float(maxi(rentable, 1)),
	}


## The running totals, for the income tab. Cumulative rather than per period,
## because what a landlord wants to know is where the money has gone.
func income_report() -> Dictionary:
	return {
		"rent_collected": _rent_collected,
		"maintenance_paid": _maintenance_paid,
		"interest_paid": _interest_paid,
		"principal_paid": _principal_paid,
		"vacancy_lost": _vacancy_lost,
		"net_cash": _rent_collected - _maintenance_paid - _interest_paid - _principal_paid,
	}


## Rent against price, for the one yield figure the game shows.
func yield_of(record: PropertyRecord) -> float:
	if record == null or record.market_value <= 0:
		return 0.0
	var rent := 0
	for tenant in tenants_in(record.property_id):
		rent += tenant.rent_amount
	return float(rent) * 52.0 / float(record.market_value)


## The address of anything the player owns or could own. Public because the
## obligation list names mortgages by where they are, not by an id.
func address_of(property_id: StringName) -> String:
	return _address_of(property_id)


func _address_of(property_id: StringName) -> String:
	var record := record_for(property_id)
	if record != null:
		return record.address
	var listing := listing_for(property_id)
	return listing.address if listing != null else String(property_id)


# --- Save -----------------------------------------------------------------

func save_state() -> Dictionary:
	var holdings: Array = []
	for record in _records:
		holdings.append(record.to_dictionary())
	var loans: Array = []
	for loan in _mortgages:
		loans.append(loan.to_dictionary())
	var people: Array = []
	for tenant in _tenants:
		people.append(tenant.to_dictionary())
	var seen: Array = []
	for listing in _listings:
		if listing.discovered:
			seen.append(String(listing.property_id))

	return {
		"records": holdings,
		"mortgages": loans,
		"tenants": people,
		"discovered": seen,
		"market_trend": _market_trend,
		"next_number": _next_number,
		"totals": {
			"rent": _rent_collected, "maintenance": _maintenance_paid,
			"interest": _interest_paid, "principal": _principal_paid,
			"vacancy": _vacancy_lost,
		},
	}


func load_state(state: Dictionary) -> void:
	# Whatever the player owned before is handed back to the world, so a load
	# into a running game does not leave a door thinking it is still owned.
	# Detached rather than released: releasing puts the address back on the
	# market and turns a home off, and build_market below is about to rebuild
	# the market anyway. The saveable group loads in no particular order, so
	# clearing a residence's `is_home` here could undo what its own load_state
	# had already restored.
	for record in _records:
		_detach(record)
	_records.clear()
	_mortgages.clear()
	_tenants.clear()
	_candidates.clear()
	_built = false
	build_market()

	_market_trend = clampf(float(state.get("market_trend", 1.0)), TREND_FLOOR, TREND_CEILING)
	_next_number = int(state.get("next_number", 1))

	for entry: Dictionary in state.get("records", []):
		var record := PropertyRecord.from_dictionary(entry)
		if record.property_id == &"":
			continue
		_records.append(record)
		# The address is no longer for sale, and the door is told who owns it.
		var listing := listing_for(record.property_id)
		if listing != null:
			_listings.erase(listing)
		_reattach(record)

	for entry: Dictionary in state.get("mortgages", []):
		var loan := MortgageData.from_dictionary(entry)
		if not loan.is_settled():
			_mortgages.append(loan)

	for entry: Dictionary in state.get("tenants", []):
		var tenant := TenantData.from_dictionary(entry)
		if record_for(tenant.property_id) != null:
			_tenants.append(tenant)

	for id in state.get("discovered", []):
		var seen := listing_for(StringName(id))
		if seen != null:
			seen.discovered = true

	var totals: Dictionary = state.get("totals", {})
	_rent_collected = int(totals.get("rent", 0))
	_maintenance_paid = int(totals.get("maintenance", 0))
	_interest_paid = int(totals.get("interest", 0))
	_principal_paid = int(totals.get("principal", 0))
	_vacancy_lost = int(totals.get("vacancy", 0))
	portfolio_changed.emit()


## Takes a door out of the player's hands without any of the consequences of a
## sale. Used only when a load is about to replace the whole portfolio.
func _detach(record: PropertyRecord) -> void:
	match record.kind:
		PropertyRecord.Kind.RESIDENTIAL:
			var home := PropertyManager.residence_by_id(record.property_id)
			if home != null:
				home.owned_by_player = false
				home.refresh_state()
		PropertyRecord.Kind.COMMERCIAL:
			var unit := PropertyManager.by_id(record.property_id)
			if unit != null:
				unit.owned_by_player = false
				unit.refresh_state()
		_:
			var block := _block_for(record.property_id)
			if block != null:
				block.owned_by_player = false
				block.refresh_state()


## Puts a loaded holding back in touch with its door, without disturbing what
## the player was doing there. A Phase M save has no property section at all,
## so nothing runs and every address stays rented exactly as it was.
func _reattach(record: PropertyRecord) -> void:
	match record.kind:
		PropertyRecord.Kind.RESIDENTIAL:
			var home := PropertyManager.residence_by_id(record.property_id)
			if home != null:
				home.owned_by_player = true
				if record.use == PropertyRecord.Use.OWNER_OCCUPIED:
					home.is_home = true
				home.refresh_state()
		PropertyRecord.Kind.COMMERCIAL:
			var unit := PropertyManager.by_id(record.property_id)
			if unit != null:
				unit.owned_by_player = true
				unit.refresh_state()
		_:
			var block := _block_for(record.property_id)
			if block != null:
				block.owned_by_player = true
				block.refresh_state()


func clear() -> void:
	for record in _records:
		_release_ownership(record)
	_records.clear()
	_mortgages.clear()
	_tenants.clear()
	_candidates.clear()
	_rent_collected = 0
	_maintenance_paid = 0
	_interest_paid = 0
	_principal_paid = 0
	_vacancy_lost = 0
	_market_trend = 1.0
	portfolio_changed.emit()
