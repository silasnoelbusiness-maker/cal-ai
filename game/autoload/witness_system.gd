extends Node
## Decides whether anyone actually saw a crime.
##
## This is what stops the police being omniscient. CrimeManager records every
## crime; only the ones this file finds a witness for are ever reported, and
## only reported crimes raise the wanted level. Stealing a car on an empty
## street is genuinely free, which is the mechanic the whole crime loop hangs
## on.
##
## Checks run cheapest-first — radius, then facing, then a raycast — so the
## expensive part only happens for the handful of NPCs who could plausibly have
## seen anything.

signal crime_witnessed(record: Dictionary, witness: Node3D)
signal crime_unseen(record: Dictionary)

@export_group("Civilians")
@export var witness_detection_radius: float = 24.0
## Full width of the vision cone, in degrees.
@export var witness_view_angle: float = 130.0
## Seconds a civilian takes to react and call it in.
@export var report_delay: float = 2.6

@export_group("Police")
## Officers notice more, from further away, and report instantly.
@export var police_detection_radius: float = 34.0
@export var police_view_angle: float = 200.0

@export_group("Debug")
## Prints why each candidate did or did not see a crime.
@export var log_checks: bool = false

## Eye height used for both ends of the line-of-sight ray.
const EYE_HEIGHT := 1.5
## Only the world layer blocks sight. Kerbs, vehicles and NPCs do not.
const SIGHT_MASK := 1 << 0


func _ready() -> void:
	CrimeManager.crime_reported.connect(_on_crime_recorded)


## Shared perception test, used here and by every police unit, so witnesses and
## pursuers agree on what "can see" means.
func can_see(
	observer: Node3D, target_position: Vector3, radius: float, view_angle_degrees: float
) -> bool:
	if observer == null or not is_instance_valid(observer):
		return false

	var to_target := target_position - observer.global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > radius:
		return false

	# Standing on top of something counts as seeing it; the cone check is
	# meaningless at zero distance.
	if distance > 1.0 and view_angle_degrees < 359.0:
		var facing := _facing_of(observer)
		if rad_to_deg(facing.angle_to(to_target / distance)) > view_angle_degrees * 0.5:
			return false

	var space := observer.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		observer.global_position + Vector3.UP * EYE_HEIGHT,
		target_position + Vector3.UP * (EYE_HEIGHT * 0.6)
	)
	query.collision_mask = SIGHT_MASK
	return space.intersect_ray(query).is_empty()


# --- Crime handling ------------------------------------------------------

func _on_crime_recorded(record: Dictionary) -> void:
	var position: Vector3 = record.get("position", Vector3.ZERO)
	var perpetrator = record.get("perpetrator")

	# Police first: an officer who sees it needs no phone call.
	var officer := _find_police_witness(position, perpetrator)
	if officer != null:
		CrimeManager.mark_witnessed(record, officer)
		crime_witnessed.emit(record, officer)
		_report(record)
		return

	var civilian := _find_civilian_witness(position, perpetrator)
	if civilian == null:
		crime_unseen.emit(record)
		if log_checks:
			print("[witness] nobody saw crime #%d" % record.get("id", -1))
		return

	CrimeManager.mark_witnessed(record, civilian)
	crime_witnessed.emit(record, civilian)
	civilian.witness_crime(position)

	# Civilians take a moment to react before calling it in, which is the
	# window the player has to get out of sight.
	await get_tree().create_timer(report_delay).timeout
	_report(record)


## Files a crime as seen by one named person, with no perception test.
##
## For the cases where witnessing is part of the act rather than something that
## might or might not have happened: the driver of a carjacked car does not need
## a line of sight to know they have just been pulled out of it. Everything after
## that — the delay, the call, the wanted level — is the ordinary path, so these
## crimes behave like any other from here on.
func witness_directly(record: Dictionary, witness: Node3D, delay: float = -1.0) -> void:
	if record.is_empty():
		return
	CrimeManager.mark_witnessed(record, witness)
	crime_witnessed.emit(record, witness)

	var wait := report_delay if delay < 0.0 else delay
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	_report(record)


func _report(record: Dictionary) -> void:
	if record.get("reported", false):
		return
	CrimeManager.mark_reported(record)
	WantedManager.on_crime_reported(record)


func _find_police_witness(position: Vector3, perpetrator: Variant) -> Node3D:
	for unit in get_tree().get_nodes_in_group(&"police"):
		if unit == perpetrator or not (unit is Node3D):
			continue
		if unit.has_method("is_on_duty") and not unit.call("is_on_duty"):
			continue
		if can_see(unit, position, police_detection_radius, police_view_angle):
			if log_checks:
				print("[witness] officer %s saw it" % unit.name)
			return unit
	return null


func _find_civilian_witness(position: Vector3, perpetrator: Variant) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for civilian in get_tree().get_nodes_in_group(&"pedestrian"):
		if civilian == perpetrator or not (civilian is Node3D):
			continue
		# Somebody already fleeing or staring at another crime is not a fresh
		# pair of eyes.
		if civilian.has_method("is_available_as_witness") and not civilian.call(
			"is_available_as_witness"
		):
			continue
		var distance: float = civilian.global_position.distance_to(position)
		if distance >= best_distance:
			continue
		if can_see(civilian, position, witness_detection_radius, witness_view_angle):
			best = civilian
			best_distance = distance
	if log_checks and best != null:
		print("[witness] civilian %s saw it from %.1fm" % [best.name, best_distance])
	return best


## Facing for the cone test. NpcWalker aims its body pivot at +Z; anything else
## falls back to the node's own forward axis.
func _facing_of(observer: Node3D) -> Vector3:
	if observer.has_method("get_facing"):
		return observer.call("get_facing")
	var forward := -observer.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
