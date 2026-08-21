class_name EquipmentData
extends Resource
## One kind of thing a business can buy and put on its floor.
##
## Data only: what it costs, how much room it takes, what it does and which
## businesses may have one. A coffee machine, a clothes rail or a gym bench is a
## new .tres rather than a new script — `role` is what the rest of the game
## switches on, and everything else is numbers.

## What this piece of equipment is *for*. The business rules read this rather
## than the id, so two different shelves are both SHELF.
## Appended to rather than reordered: the saved .tres files store these as
## numbers, and renumbering them would quietly turn every shelf into a counter.
enum Role {
	SHELF, CHECKOUT, STORAGE, FITTING, BREW,
	SEATING, COOK_STATION, PREP, COLD_STORE, PASS,
	RECEPTION, MACHINE, BAR, DANCE_FLOOR, DJ_BOOTH,
	SECURITY_POST, LIGHTING, CLEANING, DESK,
}

## Roles that seat or hold customers rather than goods. What a business can
## take through its doors at once is the sum of these.
const CUSTOMER_ROLES: Array[int] = [
	Role.SEATING, Role.MACHINE, Role.DANCE_FLOOR,
]

@export var equipment_id: StringName = &""
@export var display_name: String = "Equipment"
@export_multiline var description: String = ""
@export var role: Role = Role.SHELF
@export var purchase_price: int = 100

@export_group("Placement")
## Footprint in metres, X by Z. Used for the placement preview, the overlap test
## and the grid snap, so a wide counter cannot be squeezed into a narrow gap.
@export var placement_size: Vector2 = Vector2(2.6, 0.8)
@export var height: float = 1.4
@export var body_color: Color = Color(0.435, 0.451, 0.478)
@export var accent_color: Color = Color(0.302, 0.294, 0.278)

@export_group("Function")
## Units a shelf can hold, or a storage rack can add to the back room. Zero for
## equipment that holds nothing.
@export var capacity: int = 0
## Business type ids allowed to buy this. Empty means any.
@export var business_types_allowed: Array[StringName] = []
## Customers this one piece holds at once: seats round a table, stations on a
## machine, bodies on a stretch of dance floor. Zero for anything that serves
## nobody directly.
@export var customer_slots: int = 0
## 1-3. A dearer machine is not faster, it is nicer to be in the room with, so
## the tier feeds satisfaction and prestige rather than throughput.
@export var quality_tier: int = 1
## Points of cleanliness this costs per customer that uses it. Kitchens and gym
## machines make a mess; a shelf does not.
@export var soiling_per_use: float = 0.0

@export_group("Operating")
## Staff role that has to be on shift for this to do anything, or -1 for a
## piece that works by standing there.
@export var operated_by_role: int = -1


func allows(business_type: StringName) -> bool:
	return business_types_allowed.is_empty() or business_types_allowed.has(business_type)


func is_shelf() -> bool:
	return role == Role.SHELF


func is_checkout() -> bool:
	return role == Role.CHECKOUT


func is_storage() -> bool:
	return role == Role.STORAGE


## A workstation where a prepared product is made — the coffee machine, and
## whatever a later business type cooks on.
func is_workstation() -> bool:
	return role == Role.BREW or role == Role.COOK_STATION


## Whether customers occupy this rather than take goods off it.
func holds_customers() -> bool:
	return customer_slots > 0 and CUSTOMER_ROLES.has(role)


## A tier as the shop floor says it.
func quality_label() -> String:
	match clampi(quality_tier, 1, 3):
		3:
			return "Premium"
		2:
			return "Commercial"
		_:
			return "Basic"
