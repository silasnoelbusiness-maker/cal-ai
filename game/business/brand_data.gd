class_name BrandData
extends RefCounted
## A name several shops trade under.
##
## The thing that turns three convenience stores into a chain. A brand owns no
## stock, employs nobody and holds no money — every one of those stays with the
## branch, because two shops with the same sign still have different tills and
## different people in them. What the brand owns is the name, the colour above
## the door and a reputation that moves slowly across all of them.
##
## Deliberately not a business. A brand with no branches is a name doing
## nothing, and the company screen says so rather than pretending it trades.

## How fast a branch's standing pulls the brand's. Slow on purpose: one bad day
## at one shop should not cost the name.
const REPUTATION_DRIFT_PER_DAY := 1.6

var brand_id: StringName = &""
var brand_name: String = "Brand"
## Every branch of a brand is the same kind of business. A restaurant and a
## corner shop under one name would be a holding company, and that is what the
## company layer above is for.
var business_type: StringName = &"convenience_store"
var brand_color: Color = Color(0.286, 0.478, 0.678)
var branch_ids: Array[StringName] = []
var brand_reputation: float = 50.0
var lifetime_revenue: int = 0
var company_id: StringName = &"player_company"
var founded_on_day: int = 0


func branch_count() -> int:
	return branch_ids.size()


func has_branch(business_id: StringName) -> bool:
	return branch_ids.has(business_id)


func add_branch(business_id: StringName) -> bool:
	if business_id == &"" or branch_ids.has(business_id):
		return false
	branch_ids.append(business_id)
	return true


func remove_branch(business_id: StringName) -> bool:
	var index := branch_ids.find(business_id)
	if index < 0:
		return false
	branch_ids.remove_at(index)
	return true


## What a branch is called on the sign: the brand, then where it is. The
## address is what tells two of them apart, and the player never types it.
func branch_name(location_label: String) -> String:
	if location_label.strip_edges().is_empty():
		return brand_name
	return "%s — %s" % [brand_name, location_label.strip_edges().to_upper()]


func reputation_label() -> String:
	if brand_reputation >= 80.0:
		return "Well known"
	if brand_reputation >= 62.0:
		return "Respected"
	if brand_reputation >= 42.0:
		return "Getting known"
	if brand_reputation >= 25.0:
		return "Struggling"
	return "Bad name"


## Pulls the brand's standing towards the average of its branches. A chain is
## worth what its shops are, eventually.
func drift_towards(branch_average: float) -> void:
	if branch_ids.is_empty():
		return
	var gap := branch_average - brand_reputation
	var step := clampf(gap, -REPUTATION_DRIFT_PER_DAY, REPUTATION_DRIFT_PER_DAY)
	brand_reputation = clampf(brand_reputation + step, 0.0, 100.0)


func to_dict() -> Dictionary:
	var branches: Array = []
	for id in branch_ids:
		branches.append(String(id))
	return {
		"id": String(brand_id),
		"name": brand_name,
		"type": String(business_type),
		"color": [brand_color.r, brand_color.g, brand_color.b],
		"branches": branches,
		"reputation": brand_reputation,
		"lifetime_revenue": lifetime_revenue,
		"company": String(company_id),
		"founded_on_day": founded_on_day,
	}


static func from_dict(state: Dictionary) -> BrandData:
	var brand := BrandData.new()
	brand.brand_id = StringName(state.get("id", ""))
	brand.brand_name = String(state.get("name", "Brand"))
	brand.business_type = StringName(state.get("type", "convenience_store"))
	var rgb: Array = state.get("color", [0.286, 0.478, 0.678])
	if rgb.size() >= 3:
		brand.brand_color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	for id in state.get("branches", []):
		brand.branch_ids.append(StringName(id))
	brand.brand_reputation = float(state.get("reputation", 50.0))
	brand.lifetime_revenue = int(state.get("lifetime_revenue", 0))
	brand.company_id = StringName(state.get("company", "player_company"))
	brand.founded_on_day = int(state.get("founded_on_day", 0))
	return brand
