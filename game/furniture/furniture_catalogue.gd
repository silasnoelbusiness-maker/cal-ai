class_name FurnitureCatalogue
extends RefCounted
## Everything the furniture shop sells.
##
## Three tiers across eleven categories rather than hundreds of near-identical
## objects: the interesting decision is "can I afford the good sofa yet", not
## "which of forty beige sofas". Every entry is one line, and the shop, the
## placement preview and the lifestyle score all read this list.

const C := FurnitureData.Category
const S := FurnitureData.Shape
const T := FurnitureData.Tier

static var _items: Array[FurnitureData] = []
static var _by_id: Dictionary = {}


static func all() -> Array[FurnitureData]:
	if _items.is_empty():
		_build()
	return _items


static func by_id(id: StringName) -> FurnitureData:
	if _items.is_empty():
		_build()
	return _by_id.get(id)


static func in_category(category: FurnitureData.Category) -> Array[FurnitureData]:
	var found: Array[FurnitureData] = []
	for item in all():
		if item.category == category:
			found.append(item)
	return found


## The categories that actually have something in them, in shop order.
static func categories() -> Array:
	var found: Array = []
	for item in all():
		if not found.has(item.category):
			found.append(item.category)
	return found


static func _add(item: FurnitureData) -> void:
	_items.append(item)
	_by_id[item.furniture_id] = item


