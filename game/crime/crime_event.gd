class_name CrimeEvent
extends RefCounted

## One incident, however many people saw it.
##
## §101 is the reason this exists: a crime on a busy street can be witnessed by
## four pedestrians, and four reports of one theft must not add four thefts of
## heat. So reports aggregate into an event — the first one calls it in, the
## rest confirm it. Confirmation is not nothing: it makes the police surer of
## what they are looking for, which is what `confidence` feeds.
##
## §102 deliberately keeps this at incident level. No witness remembers a face
## next Tuesday; the event lives while the incident does and is forgotten with
## it.

var event_id: StringName = &""
var crime_type: int = 0
var position: Vector3 = Vector3.ZERO
var opened_minute: float = 0.0
## How many separate witnesses called it in. The first is what reports it.
var reports: int = 0
## The vehicle the player was in, if anybody saw one.
var vehicle_id: StringName = &""
## Whether police have actually been told.
var called_in: bool = false
## Whether anybody identified the player themselves, as against the car.
var identified_player: bool = false


static func make(id: StringName, type: int, at: Vector3, minute: float) -> CrimeEvent:
	var event := CrimeEvent.new()
	event.event_id = id
	event.crime_type = type
	event.position = at
	event.opened_minute = minute
	return event


func data() -> CrimeData:
	return CrimeData.for_type(crime_type)


func severity() -> CrimeData.Severity:
	return data().severity


## Heat this incident is worth. The first report is what it costs; further
## witnesses add a little for being sure, and stop mattering quickly — §101
## asks that reports not multiply, and a hard ceiling is the honest way to say
## the police only need to be told once.
func wanted_points() -> int:
	if reports <= 0:
		return 0
	var base := data().base_wanted_points
	var confirmations := mini(reports - 1, 3)
	return base + int(round(float(base) * 0.1 * float(confirmations)))


## How sure the police are about what they are looking for, 0-1. One witness is
## a description; three agreeing is a description they will act on.
func confidence() -> float:
	return clampf(float(reports) * 0.34, 0.0, 1.0)


## Whether another report of this kind here still belongs to this incident.
func accepts(type: int, at: Vector3, minute: float, radius: float = 18.0) -> bool:
	if crime_type != type:
		return false
	if minute - opened_minute > data().cooldown / 60.0:
		return false
	return position.distance_to(at) <= radius


func add_report(saw_player: bool, seen_vehicle: StringName = &"") -> void:
	reports += 1
	identified_player = identified_player or saw_player
	if seen_vehicle != &"" and vehicle_id == &"":
		vehicle_id = seen_vehicle
