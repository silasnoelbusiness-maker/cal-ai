class_name Hiding
extends RefCounted

## Whether the player is out of sight, and whether that counts.
##
## §33 asks for hiding based on world visibility rather than magical
## invisibility, and this is the whole of it: a place is a hiding place if
## police cannot see into it, and hiding works if nobody watched you go in.
## There is no stealth meter and no crouch button — §33 rules both out — and
## nothing here makes the player harder to see than the geometry already does.
##
## §34 is the rule that stops it being an exploit. Ducking into a shop while an
## officer watches you do it does not lose them: they saw where you went, and
## §36 keeps that location hot. Ducking into the same shop unseen does, because
## then nobody knows which door you took.
##
## §37 and §38 apply the same test to the player's own businesses and their
## home. Owning the building is not a wanted-level button; not being followed
## into it is what helps.

## Somewhere that counts as out of sight. An interior the player has entered,
## or a volume placed in the world for the purpose.
const HIDING_GROUP := &"hiding_spot"
## How near a police unit has to be for entering somewhere in front of them to
## count as having been watched.
const OBSERVED_RANGE := 34.0
## How near the middle of a room the player has to be for that room to be the
## one hiding them. Generous — interiors are large — but finite.
const INTERIOR_REACH := 40.0


## Whether the player is somewhere that hides them at all. True inside an
## interior, or inside a marked hiding volume.
static func in_cover(tree: SceneTree) -> bool:
	var player := GameManager.player
	if player == null or tree == null:
		return false
	# Interiors are the ordinary case: a room the player has walked into is a
	# room the street cannot see into.
	#
	# The room's own flag is asked first and then checked against where the
	# player actually is. The flag is set by an Area3D, and a test that
	# teleports the player across the city can leave it saying yes about a room
	# a hundred metres away — which made standing in the middle of Main Street
	# count as cover.
	for node in tree.get_nodes_in_group(&"retail_unit"):
		var room := node as RetailUnit
		if room == null or not room.is_player_inside():
			continue
		if room.global_position.distance_to(player.global_position) <= INTERIOR_REACH:
			return true
	for node in tree.get_nodes_in_group(HIDING_GROUP):
		var area := node as Area3D
		if area == null:
			continue
		if area.overlaps_body(player):
			return true
	return false


## Whether any police unit can currently see the player. The same test the
## officers themselves use, asked from the other side.
static func observed(tree: SceneTree) -> bool:
	var player := GameManager.player
	if player == null or tree == null:
		return false
	for node in tree.get_nodes_in_group(&"police"):
		var observer := node as Node3D
		if observer == null:
			continue
		if observer.global_position.distance_to(player.global_position) > OBSERVED_RANGE:
			continue
		if WitnessSystem.can_see(observer, player.global_position, OBSERVED_RANGE, 200.0):
			return true
	return false


## How often the answer is worth recomputing. The HUD asks every frame and the
## answer involves a raycast per nearby officer, which is exactly the kind of
## thing §180 warns about — the geometry does not change in a sixtieth of a
## second, so neither does this.
const CACHE_SECONDS := 0.25

static var _cached: bool = false
static var _cached_at: float = -1.0


## The question the HUD asks: is the player actually hidden right now.
##
## Three things have to be true. They are somewhere that hides them, nobody can
## see them, and the police have not just had eyes on them — that last one is
## §34's "not directly in front of police", expressed as the sighting clock
## rather than as a cone, because a player who was visible half a second ago
## was watched going in whatever the geometry says now.
static func is_hidden(tree: SceneTree) -> bool:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if _cached_at >= 0.0 and now - _cached_at < CACHE_SECONDS:
		return _cached
	_cached_at = now
	_cached = _compute(tree)
	return _cached


static func _compute(tree: SceneTree) -> bool:
	if not WantedManager.is_wanted():
		return false
	if PoliceMemory.has_fresh_sighting():
		return false
	if not in_cover(tree):
		# Cheapest test first: standing in the street is not hiding, and there
		# is no reason to cast a ray at every officer to find that out.
		return false
	return not observed(tree)


## §34's other half — a known car parked outside still draws attention, so
## hiding while the thing the police are looking for sits at the kerb is worth
## less than hiding after getting rid of it.
static func compromised_by_vehicle(tree: SceneTree) -> bool:
	if PoliceMemory.active_vehicle_id == &"":
		return false
	var player := GameManager.player
	if player == null or tree == null:
		return false
	# The car the police want, left within sight of where the player went in.
	for node in tree.get_nodes_in_group(&"vehicle"):
		var car := node as Node3D
		if car == null or not PoliceMemory.is_vehicle_known(car):
			continue
		if car.global_position.distance_to(player.global_position) <= OBSERVED_RANGE:
			return true
	return false
