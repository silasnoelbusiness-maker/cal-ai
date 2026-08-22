class_name MapMarker
extends RefCounted
## One thing worth showing on the city map.
##
## Markers are gathered fresh whenever the map is opened rather than registered
## and maintained, because everything they describe — a business's opening state,
## whether a unit is still vacant — is already owned by something else. A stale
## copy of that would be a second source of truth.

## Appended to rather than reordered: the filter states are saved by index.
enum Category {
	HOME, OWNED_BUSINESS, AVAILABLE_PROPERTY, JOB, POLICE, SHOP, LANDMARK, MY_VEHICLE,
	FOR_SALE, MY_PROPERTY, WAREHOUSE, DELIVERY, CONTACT, OBJECTIVE,
	COURT,
}

var category: Category = Category.SHOP
var label: String = ""
var detail: String = ""
var position: Vector3 = Vector3.ZERO
## Set for markers that lead somewhere the player can act on.
var target_id: StringName = &""


static func make(
	category: Category, label: String, position: Vector3, detail: String = "",
	target_id: StringName = &""
) -> MapMarker:
	var marker := MapMarker.new()
	marker.category = category
	marker.label = label
	marker.position = position
	marker.detail = detail
	marker.target_id = target_id
	return marker


static func category_name(category: Category) -> String:
	match category:
		Category.HOME:
			return "Home"
		Category.OWNED_BUSINESS:
			return "My businesses"
		Category.AVAILABLE_PROPERTY:
			return "Available property"
		Category.JOB:
			return "Jobs"
		Category.POLICE:
			return "Police"
		Category.LANDMARK:
			return "Landmarks"
		Category.MY_VEHICLE:
			return "My vehicles"
		Category.FOR_SALE:
			return "For sale"
		Category.MY_PROPERTY:
			return "My property"
		Category.WAREHOUSE:
			return "Depots"
		Category.DELIVERY:
			return "Deliveries"
		Category.CONTACT:
			return "Contacts"
		Category.COURT:
			return "Court"
		Category.OBJECTIVE:
			# Not "Jobs": Category.JOB already is, and the map came back with
			# two filter buttons reading the same word. These are the places an
			# accepted job wants the player to be.
			return "Job targets"
		_:
			return "Shops"


static func category_colour(category: Category) -> Color:
	match category:
		Category.HOME:
			return Color(0.478, 0.694, 0.961)
		Category.OWNED_BUSINESS:
			return Color(0.596, 0.918, 0.639)
		Category.AVAILABLE_PROPERTY:
			return Color(0.965, 0.816, 0.478)
		Category.JOB:
			return Color(0.847, 0.639, 0.961)
		Category.MY_VEHICLE:
			return Color(0.976, 0.812, 0.435)
		Category.FOR_SALE:
			return Color(0.902, 0.451, 0.373)
		Category.MY_PROPERTY:
			return Color(0.376, 0.847, 0.769)
		Category.WAREHOUSE:
			return Color(0.667, 0.729, 0.812)
		Category.DELIVERY:
			return Color(0.980, 0.667, 0.310)
		Category.CONTACT:
			return Color(0.706, 0.522, 0.808)
		Category.OBJECTIVE:
			return Color(0.902, 0.361, 0.404)
		Category.POLICE:
			return Color(0.412, 0.667, 0.882)
		Category.LANDMARK:
			return Color(0.902, 0.902, 0.882)
		_:
			return Color(0.729, 0.749, 0.784)
