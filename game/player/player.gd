class_name Player
extends CharacterBody3D
## On-foot player controller.
##
## Movement is camera-relative so it stays intuitive while the top-down camera
## is orbited. Acceleration and deceleration are separate so the character
## eases into a run but stops crisply. The controller owns movement only —
## interacting is delegated to the InteractionController child, and needs are
## owned by PlayerStats.

signal move_state_changed(state: MoveState)
## Emitted with the vehicle on getting in, and with null on getting out.
signal vehicle_changed(vehicle: Node3D)

enum MoveState { IDLE, WALK, RUN }

@export_group("Movement")
@export var walk_speed: float = 4.2
@export var sprint_speed: float = 7.8
## Units per second squared while input is held.
@export var acceleration: float = 30.0
## Units per second squared while input is released.
@export var deceleration: float = 38.0
## Fraction of ground control retained while airborne.
@export var air_control: float = 0.3
## Radians per second the body turns toward its heading.
@export var turn_speed: float = 12.0

@export_group("Sprint")
## Sprinting stops below this much energy.
@export var min_energy_to_sprint: float = 2.0

## Stable id for the save file.
@export var save_id: StringName = &"player"

@onready var stats: PlayerStats = $Stats
@onready var inventory: Inventory = $Inventory
@onready var interaction: InteractionController = $InteractionController
@onready var combat: CombatController = $Combat
@onready var _body_pivot: Node3D = $BodyPivot
@onready var _collision: CollisionShape3D = $Collision

var _move_state: MoveState = MoveState.IDLE
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _is_sprinting: bool = false
## The vehicle being driven, or null when on foot.
var _vehicle: Node3D = null

## The player's figure and the joints that move it. Built rather than authored
## in the scene so the player is the same drawing as everybody else in the city.
var rig: CharacterKit.Rig = null
var character_look: CharacterLook = null

var _animator: CharacterAnimator = null


func _ready() -> void:
	add_to_group(&"saveable")
	GameManager.register_player(self)
	_build_figure()


## Replaces whatever placeholder the scene shipped with a proper humanoid. The
## collider is untouched — it is still the capsule every system was tuned
## against, and a person-shaped one would only snag on kerbs.
func _build_figure() -> void:
	for child in _body_pivot.get_children():
		child.queue_free()
	character_look = CharacterLook.player_default()
	rig = CharacterKit.build(_body_pivot, character_look, true)
	_animator = CharacterAnimator.new()
	_animator.name = "Animator"
	add_child(_animator)
	_animator.setup(rig)

	# The player's own feet: always audible, and never counted against the
	# crowd's shared footstep budget.
	var steps := Footsteps.new()
	steps.name = "Footsteps"
	steps.is_player = true
	add_child(steps)
	steps.setup(self, _animator)


## Puts the player into a pose their movement cannot express — behind a till,
## carrying stock. Cleared by passing IDLE.
func set_pose(state: CharacterAnimator.State) -> void:
	if _animator != null:
		_animator.set_state(state)
		_pose_override = state


var _pose_override: int = -1


func clear_pose() -> void:
	_pose_override = -1


func _refresh_animation() -> void:
	if _animator == null:
		return
	var speed := get_planar_speed()
	_animator.set_speed(speed)
	if _pose_override >= 0:
		return
	if _vehicle != null:
		_animator.set_state(CharacterAnimator.State.IDLE)
	elif speed > sprint_speed * 0.72:
		_animator.set_state(CharacterAnimator.State.RUN)
	elif speed > 0.35:
		_animator.set_state(CharacterAnimator.State.WALK)
	else:
		_animator.set_state(CharacterAnimator.State.IDLE)


func _exit_tree() -> void:
	GameManager.unregister_player(self)


func get_stats() -> PlayerStats:
	return stats


func get_inventory() -> Inventory:
	return inventory


func get_combat() -> CombatController:
	return combat


## Called by ItemData when an equippable item is used from the bag. Forwarded
## rather than handled here: what holding something *does* belongs to combat.
func equip_item(item: ItemData) -> bool:
	return combat.equip_item(item)


func get_equipped_item() -> ItemData:
	return combat.get_equipped_item()


func get_vehicle() -> Node3D:
	return _vehicle


func is_driving() -> bool:
	return _vehicle != null


## Called by the vehicle, not by the player. The character stays in the tree so
## its position, stats and inventory keep working; it just stops driving itself
## around and stops colliding with the world it is being carried through.
func enter_vehicle(vehicle: Node3D) -> void:
	if _vehicle == vehicle:
		return
	_vehicle = vehicle
	velocity = Vector3.ZERO
	_is_sprinting = false
	set_physics_process(false)
	_body_pivot.visible = false
	_collision.set_deferred("disabled", true)
	# On-foot prompts must not fire from the driver's seat.
	interaction.set_active(false)
	_update_move_state(0.0)
	vehicle_changed.emit(vehicle)


