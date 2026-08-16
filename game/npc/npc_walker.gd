class_name NpcWalker
extends CharacterBody3D
## Movement shared by every walking NPC.
##
## Owns only "follow this path, at this speed, and face where you are going".
## Deciding *where* to go belongs to the subclass — that split is what lets a
## civilian and a police officer share one movement implementation and later
## lets a shopkeeper or a commuter reuse it without touching this file.
##
## NPCs collide with the world and kerbs but not with each other, with vehicles,
## or with the player. Crowds that shove each other into buildings look far
## worse than crowds that overlap, and a jammed pedestrian is a bug the player
## can see.

signal path_finished()

## World + kerb. Deliberately excludes NPCs, vehicles and the player.
const COLLISION_MASK := (1 << 0) | (1 << 5)
## How close counts as having reached a path node.
const ARRIVE_DISTANCE := 0.9

@export var walk_speed: float = 2.4
@export var run_speed: float = 5.4
@export var acceleration: float = 14.0
@export var turn_speed: float = 9.0
## Re-path if the current path has not been advanced for this long, which is the
## symptom of being wedged against something.
@export var stuck_timeout: float = 2.5
## Targets within this range are walked to directly when the graph would take
## the NPC the long way round. Without it, chasing a player who is standing off
## the pavement network sends an officer to the nearest pavement node — which
## can be in the opposite direction.
@export var direct_walk_limit: float = 30.0

@export_group("Appearance")
@export var body_color: Color = Color(0.478, 0.494, 0.541)
@export var accent_color: Color = Color(0.290, 0.310, 0.361)
@export var body_height: float = 1.75
@export var body_radius: float = 0.36

@onready var body_pivot: Node3D = $BodyPivot

var nav: NavGraph = null

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _speed: float = 0.0
var _running: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _stuck_time: float = 0.0
var _last_progress_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	collision_layer = 1 << 4
	collision_mask = COLLISION_MASK
	nav = get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	_last_progress_position = global_position
	_build_body()


## Placeholder figure: a capsule with a shoulder block that shows which way it
## is facing, which is the only thing the witness cone and the player need to
## read from above. Built from exports so a civilian and an officer differ by
## two colours rather than two scenes.
func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = body_radius
	shape.height = body_height
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	collider.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(collider)

	var torso := CityKit.make_material(body_color, 0.8)
	var accent := CityKit.make_material(accent_color, 0.7)

	var mesh := MeshInstance3D.new()
	mesh.name = "Torso"
	var capsule := CapsuleMesh.new()
	capsule.radius = body_radius
	capsule.height = body_height
	mesh.mesh = capsule
	mesh.material_override = torso
	mesh.position = Vector3(0.0, body_height * 0.5, 0.0)
	body_pivot.add_child(mesh)

	CityKit.add_box(
		body_pivot,
		"Facing",
		Vector3(0.0, body_height * 0.74, body_radius * 0.85),
		Vector3(body_radius * 0.9, 0.16, 0.18),
		accent,
		false,
		false
	)


func has_path() -> bool:
	return _path_index < _path.size()


func is_running() -> bool:
	return _running


func set_running(running: bool) -> void:
	_running = running


func stop() -> void:
	_path = PackedVector3Array()
	_path_index = 0
	velocity = Vector3.ZERO


## Routes to `destination` across the given graph layer. Returns false when no
## route exists, so callers can pick somewhere else rather than stand still.
func walk_to(destination: Vector3, layer: NavGraph.Layer = NavGraph.Layer.WALK) -> bool:
	if nav == null:
		return false
	var direct := global_position.distance_to(destination)
	var route := nav.find_path(layer, global_position, destination)

	if route.size() < 2:
		# No route on the graph. Close targets are still worth walking at.
		if direct > direct_walk_limit:
			return false
		route = PackedVector3Array([global_position, destination])
	else:
		# The graph only gets us to the nearest node; finish the last stretch on
		# foot so off-pavement destinations are actually reached.
		if route[route.size() - 1].distance_to(destination) > 1.0:
			route.append(destination)
		# If the first hop is further away than the destination itself, the
		# graph is sending us backwards. Go straight there instead.
		if direct <= direct_walk_limit and global_position.distance_to(route[1]) > direct:
			route = PackedVector3Array([global_position, destination])

	_path = route
	# Skip the first node: it is the one we are already standing on.
	_path_index = 1
	_stuck_time = 0.0
	_last_progress_position = global_position
	return true


func current_target() -> Vector3:
	return _path[_path_index] if has_path() else global_position


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var desired := Vector3.ZERO
	if has_path():
		var target: Vector3 = _path[_path_index]
		var to_target := target - global_position
		to_target.y = 0.0
		if to_target.length() <= ARRIVE_DISTANCE:
			_advance_path()
		else:
			desired = to_target.normalized()

	var target_speed := (run_speed if _running else walk_speed) if desired != Vector3.ZERO else 0.0
	_speed = move_toward(_speed, target_speed, acceleration * delta)

	var planar := desired * _speed
	velocity.x = planar.x
	velocity.z = planar.z

	_face(planar, delta)
	move_and_slide()
	_check_stuck(delta)


func _advance_path() -> void:
	_path_index += 1
	_stuck_time = 0.0
	_last_progress_position = global_position
	if not has_path():
		path_finished.emit()


func _face(planar_velocity: Vector3, delta: float) -> void:
	if planar_velocity.length_squared() < 0.04:
		return
	var target_yaw := atan2(planar_velocity.x, planar_velocity.z)
	body_pivot.rotation.y = lerp_angle(body_pivot.rotation.y, target_yaw, turn_speed * delta)


## Direction the NPC is facing, which is what the witness cone is measured
## against. The body pivot faces +Z at zero rotation, matching the player.
func get_facing() -> Vector3:
	var yaw := body_pivot.rotation.y
	return Vector3(sin(yaw), 0.0, cos(yaw))


## Wedged NPCs drop their path so the subclass can pick a new destination,
## rather than grinding against a wall forever.
func _check_stuck(delta: float) -> void:
	if not has_path():
		_stuck_time = 0.0
		return
	if global_position.distance_to(_last_progress_position) > 0.5:
		_last_progress_position = global_position
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time < stuck_timeout:
		return
	_stuck_time = 0.0
	stop()
	path_finished.emit()
