extends Node

## What the game remembers, and what it does about it.
##
## Autoload `LegalManager`. One owner for the criminal record, the cases, the
## money owed the courts, and every question the rest of the game asks about any
## of it. §110, §111 and §112 all say the same thing in different words: finance,
## property and jobs must *ask* rather than each working out what a record
## means, so all of that lives here.
##
## The shape of Phase R in one place:
##
##   an arrest happens  ->  note_arrest() folds the pursuit into one incident
##                      ->  a release cost is taken, or becomes a balance owed
##                      ->  a serious incident opens a case with a date
##   days pass          ->  one reminder, then the hearing, then one outcome
##   other systems ask  ->  record_modifier(), and nothing else
##
## §3 is the rule everything below obeys: friction, never demolition. Nothing
## here deletes a business, a property, a vehicle or an employee.

signal arrest_recorded(record: ArrestRecord)
signal case_opened(case: LegalCase)
signal case_resolved(case: LegalCase)
signal case_missed(case: LegalCase)
signal court_reminder(case: LegalCase)
signal record_tier_changed(tier: CriminalRecord.Tier)
signal legal_debt_changed(amount: int)

## Days between a serious arrest and the hearing it books. Long enough that the
## player goes back to running things and the date arrives while they are busy,
## which is the tension §97 is after.
const COURT_DELAY_DAYS := 4
const COURT_HOUR := 12
## How long after the listed hour the court gives up waiting.
const COURT_GRACE_HOURS := 2

## Hours in custody the legal side adds on top of Phase Q's wanted-level time,
## by severity. A serious incident costs most of a working day.
const EXTRA_HOURS := [0, 0, 2, 4, 6]

## The bill for the day in court, whatever the outcome. Not a punishment band of
## its own.
const COURT_COSTS := 350

## What a fine is scaled from. Multiplied by the severity surcharge Phase Q
## already publishes, then by the outcome band.
const FINE_BASE := 900.0

var legal_debt: int = 0
var record: CriminalRecord = CriminalRecord.new()
## Which service is retained for the next hearing. §30 — chosen up front, read
## once when a case resolves.
var counsel_id: StringName = &"public_counsel"

var save_id: StringName = &"legal"
var reset_on_missing_save: bool = true

## Offences reported since the current wanted level began. §7 — one pursuit is
## one incident, so these accumulate and are drained by the arrest.
var _incident: Array[Dictionary] = []
var _next_arrest: int = 1
var _next_case: int = 1
var _last_tier: CriminalRecord.Tier = CriminalRecord.Tier.CLEAN
## Guard so a hearing cannot be resolved twice by two callers in one frame.
var _resolving: bool = false


func _ready() -> void:
	add_to_group(&"saveable")
	CrimeManager.crime_reported.connect(_on_crime_reported)
	WantedManager.wanted_cleared.connect(_on_wanted_cleared)
	TimeManager.hour_passed.connect(_on_hour_passed)


# --- The incident --------------------------------------------------------

## Every crime filed while the player is wanted belongs to the same incident: a
## theft, the escape and the robbery at the end of it are one arrest, not three.
func _on_crime_reported(crime: Dictionary) -> void:
	_incident.append(crime)


## Getting away with it ends the incident. Only an arrest turns it into a
## record, so a clean escape leaves nothing behind.
func _on_wanted_cleared() -> void:
	if not WantedManager.is_busting():
		_incident.clear()


func current_incident() -> Array[Dictionary]:
	return _incident.duplicate()


# --- Arrest --------------------------------------------------------------

## Turns the incident into a record entry, and opens a case if it was serious.
##
## Called by WantedManager during the arrest, after the roadside fine has been
## taken: the fine is Phase Q's and the record is ours. Everything downstream
## reads the ArrestRecord this returns.
func note_arrest(
	wanted_level: int, band: CrimeData.Severity, fine_charged: int, fine_paid: int,
	goods_taken: int, stolen_vehicle: bool
) -> ArrestRecord:
	var worst := _incident_severity(band)
	var arrest := ArrestRecord.make(
		StringName("arrest_%d" % _next_arrest), TimeManager.day_index,
		int(TimeManager.total_minutes) % 1440, wanted_level,
		_incident_offences(), worst
	)
	_next_arrest += 1
	arrest.fine_charged = fine_charged
	arrest.fine_paid = fine_paid
	arrest.goods_confiscated = goods_taken
	arrest.stolen_vehicle_recovered = stolen_vehicle
	arrest.publicly_identified = _was_identified()
	arrest.release_cost = release_cost_for(worst, wanted_level)

	record.arrests.append(arrest)
	record.total_fines_paid += fine_paid
	_incident.clear()

	_take_release_cost(arrest)
	if LegalSeverity.needs_case(worst):
		_open_case(arrest)

	arrest_recorded.emit(arrest)
	_review_tier()
	return arrest


