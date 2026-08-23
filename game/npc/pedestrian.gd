class_name Pedestrian
extends NpcWalker
## A civilian going about their day.
##
## Four states, no more than Phase E needs. The thinking happens on arrival and
## on a coarse timer rather than every frame, so the crowd stays cheap as it
## grows: a pedestrian with somewhere to go does nothing per frame except walk.
##
## Schedules, shopping, jobs and relationships all hang off `_choose_wander` and
## the state enum later; nothing else here has to change for them.

signal state_changed(state: State)
signal knocked_down(impact_speed: float)
signal recovered()

enum State { IDLE, WALKING, WITNESSING, FLEEING, DODGING, KNOCKED_DOWN, FEAR }
## Whether this civilian is still on their feet. Zero health leaves them down
## rather than dead — the prototype has no need for death, and an incapacitated
## body on the pavement tells the player the same thing.
enum Condition { ACTIVE, INCAPACITATED }

## How near a venue counts as being there. The walker stops short of a door by
## its own margin, so this is deliberately generous.
const ARRIVED_WITHIN := 4.5

@export_group("Routine")
## Whether this civilian has somewhere to be. Phase S: a pedestrian with a
## routine walks to wherever somebody of their archetype would be at this hour
## rather than to a random point on the pavement, which is the whole difference
## between a crowd and a city (§11).
##
## Off for anybody with a post — a cashier, a witness placed by a test — and for
## anybody spawned to be somewhere specific.
@export var follows_routine: bool = true
## Which district this person belongs to, for the archetype mix (§23, §26).
@export var routine_district: StringName = &"harbour_row"

@export_group("Wandering")
## Cleared for civilians with a post to stand at — a shop cashier is a
## pedestrian in every other respect, and this is the only difference.
@export var wanders: bool = true
@export var idle_time_range: Vector2 = Vector2(1.5, 5.0)
## Destinations closer than this are rejected, so nobody shuffles on the spot.
@export var min_wander_distance: float = 14.0
@export_group("Reactions")
## How long a witness stares before hurrying off.
@export var witness_seconds: float = 2.6
@export var flee_seconds: float = 9.0
@export var min_flee_distance: float = 35.0

@export_group("Activation")
## Beyond this from the player a civilian stops thinking and stops walking.
##
## This is the crowd's half of the near/far split the businesses already use:
## everyone in the district the player is in is fully simulated, and the district
## they are not in costs a distance check each every second. It is set wider than
## a district is across, so nobody freezes inside the part of the city that is on
## screen.
@export var active_distance: float = 140.0
## Seconds between activation checks. One distance test per civilian at this
## rate is nothing next to what being awake costs them.
@export var activation_interval: float = 0.25
## Whether this civilian is part of the ambient crowd, and so may be put to
## sleep when nobody is near.
##
## False for anybody with a job to do inside a building — a customer at a till,
## a member of staff on a shift. Those are exactly the people who must keep
## working while the player is on the other side of the city, which is the whole
## point of the businesses' own near/far simulation. Customers and staff both
## inherit this class, so without the exemption a shop more than `active_distance`
## away had its floor frozen the moment the player left the district.
@export var ambient_crowd: bool = true

@export_group("Traffic safety")
@export var max_health: float = 100.0
## Seconds between traffic scans. Coarse deliberately: a crowd of sixteen doing
## this every frame is the most expensive thing on the street, and a quarter of
## a second is still four chances to jump before a car covers ten metres.
@export var danger_check_interval: float = 0.25
## Only cars this close are considered.
@export var danger_radius: float = 15.0
## Half-width of the corridor in front of a car that counts as its path.
@export var danger_half_width: float = 2.4
## Below this speed a car is not worth jumping out of the way of.
@export var danger_min_speed: float = 3.5
## How far sideways a dodge aims for.
@export var dodge_distance: float = 4.5
@export var dodge_seconds: float = 1.6
## Impacts below this are a shove; above it the pedestrian goes down.
@export var knockdown_speed: float = 4.0
## Damage per m/s of impact above `knockdown_speed`.
@export var damage_per_impact_speed: float = 4.0
## How long they stay down, before a slower scramble back to their feet.
@export var down_seconds: Vector2 = Vector2(2.4, 4.0)
## Below this health they stop getting up.
@export var incapacitated_below: float = 1.0

@export_group("Crime reactions")
## Civilians get away from a wanted player from this far off, per wanted star. A
## street that carries on shopping around an active police chase is the single
## thing that most makes the crime systems feel like they are not connected to
## the city.
@export var wanted_fear_radius: float = 11.0

