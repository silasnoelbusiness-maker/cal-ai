class_name CriminalCareer
extends RefCounted

## What kind of criminal the player has actually been.
##
## §72 and §73 ask for three paths and a light progression that derives from
## completed work rather than from spent points. So there is nothing to allocate
## here: the counters go up as jobs finish, and the specialisation is simply
## whichever counter is highest.
##
## §74 keeps the payoff modest — better offers and slightly better money, not
## superpowers.

enum Path { NONE, GOODS, VEHICLE, CONTRACT }

const PATH_NAMES := {
	Path.NONE: "No record of note",
	Path.GOODS: "Goods specialist",
	Path.VEHICLE: "Vehicle specialist",
	Path.CONTRACT: "Contract specialist",
}

## Jobs of a kind needed for each rung of that speciality.
const RANK_THRESHOLDS := [0, 3, 8, 16, 28]
const RANK_NAMES := ["Unproven", "Working", "Established", "Sought after", "First call"]

## What a rung is worth on the payout, per §74. Twelve per cent at the top.
const RANK_BONUS := [0.0, 0.03, 0.06, 0.09, 0.12]

var goods_jobs: int = 0
var vehicle_jobs: int = 0
var contract_jobs: int = 0
var requests_filled: int = 0
var jobs_failed: int = 0
var jobs_abandoned: int = 0
var lifetime_illegal_income: int = 0
var best_single_payout: int = 0


## Which objectives count towards which path. One table, so the career screen
## and the crediting code cannot disagree.
static func path_of(objective: int) -> Path:
	match objective:
		IllegalJobData.Objective.STOLEN_GOODS_RUN, \
		IllegalJobData.Objective.MULTI_STOP_RUN, \
		IllegalJobData.Objective.RETRIEVE_STASH:
			return Path.GOODS
		IllegalJobData.Objective.VEHICLE_DELIVERY:
			return Path.VEHICLE
		IllegalJobData.Objective.ROBBERY_CONTRACT, \
		IllegalJobData.Objective.HIGH_RISK_THEFT:
			return Path.CONTRACT
		_:
			return Path.NONE


func count_of(path: Path) -> int:
	match path:
		Path.GOODS:
			return goods_jobs
		Path.VEHICLE:
			return vehicle_jobs
		Path.CONTRACT:
			return contract_jobs
		_:
			return 0


func credit(objective: int) -> void:
	match path_of(objective):
		Path.GOODS:
			goods_jobs += 1
		Path.VEHICLE:
			vehicle_jobs += 1
		Path.CONTRACT:
			contract_jobs += 1
		_:
			pass


func total_jobs() -> int:
	return goods_jobs + vehicle_jobs + contract_jobs


## The speciality: whatever has been done most. Ties go to nothing, because
## somebody who has done one of each is not a specialist in anything.
func speciality() -> Path:
	var best := Path.NONE
	var most := 0
	for path in [Path.GOODS, Path.VEHICLE, Path.CONTRACT]:
		var count := count_of(path)
		if count > most:
			most = count
			best = path
		elif count == most and count > 0:
			best = Path.NONE
	return best


static func path_name(path: Path) -> String:
	return String(PATH_NAMES.get(path, "No record of note"))


func rank_in(path: Path) -> int:
	var count := count_of(path)
	var reached := 0
	for candidate in range(RANK_THRESHOLDS.size()):
		if count >= int(RANK_THRESHOLDS[candidate]):
			reached = candidate
	return reached


func rank_name(path: Path) -> String:
	return String(RANK_NAMES[clampi(rank_in(path), 0, RANK_NAMES.size() - 1)])


## Jobs still needed for the next rung in a path, or -1 at the top.
func to_next_rank(path: Path) -> int:
	var rank := rank_in(path)
	if rank >= RANK_THRESHOLDS.size() - 1:
		return -1
	return int(RANK_THRESHOLDS[rank + 1]) - count_of(path)


## What the player's standing in a path is worth on a payout of that kind.
func payout_bonus(objective: int) -> float:
	var path := path_of(objective)
	if path == Path.NONE:
		return 0.0
	return float(RANK_BONUS[clampi(rank_in(path), 0, RANK_BONUS.size() - 1)])


func to_dict() -> Dictionary:
	return {
		"goods": goods_jobs,
		"vehicle": vehicle_jobs,
		"contract": contract_jobs,
		"requests": requests_filled,
		"failed": jobs_failed,
		"abandoned": jobs_abandoned,
		"income": lifetime_illegal_income,
		"best": best_single_payout,
	}


static func from_dict(state: Dictionary) -> CriminalCareer:
	var career := CriminalCareer.new()
	career.goods_jobs = int(state.get("goods", 0))
	career.vehicle_jobs = int(state.get("vehicle", 0))
	career.contract_jobs = int(state.get("contract", 0))
	career.requests_filled = int(state.get("requests", 0))
	career.jobs_failed = int(state.get("failed", 0))
	career.jobs_abandoned = int(state.get("abandoned", 0))
	career.lifetime_illegal_income = int(state.get("income", 0))
	career.best_single_payout = int(state.get("best", 0))
	return career