## Called by the vehicle when stepping out. `at` is the already-validated spot
## beside the car.
func exit_vehicle(at: Transform3D) -> void:
	if _vehicle == null:
		return
	_vehicle = null
	global_position = at.origin
	_body_pivot.rotation.y = at.basis.get_euler().y
	velocity = Vector3.ZERO
	_collision.set_deferred("disabled", false)
	_body_pivot.visible = true
	set_physics_process(true)
	interaction.set_active(true)
	vehicle_changed.emit(null)


func get_move_state() -> MoveState:
	return _move_state


func is_sprinting() -> bool:
	return _is_sprinting


## Horizontal speed in units/second. The camera reads this to widen the view
## as the player speeds up; vehicles expose the same method later.
func get_planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Which way the figure is turned. The node itself never rotates — only the body
## pivot does — so anything that needs the player's heading has to ask for it
## rather than read the transform. The camera's look-ahead does.
func get_facing() -> Vector3:
	var yaw := _body_pivot.rotation.y
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var input_dir := _get_camera_relative_input()
	_update_sprint(input_dir, delta)

	var target_speed := sprint_speed if _is_sprinting else walk_speed
	var target_velocity := input_dir * target_speed

	var rate := acceleration if input_dir.length_squared() > 0.0 else deceleration
	if not is_on_floor():
		rate *= air_control

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	planar = planar.move_toward(target_velocity, rate * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	_face_movement(planar, delta)
	move_and_slide()
	_update_move_state(planar.length())


## Maps WASD onto the ground plane using the active camera's yaw, so "forward"
## always means "away from the camera" no matter how the rig is orbited.
func _get_camera_relative_input() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO

	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var basis := camera.global_transform.basis
		forward = -Vector3(basis.z.x, 0.0, basis.z.z)
		right = Vector3(basis.x.x, 0.0, basis.x.z)
		if forward.length_squared() < 0.001:
			# Camera pointing almost straight down; fall back to world axes.
			forward = Vector3.FORWARD
			right = Vector3.RIGHT
		forward = forward.normalized()
		right = right.normalized()

	return (right * input.x + forward * -input.y).limit_length(1.0)


func _update_sprint(input_dir: Vector3, delta: float) -> void:
	var wants_sprint := Input.is_action_pressed("sprint") and input_dir.length_squared() > 0.01
	_is_sprinting = wants_sprint and stats.has_energy_to_sprint(min_energy_to_sprint)

	if _is_sprinting:
		stats.drain_sprint_energy(delta)
	elif input_dir.length_squared() < 0.01:
		stats.recover_idle_energy(delta)


func _face_movement(planar_velocity: Vector3, delta: float) -> void:
	if planar_velocity.length_squared() < 0.05:
		return
	var target_yaw := atan2(planar_velocity.x, planar_velocity.z)
	_body_pivot.rotation.y = lerp_angle(_body_pivot.rotation.y, target_yaw, turn_speed * delta)
	_refresh_animation()


func _update_move_state(speed: float) -> void:
	var new_state := MoveState.IDLE
	if speed > walk_speed + 0.5:
		new_state = MoveState.RUN
	elif speed > 0.2:
		new_state = MoveState.WALK

	if new_state == _move_state:
		return
	_move_state = new_state
	move_state_changed.emit(_move_state)


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var slots: Array = []
	for slot in inventory.get_slots():
		if slot.is_empty():
			continue
		slots.append({
			"id": String(slot.item.id),
			"quantity": slot.quantity,
			"stolen": slot.stolen,
		})

	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"facing": _body_pivot.rotation.y,
		"health": stats.health,
		"energy": stats.energy,
		"hunger": stats.hunger,
		"inventory": slots,
		"equipped": String(combat.get_equipped_item().id) if combat.get_equipped_item() != null else "",
	}


func load_state(state: Dictionary) -> void:
	var raw: Array = state.get("position", [])
	if raw.size() == 3:
		# Routed through GameManager so the camera cuts instead of flying, and
		# the HUD covers the jump — the same path doorways use.
		GameManager.teleport_player(
			Transform3D(global_transform.basis, Vector3(raw[0], raw[1], raw[2]))
		)
	_body_pivot.rotation.y = float(state.get("facing", _body_pivot.rotation.y))

	stats.restore_values(
		float(state.get("health", stats.health)),
		float(state.get("energy", stats.energy)),
		float(state.get("hunger", stats.hunger))
	)

	inventory.clear()
	for entry in state.get("inventory", []):
		var item := ItemCatalogue.by_id(StringName(entry.get("id", "")))
		# An item that no longer exists in the catalogue is dropped rather than
		# breaking the whole load.
		if item != null:
			var quantity := int(entry.get("quantity", 1))
			# A save written before provenance existed has no "stolen" key, and
			# the goods in it were all legitimately obtained.
			var stolen := clampi(int(entry.get("stolen", 0)), 0, quantity)
			if stolen > 0:
				inventory.add(item, stolen, true)
			if quantity - stolen > 0:
				inventory.add(item, quantity - stolen, false)

	# Absent from a save written before equipment existed, and empty-handed is
	# the right answer for one.
	combat.unequip_item()
	var held := ItemCatalogue.by_id(StringName(state.get("equipped", "")))
	if held != null:
		combat.equip_item(held)