## What buying your way out costs. Severity sets the multiple, the level it
## happened at sets the base, recent history pushes it up, retained counsel
## takes a little off.
func release_cost_for(band: CrimeData.Severity, wanted_level: int) -> int:
	var multiplier := LegalSeverity.release_multiplier(band)
	if multiplier <= 0.0:
		return 0
	var base := float(WantedManager.fine_by_level(wanted_level)) * multiplier
	base *= 1.0 + 0.08 * float(record.recent_arrests(TimeManager.day_index, 60))
	base *= 1.0 - LegalService.by_id(counsel_id).release_relief
	return maxi(roundi(base), 0)


## §17 — never a soft-lock. What cannot be paid becomes a balance owed, and the
## player still walks out.
func _take_release_cost(arrest: ArrestRecord) -> void:
	if arrest.release_cost <= 0:
		return
	var paid: int = mini(arrest.release_cost, EconomyManager.cash)
	if paid > 0:
		EconomyManager.spend(paid, "Release cost", EconomyManager.Source.LEGAL)
	record.total_legal_costs += paid
	add_legal_debt(arrest.release_cost - paid)


## Hours the legal side adds to Phase Q's custody time. §10 — repeat serious
## offending costs longer and still never becomes a sentence. There is no
## prison in Phase R and the player is always playable afterwards.
func extra_custody_hours(band: CrimeData.Severity) -> int:
	var hours := int(EXTRA_HOURS[clampi(int(band), 0, EXTRA_HOURS.size() - 1)])
	if record.count_of_severity(band) > 2:
		hours += 2
	return hours


## Whether anybody could say who it was. A crime nobody linked to the player is
## on the record but is not a public scandal — §45.
func _was_identified() -> bool:
	for crime in _incident:
		if bool(crime.get("identified_player", false)):
			return true
	return _incident.is_empty()


func _incident_offences() -> PackedStringArray:
	var names := PackedStringArray()
	var seen := {}
	var ordered := _incident.duplicate()
	ordered.sort_custom(
		func(a, b): return int(a.get("severity", 0)) > int(b.get("severity", 0))
	)
	for crime in ordered:
		# CrimeData's own display name rather than the record's, which is the
		# enum key with the underscores taken out and reads as HIT AND RUN.
		var data := CrimeData.for_type(int(crime.get("type", 0)))
		var label := (
			data.display_name if data != null and data.display_name != ""
			else String(crime.get("type_name", "Offence"))
		)
		if seen.has(label):
			continue
		seen[label] = true
		names.append(label)
	if names.is_empty():
		names.append("Arrested on suspicion")
	return names


## The band the whole incident is judged at: the worst single thing in it, or
## whatever Phase Q had already decided if nothing was filed.
func _incident_severity(fallback: CrimeData.Severity) -> CrimeData.Severity:
	var worst := fallback
	for crime in _incident:
		var band := CrimeData.severity_of(int(crime.get("type", 0)))
		if band > worst:
			worst = band
	return worst


# --- Cases ---------------------------------------------------------------

func _open_case(arrest: ArrestRecord) -> void:
	var case := LegalCase.make(
		StringName("case_%d" % _next_case), arrest.arrest_id,
		arrest.headline(), arrest.severity,
		TimeManager.day_index + COURT_DELAY_DAYS, COURT_HOUR
	)
	_next_case += 1
	case.counsel_id = counsel_id
	arrest.case_id = case.case_id
	record.cases.append(case)
	GameManager.notify(
		"CASE OPENED\n%s  ·  court in %d days" % [case.title.to_upper(), COURT_DELAY_DAYS],
		GameManager.Tone.BAD
	)
	AudioManager.play(&"case_opened", AudioBuses.SFX, -10.0)
	case_opened.emit(case)


func open_cases() -> Array[LegalCase]:
	return record.open_cases()


