class_name LegalDebug
extends RefCounted

## Development-only entry points for Phase R's legal and underworld systems.
##
## §132. Everything here drives the real code path rather than setting the state
## it wants — Phase Q taught that lesson twice, when a debug helper reached a
## state by the back door and the tests written against it verified something
## the game itself never produced. So `create_arrest` really arrests, and
## `resolve_court` really goes through the one-outcome guard.

## Files an arrest of a given seriousness, without needing a pursuit. Goes
## through the same note_arrest the bust uses.
static func create_arrest(
	severity: CrimeData.Severity = CrimeData.Severity.SERIOUS,
	wanted_level: int = 3
) -> ArrestRecord:
	var fine := WantedManager.fine_by_level(wanted_level)
	return LegalManager.note_arrest(wanted_level, severity, fine, fine, 0, false)


## An arrest that names a real crime, so the record reads like a record. The
## crime is filed first and the arrest then aggregates it exactly as a pursuit
## would.
static func create_case(
	type: int = CrimeManager.CrimeType.ROBBERY, wanted_level: int = 4
) -> LegalCase:
	var player := GameManager.player
	var at := player.global_position if player != null else Vector3.ZERO
	CrimeManager.report_crime(type, at, player, null)
	var arrest := create_arrest(CrimeData.severity_of(type), wanted_level)
	return LegalManager.case_by_id(arrest.case_id)


## Moves the next hearing to today so it can be sat without waiting four days.
static func schedule_court_now() -> LegalCase:
	var case := LegalManager.next_case()
	if case == null:
		return null
	case.court_day = TimeManager.day_index
	case.court_hour = TimeManager.hour
	return case


static func resolve_court(attend: bool = true) -> LegalCase:
	var case := LegalManager.next_case()
	if case == null:
		return null
	LegalManager.resolve_case(case, attend)
	return case


## Walks the clock past a listed hearing so the missed-court path runs for
## real, rather than setting the counter it increments.
static func miss_court() -> void:
	var case := LegalManager.next_case()
	if case == null:
		return
	var days := maxi(case.days_until(TimeManager.day_index), 0) + 1
	TimeManager.advance_minutes(days * 1440)


## Arrests repeatedly until the record reaches a tier. Used by the tests that
## care about what a tier does rather than about how it is reached.
static func set_record_tier(tier: CriminalRecord.Tier) -> void:
	var guard := 0
	while LegalManager.tier() < tier and guard < 40:
		guard += 1
		create_arrest(CrimeData.Severity.EXTREME, 5)


static func set_legal_debt(amount: int) -> void:
	LegalManager.legal_debt = 0
	LegalManager.add_legal_debt(amount)


static func retain(id: StringName) -> bool:
	return LegalManager.retain(id)


static func trigger_scandal(magnitude: float = 6.0) -> void:
	CompanyManager.apply_owner_scandal(magnitude, "Debug scandal")


static func clear_scandal() -> void:
	CompanyManager.scandal_penalty = 0.0
	CompanyManager.scandal_until_day = -1
	CompanyManager.scandal_reason = ""


# --- Underworld ----------------------------------------------------------

static func set_trust(contact_id: StringName, value: int) -> void:
	var link := Underworld.relationship(contact_id)
	link.trust = clampi(value, 0, ContactRelationship.MAX_TRUST)
	Underworld._review_chains(contact_id)


## Raises trust until the next rung of this contact's ladder opens.
static func advance_chain(contact_id: StringName) -> JobChain:
	var next_rung := Underworld.next_chain_for(contact_id)
	if next_rung == null:
		return Underworld.chain_for(contact_id)
	if Underworld.reputation < next_rung.reputation_required:
		Underworld.add_reputation(next_rung.reputation_required - Underworld.reputation)
	set_trust(contact_id, next_rung.trust_required)
	return Underworld.chain_for(contact_id)


static func post_request(contact_id: StringName) -> ContactRequest:
	return Underworld.post_request(CriminalContactData.by_id(contact_id))


static func generate_board(contact_id: StringName) -> Array[IllegalJobData]:
	return Underworld.refresh_board(CriminalContactData.by_id(contact_id))


## Finishes whatever is running, through the real completion path.
static func complete_active_job() -> IllegalJobData:
	var job := Underworld.active_job()
	if job == null:
		return null
	Underworld.note_objective(job.objective, job.target_id, job.target_quantity)
	return job
