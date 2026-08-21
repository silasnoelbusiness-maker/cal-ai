class_name ServiceQueue
extends RefCounted
## A line of people waiting for the same thing.
##
## Phase H grew a queue inside the shop's customer spawner, and by Phase O there
## were five things worth queueing for: a till, a coffee counter, a table, a
## reception desk and a rope outside a nightclub. They are all the same problem
## — an ordered list, a limited length, and a spot on the floor for each place
## in it — so they are all this.
##
## Holds no nodes and no scene knowledge. Whoever owns the queue tells it where
## the front is and which way it runs, and it hands back a position per place.

## Metres between one person and the next.
var spacing: float = 1.5
## How many will stand in it before the rest give up.
var limit: int = 4
## Where the first place stands, in world space.
var head: Vector3 = Vector3.ZERO
## Unit vector back down the line from the head.
var direction: Vector3 = Vector3.BACK

var _waiting: Array = []


func configure(head_point: Vector3, back_direction: Vector3, max_length: int, gap: float = 1.5) -> void:
	head = head_point
	var flat := Vector3(back_direction.x, 0.0, back_direction.z)
	direction = flat.normalized() if flat.length_squared() > 0.001 else Vector3.BACK
	limit = maxi(max_length, 1)
	spacing = maxf(gap, 0.6)


func size() -> int:
	return _waiting.size()


func is_empty() -> bool:
	return _waiting.is_empty()


func is_full() -> bool:
	return _waiting.size() >= limit


func contains(who: Object) -> bool:
	return _waiting.has(who)


func place_of(who: Object) -> int:
	return _waiting.find(who)


## Where a given place in the line stands. Place zero is the front.
func position_of_place(place: int) -> Vector3:
	return head + direction * (spacing * float(maxi(place, 0)))


func position_of(who: Object) -> Vector3:
	return position_of_place(place_of(who))


## Joins the back of the line. Fails when it is already too long, which is what
## a customer reads as "not worth waiting for".
func join(who: Object) -> bool:
	if who == null or _waiting.has(who) or is_full():
		return false
	_waiting.append(who)
	return true


func leave(who: Object) -> bool:
	var index := _waiting.find(who)
	if index < 0:
		return false
	_waiting.remove_at(index)
	return true


func front() -> Object:
	return _waiting[0] if not _waiting.is_empty() else null


## Takes the person at the front off the line and returns them.
func take_front() -> Object:
	if _waiting.is_empty():
		return null
	return _waiting.pop_front()


func members() -> Array:
	return _waiting.duplicate()


## Drops anybody who has been freed since they joined. Called before the queue
## is read, so a customer who was deleted mid-wait never holds up the line.
func prune() -> int:
	var removed := 0
	for i in range(_waiting.size() - 1, -1, -1):
		var who: Object = _waiting[i]
		if who == null or not is_instance_valid(who):
			_waiting.remove_at(i)
			removed += 1
	return removed


func clear() -> void:
	_waiting.clear()