@export_group("Fear")
## How long a frightened civilian stays frightened before fleeing properly.
@export var fear_seconds: float = 4.0
## Roughly one civilian in this many fights back instead of running. Kept low:
## a street where everyone squares up is not the reaction the crime systems are
## trying to produce.
@export var defiance_chance: float = 0.12

var state: State = State.IDLE
var condition: Condition = Condition.ACTIVE
var health: float = 100.0
var _state_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _crime_position: Vector3 = Vector3.ZERO
var _danger_timer: float = 0.0
var _activation_timer: float = 0.0
var _active: bool = true
var _threat_position: Vector3 = Vector3.ZERO
## This person's day. Fetched once from RoutineManager and then kept, so they
## remain the same person rather than being reinvented every time they finish a
## walk.
var _schedule: RoutineSchedule = null
## What they were doing when they last chose a destination, so a change of
## activity is what sends them somewhere new.
var _last_activity: int = -1
## Set while they are inside a building, which is what makes §13's "enter" and
## §14's "leave" visible rather than a vanishing act on the pavement.
var _indoors: bool = false
## Stood down by the crowd director: off the street entirely for this part of
## the day. Distinct from being far from the player, which is temporary.
var _stood_down: bool = false


func _ready() -> void:
	super()
	_rng.randomize()
	health = max_health
	add_to_group(&"pedestrian")
	add_to_group(&"witness")
	path_finished.connect(_on_path_finished)
	# Stagger the traffic scans too, so the crowd's checks spread across frames
	# instead of all landing on the same one.
	_danger_timer = _rng.randf_range(0.0, danger_check_interval)
	# Staggered as well, for the same reason: a crowd all testing their distance
	# to the player on one frame is the spike this is meant to avoid.
	_activation_timer = _rng.randf_range(0.0, activation_interval)
	# Stagger the first decision so a freshly spawned crowd does not all move
	# off on the same frame.
	_enter_idle(_rng.randf_range(0.0, 2.5))


## True while this civilian is close enough to the player to be worth simulating.
func is_active() -> bool:
	return _active


## Brings a civilian back into simulation immediately rather than at the next
## check. For anything that puts one somewhere and then expects it to behave.
func wake() -> void:
	_refresh_activation()


func _process(delta: float) -> void:
	_activation_timer -= delta
	if _activation_timer <= 0.0:
		_activation_timer = activation_interval
		_refresh_activation()
	if not _active:
		return

	_danger_timer -= delta
	if _danger_timer <= 0.0:
		_danger_timer = danger_check_interval
		_check_traffic()
		_check_wanted_player()

	_state_timer -= delta
	if _state_timer > 0.0:
		return

	# Their time inside is up: back out of the door they went in by (§14).
	if _indoors:
		_leave_building()
		return

	if condition == Condition.INCAPACITATED:
		_state_timer = 4.0
		return

	match state:
		State.IDLE:
			_choose_wander()
		State.WITNESSING:
			_begin_fleeing()
		State.FLEEING:
			_enter_idle(_rng.randf_range(idle_time_range.x, idle_time_range.y))
		State.KNOCKED_DOWN:
			_stand_up()
		State.FEAR:
			# Frightened people do not stand still forever: once the immediate
			# shock passes they get out of the area.
			_begin_fleeing()
		State.DODGING:
			# Out of the road; carry on shaken rather than resuming mid-street.
			_begin_fleeing()
		State.WALKING:
			# Walking ends on arrival, not on a timer.
			_state_timer = 1.0


## Switches this civilian off when the player is nowhere near them, and back on
## when they come back. Off means no traffic scan, no decisions and no movement;
## they stand where they were until somebody is there to see them.
func _refresh_activation() -> void:
	var player := GameManager.player
	var active := (
		not _stood_down
		and (
			not ambient_crowd
			or player == null
			or global_position.distance_to(player.global_position) <= active_distance
		)
	)
	_active = active
	# Applied every time rather than only on a change. The crowd director also
	# touches these flags, and an early return here once let it leave somebody
	# physics-processing on the far side of the city — a crowd that was meant to
	# cost nothing quietly walking about with nobody watching.
	#
	# Somebody inside a building stays inside it. Walking away and back must not
	# turn them out onto the pavement.
	set_physics_process(active and not _indoors)
	if not active:
		velocity = Vector3.ZERO


