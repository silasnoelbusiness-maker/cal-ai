class_name DistrictData
extends RefCounted
## What a part of the city is like, as data.
##
## Everything that varies between one district and another and is not geometry:
## how busy it is, what it costs, how quickly the police turn up. Systems ask
## WorldManager which district a position is in and read these numbers rather
## than checking coordinates themselves, which is what lets a third district be
## an entry in a table instead of a change to the traffic manager.

var district_id: StringName = &""
var display_name: String = "District"
## Bounds on the ground plane, in world space. Districts do not overlap.
var world_bounds: Rect2 = Rect2()
var center_position: Vector3 = Vector3.ZERO

## Multipliers on the city-wide baseline.
var traffic_density: float = 1.0
var pedestrian_density: float = 1.0
## How much passing trade a business here gets before its own address is
## considered. Property-level quality multiplies on top of this.
var commercial_demand_modifier: float = 1.0
var commercial_rent_modifier: float = 1.0
var residential_rent_modifier: float = 1.0
## Scales how far officers will travel to a call raised here.
var police_presence: float = 1.0
## Shown when the player first crosses in.
var subtitle: String = ""


static func make(
	id: StringName, display: String, bounds: Rect2, subtitle: String = ""
) -> DistrictData:
	var district := DistrictData.new()
	district.district_id = id
	district.display_name = display
	district.world_bounds = bounds
	district.center_position = Vector3(
		bounds.get_center().x, 0.0, bounds.get_center().y
	)
	district.subtitle = subtitle
	return district


func contains(position: Vector3) -> bool:
	return world_bounds.has_point(Vector2(position.x, position.z))


## How far outside the district a position is, for picking the nearest one when
## a point falls in a gap between them.
func distance_to(position: Vector3) -> float:
	var point := Vector2(position.x, position.z)
	if world_bounds.has_point(point):
		return 0.0
	var clamped := Vector2(
		clampf(point.x, world_bounds.position.x, world_bounds.end.x),
		clampf(point.y, world_bounds.position.y, world_bounds.end.y)
	)
	return point.distance_to(clamped)