func next_case() -> LegalCase:
	return record.next_case(TimeManager.day_index)


func case_by_id(id: StringName) -> LegalCase:
	return record.case_by_id(id)


## Whether a hearing can be sat right now — the date is today and the hour has
## come. What the courthouse door asks before it opens the screen.
func case_ready_now() -> LegalCase:
	var today := TimeManager.day_index
	var hour := TimeManager.hour
	for case in record.cases:
		if case.is_due(today, hour):
			return case
	return null


## Settles a case. §104 — one outcome, ever. A case already settled returns
## false and changes nothing, whatever asked and however many times.
func resolve_case(case: LegalCase, attended: bool) -> bool:
	if case == null or case.is_settled() or _resolving:
		return false
	_resolving = true
	var service := LegalService.by_id(case.counsel_id)
	case.attended = attended
	case.outcome = _decide_outcome(case, service, attended)

	case.fine_applied = _fine_for(case, service)
	case.costs_applied = 0 if case.outcome == LegalCase.Outcome.DISMISSED else COURT_COSTS
	_charge(case.fine_applied + case.costs_applied)
	record.total_fines_paid += case.fine_applied
	record.total_legal_costs += case.costs_applied

	case.status = (
		LegalCase.Status.DISMISSED if case.outcome == LegalCase.Outcome.DISMISSED
		else LegalCase.Status.RESOLVED
	)
	GameManager.notify(
		"CASE RESOLVED\n%s  ·  %s" % [case.title.to_upper(), case.outcome_name()],
		GameManager.Tone.GOOD if case.outcome == LegalCase.Outcome.DISMISSED
		else GameManager.Tone.BAD
	)
	AudioManager.play(&"case_resolved", AudioBuses.SFX, -9.0)
	# §96 — the morning in court is gone from the day whether the player stood
	# in the room or not. Everything TimeManager drives runs through it.
	if attended:
		TimeManager.advance_minutes(120)
	case_resolved.emit(case)
	_review_tier()
	_consider_scandal(case)
	_resolving = false
	return true


## Which band the hearing lands in. §24 — severity, recent history, missed
## dates, attendance, representation and a little variance. No evidence
## simulation, no strategy, and never a guaranteed result.
func _decide_outcome(
	case: LegalCase, service: LegalService, attended: bool
) -> LegalCase.Outcome:
	var score := 0.5
	score -= 0.18 * float(int(case.severity) - int(CrimeData.Severity.SERIOUS))
	score -= 0.04 * float(record.recent_arrests(TimeManager.day_index, 90))
	score -= 0.05 * float(record.missed_court_events)
	score += 0.2 if attended else -0.25
	score += service.outcome_bonus
	score += randf_range(-0.12, 0.12)

	if score >= 0.85:
		return LegalCase.Outcome.DISMISSED
	if score >= 0.6:
		return LegalCase.Outcome.REDUCED
	if score >= 0.3:
		return LegalCase.Outcome.FINE
	return LegalCase.Outcome.HEAVY_FINE


func _fine_for(case: LegalCase, service: LegalService) -> int:
	if case.outcome == LegalCase.Outcome.DISMISSED:
		return 0
	var base := WantedManager.severity_multiplier(case.severity) * FINE_BASE
	match case.outcome:
		LegalCase.Outcome.REDUCED:
			base *= 0.45
		LegalCase.Outcome.HEAVY_FINE:
			base *= 1.8
		_:
			pass
	base *= 1.0 - service.fine_relief
	return maxi(roundi(base), 0)


## Money out, with whatever cannot be covered becoming a balance rather than an
## overdraft or a soft-lock.
func _charge(amount: int) -> void:
	if amount <= 0:
		return
	var paid: int = mini(amount, EconomyManager.cash)
	if paid > 0:
		EconomyManager.spend(paid, "Court", EconomyManager.Source.LEGAL)
	add_legal_debt(amount - paid)


# --- Missed court --------------------------------------------------------

## §25 — ignoring a date costs money and makes the case worse. It does not light
## the city up, and §139: it happens once. The case is relisted rather than
## escaped, because a missed hearing is not a way out.
func _miss_case(case: LegalCase) -> void:
	if case == null or not case.is_open() or case.missed_notice_shown:
		return
	case.missed_notice_shown = true
	record.missed_court_events += 1
	var penalty := 400 + 250 * int(case.severity)
	_charge(penalty)
	case.court_day = TimeManager.day_index + COURT_DELAY_DAYS
	case.reminder_shown = false
	GameManager.notify(
		"COURT MISSED\n%s  ·  -$%s  ·  relisted" % [
			case.title.to_upper(), EconomyManager.with_thousands_separator(penalty)
		],
		GameManager.Tone.BAD
	)
	case_missed.emit(case)
	_review_tier()


