class_name Goal
extends RefCounted

## One thing worth working toward.
##
## §86 is explicit that this is guidance rather than a locked skill tree, and
## §94 that the two tracks coexist — a player can be building a company and a
## reputation at the same time and neither closes the other off. So a goal has
## no prerequisites beyond a tier, nothing is ever locked, and completing one
## grants nothing but the acknowledgement.
##
## Goals are data. A goal is a metric, a number, and a sentence; the metric
## itself is read by ProgressionManager, which is the only file that knows how
## to ask the rest of the game a question.

enum Track { LEGAL, CRIMINAL }

## §87–§92 for the legal ladder, §93 for the criminal one.
enum Tier { STARTING, ENTREPRENEUR, OWNER, CEO, TYCOON, MOGUL }

const TIER_NAMES := {
	Tier.STARTING: "Starting out",
	Tier.ENTREPRENEUR: "Entrepreneur",
	Tier.OWNER: "Business owner",
	Tier.CEO: "Chief executive",
	Tier.TYCOON: "Tycoon",
	Tier.MOGUL: "Capital mogul",
}

const CRIMINAL_TIER_NAMES := {
	Tier.STARTING: "Nobody",
	Tier.ENTREPRENEUR: "Known on the street",
	Tier.OWNER: "Connected",
	Tier.CEO: "Established",
	Tier.TYCOON: "Notorious",
	Tier.MOGUL: "Untouchable",
}

var goal_id: StringName = &""
var label: String = "Goal"
var detail: String = ""
var track: Track = Track.LEGAL
var tier: Tier = Tier.STARTING
## What to ask the game, and what answer completes this.
var metric: StringName = &"cash"
var target: float = 0.0
## Whether the number is money, so the screen can format it.
var is_money: bool = false


static func make(
	id: StringName, name: String, text: String, which: Track, rung: Tier,
	key: StringName, amount: float, money: bool = false
) -> Goal:
	var goal := Goal.new()
	goal.goal_id = id
	goal.label = name
	goal.detail = text
	goal.track = which
	goal.tier = rung
	goal.metric = key
	goal.target = amount
	goal.is_money = money
	return goal


static func tier_name(which: Track, rung: Tier) -> String:
	var table := CRIMINAL_TIER_NAMES if which == Track.CRIMINAL else TIER_NAMES
	return String(table.get(rung, "Starting out"))


func track_name() -> String:
	return "Criminal" if track == Track.CRIMINAL else "Legal"


## How far along, 0–1.
func progress(value: float) -> float:
	if target <= 0.0:
		return 1.0
	return clampf(value / target, 0.0, 1.0)


func is_met(value: float) -> bool:
	return value >= target
