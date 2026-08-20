class_name TenantData
extends RefCounted
## Somebody renting one of the player's properties.
##
## Data only, and deliberately so: a tenant is a name, a budget, a reliability
## and a payment schedule. There is no tenant walking around a flat the player
## owns across the city, and there should not be — a portfolio of nine units
## would otherwise be nine more people to simulate for no gameplay at all.
##
## What the player actually interacts with is the decision: this applicant pays
## more but is less reliable, that one is dull and always pays.

enum Kind { RESIDENTIAL, COMMERCIAL }
enum PaymentState { CURRENT, LATE, MISSED }

## Original names, assembled from two lists. Nothing here is anybody real.
const FIRST_NAMES: Array[String] = [
	"Jordan", "Nadia", "Emeka", "Sofia", "Callum", "Priya", "Tomas", "Ines",
	"Rafael", "Marta", "Yusuf", "Elena", "Bram", "Aoife", "Kofi", "Lena",
]
const LAST_NAMES: Array[String] = [
	"Hayes", "Okonkwo", "Vance", "Reyes", "Balint", "Nasser", "Croft", "Serra",
	"Dunne", "Petrov", "Adeyemi", "Larsen", "Quinn", "Farrow", "Ibarra",
]
## Fictional shopfronts for commercial tenancies. Invented, and deliberately
## dull in the way real small businesses are.
const TRADE_NAMES: Array[String] = [
	"Bluebird Cafe", "Harbour Goods", "Northstar Services", "Kettle & Crumb",
	"Meridian Print", "Anchor Hardware", "Rowan Bookshop", "Copperline Salon",
]

var tenant_id: StringName = &""
var tenant_name: String = "Tenant"
var kind: Kind = Kind.RESIDENTIAL
## 0-100. How much they can comfortably pay, and how likely they are to keep
## paying it. Two different things: a well-off unreliable tenant exists.
var income_quality: int = 50
var reliability: int = 70
var rent_budget: int = 0
var lease_start_day: int = 0
var lease_end_day: int = 0
var property_id: StringName = &""
## Which unit of a multi-unit building, or -1 for a whole-property tenancy.
var unit_index: int = -1
var payment_state: PaymentState = PaymentState.CURRENT
var missed_payments: int = 0
var satisfaction: int = 70
var next_rent_day: int = 0
## What they actually agreed to pay, which is the asking rent at the time.
var rent_amount: int = 0


func is_commercial() -> bool:
	return kind == Kind.COMMERCIAL


func reliability_label() -> String:
	if reliability >= 80:
		return "High"
	if reliability >= 55:
		return "Fair"
	return "Low"


func lease_days_left(day: int) -> int:
	return maxi(lease_end_day - day, 0)


func payment_label() -> String:
	match payment_state:
		PaymentState.LATE:
			return "LATE"
		PaymentState.MISSED:
			return "MISSED"
		_:
			return "Current"


## How likely they are to pay on any given rent day, from reliability alone.
func payment_chance() -> float:
	return clampf(0.55 + float(reliability) / 100.0 * 0.44, 0.0, 0.99)


## How hard they are on the place. A careful tenant costs a fraction of a point
## of condition per rent period; a careless one costs a little more. Both are
## deliberately mild — a tenant should not wreck a flat in a fortnight.
func wear_per_period() -> float:
	return lerpf(0.55, 0.12, clampf(float(reliability) / 100.0, 0.0, 1.0))


## Whether they will sign at this asking rent. Somebody whose budget is well
## over the asking price says yes readily; somebody stretched says no.
func would_accept(asking_rent: int) -> bool:
	return asking_rent <= rent_budget


static func generate(
	kind: Kind, market_rent: int, rng: RandomNumberGenerator, index: int
) -> TenantData:
	var tenant := TenantData.new()
	tenant.tenant_id = StringName("tenant_%d" % index)
	tenant.kind = kind
	tenant.income_quality = rng.randi_range(25, 95)
	tenant.reliability = rng.randi_range(35, 98)
	# What they can pay follows what they earn, spread either side of the going
	# rate so some applicants can afford above-market rent and some cannot.
	var stretch := lerpf(0.78, 1.35, float(tenant.income_quality) / 100.0)
	tenant.rent_budget = maxi(roundi(float(market_rent) * stretch), 1)

	if kind == Kind.COMMERCIAL:
		tenant.tenant_name = TRADE_NAMES[rng.randi_range(0, TRADE_NAMES.size() - 1)]
	else:
		tenant.tenant_name = "%s %s" % [
			FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)],
			LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
		]
	return tenant


func to_dictionary() -> Dictionary:
	return {
		"tenant_id": String(tenant_id),
		"tenant_name": tenant_name,
		"kind": int(kind),
		"income_quality": income_quality,
		"reliability": reliability,
		"rent_budget": rent_budget,
		"lease_start_day": lease_start_day,
		"lease_end_day": lease_end_day,
		"property_id": String(property_id),
		"unit_index": unit_index,
		"payment_state": int(payment_state),
		"missed_payments": missed_payments,
		"satisfaction": satisfaction,
		"next_rent_day": next_rent_day,
		"rent_amount": rent_amount,
	}


static func from_dictionary(state: Dictionary) -> TenantData:
	var tenant := TenantData.new()
	tenant.tenant_id = StringName(state.get("tenant_id", ""))
	tenant.tenant_name = String(state.get("tenant_name", "Tenant"))
	tenant.kind = int(state.get("kind", int(Kind.RESIDENTIAL))) as Kind
	tenant.income_quality = int(state.get("income_quality", 50))
	tenant.reliability = int(state.get("reliability", 70))
	tenant.rent_budget = int(state.get("rent_budget", 0))
	tenant.lease_start_day = int(state.get("lease_start_day", 0))
	tenant.lease_end_day = int(state.get("lease_end_day", 0))
	tenant.property_id = StringName(state.get("property_id", ""))
	tenant.unit_index = int(state.get("unit_index", -1))
	tenant.payment_state = int(state.get("payment_state", 0)) as PaymentState
	tenant.missed_payments = int(state.get("missed_payments", 0))
	tenant.satisfaction = int(state.get("satisfaction", 70))
	tenant.next_rent_day = int(state.get("next_rent_day", 0))
	tenant.rent_amount = int(state.get("rent_amount", 0))
	return tenant
