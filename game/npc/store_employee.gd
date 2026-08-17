class_name StoreEmployee
extends Pedestrian
## Somebody behind a counter.
##
## A pedestrian in every respect except that they have a post to stand at, so
## they inherit the witness cone, the fear state, health and the knockdown for
## free. That is the whole reason shop staff are not their own NPC type: a
## cashier who gets run over should behave exactly like anyone else who does.

## Where they stand, and which way they face, in world space. Filled in by
## whoever builds the shop.
@export var post_position: Vector3 = Vector3.ZERO
@export var post_facing: Vector3 = Vector3.FORWARD
## How far they may drift before walking back.
@export var post_tolerance: float = 1.4


func _ready() -> void:
	super()
	wanders = false
	add_to_group(&"store_employee")
	if post_position == Vector3.ZERO:
		post_position = global_position
	_face_post()


## Frightened staff still return to the till once the fright passes, rather than
## fleeing the building and leaving the shop unstaffed forever.
func _on_path_finished() -> void:
	super()
	_face_post()


func _process(delta: float) -> void:
	super(delta)
	if is_down() or is_incapacitated() or is_afraid():
		return
	if state == State.IDLE and global_position.distance_to(post_position) > post_tolerance:
		walk_to(post_position)


func _face_post() -> void:
	var flat := Vector3(post_facing.x, 0.0, post_facing.z)
	if flat.length_squared() > 0.01:
		body_pivot.rotation.y = atan2(flat.x, flat.z)
