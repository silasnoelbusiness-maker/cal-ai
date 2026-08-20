class_name FurnitureData
extends RefCounted
## One thing you can buy for a home.
##
## Deliberately a plain object built by the catalogue rather than a .tres per
## item: furniture has no behaviour to author and no scene to point at — every
## piece is drawn from CityKit primitives out of these numbers, the same way the
## city and its interiors are. Adding a lamp is a line in the catalogue.

## What the item is for. Placement rules and the lifestyle score both read this
## rather than the id, so two different sofas are both SEATING.
enum Category { BED, SEATING, TABLE, CHAIR, SCREEN, LAMP, DRESSER, RUG, PLANT, DECOR, STORAGE }

## How it is drawn. A silhouette, not a colour — the difference between a
## roster of furniture and one box painted eleven ways.
enum Shape { SLAB, SOFA, TABLE, CHAIR, SCREEN, LAMP, CABINET, RUG, PLANT, PANEL }

## Quality band. The price, the lifestyle value and the name all follow it.
enum Tier { BASIC, STANDARD, PREMIUM }

var furniture_id: StringName = &""
var display_name: String = "Furniture"
var category: Category = Category.DECOR
var shape: Shape = Shape.SLAB
var tier: Tier = Tier.BASIC
var purchase_price: int = 100
## What owning it says about the place. Capped by category when the score is
## worked out, so twenty plants are not twenty plants' worth of lifestyle.
var lifestyle_value: int = 2
## How pleasant the place is to be in. Read by the home comfort score and, for
## a bed, by how well the player sleeps.
var comfort_value: int = 2

## Footprint in metres, X by Z, and how tall it stands.
var placement_size: Vector2 = Vector2(1.0, 1.0)
var height: float = 0.6
var body_color: Color = Color(0.435, 0.451, 0.478)
var accent_color: Color = Color(0.302, 0.294, 0.278)
## Personal items a storage piece holds. Zero for everything that is not one.
var storage_slots: int = 0


static func make(
	furniture_id: StringName, display_name: String, category: Category, shape: Shape,
	tier: Tier, purchase_price: int, lifestyle_value: int, comfort_value: int,
	placement_size: Vector2, height: float, body_color: Color, accent_color: Color,
	storage_slots: int = 0
) -> FurnitureData:
	var item := FurnitureData.new()
	item.furniture_id = furniture_id
	item.display_name = display_name
	item.category = category
	item.shape = shape
	item.tier = tier
	item.purchase_price = purchase_price
	item.lifestyle_value = lifestyle_value
	item.comfort_value = comfort_value
	item.placement_size = placement_size
	item.height = height
	item.body_color = body_color
	item.accent_color = accent_color
	item.storage_slots = storage_slots
	return item


func is_bed() -> bool:
	return category == Category.BED


func is_storage() -> bool:
	return storage_slots > 0


## What a second-hand dealer gives back for it. Furniture is not an investment;
## this is here so removing something the player regrets is not a total loss.
func resale_value() -> int:
	return maxi(roundi(float(purchase_price) * 0.55), 1)


static func category_name(category: Category) -> String:
	match category:
		Category.BED:
			return "Beds"
		Category.SEATING:
			return "Sofas"
		Category.TABLE:
			return "Tables"
		Category.CHAIR:
			return "Chairs"
		Category.SCREEN:
			return "Televisions"
		Category.LAMP:
			return "Lamps"
		Category.DRESSER:
			return "Dressers"
		Category.RUG:
			return "Rugs"
		Category.PLANT:
			return "Plants"
		Category.STORAGE:
			return "Storage"
		_:
			return "Decor"


static func tier_name(tier: Tier) -> String:
	match tier:
		Tier.PREMIUM:
			return "Premium"
		Tier.STANDARD:
			return "Standard"
		_:
			return "Basic"
