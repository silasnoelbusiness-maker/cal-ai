class_name StoreZone
extends Area3D
## The inside of a shop, for the purpose of noticing theft.
##
## Walking out with goods you have not paid for is the moment shoplifting
## happens — not picking them up. This watches the doorway so the crime is filed
## exactly then, which is what gives the player a window to put something back or
## take it to the till.
##
## Filing it here rather than in the shelf also means one zone covers any number
## of shelves, and the same component works for a shop with a back room, a diner
## or anything else with an inside and an outside.

signal player_entered()
signal player_left_with_goods(count: int)

@export var store_name: String = "Shop"
## The counter this belongs to, so a robbery in progress can be abandoned by
## walking out.
@export var shop_path: NodePath


func _ready() -> void:
	add_to_group(&"store_zone")
	collision_layer = 0
	collision_mask = 1 << 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body != GameManager.player:
		return
	player_entered.emit()


func _on_body_exited(body: Node3D) -> void:
	if body != GameManager.player:
		return

	var shop := get_node_or_null(shop_path) as Shop
	if shop != null and shop.is_being_robbed():
		shop.abandon_robbery()

	var stolen := _stolen_carried(body)
	if stolen <= 0:
		return

	CrimeManager.report_crime(
		CrimeManager.CrimeType.SHOPLIFTING,
		global_position,
		body,
		shop,
		false,
		{"quantity": stolen, "store_name": store_name}
	)
	player_left_with_goods.emit(stolen)


func _stolen_carried(body: Node3D) -> int:
	if not body.has_method("get_inventory"):
		return 0
	var inventory = body.call("get_inventory")
	if inventory == null or not inventory.has_method("stolen_count"):
		return 0
	return int(inventory.call("stolen_count"))
