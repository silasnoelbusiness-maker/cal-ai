class_name CrimeData
extends RefCounted

## What a kind of crime *is*, as data rather than as a name the code checks for.
##
## Phase J put severity, points and evidence in a dictionary inside
## CrimeManager. That was right, and this is the same idea grown up: one row per
## crime type carrying everything the rest of the game needs to know about it —
## how serious it is, what a reported one costs in heat, how the police answer
## it, what it is worth to a criminal reputation, and which column of the
## illegal ledger its money lands in.
##
## The point of the table is that nothing outside it names a crime. Police
## response reads a severity, the wanted meter reads points, the underworld
## reads a reputation reward. Tuning the game's whole risk-and-reward balance is
## editing this file, and adding a crime is adding a row — §11 asks for exactly
## that, and it is what stops "is this a robbery?" appearing in five places.

## How bad the act is, independent of what it costs to be chased for. §12.
enum Severity { MINOR, MODERATE, SERIOUS, SEVERE, EXTREME }

const SEVERITY_NAMES := {
	Severity.MINOR: "MINOR",
	Severity.MODERATE: "MODERATE",
	Severity.SERIOUS: "SERIOUS",
	Severity.SEVERE: "SEVERE",
	Severity.EXTREME: "EXTREME",
}

## Which column of the illegal ledger money from this lands in. §68.
enum Income { NONE, STOLEN_GOODS, VEHICLE_CRIME, ILLEGAL_JOBS, ROBBERY }

const INCOME_NAMES := {
	Income.NONE: "",
	Income.STOLEN_GOODS: "Stolen goods",
	Income.VEHICLE_CRIME: "Vehicle crime",
	Income.ILLEGAL_JOBS: "Illegal jobs",
	Income.ROBBERY: "Robbery",
}

var crime_id: StringName = &""
var display_name: String = "Crime"
var severity: Severity = Severity.MINOR
## Whether this needs somebody to see it before police hear about it. A shop
## robbery is reported by the shop whether or not a passer-by watched; a theft
## from an empty street is not reported by anybody.
var witness_report_required: bool = true
## What one reported instance adds to the wanted meter.
var base_wanted_points: int = 10
## Which response shape the police use. See CrimeProfile.
var police_response_profile: StringName = &"routine"
## What pulling it off is worth on the street. Deliberately small and flat:
## §80 warns against rewarding random harm, so violence is worth no more than
## the theft it covers.
var criminal_reputation_reward: int = 0
var illegal_income_category: Income = Income.NONE
## Seconds before another of the same kind at the same place counts as a fresh
## incident rather than more of the one already reported. §101.
var cooldown: float = 20.0


static func make(
	id: StringName, name: String, level: Severity, points: int,
	profile: StringName, reputation: int = 0,
	income: Income = Income.NONE, needs_witness: bool = true,
	cool: float = 20.0
) -> CrimeData:
	var data := CrimeData.new()
	data.crime_id = id
	data.display_name = name
	data.severity = level
	data.base_wanted_points = points
	data.police_response_profile = profile
	data.criminal_reputation_reward = reputation
	data.illegal_income_category = income
	data.witness_report_required = needs_witness
	data.cooldown = cool
	return data


static func severity_name(level: Severity) -> String:
	return String(SEVERITY_NAMES.get(level, "MINOR"))


static func income_name(category: Income) -> String:
	return String(INCOME_NAMES.get(category, ""))


## The whole catalogue, keyed by CrimeManager.CrimeType.
##
## Built once and cached. Keyed by the existing enum rather than by a new one so
## that every crime already filed by Phases J to P lands here without any of
## them being rewritten — Phase Q is meant to deepen the crime side, not to
## re-cut what a crime record looks like.
static var _table: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty():
		_build()
	return _table


static func for_type(type: int) -> CrimeData:
	var found: CrimeData = table().get(type)
	return found if found != null else make(
		&"unknown", "Crime", Severity.MINOR, 5, &"routine"
	)


## Convenience for the places that only want the number.
static func points_for(type: int) -> int:
	return for_type(type).base_wanted_points


static func severity_of(type: int) -> Severity:
	return for_type(type).severity


static func _build() -> void:
	# Ordered by how seriously the city takes it. The gap between shoplifting
	# and a store robbery is the whole reason §96 exists: taking a chocolate bar
	# must not put five stars over the city.
	_table = {
		CrimeManager.CrimeType.TRESPASSING: make(
			&"trespassing", "Trespassing", Severity.MINOR, 5, &"routine", 0,
			Income.NONE, true, 30.0
		),
		CrimeManager.CrimeType.SHOPLIFTING: make(
			&"shoplifting", "Shoplifting", Severity.MINOR, 10, &"routine", 1,
			Income.STOLEN_GOODS, true, 25.0
		),
		CrimeManager.CrimeType.VEHICLE_THEFT: make(
			&"vehicle_theft", "Vehicle theft", Severity.MODERATE, 20, &"patrol", 2,
			Income.VEHICLE_CRIME, true, 20.0
		),
		CrimeManager.CrimeType.ASSAULT: make(
			&"assault", "Assault", Severity.SERIOUS, 25, &"patrol", 0,
			Income.NONE, true, 15.0
		),
		CrimeManager.CrimeType.VEHICULAR_ASSAULT: make(
			&"vehicular_assault", "Vehicular assault", Severity.SERIOUS, 25,
			&"patrol", 0, Income.NONE, true, 15.0
		),
		CrimeManager.CrimeType.BURGLARY: make(
			&"burglary", "Burglary", Severity.SERIOUS, 30, &"patrol", 3,
			Income.STOLEN_GOODS, true, 25.0
		),
		CrimeManager.CrimeType.HIT_AND_RUN: make(
			&"hit_and_run", "Hit and run", Severity.SERIOUS, 30, &"patrol", 0,
			Income.NONE, true, 20.0
		),
		# §99 — taking a car off somebody who is sitting in it is a different
		# thing from taking one nobody is near, and the city agrees.
		CrimeManager.CrimeType.CARJACKING: make(
			&"carjacking", "Carjacking", Severity.SEVERE, 35, &"coordinated", 4,
			Income.VEHICLE_CRIME, true, 20.0
		),
		# A shop rings the police itself, which is why this needs no witness.
		# Left at Phase J's forty. Phase Q gets its escalation from the
		# thresholds and the response profiles, not by quietly making every
		# old crime worth more — the balance the earlier phases were tested
		# against is still the balance.
		CrimeManager.CrimeType.STORE_ROBBERY: make(
			&"store_robbery", "Store robbery", Severity.SEVERE, 40, &"coordinated",
			5, Income.ROBBERY, false, 30.0
		),
		CrimeManager.CrimeType.ROBBERY: make(
			&"robbery", "Robbery", Severity.SEVERE, 40, &"coordinated", 5,
			Income.ROBBERY, true, 30.0
		),
	}