## Taken off the street, or put back on it, by the crowd director. The person
## owns their own activation either way: the director says whether they are
## out, and this file decides what that costs.
func stand_down(down: bool) -> void:
	if _stood_down == down:
		return
	_stood_down = down
	visible = not down
	if down:
		velocity = Vector3.ZERO
	# Idle processing is what notices the player coming back, so it stops only
	# for somebody who is not on the street at all.
	set_process(not down)
	_refresh_activation()


func is_stood_down() -> bool:
	return _stood_down


## Repositioning somebody to their routine venue was tried in Phase S and
## withdrawn. It filled the plaza, and it also teleported Central residents to
## the harbour park when that park's bench happened to be their nearest one,
## inverted both districts' headcounts, and dropped people into the road in
## front of moving traffic. The suite caught all three.
##
## The lesson is that a routine destination is only meaningful to somebody who
## is going to walk there. If a future phase wants a fuller park, the answer is
## more people, or a destination chosen inside the person's own district — not
## a teleport.


## Called by the witness system when this civilian sees a crime.
func witness_crime(crime_position: Vector3) -> void:
	# Anything close enough to be seen from is close enough to be awake, but a
	# civilian who has just been moved here has not had their check yet.
	_refresh_activation()
	if state == State.WITNESSING or state == State.FLEEING or state == State.KNOCKED_DOWN:
		return
	_crime_position = crime_position
	stop()
	set_running(false)
	_set_state(State.WITNESSING)
	_state_timer = witness_seconds
	# Turn to look at what just happened.
	var to_crime := crime_position - global_position
	to_crime.y = 0.0
	if to_crime.length_squared() > 0.01:
		body_pivot.rotation.y = atan2(to_crime.x, to_crime.z)


## Who can still see a crime and call it in.
##
## Deliberately wider than "going about their day": somebody already frightened,
## or running from a chase, is looking straight at the person causing it, and
## they report what they see. If they did not, a player at one star could never
## escalate in a street they had already cleared — every remaining witness would
## be too scared to notice a robbery happening in front of them.
##
## The exclusions are the ones that genuinely cannot report: face-down on the
## pavement, out cold, or already mid-report on something else.
func is_available_as_witness() -> bool:
	if condition != Condition.ACTIVE:
		return false
	return state != State.KNOCKED_DOWN and state != State.WITNESSING


## Stands still and makes no decisions for `seconds`. Reactions still interrupt
## it — being knocked down or seeing a crime overrides the state outright — so
## this is "nothing to do right now", not a freeze. Waiting at a crossing, or
## queuing at a counter, will want exactly this.
func wait_for(seconds: float) -> void:
	if state == State.KNOCKED_DOWN:
		return
	_enter_idle(seconds)


# --- Traffic safety ------------------------------------------------------

func is_down() -> bool:
	return state == State.KNOCKED_DOWN


## Struck by a vehicle. Returns true if this actually put them on the floor, so
## the caller can tell a knockdown from a nudge at walking pace.
##
## No ragdoll and no gore: they drop, lie there a moment, get up and hurry off.
## That is enough to make running people over feel like something happened
## without the phase turning into a physics project.
func knock_down(impact_speed: float, from_direction: Vector3 = Vector3.ZERO) -> bool:
	if state == State.KNOCKED_DOWN:
		return false
	if impact_speed < knockdown_speed:
		# A shove at parking speed: step aside, stay upright. `from_direction`
		# points from the car to them, so following it is away from the car.
		_dodge_away(global_position + from_direction * dodge_distance)
		return false

	stop()
	set_running(false)
	# Remember roughly where the car came from, so they run away from it rather
	# than back into the road when they get up.
	_threat_position = global_position - from_direction * dodge_distance
	health = maxf(health - (impact_speed - knockdown_speed) * damage_per_impact_speed, 1.0)
	# Out of the collision world while down, so nothing walks into a body on the
	# floor and no car re-triggers the same impact every frame.
	collision_layer = 0
	_lay_down(from_direction)
	_set_state(State.KNOCKED_DOWN)
	_state_timer = _rng.randf_range(down_seconds.x, down_seconds.y)
	knocked_down.emit(impact_speed)
	return true


func _stand_up() -> void:
	# Nobody gets up from zero. They stay on the floor, out of the collision
	# world, until something restores them — which nothing does yet, and which is
	# the whole of "incapacitated" for now.
	if health <= incapacitated_below:
		condition = Condition.INCAPACITATED
		_state_timer = 6.0
		return
	collision_layer = 1 << 4
	body_pivot.rotation.x = 0.0
	body_pivot.position.y = 0.0
	recovered.emit()
	# Someone who has just been run over does not go back to window shopping.
	_crime_position = _threat_position
	_begin_fleeing()


