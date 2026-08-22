class_name CriminalReputation
extends RefCounted

## What the street thinks of the player.
##
## Deliberately its own number, separate from business reputation, brand
## reputation, lifestyle and net worth (§78). A player can be a respected
## restaurateur and a nobody to the underworld, or the reverse, and neither
## should leak into the other — that separation is most of what makes running
## both lives at once interesting.
##
## Nought to a hundred, in five named tiers. The tiers are what unlock things;
## the number is what moves. §80 sets the shape of the gains: doing a job
## properly is worth something, and hurting people at random is not.

enum Tier { UNKNOWN, STREET_KNOWN, CONNECTED, ESTABLISHED, NOTORIOUS }

const TIER_NAMES := {
	Tier.UNKNOWN: "UNKNOWN",
	Tier.STREET_KNOWN: "STREET KNOWN",
	Tier.CONNECTED: "CONNECTED",
	Tier.ESTABLISHED: "ESTABLISHED",
	Tier.NOTORIOUS: "NOTORIOUS",
}

## Reputation at which each tier begins. Index matches the enum.
const TIER_THRESHOLDS: Array[int] = [0, 15, 35, 60, 85]

const MAX_REPUTATION := 100


static func tier_for(value: int) -> Tier:
	var reached := Tier.UNKNOWN
	for candidate in range(TIER_THRESHOLDS.size()):
		if value >= TIER_THRESHOLDS[candidate]:
			reached = candidate as Tier
	return reached


static func tier_name(tier: Tier) -> String:
	return String(TIER_NAMES.get(tier, "UNKNOWN"))


static func name_for(value: int) -> String:
	return tier_name(tier_for(value))


## Reputation needed for the next tier, or -1 at the top.
static func next_threshold(value: int) -> int:
	for candidate in range(TIER_THRESHOLDS.size()):
		if value < TIER_THRESHOLDS[candidate]:
			return TIER_THRESHOLDS[candidate]
	return -1


## How far through the current tier, 0-1, for a bar to draw.
static func progress(value: int) -> float:
	var next := next_threshold(value)
	if next < 0:
		return 1.0
	var floor_value := TIER_THRESHOLDS[int(tier_for(value))]
	var span := maxi(next - floor_value, 1)
	return clampf(float(value - floor_value) / float(span), 0.0, 1.0)


## What a fence pays, as a fraction of what the goods are worth. §67 — thirty
## per cent to a stranger, sixty to somebody with a name. The spread is the
## reason building a reputation is worth doing at all.
static func fence_rate(value: int) -> float:
	return lerpf(0.30, 0.60, clampf(float(value) / float(MAX_REPUTATION), 0.0, 1.0))
