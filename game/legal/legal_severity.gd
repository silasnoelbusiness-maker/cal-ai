class_name LegalSeverity
extends RefCounted

## How seriously the city takes an incident, and what that costs.
##
## Phase Q already answers "how bad is this crime" in `CrimeData.Severity`, and
## §4 is explicit that Phase R must not build a second severity table. So this
## classifies nothing. It reads the band Phase Q produced for the whole incident
## and answers the questions only the legal system asks of it: does this need a
## court date, what does release cost, how long does the record remember it.
##
## Everything here is fictional and deliberately coarse. Phase R has no interest
## in real sentencing rules, and a game does not need them.

## What a single incident is worth on the record, before repeat history.
## Indexed by CrimeData.Severity.
const RECORD_WEIGHT := [1, 3, 7, 14, 22]

## How long one incident keeps its full weight, in days. After this it fades —
## see CriminalRecord.pressure(). A shoplifting stops mattering long before an
## armed robbery does, which is §13.
const WEIGHT_FULL_DAYS := [10, 25, 60, 120, 200]

## Below this band an incident is dealt with on the spot: a fine, a few hours, a
## line on the record, no case (§8). At or above it, a case opens (§9).
const COURT_FROM: CrimeData.Severity = CrimeData.Severity.SERIOUS

## Release cost as a multiple of the arrest fine, by severity. A minor arrest is
## simply over; the serious end has to be bought out of.
const RELEASE_MULTIPLIER := [0.0, 0.0, 0.55, 0.9, 1.4]


static func weight_of(band: CrimeData.Severity) -> int:
	return int(RECORD_WEIGHT[clampi(int(band), 0, RECORD_WEIGHT.size() - 1)])


static func full_days(band: CrimeData.Severity) -> int:
	return int(WEIGHT_FULL_DAYS[clampi(int(band), 0, WEIGHT_FULL_DAYS.size() - 1)])


## Whether an incident this serious opens a case with a court date.
static func needs_case(band: CrimeData.Severity) -> bool:
	return int(band) >= int(COURT_FROM)


static func release_multiplier(band: CrimeData.Severity) -> float:
	return float(RELEASE_MULTIPLIER[clampi(int(band), 0, RELEASE_MULTIPLIER.size() - 1)])


## The name Phase Q already uses, so the legal screen and the wanted HUD agree.
static func name_of(band: CrimeData.Severity) -> String:
	return CrimeData.severity_name(band)
