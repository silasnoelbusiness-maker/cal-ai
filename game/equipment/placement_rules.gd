class_name PlacementRules
extends RefCounted
## The geometry every placement mode needs, in one place.
##
## Putting a counter on a shop floor and putting a sofa in a flat are different
## errands with different rules about what is legal, but the arithmetic
## underneath is the same: turn a footprint by its rotation, work out the
## rectangle it covers, and keep a gap between it and its neighbours. That much
## is shared rather than written twice.

## Clearance kept between two placed things, in metres. Without it, two pieces
## can sit flush and read as one object.
const SEPARATION := 0.15

## Degrees per press of the rotate key.
const ROTATION_STEP := 90.0


## A footprint turned by a rotation in degrees. Only quarter turns change it,
## which is exactly what the rotation step produces.
static func rotated_size(size: Vector2, rotation_degrees: float) -> Vector2:
	var quarter_turned := int(round(rotation_degrees / 90.0)) % 2 != 0
	return Vector2(size.y, size.x) if quarter_turned else size


## The rectangle a piece covers on the floor, centred on its position.
static func footprint(local_point: Vector3, size: Vector2) -> Rect2:
	return Rect2(local_point.x - size.x * 0.5, local_point.z - size.y * 0.5, size.x, size.y)


## The same rectangle with the clearance added, for testing against neighbours.
static func spaced_footprint(local_point: Vector3, size: Vector2) -> Rect2:
	return footprint(local_point, size).grow(SEPARATION)


## Half-metre grid. Fine enough to line things up along a wall, coarse enough
## that nothing ends up a centimetre out of true.
static func snap(local_point: Vector3) -> Vector3:
	return Vector3(roundf(local_point.x * 2.0) / 2.0, 0.0, roundf(local_point.z * 2.0) / 2.0)


## Whether a rectangle sits entirely inside another, allowing for the wall
## thickness a room wants kept clear.
static func contains(area: Rect2, rect: Rect2, margin: float = 0.0) -> bool:
	return area.grow(-margin).encloses(rect)
