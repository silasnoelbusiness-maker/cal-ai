class_name MarketingCampaign
extends RefCounted
## An advertising push, and what it is worth.
##
## Marketing buys *attention*, never money: a campaign raises how many people
## walk in and nothing else. A badly run shop that advertises gets more people
## through the door to be disappointed, which is exactly right — it shows up as
## lost sales and a falling reputation rather than as free revenue.

var campaign_id: StringName = &""
var display_name: String = "Campaign"
var cost: int = 100
var duration_days: int = 2
## Multiplier on customer arrivals while it runs.
var demand_bonus: float = 0.15
var expires_on_day: int = 0


static func make(
	id: StringName, display: String, cost: int, days: int, bonus: float
) -> MarketingCampaign:
	var campaign := MarketingCampaign.new()
	campaign.campaign_id = id
	campaign.display_name = display
	campaign.cost = cost
	campaign.duration_days = days
	campaign.demand_bonus = bonus
	return campaign


## What can be bought. Bigger campaigns are better value per day and worse value
## per pound up front, which is the decision.
static func catalogue() -> Array[MarketingCampaign]:
	return [
		make(&"flyers", "Flyers", 100, 2, 0.12),
		make(&"social", "Social Media Ads", 300, 3, 0.25),
		make(&"local_ads", "Local Radio Ads", 750, 5, 0.45),
	]


static func by_id(id: StringName) -> MarketingCampaign:
	for campaign in catalogue():
		if campaign.campaign_id == id:
			return campaign
	return null


func start(day_index: int) -> void:
	expires_on_day = day_index + duration_days


func is_running(day_index: int) -> bool:
	return day_index < expires_on_day


func days_left(day_index: int) -> int:
	return maxi(expires_on_day - day_index, 0)


func to_dict() -> Dictionary:
	return {"id": String(campaign_id), "expires": expires_on_day}


static func from_dict(state: Dictionary) -> MarketingCampaign:
	var campaign := by_id(StringName(state.get("id", "")))
	if campaign == null:
		return null
	campaign.expires_on_day = int(state.get("expires", 0))
	return campaign
