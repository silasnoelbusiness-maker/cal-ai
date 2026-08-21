class_name DistressState
extends RefCounted
## How much trouble a business is in, and the rules for saying so.
##
## Five states rather than a number, because the player needs to know what to do
## and "solvency 0.42" does not tell them. Each step up is a fact about unpaid
## obligations rather than a mood, and each one is reversible by paying: a
## business climbs back out of DISTRESSED the moment its arrears are cleared,
## which is what makes rescuing one worth doing.
##
## Nothing here closes anything. CRITICAL is a warning with a countdown, and the
## closing is BusinessManager's to do, after the player has had days to react.

enum State { HEALTHY, WARNING, DISTRESSED, CRITICAL, CLOSED, LIQUIDATING }

const STATE_NAMES := {
	State.HEALTHY: "HEALTHY",
	State.WARNING: "WARNING",
	State.DISTRESSED: "DISTRESSED",
	State.CRITICAL: "CRITICAL",
	State.CLOSED: "CLOSED",
	State.LIQUIDATING: "LIQUIDATING",
}

## Days a business may sit at CRITICAL before it is closed for the player. Long
## enough to drive across the city, sell a car and put the money in.
const DAYS_AT_CRITICAL_BEFORE_CLOSURE := 4
## Overdue money that counts as being in real trouble rather than merely short.
const DISTRESSED_ARREARS := 400
## Missed payments across everything before a business is critical.
const CRITICAL_MISSES := 5


static func label(state: State) -> String:
	return String(STATE_NAMES.get(state, "UNKNOWN"))


## The colour a card is drawn in. Kept here so the dashboard, the map and the
## notifications cannot disagree about what "distressed" looks like.
static func colour(state: State) -> Color:
	match state:
		State.WARNING:
			return Color(0.878, 0.741, 0.325)
		State.DISTRESSED:
			return Color(0.898, 0.518, 0.243)
		State.CRITICAL:
			return Color(0.859, 0.271, 0.271)
		State.CLOSED, State.LIQUIDATING:
			return Color(0.545, 0.565, 0.612)
		_:
			return Color(0.376, 0.780, 0.549)


## Where a business stands, from what it owes and what it holds.
##
## `arrears` is everything already unpaid, `misses` how many separate payments
## have been missed, `cash` what is in the account and `due_soon` what falls due
## within the forecast window.
static func evaluate(arrears: int, misses: int, cash: int, due_soon: int) -> State:
	if misses >= CRITICAL_MISSES or (arrears >= DISTRESSED_ARREARS * 3 and cash <= 0):
		return State.CRITICAL
	if arrears >= DISTRESSED_ARREARS or misses >= 2:
		return State.DISTRESSED
	if arrears > 0 or cash < due_soon:
		return State.WARNING
	return State.HEALTHY


## Whether a state is one the player should be told about loudly.
static func is_alarming(state: State) -> bool:
	return state == State.DISTRESSED or state == State.CRITICAL


static func is_trading(state: State) -> bool:
	return state != State.CLOSED and state != State.LIQUIDATING
