extends Node

## Police blocking a road at four and five stars.
##
## §44 allows roadblocks only at the top two levels, and §183 sets the design
## rule: a roadblock should create a decision, not an unavoidable capture. So
## these never seal the city. They sit on a chosen road node, they leave the
## junctions either side of them open, and there is always another way round —
## which is the point. A player who turns off Main Street because there are two
## cars across it has made a choice, and that is the whole feature.
##
## §45 lists what a placement must not do: appear inside a junction, overlap a
## building, or pop into existence in front of the player. Each is checked
## before a block is committed, and a node that fails any of them is skipped
## rather than fixed up.
##
## Nothing here is permanent. §47 and §161: blocks expire on their own, and
## clearing the wanted level takes every one of them down.

signal roadblock_placed(position: Vector3)
signal roadblock_cleared(position: Vector3)

## Wanted level from which the shift may block roads at all.
const MIN_LEVEL := 4
## How many may stand at once, per wanted level. Small on purpose: §183 again,
## and §180 — a dozen blocks is a performance problem as well as a cage.
const MAX_BLOCKS_BY_LEVEL: Array[int] = [0, 0, 0, 0, 2, 3]
## Never nearer the player than this, so nothing materialises in front of them.
const MIN_DISTANCE_FROM_PLAYER := 85.0
## And never further than this, or it is blocking a road nobody is near.
const MAX_DISTANCE_FROM_PLAYER := 260.0
## Two blocks this close together are one block with extra cars.
const MIN_SEPARATION := 70.0
## Junction nodes have several ways out; a block belongs on a stretch of road.
const MAX_SUCCESSORS_FOR_BLOCK := 1
## Seconds a block stands before it is stood down.
const LIFETIME := 55.0
## How often placement is reconsidered.
const REVIEW_INTERVAL := 2.5

var save_id: StringName = &"roadblocks"
var reset_on_missing_save: bool = true

## Statistics. §144.
var roadblocks_encountered: int = 0

var _blocks: Array[Dictionary] = []
var _review_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"saveable")
	_rng.randomize()


func _process(delta: float) -> void:
	if GameManager.is_paused():
		return
	_expire(delta)
	_review_timer -= delta
	if _review_timer > 0.0:
		return
	_review_timer = REVIEW_INTERVAL
	_review()


func count() -> int:
	return _blocks.size()


func positions() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for block in _blocks:
		found.append(block["position"])
	return found


## Whether the shift is allowed to block roads right now.
func allowed() -> bool:
	if WantedManager.level < MIN_LEVEL:
		return false
	if not PoliceResponseManager.profile().roadblocks:
		return false
	return PoliceResponseManager.is_active()


func budget() -> int:
	var level := WantedManager.level
	if level < 0 or level >= MAX_BLOCKS_BY_LEVEL.size():
		return 0
	return int(MAX_BLOCKS_BY_LEVEL[level])


## Takes every block down. Called when the wanted level clears and on arrest.
func clear() -> void:
	for block in _blocks.duplicate():
		_remove(block)
	_blocks.clear()


# --- Placement -----------------------------------------------------------

func _review() -> void:
	if not allowed():
		if not _blocks.is_empty():
			clear()
		return
	while _blocks.size() < budget():
		if not _place_one():
			return


## Puts one block on a validated node, or returns false if the city has nowhere
## sensible for it. Failing is a perfectly good answer: §183 would rather have
## no block than a bad one.
func _place_one() -> bool:
	var network := _network()
	var player := GameManager.player
	if network == null or not network.is_ready() or player == null:
		return false
	var node := _pick_node(network, player.global_position)
	if node < 0:
		return false

	var position := network.node_position(node)
	var direction := network.node_direction(node)
	var holder := Node3D.new()
	holder.name = "Roadblock_%d" % node
	# Vehicles face -Z, and a block sits across the lane rather than along it.
	holder.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)
	var world := get_tree().current_scene
	if world == null:
		return false
	world.add_child(holder)
	holder.global_position = position
	_dress(holder, direction)

	_blocks.append({
		"node": node,
		"position": position,
		"holder": holder,
		"age": 0.0,
	})
	roadblocks_encountered += 1
	roadblock_placed.emit(position)
	GameManager.notify("ROADBLOCK AHEAD", GameManager.Tone.BAD)
	AudioManager.play(&"alert", AudioBuses.SFX, -8.0)
	return true


