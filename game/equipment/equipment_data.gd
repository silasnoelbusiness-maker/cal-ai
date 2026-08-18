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
enum Role { SHELF, CHECKOUT, STORAGE, FITTING, BREW }

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
	return role == Role.BREW
