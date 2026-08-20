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
## Clothing colour. Kept as the export it always was so everything that dressed
## a walker before still does — it is now the colour of the figure's top rather
## than of a capsule.
@export var body_color: Color = Color(0.478, 0.494, 0.541)
@export var accent_color: Color = Color(0.290, 0.310, 0.361)
@export var body_height: float = 1.75
@export var body_radius: float = 0.36
## Which kind of person this is. Decides the uniform, and nothing else — an
## officer and a shopper are the same figure in different clothes.
@export var look_category: CharacterLook.Category = CharacterLook.Category.CIVILIAN
## Crowd members do not cast shadows; the figures the eye follows do.
@export var casts_shadow: bool = false
## Seeds the look, so a given walker is the same person every run. Left at zero
## it is seeded from the node name.
@export var appearance_seed: int = 0

## The figure's joints, for anything that wants to hang something off a hand or
## read where the head is.
var rig: CharacterKit.Rig = null
var character_look: CharacterLook = null

var _animator: CharacterAnimator = null

## The turnable part of the figure. Comes from the scene for NPCs that have one,
## and is built here for the ones created in code — a shop's cashier, or the
## driver pulled out of a carjacked car.
var body_pivot: Node3D = null

var nav: NavGraph = null

var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _speed: float = 0.0
var _running: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _stuck_time: float = 0.0
var _last_progress_position: Vector3 = Vector3.ZERO
var _pending_shove: Vector3 = Vector3.ZERO


func _ready() -> void:
	collision_layer = 1 << 4
	collision_mask = COLLISION_MASK
	nav = get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	_last_progress_position = global_position

	body_pivot = get_node_or_null("BodyPivot")
	if body_pivot == null:
		body_pivot = Node3D.new()
		body_pivot.name = "BodyPivot"
		add_child(body_pivot)

	_build_body()


## A stylized humanoid, built from the walker's own colours.
##
## The collision is still a capsule — a person-shaped collider would catch on
## kerbs and doorframes for no gain — so what changed is only what you see.
func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = body_radius
	shape.height = body_height
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	collider.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(collider)

	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_seed if appearance_seed != 0 else hash(name)
	character_look = CharacterLook.random(rng, look_category)
	# Height varies around the exported figure height rather than being set to
	# it: a crowd where everybody is exactly 1.75m reads as clones, and the
	# collision capsule is unchanged either way, so nothing about how they walk
	# or what they bump into moves with it.
	character_look.height = body_height * rng.randf_range(0.93, 1.07)
	# The exported colours win, so every caller that dressed a walker before
	# still decides what it wears.
	character_look.top = body_color
	character_look.accent = accent_color
	if look_category == CharacterLook.Category.POLICE:
		character_look.accent = Color(0.914, 0.792, 0.290)

	rig = CharacterKit.build(body_pivot, character_look, casts_shadow)
	CharacterKit.add_uniform(rig, character_look)

	_animator = CharacterAnimator.new()
	_animator.name = "Animator"
	add_child(_animator)
	_animator.setup(rig)
	_attach_footsteps()


## Re-dresses a figure that is already in the tree.
##
## Needed because some NPCs learn what they are only after they are added — a
## shop's staff are created and then told which role they are working. Rebuilds
## rather than tinting: a change of role can change the uniform, not just the
## colour.
func restyle(top: Color, accent: Color, category: CharacterLook.Category) -> void:
	body_color = top
	accent_color = accent
	look_category = category
	if body_pivot == null:
		return
	for child in body_pivot.get_children():
		child.queue_free()
	if _animator != null:
		_animator.queue_free()
		_animator = null

	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_seed if appearance_seed != 0 else hash(name)
	character_look = CharacterLook.random(rng, category)
	character_look.height = body_height * rng.randf_range(0.93, 1.07)
	character_look.top = top
	character_look.accent = accent
	rig = CharacterKit.build(body_pivot, character_look, casts_shadow)
	CharacterKit.add_uniform(rig, character_look)
	_animator = CharacterAnimator.new()
	_animator.name = "Animator"
	add_child(_animator)
	_animator.setup(rig)
	_attach_footsteps()


## Footsteps for a walker, replacing any previous set. Nearby civilians are
## audible; the distance test and the shared voice limit live in Footsteps
## itself, so a crowd of forty does not become forty sources.
func _attach_footsteps() -> void:
	var existing := get_node_or_null("Footsteps")
	if existing != null:
		existing.queue_free()
	var steps := Footsteps.new()
	steps.name = "Footsteps"
	add_child(steps)
	steps.setup(self, _animator)


## The animator, for anything that needs to read the stride.
func get_animator() -> CharacterAnimator:
	return _animator


## What the figure should be doing. Overridden by anything with a better idea —
## a cashier at a till, an officer in a pursuit.
func animation_state() -> CharacterAnimator.State:
	if _speed > run_speed * 0.7:
		return CharacterAnimator.State.RUN
	if _speed > 0.35:
		return CharacterAnimator.State.WALK
	return CharacterAnimator.State.IDLE


## Forces a pose that movement alone cannot express.
func set_pose(state: CharacterAnimator.State) -> void:
	if _animator != null:
		_animator.set_state(state)


func _refresh_animation() -> void:
	if _animator == null:
		return
	_animator.set_speed(_speed)
	_animator.set_state(animation_state())


func has_path() -> bool:
	return _path_index < _path.size()


## The route still to be walked, for the world debug view. Everything before the
## current index has already been covered and is not worth drawing.
func debug_path() -> PackedVector3Array:
	if not has_path():
		return PackedVector3Array()
	return _path.slice(maxi(_path_index - 1, 0))


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
	_refresh_animation()
	move_and_slide()
	if _pending_shove != Vector3.ZERO:
		move_and_collide(_pending_shove)
		_pending_shove = Vector3.ZERO
	_check_stuck(delta)


## Knocks this NPC back by `distance` metres. Applied on the next physics frame
## rather than immediately: whoever threw the punch is not in the physics step,
## and a kinematic body moved from outside it slides through walls.
func shove(direction: Vector3, distance: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if distance <= 0.0 or flat.length_squared() < 0.0001:
		return
	_pending_shove = flat.normalized() * distance


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
