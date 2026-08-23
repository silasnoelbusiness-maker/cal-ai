class_name OnboardingChain
extends RefCounted

## The opening sequence, in order.
##
## §70 — short. Seven steps, none of them a wall of text, and the last one
## hands the player over to the goal list rather than to another tutorial.
## §73 — every one of them is a thing they will keep doing all game; nothing
## here exists only to be tutorialised.


static func steps() -> Array[OnboardingStep]:
	return [
		OnboardingStep.flag(
			&"open_map", "Get your bearings",
			"Open the city map.",
			&"map_opened",
			"Press M.",
			true
		),
		OnboardingStep.metric(
			&"work_shift", "Find work",
			"Take a shift at any job in the city.",
			&"shifts_worked", 1.0,
			"Jobs are marked on the map. Walk up and interact."
		),
		OnboardingStep.metric(
			&"first_money", "Put money aside",
			"Get $200 to your name.",
			&"cash", 200.0,
			"Another shift or two will do it."
		),
		OnboardingStep.flag(
			&"buy_food", "Eat something",
			"Buy food from a shop.",
			&"food_bought",
			"Hunger drains all day. Shops sell what fixes it.",
			true
		),
		OnboardingStep.flag(
			&"sleep", "Get some sleep",
			"Sleep the night at your flat.",
			&"slept",
			"Your bed is at home. Sleeping restores energy.",
			true
		),
		OnboardingStep.flag(
			&"check_profile", "Take stock",
			"Open your profile to see where you stand.",
			&"profile_opened",
			"Press P.",
			true
		),
		OnboardingStep.flag(
			&"pin_goal", "Decide what you want",
			"Pin a goal to work toward.",
			&"goal_pinned",
			"The goals screen lists both ways up. Pin up to three.",
			true
		),
	]