static func _build() -> void:
	_items = []
	_by_id = {}

	# --- Beds. The one piece with a mechanical effect: a better mattress is a
	# better night, which is the only place furniture touches the numbers.
	_add(FurnitureData.make(
		&"bed_single", "Single Bed", C.BED, S.SLAB, T.BASIC, 260, 3, 4,
		Vector2(1.1, 2.0), 0.55, Color(0.416, 0.475, 0.549), Color(0.796, 0.788, 0.741)
	))
	_add(FurnitureData.make(
		&"bed_double", "Double Bed", C.BED, S.SLAB, T.STANDARD, 900, 7, 8,
		Vector2(1.7, 2.1), 0.58, Color(0.353, 0.310, 0.278), Color(0.847, 0.839, 0.796)
	))
	_add(FurnitureData.make(
		&"bed_kingsize", "Kingsize Bed", C.BED, S.SLAB, T.PREMIUM, 3200, 14, 14,
		Vector2(2.1, 2.2), 0.62, Color(0.235, 0.212, 0.196), Color(0.918, 0.910, 0.878)
	))

	# --- Seating.
	_add(FurnitureData.make(
		&"sofa_basic", "Two-Seat Sofa", C.SEATING, S.SOFA, T.BASIC, 300, 3, 4,
		Vector2(1.9, 0.9), 0.80, Color(0.404, 0.427, 0.451), Color(0.310, 0.333, 0.357)
	))
	_add(FurnitureData.make(
		&"sofa_standard", "Corner Sofa", C.SEATING, S.SOFA, T.STANDARD, 1100, 8, 9,
		Vector2(2.6, 1.0), 0.84, Color(0.286, 0.353, 0.396), Color(0.216, 0.271, 0.310)
	))
	_add(FurnitureData.make(
		&"sofa_premium", "Leather Suite", C.SEATING, S.SOFA, T.PREMIUM, 2600, 15, 14,
		Vector2(2.8, 1.1), 0.86, Color(0.318, 0.204, 0.161), Color(0.239, 0.153, 0.122)
	))

	# --- Tables.
	_add(FurnitureData.make(
		&"table_basic", "Folding Table", C.TABLE, S.TABLE, T.BASIC, 120, 2, 2,
		Vector2(1.2, 0.8), 0.74, Color(0.545, 0.478, 0.404), Color(0.420, 0.373, 0.318)
	))
	_add(FurnitureData.make(
		&"table_standard", "Dining Table", C.TABLE, S.TABLE, T.STANDARD, 620, 6, 5,
		Vector2(1.8, 1.0), 0.76, Color(0.400, 0.278, 0.176), Color(0.302, 0.212, 0.137)
	))
	_add(FurnitureData.make(
		&"table_premium", "Walnut Table", C.TABLE, S.TABLE, T.PREMIUM, 1900, 12, 8,
		Vector2(2.2, 1.1), 0.78, Color(0.259, 0.169, 0.110), Color(0.196, 0.129, 0.086)
	))

	# --- Chairs. Cheap, and bought several at a time, which is exactly the sort
	# of thing the lifestyle cap exists for.
	_add(FurnitureData.make(
		&"chair_basic", "Kitchen Chair", C.CHAIR, S.CHAIR, T.BASIC, 60, 1, 1,
		Vector2(0.5, 0.5), 0.90, Color(0.510, 0.451, 0.384), Color(0.396, 0.353, 0.302)
	))
	_add(FurnitureData.make(
		&"chair_premium", "Armchair", C.CHAIR, S.CHAIR, T.PREMIUM, 780, 6, 7,
		Vector2(0.9, 0.9), 0.94, Color(0.310, 0.271, 0.325), Color(0.239, 0.208, 0.251)
	))

	# --- Televisions.
	_add(FurnitureData.make(
		&"tv_basic", "Small Television", C.SCREEN, S.SCREEN, T.BASIC, 340, 3, 3,
		Vector2(1.0, 0.4), 1.05, Color(0.157, 0.165, 0.184), Color(0.098, 0.157, 0.208)
	))
	_add(FurnitureData.make(
		&"tv_premium", "Wall Television", C.SCREEN, S.SCREEN, T.PREMIUM, 2200, 12, 9,
		Vector2(1.8, 0.4), 1.20, Color(0.086, 0.090, 0.102), Color(0.129, 0.220, 0.290)
	))

	# --- Lamps.
	_add(FurnitureData.make(
		&"lamp_basic", "Floor Lamp", C.LAMP, S.LAMP, T.BASIC, 90, 2, 3,
		Vector2(0.4, 0.4), 1.55, Color(0.376, 0.384, 0.400), Color(0.949, 0.878, 0.706)
	))
	_add(FurnitureData.make(
		&"lamp_premium", "Brass Standard Lamp", C.LAMP, S.LAMP, T.PREMIUM, 640, 7, 6,
		Vector2(0.5, 0.5), 1.75, Color(0.706, 0.569, 0.290), Color(0.980, 0.937, 0.804)
	))

	# --- Dressers and storage. Storage is the only other functional category:
	# a cabinet is somewhere to put things, and how much fits depends on which.
	_add(FurnitureData.make(
		&"dresser_basic", "Chest of Drawers", C.DRESSER, S.CABINET, T.BASIC, 220, 2, 2,
		Vector2(1.0, 0.5), 0.90, Color(0.478, 0.400, 0.325), Color(0.361, 0.310, 0.259)
	))
	_add(FurnitureData.make(
		&"dresser_premium", "Oak Dresser", C.DRESSER, S.CABINET, T.PREMIUM, 1400, 10, 6,
		Vector2(1.4, 0.6), 1.05, Color(0.290, 0.196, 0.129), Color(0.208, 0.145, 0.098)
	))
	_add(FurnitureData.make(
		&"storage_locker", "Storage Cabinet", C.STORAGE, S.CABINET, T.BASIC, 380, 2, 1,
		Vector2(0.9, 0.6), 1.60, Color(0.427, 0.443, 0.459), Color(0.318, 0.333, 0.345), 12
	))
	_add(FurnitureData.make(
		&"storage_wardrobe", "Fitted Wardrobe", C.STORAGE, S.CABINET, T.PREMIUM, 1600, 8, 4,
		Vector2(1.6, 0.7), 2.10, Color(0.267, 0.239, 0.212), Color(0.196, 0.176, 0.157), 30
	))

	# --- Rugs, plants and pictures. No function at all, and that is fine: they
	# are how a room stops looking like a room with things in it.
	_add(FurnitureData.make(
		&"rug_basic", "Woven Rug", C.RUG, S.RUG, T.BASIC, 110, 2, 3,
		Vector2(2.0, 1.4), 0.03, Color(0.494, 0.376, 0.310), Color(0.376, 0.286, 0.235)
	))
	_add(FurnitureData.make(
		&"rug_premium", "Persian Rug", C.RUG, S.RUG, T.PREMIUM, 950, 9, 7,
		Vector2(2.8, 1.9), 0.04, Color(0.451, 0.180, 0.169), Color(0.318, 0.263, 0.157)
	))
	_add(FurnitureData.make(
		&"plant_small", "Potted Plant", C.PLANT, S.PLANT, T.BASIC, 45, 1, 2,
		Vector2(0.4, 0.4), 0.80, Color(0.243, 0.435, 0.263), Color(0.478, 0.325, 0.243)
	))
	_add(FurnitureData.make(
		&"plant_large", "Fig Tree", C.PLANT, S.PLANT, T.STANDARD, 260, 4, 4,
		Vector2(0.7, 0.7), 1.70, Color(0.216, 0.400, 0.243), Color(0.400, 0.290, 0.216)
	))
	_add(FurnitureData.make(
		&"art_print", "Framed Print", C.DECOR, S.PANEL, T.BASIC, 130, 2, 1,
		Vector2(0.7, 0.12), 0.90, Color(0.239, 0.196, 0.145), Color(0.729, 0.690, 0.596)
	))
	_add(FurnitureData.make(
		&"art_canvas", "Original Canvas", C.DECOR, S.PANEL, T.PREMIUM, 1800, 11, 4,
		Vector2(1.2, 0.14), 1.10, Color(0.180, 0.153, 0.129), Color(0.545, 0.318, 0.220)
	))
