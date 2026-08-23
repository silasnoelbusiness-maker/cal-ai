class_name HelpTopics
extends RefCounted

## The guide, as plain sentences.
##
## §84 asks for a help screen that explains the systems; §85 that it be
## readable rather than exhaustive. So this is prose, not a key map — the
## controls screen already lists the keys, and repeating them here would go
## stale the first time one moved.
##
## Every line describes something the game actually does. If a line here stops
## being true, the line is the bug.


static func sections() -> Array[Dictionary]:
	return [
		{
			"title": "Money",
			"lines": [
				"Wages, deliveries and shop takings are legal income. Anything from a job you were offered in a back room is not, and the difference is on your record for good.",
				"Cash in hand is not net worth. Property, vehicles, stock and business value all count, and so do the loans against them.",
			],
		},
		{
			"title": "Work",
			"lines": [
				"Job stations run to opening hours and cap how many shifts they will give you in a day. Come back tomorrow, or find another.",
				"Shifts cost time and energy. Eat and sleep or the pay gets worse.",
			],
		},
		{
			"title": "Business",
			"lines": [
				"You rent a unit, fit it out, stock it and hire. Customers arrive when you are open and staffed; an empty shop still pays rent.",
				"A manager runs a shop while you are elsewhere — restocking, positioning staff and calling in cover. They cost more than they earn until the shop is big enough to need one.",
				"Brands group shops under one name and lift trade across all of them.",
			],
		},
		{
			"title": "Property",
			"lines": [
				"Renting a home is a weekly bill. Buying one is a mortgage, and missing payments starts a foreclosure that you can still cure.",
				"Property you own can be let to tenants, occupied by you, or used by your own businesses.",
			],
		},
		{
			"title": "The police",
			"lines": [
				"Crimes are reported by whoever sees them. No witness, no report — but cameras and passers-by count as witnesses.",
				"Stars measure what the police are willing to spend on you. Breaking line of sight starts an escape; being seen again ends it.",
				"Getting away clears the heat on that incident. It does not clear your record.",
			],
		},
		{
			"title": "Courts and record",
			"lines": [
				"Serious arrests come with a court date. Turn up and the outcome depends on your record and your counsel; miss it and it is treated as the worst version of itself.",
				"A record makes landlords, lenders and employers harder work. It never takes anything you already own away from you.",
				"Old convictions fade. They never quite disappear.",
			],
		},
		{
			"title": "The underworld",
			"lines": [
				"Contacts deal with you at all only once your name means something, and each one keeps their own opinion of you separately.",
				"Finished jobs build trust and open better work from that contact. Failed and abandoned jobs cost it.",
			],
		},
		{
			"title": "Goals",
			"lines": [
				"Goals are suggestions, not a skill tree. Nothing is locked, nothing is lost by ignoring them, and the legal and criminal ladders can both be climbed at once.",
				"Pin up to three and they show on the HUD. Pin nothing and the game suggests what you are closest to.",
			],
		},
	]