# --- The calendar --------------------------------------------------------

func _on_hour_passed(hour: int) -> void:
	var today := TimeManager.day_index
	for case in record.cases:
		if not case.is_open():
			continue
		# §129 and §130 — one reminder, the day before or the morning of.
		if not case.reminder_shown and case.days_until(today) <= 1:
			case.reminder_shown = true
			GameManager.notify(
				"COURT DATE %s\n%s  ·  %s" % [
					"TODAY" if case.days_until(today) <= 0 else "TOMORROW",
					case.title.to_upper(), case.court_time_label()
				],
				GameManager.Tone.INFO
			)
			AudioManager.play(&"court_reminder", AudioBuses.SFX, -12.0)
			court_reminder.emit(case)
		# Sat through the listed hour without turning up.
		var late := today == case.court_day and hour > case.court_hour + COURT_GRACE_HOURS
		if today > case.court_day or late:
			_miss_case(case)


# --- Legal debt ----------------------------------------------------------

## §18 — a balance, not a loan. It does not grow on its own, and nothing
## forecloses on it.
func add_legal_debt(amount: int) -> void:
	if amount <= 0:
		return
	legal_debt += amount
	legal_debt_changed.emit(legal_debt)


## Pays what the player can afford towards the balance. Returns what went.
func pay_legal_debt(amount: int) -> int:
	var wanted: int = clampi(amount, 0, legal_debt)
	var paid: int = mini(wanted, EconomyManager.cash)
	if paid <= 0:
		return 0
	EconomyManager.spend(paid, "Legal balance", EconomyManager.Source.LEGAL)
	legal_debt -= paid
	record.total_legal_costs += paid
	legal_debt_changed.emit(legal_debt)
	return paid


# --- What the record means to everybody else -----------------------------

func tier() -> CriminalRecord.Tier:
	return record.tier(TimeManager.day_index)


func tier_name() -> String:
	return CriminalRecord.tier_name(tier())


func pressure() -> float:
	return record.pressure(TimeManager.day_index)


func has_outstanding_matter() -> bool:
	return record.has_outstanding_matter(TimeManager.day_index)


## 0.0 for a clean player, up to 1.0 at the top of the scale. The single number
## §110-§112 ask for, so no other file has to know what a tier is.
func record_modifier() -> float:
	var value := float(int(tier())) / float(int(CriminalRecord.Tier.HIGH_RISK))
	if has_outstanding_matter():
		value = minf(value + 0.15, 1.0)
	return clampf(value, 0.0, 1.0)


# --- What a landlord, a lender and an employer make of it ----------------

## Rent above which a landlord is the sort to look somebody up. §39 — cheap
## addresses do not care, which is what makes §143 true: a player can always
## put a roof over their head, whatever they have done.
const PREMIUM_RENT := 420
## Above this rent the standards are higher again.
const LUXURY_RENT := 900

## What a landlord makes of the player, for a place at this rent.
##
## Returns `accepted`, any `extra_deposit` they want on top of the usual, and a
## `reason` to show when they say no. §38 — not every landlord asks; §40 — this
## has no bearing on property the player already owns.
func landlord_view(rent_amount: int) -> Dictionary:
	var clean := {"accepted": true, "extra_deposit": 0, "reason": ""}
	if rent_amount < PREMIUM_RENT:
		return clean
	var level := int(tier())
	var bar := 3 if rent_amount >= LUXURY_RENT else 4
	if level >= bar:
		return {
			"accepted": false,
			"extra_deposit": 0,
			"reason": "The landlord ran a check. %s." % tier_name(),
		}
	if level >= bar - 1 or has_outstanding_matter():
		# Not a refusal — a bigger deposit. §39.
		return {
			"accepted": true,
			"extra_deposit": roundi(float(rent_amount) * 1.5),
			"reason": "They want more down, given the check.",
		}
	return clean


