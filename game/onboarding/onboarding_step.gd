class_name OnboardingStep
extends RefCounted

## One instruction in the opening sequence.
##
## §71 — the tutorial teaches by asking the player to do the real thing, so a
## step has no scripted sequence of its own. It is a sentence and a condition,
## and the condition is checked against the same live game state everything
## else reads.
##
## Two kinds of condition, deliberately no more:
##   METRIC — a number the game already tracks passed a threshold. Anything
##            ProgressionManager can answer works here for free.
##   FLAG   — something happened that is not a number, reported by one line at
##            the place it happens.

enum Trigger { METRIC, FLAG }

var step_id: StringName = &""
var title: String = ""
var instruction: String = ""
## The extra sentence shown if the player sits on a step for a while (§78).
var hint: String = ""
var trigger: Trigger = Trigger.FLAG
## For METRIC: what to ask and how much. For FLAG: the flag's name in `key`.
var key: StringName = &""
var target: float = 1.0
## A step the player can be past before they reach it — §75's smart skipping.
## An always-skippable step never blocks the chain.
var can_be_already_done: bool = true


static func metric(
	id: StringName, name: String, text: String, what: StringName,
	amount: float, tip: String = ""
) -> OnboardingStep:
	var step := OnboardingStep.new()
	step.step_id = id
	step.title = name
	step.instruction = text
	step.hint = tip
	step.trigger = Trigger.METRIC
	step.key = what
	step.target = amount
	return step


static func flag(
	id: StringName, name: String, text: String, what: StringName,
	tip: String = "", retroactive: bool = false
) -> OnboardingStep:
	var step := OnboardingStep.new()
	step.step_id = id
	step.title = name
	step.instruction = text
	step.hint = tip
	step.trigger = Trigger.FLAG
	step.key = what
	# A flag is a moment, not a state, so by default having done it before the
	# step was reached does not count. Steps that describe something the player
	# obviously already knows how to do opt in.
	step.can_be_already_done = retroactive
	return step
