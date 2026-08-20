class_name OwnedFurniture
extends RefCounted
## One piece of furniture the player owns.
##
## The same record-as-truth arrangement the cars and the shop equipment use. A
## sofa is a record with a position on it; the box in the room is drawn from
## that record, which is why a reloaded flat looks exactly like the flat the
## player left rather than approximately like it.
##
## Storing a piece does not destroy it — it clears the residence and the
## transform and leaves the record on the books, which is what makes moving
## house with your own furniture possible.

var instance_id: StringName = &""
var furniture_id: StringName = &""
## The residence it stands in, or empty while it is in storage.
var residence_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var rotation_y: float = 0.0
## What was paid, for the profile screen and for resale.
var purchase_price: int = 0


func data() -> FurnitureData:
	return FurnitureCatalogue.by_id(furniture_id)


func display_name() -> String:
	var definition := data()
	return definition.display_name if definition != null else String(furniture_id).capitalize()


func is_placed() -> bool:
	return residence_id != &""


## Footprint with the piece's own rotation taken into account, so a sofa turned
## sideways occupies a sideways sofa's worth of floor.
func footprint_size() -> Vector2:
	var definition := data()
	if definition == null:
		return Vector2.ONE
	var quarter_turned := int(round(rad_to_deg(rotation_y) / 90.0)) % 2 != 0
	var size := definition.placement_size
	return Vector2(size.y, size.x) if quarter_turned else size


func to_dictionary() -> Dictionary:
	return {
		"instance_id": String(instance_id),
		"furniture_id": String(furniture_id),
		"residence_id": String(residence_id),
		"position": [position.x, position.y, position.z],
		"rotation_y": rotation_y,
		"purchase_price": purchase_price,
	}


static func from_dictionary(state: Dictionary) -> OwnedFurniture:
	var record := OwnedFurniture.new()
	record.instance_id = StringName(state.get("instance_id", ""))
	record.furniture_id = StringName(state.get("furniture_id", ""))
	record.residence_id = StringName(state.get("residence_id", ""))
	var raw: Array = state.get("position", [])
	if raw.size() == 3:
		record.position = Vector3(raw[0], raw[1], raw[2])
	record.rotation_y = float(state.get("rotation_y", 0.0))
	record.purchase_price = int(state.get("purchase_price", 0))
	return record
