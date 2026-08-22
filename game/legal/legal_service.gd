class_name LegalService
extends RefCounted

## Representation, as a game modifier rather than a profession.
##
## §27 and §28 want three fictional tiers that nudge an outcome and cost money.
## §30 is the important one: a service is chosen for a case and the case then
## resolves once, so this can never become a reroll button.
##
## Nothing here is advice, and none of these are real firms.

var service_id: StringName = &"public_counsel"
var display_name: String = "Public counsel"
var blurb: String = "Assigned, free, and stretched thin."
## Flat cost to retain.
var cost: int = 0
## Added to the roll that picks an outcome band. Small on purpose — §28 says a
## lawyer may improve the odds and may not buy innocence.
var outcome_bonus: float = 0.0
## Fraction knocked off whatever fine the hearing lands on.
var fine_relief: float = 0.0
## Fraction knocked off the release cost at the roadside.
var release_relief: float = 0.0


static func make(
	id: StringName, name: String, text: String, price: int,
	bonus: float, relief: float, release: float
) -> LegalService:
	var service := LegalService.new()
	service.service_id = id
	service.display_name = name
	service.blurb = text
	service.cost = price
	service.outcome_bonus = bonus
	service.fine_relief = relief
	service.release_relief = release
	return service


## The three tiers. Public counsel is always available and always free, so a
## broke player is never without representation and §17's no-soft-lock rule
## holds on this side too.
static func catalogue() -> Array[LegalService]:
	return [
		make(
			&"public_counsel", "Public counsel",
			"Assigned to you, costs nothing, and has four other cases today.",
			0, 0.0, 0.0, 0.0
		),
		make(
			&"harbour_legal", "Harbour Row Legal",
			"Two rooms above a chandlery. They answer the phone.",
			2400, 0.12, 0.15, 0.1
		),
		make(
			&"pell_and_vane", "Pell & Vane",
			"Central District, glass frontage, and they want paying first.",
			9000, 0.26, 0.3, 0.2
		),
	]


static func by_id(id: StringName) -> LegalService:
	for service in catalogue():
		if service.service_id == id:
			return service
	return catalogue()[0]
