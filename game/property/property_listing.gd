class_name PropertyListing
extends RefCounted
## A property on the market.
##
## The catalogue entry for something the player does not own yet: what it is,
## what it costs, what a lender would want down, and what it might earn. Built
## by RealEstate from the city's own doors rather than authored twice, so an
## address only exists once in the project.
##
## A listing is not a record. The moment it is bought it becomes a
## PropertyRecord and the listing goes.

var property_id: StringName = &""
var address: String = ""
var district_id: StringName = &"harbour_row"
var kind: PropertyRecord.Kind = PropertyRecord.Kind.RESIDENTIAL
var size_label: String = ""
var floor_area: int = 40
var asking_price: int = 0
var market_value: int = 0
var condition: float = 85.0
var location_quality: int = 50
var estimated_rent: int = 0
var base_maintenance: int = 80
var mortgage_available: bool = true
## Set once the player has stood in front of it. Until then it is not on the
## market screen — the city is meant to be walked, not browsed.
var discovered: bool = false


func kind_label() -> String:
	match kind:
		PropertyRecord.Kind.COMMERCIAL:
			return "Commercial unit"
		PropertyRecord.Kind.MULTI_UNIT:
			return "Multi-unit residential"
		_:
			return "Residential unit"


## The deposit a lender wants. Steeper on commercial and on multi-unit, which is
## what makes the cheap flat the first rung of the ladder.
func down_payment_fraction() -> float:
	match kind:
		PropertyRecord.Kind.COMMERCIAL:
			return 0.25
		PropertyRecord.Kind.MULTI_UNIT:
			return 0.30
		_:
			return 0.20


func required_down_payment() -> int:
	return roundi(float(asking_price) * down_payment_fraction())


func financed_amount() -> int:
	return maxi(asking_price - required_down_payment(), 0)


## Annual rent over price. The one yield figure the game shows — enough to
## compare two listings, and not the start of a page of finance ratios.
func gross_yield() -> float:
	if asking_price <= 0:
		return 0.0
	# Rent is charged weekly, so a year is fifty-two of them.
	return float(estimated_rent) * 52.0 / float(asking_price)


func yield_label() -> String:
	return "%.1f%% a year" % (gross_yield() * 100.0)


func condition_label() -> String:
	if condition >= 90.0:
		return "Excellent"
	if condition >= 75.0:
		return "Good"
	if condition >= 55.0:
		return "Fair"
	if condition >= 35.0:
		return "Poor"
	return "Derelict"


func location_label() -> String:
	if location_quality >= 75:
		return "High demand"
	if location_quality >= 50:
		return "Steady"
	if location_quality >= 30:
		return "Quiet"
	return "Fringe"
