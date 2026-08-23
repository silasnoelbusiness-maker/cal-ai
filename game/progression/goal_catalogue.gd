class_name GoalCatalogue
extends RefCounted

## Every goal in the game, as one table.
##
## §87–§92 give the legal ladder and §93 the criminal one; §100–§105 give the
## long-term targets. They are all here because a goal is a line of data, and
## having them in one place is what makes §95's "show a few, not forty" a
## selection problem rather than an architecture problem.
##
## §99 and §107 — none of this ends the game. The last rung is a prestige
## marker and the sandbox carries on.


static func all() -> Array[Goal]:
	var L := Goal.Track.LEGAL
	var C := Goal.Track.CRIMINAL
	var T := Goal.Tier
	return [
		# --- §87 Starting out ---------------------------------------------
		Goal.make(&"first_shift", "Work a shift", "Any job will do to begin with.",
			L, T.STARTING, &"shifts_worked", 1),
		Goal.make(&"first_1k", "Earn your first $1,000", "Wages, deliveries, anything.",
			L, T.STARTING, &"lifetime_income", 1000, true),
		Goal.make(&"first_vehicle", "Get a vehicle", "Walking the city gets old.",
			L, T.STARTING, &"vehicles_owned", 1),
		Goal.make(&"cash_5k", "Put $5,000 aside", "Enough to start something.",
			L, T.STARTING, &"cash", 5000, true),

		# --- §88 Entrepreneur ---------------------------------------------
		Goal.make(&"first_business", "Open your first business",
			"Lease a unit, fit it out, open the doors.",
			L, T.ENTREPRENEUR, &"businesses", 1),
		Goal.make(&"serve_25", "Serve 25 customers", "Somebody has to buy something.",
			L, T.ENTREPRENEUR, &"customers_served", 25),
		Goal.make(&"first_employee", "Hire your first employee",
			"You cannot stand behind the counter forever.",
			L, T.ENTREPRENEUR, &"employees", 1),
		Goal.make(&"worth_25k", "Reach $25,000 net worth", "",
			L, T.ENTREPRENEUR, &"net_worth", 25000, true),

		# --- §89 Business owner -------------------------------------------
		Goal.make(&"two_businesses", "Own two businesses", "One is a job. Two is a company.",
			L, T.OWNER, &"businesses", 2),
		Goal.make(&"first_manager", "Put a manager in charge",
			"So a branch runs when you are not in it.",
			L, T.OWNER, &"managers", 1),
		Goal.make(&"company_100k", "Reach $100,000 company value", "",
			L, T.OWNER, &"company_value", 100000, true),
		Goal.make(&"first_property", "Buy your first property", "",
			L, T.OWNER, &"properties", 1),

		# --- §90 Chief executive ------------------------------------------
		Goal.make(&"five_locations", "Run five locations", "",
			L, T.CEO, &"businesses", 5),
		Goal.make(&"twentyfive_staff", "Employ twenty-five people", "",
			L, T.CEO, &"employees", 25),
		Goal.make(&"own_warehouse", "Take on a warehouse",
			"Stock has to live somewhere.", L, T.CEO, &"warehouses", 1),
		Goal.make(&"three_brands", "Run three brands", "",
			L, T.CEO, &"brands", 3),
		Goal.make(&"company_500k", "Reach $500,000 company value", "",
			L, T.CEO, &"company_value", 500000, true),

		# --- §91 Tycoon ----------------------------------------------------
		Goal.make(&"worth_1m", "Reach $1,000,000 net worth", "",
			L, T.TYCOON, &"net_worth", 1000000, true),
		Goal.make(&"three_properties", "Hold three properties", "",
			L, T.TYCOON, &"properties", 3),
		Goal.make(&"premium_home", "Live somewhere worth living",
			"A premium residence.", L, T.TYCOON, &"lifestyle", 70),
		Goal.make(&"garage_collection", "Keep four vehicles", "",
			L, T.TYCOON, &"vehicles_owned", 4),
		# §105 — the interesting one, because it argues with leverage.
		Goal.make(&"debt_free", "Owe nobody anything",
			"No loans, no mortgages, at six figures of net worth.",
			L, T.TYCOON, &"debt_free_wealth", 1),

		# --- §92 and §106 Capital mogul ------------------------------------
		Goal.make(&"worth_5m", "Reach $5,000,000 net worth", "",
			L, T.MOGUL, &"net_worth", 5000000, true),
		Goal.make(&"street_capital", "STREET CAPITAL",
			"Ten million, and a city that knows your name.",
			L, T.MOGUL, &"net_worth", 10000000, true),

		# --- §93 The other ladder ------------------------------------------
		Goal.make(&"meet_contact", "Meet somebody who deals",
			"There is a lock-up on the dock road.",
			C, T.STARTING, &"contacts_known", 1),
		Goal.make(&"first_illegal_job", "Finish a job for them", "",
			C, T.STARTING, &"illegal_jobs", 1),
		Goal.make(&"street_known", "Become known on the street", "",
			C, T.ENTREPRENEUR, &"criminal_reputation",
			float(CriminalReputation.TIER_THRESHOLDS[1])),
		Goal.make(&"escape_three", "Lose them at three stars", "",
			C, T.ENTREPRENEUR, &"best_escape", 3),
		Goal.make(&"trust_45", "Have somebody trust you", "Forty-five with one contact.",
			C, T.OWNER, &"best_trust", 45),
		Goal.make(&"vehicle_request", "Fill a premium vehicle order", "",
			C, T.OWNER, &"requests_filled", 1),
		Goal.make(&"established", "Become established", "",
			C, T.CEO, &"criminal_reputation",
			float(CriminalReputation.TIER_THRESHOLDS[3])),
		Goal.make(&"illegal_100k", "Earn $100,000 outside the law", "",
			C, T.CEO, &"illegal_income", 100000, true),
		Goal.make(&"escape_five", "Lose them at five stars",
			"The whole shift, and you walk away.",
			C, T.TYCOON, &"best_escape", 5),
		Goal.make(&"notorious", "Become notorious", "",
			C, T.TYCOON, &"criminal_reputation",
			float(CriminalReputation.TIER_THRESHOLDS[4])),
		Goal.make(&"inner_circle", "Get inside somebody's circle",
			"Ninety trust with one contact.",
			C, T.MOGUL, &"best_trust", 90),
	]


static func by_id(id: StringName) -> Goal:
	for goal in all():
		if goal.goal_id == id:
			return goal
	return null


static func for_track(track: Goal.Track) -> Array[Goal]:
	var found: Array[Goal] = []
	for goal in all():
		if goal.track == track:
			found.append(goal)
	return found