# --- Fear and harm -------------------------------------------------------

func is_incapacitated() -> bool:
	return condition == Condition.INCAPACITATED


## Frightened, and looking at whatever frightened them. Used by the robbery, and
## by anyone nearby when something serious happens.
##
## Fear is not the same as fleeing: a cashier being robbed has to stay at the
## till long enough to hand the money over, and a witness has to see the thing
## before running from it. FEAR holds them in place, then falls through to
## FLEEING on its own timer.
func enter_fear(source_position: Vector3, seconds: float = -1.0) -> void:
	if state == State.KNOCKED_DOWN or is_incapacitated():
		return
	_threat_position = source_position
	_crime_position = source_position
	stop()
	set_running(false)
	_set_state(State.FEAR)
	_state_timer = fear_seconds if seconds < 0.0 else seconds

	var to_source := source_position - global_position
	to_source.y = 0.0
	if to_source.length_squared() > 0.01:
		body_pivot.rotation.y = atan2(to_source.x, to_source.z)


func is_afraid() -> bool:
	return state == State.FEAR


## Damage from a punch, a shove or anything else that is not a car. Returns true
## if this put them down.
func take_damage(amount: float, from_direction: Vector3 = Vector3.ZERO) -> bool:
	if amount <= 0.0 or is_incapacitated():
		return false
	health = maxf(health - amount, 0.0)

	if health <= incapacitated_below:
		# Straight to the floor, and staying there.
		stop()
		collision_layer = 0
		_lay_down(from_direction)
		_set_state(State.KNOCKED_DOWN)
		condition = Condition.INCAPACITATED
		_state_timer = 6.0
		knocked_down.emit(amount)
		return true

	# Still standing: frightened, and away from whoever did it. A small minority
	# stand their ground instead, so a street is not uniformly cowardly.
	var threat := global_position - from_direction * dodge_distance
	if _rng.randf() < defiance_chance:
		enter_fear(threat, fear_seconds * 0.5)
	else:
		_crime_position = threat
		_begin_fleeing()
	return false


func _lay_down(from_direction: Vector3) -> void:
	var flat := Vector3(from_direction.x, 0.0, from_direction.z)
	if flat.length_squared() > 0.01:
		body_pivot.rotation.y = atan2(flat.x, flat.z)
	# The pivot sits at the feet, so a quarter turn about X lays the figure out
	# in the direction it was hit, and lifting it by a radius rests it on the
	# ground instead of half-buried.
	body_pivot.rotation.x = -PI * 0.5
	body_pivot.position.y = body_radius


## Looks for a car bearing down on this pedestrian. Corridor test rather than a
## physics query: a dot product per nearby vehicle costs nothing, and being
## approximately right about "that car is coming at me" is all the reaction
## needs.
func _check_traffic() -> void:
	if state == State.KNOCKED_DOWN or state == State.DODGING:
		return

	for node in get_tree().get_nodes_in_group(&"vehicle"):
		var car := node as Vehicle
		if car == null or car.get_planar_speed() < danger_min_speed:
			continue

		var offset := global_position - car.global_position
		offset.y = 0.0
		if offset.length() > danger_radius:
			continue

		var forward := -car.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.01:
			continue
		forward = forward.normalized()
		# Reversing cars point their danger the other way.
		if car.get_forward_speed() < 0.0:
			forward = -forward

		var ahead := offset.dot(forward)
		if ahead < 0.0 or ahead > danger_radius:
			continue
		var sideways := offset.dot(forward.cross(Vector3.UP))
		if absf(sideways) > danger_half_width:
			continue

		_threat_position = car.global_position
		_dodge_away(global_position + forward.cross(Vector3.UP) * signf_or_random(sideways) * dodge_distance)
		return


## Clears the street around somebody the police are after. Runs on the same
## coarse timer as the traffic scan — a distance check per civilian per quarter
## second — and widens with the wanted level, so one star turns heads nearby and
## three empties the block.
func _check_wanted_player() -> void:
	if not (state == State.IDLE or state == State.WALKING):
		return
	if WantedManager.level <= 0:
		return
	var player := GameManager.player
	if player == null:
		return
	var radius := wanted_fear_radius * float(WantedManager.level)
	if global_position.distance_to(player.global_position) > radius:
		return
	enter_fear(player.global_position, fear_seconds * 0.5)