## Whether a lender will look at new borrowing, and what it costs extra.
##
## §41 and §43 — existing mortgages and loans are never touched by this. Only a
## fresh application asks, and only a serious record or an unsettled matter
## changes the answer.
func lender_view() -> Dictionary:
	var level := int(tier())
	if has_outstanding_matter() and level >= int(CriminalRecord.Tier.SERIOUS):
		return {
			"accepted": false,
			"deposit_multiplier": 1.0,
			"reason": "A lender will not look at this with a court matter open.",
		}
	if level >= int(CriminalRecord.Tier.REPEAT):
		return {
			"accepted": false,
			"deposit_multiplier": 1.0,
			"reason": "A lender will not look at this. %s." % tier_name(),
		}
	if level >= int(CriminalRecord.Tier.SERIOUS):
		return {
			"accepted": true,
			"deposit_multiplier": 1.35,
			"reason": "They will lend, but they want more down.",
		}
	return {"accepted": true, "deposit_multiplier": 1.0, "reason": ""}


## How much of the candidate pool will not take a job from this owner. §49 —
## modest, and it never empties the pool.
func hiring_penalty() -> float:
	return clampf(record_modifier() * 0.4, 0.0, 0.4)


func _review_tier() -> void:
	var now := tier()
	if now == _last_tier:
		return
	var risen := now > _last_tier
	_last_tier = now
	AudioManager.play(&"record_tier", AudioBuses.SFX, -11.0)
	GameManager.notify(
		"RECORD: %s" % CriminalRecord.tier_name(now).to_upper(),
		GameManager.Tone.BAD if risen else GameManager.Tone.GOOD
	)
	record_tier_changed.emit(now)


# --- Scandal -------------------------------------------------------------

## §44-§46. Only a serious case the city could pin on the player touches the
## company, and even then it is a nudge with an expiry. §116 — never equity.
func _consider_scandal(case: LegalCase) -> void:
	if case.outcome == LegalCase.Outcome.DISMISSED:
		return
	if int(case.severity) < int(CrimeData.Severity.SEVERE):
		return
	var arrest := record.arrest_by_id(case.arrest_id)
	if arrest != null and not arrest.publicly_identified:
		return
	var magnitude := 2.0 + 1.5 * float(int(case.severity) - int(CrimeData.Severity.SEVERE))
	magnitude += 0.5 * float(record.recent_arrests(TimeManager.day_index, 90))
	CompanyManager.apply_owner_scandal(magnitude, case.title)


# --- Representation ------------------------------------------------------

func counsel() -> LegalService:
	return LegalService.by_id(counsel_id)


func retain(id: StringName) -> bool:
	var service := LegalService.by_id(id)
	if service.service_id == counsel_id:
		return false
	if service.cost > 0 and not EconomyManager.can_afford(service.cost):
		GameManager.notify("YOU CANNOT COVER THAT RETAINER", GameManager.Tone.BAD)
		return false
	if service.cost > 0:
		EconomyManager.spend(
			service.cost, "%s — retainer" % service.display_name, EconomyManager.Source.LEGAL
		)
		record.total_legal_costs += service.cost
	counsel_id = service.service_id
	# Only hearings not yet held can benefit. §30 again.
	for case in record.cases:
		if case.is_open():
			case.counsel_id = counsel_id
	GameManager.notify("RETAINED %s" % service.display_name.to_upper(), GameManager.Tone.GOOD)
	return true


# --- Save ----------------------------------------------------------------

func clear() -> void:
	record = CriminalRecord.new()
	legal_debt = 0
	counsel_id = &"public_counsel"
	_incident.clear()
	_next_arrest = 1
	_next_case = 1
	_last_tier = CriminalRecord.Tier.CLEAN


func save_state() -> Dictionary:
	return {
		"record": record.to_dict(),
		"debt": legal_debt,
		"counsel": String(counsel_id),
		"next_arrest": _next_arrest,
		"next_case": _next_case,
	}


func load_state(state: Dictionary) -> void:
	clear()
	var stored: Variant = state.get("record", {})
	if stored is Dictionary:
		record = CriminalRecord.from_dict(stored)
	legal_debt = int(state.get("debt", 0))
	counsel_id = StringName(state.get("counsel", "public_counsel"))
	_next_arrest = int(state.get("next_arrest", record.arrests.size() + 1))
	_next_case = int(state.get("next_case", record.cases.size() + 1))
	_last_tier = tier()
