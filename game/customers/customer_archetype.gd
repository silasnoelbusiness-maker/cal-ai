class_name CustomerArchetype
extends RefCounted
## Who walked in.
##
## Six kinds of person, each caring about a different thing. Not a demographic
## simulation and not meant to become one — the whole of it is that an office
## worker on a lunch hour minds a queue and a student minds the price, so the
## same shop is a different shop depending on where it is and when.

const WORKER := &"worker"
const STUDENT := &"student"
const OFFICE := &"office"
const AFFLUENT := &"affluent"
const NIGHTLIFE := &"nightlife"
const FITNESS := &"fitness"

## id -> [label, price sensitivity, quality weight, patience, colour]
## Price sensitivity above 1 means they feel a high price more than most.
const KINDS := {
	WORKER: ["Worker", 1.15, 0.85, 1.0, Color(0.475, 0.529, 0.588)],
	STUDENT: ["Student", 1.45, 0.70, 1.25, Color(0.545, 0.616, 0.482)],
	OFFICE: ["Office", 0.95, 1.05, 0.75, Color(0.400, 0.451, 0.549)],
	AFFLUENT: ["Affluent", 0.62, 1.35, 0.85, Color(0.639, 0.573, 0.427)],
	NIGHTLIFE: ["Nightlife", 0.85, 1.20, 1.15, Color(0.588, 0.435, 0.663)],
	FITNESS: ["Fitness", 1.05, 1.10, 1.0, Color(0.435, 0.588, 0.510)],
}

## Used when a business type says nothing about who comes in.
const DEFAULT_WEIGHTS := {WORKER: 1.0, STUDENT: 0.6, OFFICE: 0.8}


static func label(id: StringName) -> String:
	var entry: Array = KINDS.get(id, [])
	return String(entry[0]) if not entry.is_empty() else "Customer"


static func price_sensitivity(id: StringName) -> float:
	var entry: Array = KINDS.get(id, [])
	return float(entry[1]) if entry.size() > 1 else 1.0


static func quality_weight(id: StringName) -> float:
	var entry: Array = KINDS.get(id, [])
	return float(entry[2]) if entry.size() > 2 else 1.0


static func patience(id: StringName) -> float:
	var entry: Array = KINDS.get(id, [])
	return float(entry[3]) if entry.size() > 3 else 1.0


static func colour(id: StringName) -> Color:
	var entry: Array = KINDS.get(id, [])
	return entry[4] if entry.size() > 4 else Color(0.5, 0.5, 0.55)


## Picks who turned up, from whatever mix the business type attracts.
static func pick(business: BusinessInstance, rng: RandomNumberGenerator) -> StringName:
	var definition := business.type_data() if business != null else null
	var weights: Dictionary = DEFAULT_WEIGHTS
	if definition != null and not definition.archetype_weights.is_empty():
		weights = definition.archetype_weights

	var total := 0.0
	for id: StringName in weights:
		total += maxf(float(weights[id]), 0.0)
	if total <= 0.0:
		return WORKER
	var roll := rng.randf() * total
	for id: StringName in weights:
		roll -= maxf(float(weights[id]), 0.0)
		if roll <= 0.0:
			return id
	return WORKER
