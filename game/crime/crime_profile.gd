class_name CrimeProfile
extends RefCounted

## How the police answer a kind of crime.
##
## The shape of a response, separated from the crime that caused it, so that
## "how many cars come" is a property of the situation rather than a switch on
## the offence. Three profiles cover Phase Q: somebody takes a look, a patrol
## comes out, or the shift is coordinated. Which one a crime uses is a field in
## CrimeData, and what each one means is here.
##
## Note what is *not* here: speed multipliers. §181 is explicit that a higher
## wanted level should be harder because the police behave differently, not
## because their cars become unrealistically fast. So a profile changes how many
## units, how far they will come, how long they persist and whether they may set
## up roadblocks — never how quickly they drive.

var profile_id: StringName = &"routine"
var display_name: String = "Routine"
## Units this profile is willing to commit, before the wanted level's own cap.
var units: int = 1
## How far away an officer will answer the call from.
var radius: float = 90.0
## Seconds the search persists once the player is out of sight.
var search_seconds: float = 20.0
## Whether units try to cut the player off rather than follow.
var intercepts: bool = false
## Whether the shift may block roads for this.
var roadblocks: bool = false


static func make(
	id: StringName, name: String, unit_count: int, reach: float,
	persistence: float, cut_off: bool = false, blocks: bool = false
) -> CrimeProfile:
	var profile := CrimeProfile.new()
	profile.profile_id = id
	profile.display_name = name
	profile.units = unit_count
	profile.radius = reach
	profile.search_seconds = persistence
	profile.intercepts = cut_off
	profile.roadblocks = blocks
	return profile


static var _table: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty():
		_table = {
			# Somebody wanders over. A shoplifter who walks out briskly is gone.
			&"routine": make(&"routine", "Routine", 1, 80.0, 16.0),
			# A car is sent. This is the ordinary police response.
			&"patrol": make(&"patrol", "Patrol", 2, 150.0, 26.0),
			# The shift is told. Units try to cut the player off rather than
			# queue up behind them, and roads may be blocked.
			&"coordinated": make(
				&"coordinated", "Coordinated", 4, 240.0, 38.0, true, true
			),
		}
	return _table


static func by_id(id: StringName) -> CrimeProfile:
	var found: CrimeProfile = table().get(id)
	return found if found != null else table()[&"routine"]


static func for_crime(type: int) -> CrimeProfile:
	return by_id(CrimeData.for_type(type).police_response_profile)
