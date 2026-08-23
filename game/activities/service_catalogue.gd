class_name ServiceCatalogue
extends RefCounted

## What each kind of counter sells.
##
## Prices sit against the warehouse shift's $120 and the corner shop's $15
## meal: eating out is worth it for the time it saves and the state it leaves
## you in, and it is never the cheap option.
##
## A gym is worth using without any strength stat, because a session buys back
## health and costs the energy to earn it. The point of going is that health
## comes back faster than it would sitting at home.

enum Kind { CAFE, DINER, GYM, BAR }

const KIND_NAMES := {
	Kind.CAFE: "Cafe",
	Kind.DINER: "Diner",
	Kind.GYM: "Gym",
	Kind.BAR: "Bar",
}


static func kind_name(kind: Kind) -> String:
	return String(KIND_NAMES.get(kind, "Counter"))


static func for_kind(kind: Kind) -> Array[VenueService]:
	match kind:
		Kind.CAFE:
			return [
				VenueService.make(
					&"coffee", "Coffee", "Black, and quickly.",
					4, 6, 3.0, 22.0
				),
				VenueService.make(
					&"pastry_and_coffee", "Coffee and a pastry",
					"Standing at the window.", 9, 12, 18.0, 22.0
				),
				VenueService.make(
					&"sit_and_read", "Sit a while",
					"Nothing to do for half an hour.", 6, 35, 4.0, 30.0, 2.0
				),
			]
		Kind.DINER:
			return [
				VenueService.make(
					&"breakfast", "Breakfast", "Eggs, and enough of them.",
					12, 25, 45.0, 10.0, 2.0
				),
				VenueService.make(
					&"plate_of_the_day", "Plate of the day",
					"Whatever is on the board.", 16, 30, 60.0, 8.0, 4.0
				),
				VenueService.make(
					&"late_supper", "Late supper",
					"The kitchen closes after this.", 19, 30, 65.0, 4.0, 4.0
				),
			]
		Kind.GYM:
			return [
				VenueService.make(
					&"quick_session", "Half an hour", "Enough to feel it.",
					10, 30, -6.0, -14.0, 8.0
				),
				VenueService.make(
					&"full_session", "A proper session", "You will sleep well.",
					16, 70, -12.0, -26.0, 18.0
				),
				VenueService.make(
					&"shower_only", "Shower and out", "Ten minutes of hot water.",
					4, 10, 0.0, 6.0, 1.0
				),
			]
		Kind.BAR:
			return [
				VenueService.make(
					&"one_drink", "One drink", "Just the one.",
					8, 20, 4.0, -6.0
				),
				VenueService.make(
					&"stay_out", "Stay out a while", "The night goes somewhere.",
					26, 90, 6.0, -30.0
				),
			]
	return []


static func by_id(kind: Kind, id: StringName) -> VenueService:
	for service in for_kind(kind):
		if service.service_id == id:
			return service
	return null
