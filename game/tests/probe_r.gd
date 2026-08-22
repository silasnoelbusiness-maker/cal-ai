extends Node

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	for i in 60:
		await get_tree().physics_frame

	EconomyManager.restore(200000)
	print("day=", TimeManager.day_index, " tier=", LegalManager.tier_name())

	# A minor incident: shoplifting, arrested at one star.
	UnderworldDebug.force_report(CrimeManager.CrimeType.SHOPLIFTING)
	await get_tree().physics_frame
	WantedManager.set_level(1)
	WantedManager.request_bust()
	for i in 260:
		await get_tree().physics_frame
	print("--- after minor ---")
	print("arrests=", LegalManager.record.arrest_count(),
		" cases=", LegalManager.record.cases.size(),
		" tier=", LegalManager.tier_name(),
		" pressure=", LegalManager.pressure())
	var a1 := LegalManager.record.arrests[0]
	print("  headline=", a1.headline(), " sev=", a1.severity_name(),
		" release=", a1.release_cost, " case=", a1.case_id)

	# A serious incident: robbery, arrested at four stars.
	UnderworldDebug.force_report(CrimeManager.CrimeType.ROBBERY)
	await get_tree().physics_frame
	WantedManager.set_level(4)
	WantedManager.request_bust()
	for i in 260:
		await get_tree().physics_frame
	print("--- after serious ---")
	print("arrests=", LegalManager.record.arrest_count(),
		" cases=", LegalManager.record.cases.size(),
		" tier=", LegalManager.tier_name(),
		" pressure=", LegalManager.pressure(),
		" debt=", LegalManager.legal_debt)
	var case := LegalManager.next_case()
	if case != null:
		print("  case=", case.title, " day=", case.court_day,
			" today=", TimeManager.day_index, " sev=", case.severity_name())
		var ok := LegalManager.resolve_case(case, true)
		print("  resolved=", ok, " outcome=", case.outcome_name(),
			" fine=", case.fine_applied, " costs=", case.costs_applied)
		print("  again=", LegalManager.resolve_case(case, true))
	print("modifier=", LegalManager.record_modifier())
	get_tree().quit(0)
