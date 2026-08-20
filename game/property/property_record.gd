class_name PropertyRecord
extends RefCounted
## One piece of real estate, as the investment side sees it.
##
## The physical door in the street is still a CommercialProperty or a
## ResidenceProperty node and still does its own leasing; this is the ownership
## layer on top, keyed to the same `property_id`. That is the whole reason the
## two are separate: renting a shop unit from a landlord and owning the building
## are different relationships with the same address, and a player can do both
## in sequence without anything about the shop changing.
##
## A record exists only for property the player owns. What is merely for sale is
## a PropertyListing.

enum Kind { RESIDENTIAL, COMMERCIAL, MULTI_UNIT }

## What the property is doing, which is not the same as who owns it.
##   VACANT              — owned, empty, earning nothing.
##   TENANTED            — an NPC pays rent for it.
##   OWNER_OCCUPIED      — the player lives here.
##   BUSINESS_OCCUPIED   — one of the player's own businesses trades from here.
##   LISTED_FOR_RENT     — empty and looking for a tenant.
enum Use { VACANT, TENANTED, OWNER_OCCUPIED, BUSINESS_OCCUPIED, LISTED_FOR_RENT }

## How many units a small block holds. Four: enough to make occupancy a
## fraction rather than a coin flip, few enough that it is still one building.
const MULTI_UNIT_COUNT := 4

var property_id: StringName = &""
var address: String = ""
var district_id: StringName = &"harbour_row"
var kind: Kind = Kind.RESIDENTIAL
var size_label: String = "Studio"
var floor_area: int = 40
## 0-100, both. Condition is the state of the building; location quality is the
## pitch it stands on and never changes.
var condition: float = 85.0
var location_quality: int = 50

var purchase_price: int = 0
var purchase_day: int = 0
## What it is worth today. Recomputed by RealEstate rather than stored blindly,
## but kept here so a screen can read it without recomputing.
var market_value: int = 0
var mortgage_id: StringName = &""

var use: Use = Use.VACANT
## Asking rent while listed, and the going rate for the address.
var asking_rent: int = 0
var market_rent: int = 0
var days_vacant: int = 0
## For a multi-unit block: one entry per unit, each VACANT, TENANTED or
## LISTED_FOR_RENT. Single properties leave this empty and use `use`.
var unit_uses: Array[int] = []
var unit_rents: Array[int] = []

## Periodic upkeep, before condition is taken into account.
var base_maintenance: int = 80


func is_multi_unit() -> bool:
	return kind == Kind.MULTI_UNIT


func unit_count() -> int:
	return unit_uses.size() if is_multi_unit() else 1


func has_mortgage() -> bool:
	return mortgage_id != &""


func kind_label() -> String:
	match kind:
		Kind.COMMERCIAL:
			return "Commercial"
		Kind.MULTI_UNIT:
			return "Multi-unit residential"
		_:
			return "Residential"


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


## What the player is doing with it, in the words the portfolio uses.
func use_label() -> String:
	if is_multi_unit():
		return "%d of %d let" % [occupied_units(), unit_count()]
	match use:
		Use.TENANTED:
			return "Tenanted"
		Use.OWNER_OCCUPIED:
			return "Your home"
		Use.BUSINESS_OCCUPIED:
			return "Your business"
		Use.LISTED_FOR_RENT:
			return "Listed to let"
		_:
			return "Vacant"


func occupied_units() -> int:
	if not is_multi_unit():
		return 1 if use == Use.TENANTED else 0
	var count := 0
	for state in unit_uses:
		if state == int(Use.TENANTED):
			count += 1
	return count


## Units that could earn rent — every unit of a block, or the property itself
## unless the player is living or trading in it.
func rentable_units() -> int:
	if is_multi_unit():
		return unit_count()
	return 0 if use == Use.OWNER_OCCUPIED or use == Use.BUSINESS_OCCUPIED else 1


func occupancy_fraction() -> float:
	var rentable := rentable_units()
	if rentable <= 0:
		return 0.0
	return float(occupied_units()) / float(rentable)


## Upkeep for one period. A property in poor repair costs more to keep standing,
## which is what stops neglect being free.
func maintenance_cost() -> int:
	var wear := lerpf(1.6, 0.85, clampf(condition / 100.0, 0.0, 1.0))
	return maxi(roundi(float(base_maintenance) * wear), 1)


## Whether the player may sell it. A business trading from a unit the player
## owns has nowhere to go if the building is sold out from under it, and there
## is no relocation system, so the sale is blocked rather than allowed to
## destroy the shop. See RealEstate.sale_blocked_reason.
func is_sellable() -> bool:
	return use != Use.BUSINESS_OCCUPIED


func to_dictionary() -> Dictionary:
	return {
		"property_id": String(property_id),
		"address": address,
		"district_id": String(district_id),
		"kind": int(kind),
		"size_label": size_label,
		"floor_area": floor_area,
		"condition": condition,
		"location_quality": location_quality,
		"purchase_price": purchase_price,
		"purchase_day": purchase_day,
		"market_value": market_value,
		"mortgage_id": String(mortgage_id),
		"use": int(use),
		"asking_rent": asking_rent,
		"market_rent": market_rent,
		"days_vacant": days_vacant,
		"unit_uses": unit_uses.duplicate(),
		"unit_rents": unit_rents.duplicate(),
		"base_maintenance": base_maintenance,
	}


static func from_dictionary(state: Dictionary) -> PropertyRecord:
	var record := PropertyRecord.new()
	record.property_id = StringName(state.get("property_id", ""))
	record.address = String(state.get("address", ""))
	record.district_id = StringName(state.get("district_id", "harbour_row"))
	record.kind = int(state.get("kind", int(Kind.RESIDENTIAL))) as Kind
	record.size_label = String(state.get("size_label", "Studio"))
	record.floor_area = int(state.get("floor_area", 40))
	record.condition = clampf(float(state.get("condition", 85.0)), 0.0, 100.0)
	record.location_quality = int(state.get("location_quality", 50))
	record.purchase_price = int(state.get("purchase_price", 0))
	record.purchase_day = int(state.get("purchase_day", 0))
	record.market_value = int(state.get("market_value", 0))
	record.mortgage_id = StringName(state.get("mortgage_id", ""))
	record.use = int(state.get("use", int(Use.VACANT))) as Use
	record.asking_rent = int(state.get("asking_rent", 0))
	record.market_rent = int(state.get("market_rent", 0))
	record.days_vacant = int(state.get("days_vacant", 0))
	for value in state.get("unit_uses", []):
		record.unit_uses.append(int(value))
	for value in state.get("unit_rents", []):
		record.unit_rents.append(int(value))
	record.base_maintenance = int(state.get("base_maintenance", 80))
	return record