## Sideways is signed; standing exactly in the middle of the lane is not, so
## pick a side rather than freezing.
func signf_or_random(value: float) -> float:
	if absf(value) < 0.05:
		return 1.0 if _rng.randf() < 0.5 else -1.0
	return signf(value)


func _dodge_away(destination: Vector3) -> void:
	if state == State.KNOCKED_DOWN:
		return
	set_running(true)
	_set_state(State.DODGING)
	_state_timer = dodge_seconds
	if not walk_to(destination):
		# Nowhere to route to; still get off the spot.
		walk_to(global_position + (destination - global_position).normalized() * 2.0)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)


func _enter_idle(seconds: float) -> void:
	stop()
	set_running(false)
	_set_state(State.IDLE)
	_state_timer = seconds


func _choose_wander() -> void:
	if not wanders:
		_state_timer = 2.0
		return
	if nav == null:
		_state_timer = 2.0
		return
	# Somewhere to be, if this person has a life. Falls through to the old
	# random walk when their activity has nowhere to happen, so a district
	# missing a gym does not strand everybody who wanted one.
	if follows_routine and _route_to_activity():
		return
	var destination := nav.random_point_away_from(
		NavGraph.Layer.WALK, global_position, min_wander_distance, _rng
	)
	if not send_to(destination):
		# Nowhere to go from here; wait and try again rather than spin.
		_state_timer = 1.5


## The routine half of choosing where to go.
##
## Returns false when there is nothing to do about it, which is the caller's cue
## to fall back on wandering. §11 — the visible result is people walking towards
## workplaces, shops and doorways rather than to arbitrary pavement.
func _route_to_activity() -> bool:
	if _schedule == null:
		_schedule = RoutineManager.schedule_for(
			StringName(get_path()), routine_district
		)
	var activity := RoutineManager.activity_for(_schedule)
	var destination := RoutineManager.destination_for(_schedule, global_position)
	if destination == Vector3.INF:
		return false
	# Already there, and it is somewhere with a door: go in rather than stand
	# outside it looking at it (§13).
	if global_position.distance_to(destination) < ARRIVED_WITHIN:
		if RoutineActivity.is_indoors(activity):
			_enter_building()
			return true
		_enter_idle(_rng.randf_range(4.0, 12.0))
		return true
	_last_activity = int(activity)
	return send_to(destination)


## Steps inside. Nothing is loaded and no interior is entered — the person is
## hidden and parked for a while, which is what an onlooker sees and costs
## nothing. §14 brings them back out of the same door.
func _enter_building() -> void:
	if _indoors:
		return
	_indoors = true
	visible = false
	set_physics_process(false)
	_set_state(State.IDLE)
	# Long enough to read as "they went in", short enough that a street does not
	# quietly empty itself over an afternoon.
	_state_timer = _rng.randf_range(20.0, 70.0)


func _leave_building() -> void:
	if not _indoors:
		return
	_indoors = false
	visible = true
	set_physics_process(_active and not _stood_down)
	_state_timer = 0.5


## What this person is doing, for the tests and the debug overlay.
func routine_activity() -> int:
	if _schedule == null:
		return -1
	return int(RoutineManager.activity_for(_schedule))


func routine_archetype_name() -> String:
	return _schedule.archetype_name() if _schedule != null else ""


func is_indoors() -> bool:
	return _indoors


## Sends this civilian somewhere and puts them in the state that keeps them
## going there.
##
## walk_to on its own only hands over a route. The idle timer is still running
## underneath it, and when it expires the civilian picks somewhere of their own
## and walks off — which is right for a crowd and wrong for anybody who has
## actually been sent somewhere. Everything that wants a civilian to go to one
## particular place goes through here.
func send_to(destination: Vector3) -> bool:
	if not walk_to(destination):
		return false
	_set_state(State.WALKING)
	_state_timer = 1.0
	return true


func _begin_fleeing() -> void:
	set_running(true)
	_set_state(State.FLEEING)
	_state_timer = flee_seconds
	if nav == null:
		return
	var away := nav.random_point_away_from(
		NavGraph.Layer.WALK, _crime_position, min_flee_distance, _rng
	)
	walk_to(away)


func _on_path_finished() -> void:
	match state:
		State.FLEEING:
			# Keep running until the flee timer is up.
			_begin_fleeing()
		State.WITNESSING, State.KNOCKED_DOWN:
			pass
		State.DODGING:
			# Off the road already; wait out the timer rather than wandering back.
			pass
		_:
			_enter_idle(_rng.randf_range(idle_time_range.x, idle_time_range.y))
