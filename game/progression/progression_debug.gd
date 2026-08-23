class_name ProgressionDebug
extends RefCounted

## Development-only entry points for the Phase S systems.
##
## Same rule as the legal debug: everything here drives the real code path
## rather than setting the state it wants. `reach_goal` does not mark a goal
## done — it moves the number the goal is watching until the goal notices, so a
## test written against this is testing the game and not the helper.


## Moves the metric a goal watches far enough to complete it, where the metric
## is one a helper can honestly move. Returns whether it worked; a goal about
## net worth or the underworld says no rather than lying about it.
static func reach_goal(goal_id: StringName) -> bool:
	var goal := Progression.goal_by_id(goal_id)
	if goal == null or Progression.is_complete(goal_id):
		return false
	match goal.metric:
		&"shifts_worked":
			LifeStats.add(&"shifts_worked", int(ceil(goal.target)))
		&"cash", &"lifetime_income":
			EconomyManager.deposit(
				int(ceil(goal.target)), "Debug", EconomyManager.Source.LEGAL
			)
		_:
			return false
	Progression.evaluate()
	return Progression.is_complete(goal_id)


## Walks the opening guide to its end through the real reports, so the state
## it leaves behind is one the game could actually have produced.
static func finish_onboarding() -> void:
	var guard := 0
	while Onboarding.is_running() and guard < 40:
		guard += 1
		var step: OnboardingStep = Onboarding.current()
		if step == null:
			return
		if step.trigger == OnboardingStep.Trigger.FLAG:
			Onboarding.report(step.key)
			continue
		# A metric step: move the number rather than faking the step.
		match step.key:
			&"shifts_worked":
				LifeStats.add(&"shifts_worked", int(ceil(step.target)))
			&"cash":
				EconomyManager.deposit(
					int(ceil(step.target)), "Debug", EconomyManager.Source.LEGAL
				)
			_:
				# Nothing honest to move. Skipping is what a player would do.
				Onboarding.skip()
				return
		Onboarding.report(&"_tick")


## A readable dump of where the player stands, for the console.
static func summary() -> String:
	var lines := PackedStringArray()
	lines.append("LEGAL   %s" % Goal.tier_name(
		Goal.Track.LEGAL, Progression.tier_on(Goal.Track.LEGAL)
	))
	lines.append("CRIMINAL %s" % Goal.tier_name(
		Goal.Track.CRIMINAL, Progression.tier_on(Goal.Track.CRIMINAL)
	))
	lines.append("goals    %d of %d" % [
		Progression.completed_count(), Progression.all_goals().size()
	])
	lines.append("guide    %s" % (
		"step %d/%d" % [Onboarding.step_number(), Onboarding.step_count()]
		if Onboarding.is_running()
		else ("skipped" if Onboarding.was_skipped() else "done")
	))
	for goal in Progression.pinned():
		lines.append("  pinned %s  %.0f/%.0f" % [
			goal.label, Progression.value_for(goal.metric), goal.target
		])
	for group: StringName in LifeStats.COUNTERS:
		var parts := PackedStringArray()
		for entry in LifeStats.COUNTERS[group]:
			parts.append("%s %d" % [entry[0], LifeStats.get_counter(entry[0])])
		lines.append("%-8s %s" % [group, "  ".join(parts)])
	return "\n".join(lines)