## Finds a road node worth blocking. §45 in full: on a real stretch of road,
## not in a junction, not on top of another block, far enough from the player
## to be a decision rather than a wall, and clear of the buildings either side.
func _pick_node(network: RoadNetwork, player_at: Vector3) -> int:
	var best := -1
	var best_score := -INF
	for attempt in 40:
		var node := network.random_node(_rng)
		if node < 0:
			continue
		var position := network.node_position(node)
		var distance := position.distance_to(player_at)
		if distance < MIN_DISTANCE_FROM_PLAYER or distance > MAX_DISTANCE_FROM_PLAYER:
			continue
		# A junction has several ways out of it. Blocking one is both unfair
		# and visually wrong — the cars end up across the box.
		if network.successors(node).size() > MAX_SUCCESSORS_FOR_BLOCK:
			continue
		if _too_close_to_existing(position):
			continue
		if _obstructed(position):
			continue
		# Prefer blocks between the player and where they seem to be going, so
		# the shift looks like it is thinking rather than sprinkling cars.
		var score := -distance
		var heading := PoliceMemory.last_known_heading
		if heading != Vector3.ZERO:
			var to_block := (position - player_at).normalized()
			score += to_block.dot(heading) * 120.0
		if score > best_score:
			best_score = score
			best = node
	return best


func _too_close_to_existing(position: Vector3) -> bool:
	for block in _blocks:
		if position.distance_to(block["position"]) < MIN_SEPARATION:
			return true
	return false


## A quick look for anything solid where the barrier would stand. Cheap on
## purpose: a sphere cast against the world layer, not a survey.
func _obstructed(position: Vector3) -> bool:
	var space := get_tree().root.world_3d.direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 3.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3(0.0, 1.0, 0.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	return not space.intersect_shape(query, 1).is_empty()


## Two cars nose to tail across the lane and a line of cones. Stylised, as §46
## asks — the block reads instantly from above and costs almost nothing.
func _dress(holder: Node3D, direction: Vector3) -> void:
	var across := Vector3(-direction.z, 0.0, direction.x).normalized()
	var body := CityKit.make_material(Color(0.851, 0.867, 0.898))
	var stripe := CityKit.make_emissive_material(Color(0.243, 0.416, 0.769), 1.4)
	var cone := CityKit.make_emissive_material(Color(0.949, 0.502, 0.196), 0.8)

	for side: float in [-1.0, 1.0]:
		var at: Vector3 = across * (side * 2.4)
		CityKit.add_box(
			holder, "Car%d" % int(side), at + Vector3(0.0, 0.7, 0.0),
			Vector3(4.2, 1.3, 1.9), body, true
		)
		CityKit.add_box(
			holder, "Bar%d" % int(side), at + Vector3(0.0, 1.5, 0.0),
			Vector3(1.4, 0.22, 0.5), stripe, false, false
		)
	for i in 5:
		CityKit.add_box(
			holder, "Cone%d" % i,
			across * (float(i) * 1.6 - 3.2) + direction * 3.0 + Vector3(0.0, 0.35, 0.0),
			Vector3(0.36, 0.7, 0.36), cone, false, false
		)


# --- Lifecycle -----------------------------------------------------------

func _expire(delta: float) -> void:
	for block in _blocks.duplicate():
		block["age"] = float(block["age"]) + delta
		if float(block["age"]) < LIFETIME:
			continue
		_remove(block)


func _remove(block: Dictionary) -> void:
	var holder: Node3D = block.get("holder")
	if holder != null and is_instance_valid(holder):
		holder.queue_free()
	_blocks.erase(block)
	roadblock_cleared.emit(block.get("position", Vector3.ZERO))


func _network() -> RoadNetwork:
	return get_tree().get_first_node_in_group(&"road_network") as RoadNetwork


func save_state() -> Dictionary:
	# The blocks themselves are not saved: they are police response, and §120
	# is explicit that temporary units need not persist perfectly. What is
	# saved is the tally, which is a statistic rather than a thing in the world.
	return {"encountered": roadblocks_encountered}


func load_state(state: Dictionary) -> void:
	clear()
	roadblocks_encountered = int(state.get("encountered", 0))
