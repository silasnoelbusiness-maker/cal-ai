class_name IllegalJobData
extends RefCounted

## One piece of work from a criminal contact.
##
## Built on the courier job's shape (§83) rather than beside it: a job is an
## objective, a target, a reward, a clock and a status, and the player accepts
## or declines. What makes these different from courier runs is that doing them
## is itself a crime, so the police response is the game's existing one — no
## job here spawns its own pursuit.
##
## Four types and no more (§84). Each reuses gameplay that already exists:
## stealing a car, carrying something across town, robbing a till. Phase Q's
## contribution is a reason to do it and somebody to do it for.

## Phase R adds the last two (§79, §80). Both are deliberately abstract: a
## marked package to move, and a marked item to fetch back. Neither names a
## commodity, and neither describes a method.
enum Objective {
	VEHICLE_DELIVERY, STOLEN_GOODS_RUN, ROBBERY_CONTRACT, HIGH_RISK_THEFT,
	MULTI_STOP_RUN, RETRIEVE_STASH,
}
enum Status { OFFERED, ACTIVE, COMPLETE, FAILED, EXPIRED }
enum Risk { LOW, MEDIUM, HIGH, EXTREME }

const OBJECTIVE_NAMES := {
	Objective.VEHICLE_DELIVERY: "Vehicle delivery",
	Objective.STOLEN_GOODS_RUN: "Stolen goods run",
	Objective.ROBBERY_CONTRACT: "Robbery contract",
	Objective.HIGH_RISK_THEFT: "High-risk theft",
	Objective.MULTI_STOP_RUN: "Multi-stop run",
	Objective.RETRIEVE_STASH: "Retrieve a package",
}

const RISK_NAMES := {
	Risk.LOW: "LOW",
	Risk.MEDIUM: "MEDIUM",
	Risk.HIGH: "HIGH",
	Risk.EXTREME: "EXTREME",
}

const STATUS_NAMES := {
	Status.OFFERED: "OFFERED",
	Status.ACTIVE: "ACTIVE",
	Status.COMPLETE: "COMPLETE",
	Status.FAILED: "FAILED",
	Status.EXPIRED: "EXPIRED",
}

var job_id: StringName = &""
var contact_id: StringName = &""
var objective: Objective = Objective.VEHICLE_DELIVERY
## What has to be acquired or hit. A vehicle class, an item id, a business id —
## whatever the objective type means by a target.
var target_id: StringName = &""
var target_name: String = "Target"
## Units wanted, for the objectives that count things.
var target_quantity: int = 1
var reward: int = 0
var risk: Risk = Risk.MEDIUM
## In-game hours to do it in. Zero is untimed.
var time_limit_hours: int = 8
## Deadline in absolute game minutes, set when accepted.
var deadline_minute: float = -1.0
var reputation_reward: int = 3
var status: Status = Status.OFFERED
## How much has been done, for objectives with more than one step.
var progress: int = 0


static func make(
	id: StringName, from_contact: StringName, kind: Objective,
	target: StringName, target_label: String, pay: int,
	danger: Risk, hours: int, reputation: int, quantity: int = 1
) -> IllegalJobData:
	var job := IllegalJobData.new()
	job.job_id = id
	job.contact_id = from_contact
	job.objective = kind
	job.target_id = target
	job.target_name = target_label
	job.reward = pay
	job.risk = danger
	job.time_limit_hours = hours
	job.reputation_reward = reputation
	job.target_quantity = maxi(quantity, 1)
	return job


static func objective_name(kind: Objective) -> String:
	return String(OBJECTIVE_NAMES.get(kind, "Job"))


static func risk_name(danger: Risk) -> String:
	return String(RISK_NAMES.get(danger, "MEDIUM"))


func objective_label() -> String:
	return objective_name(objective)


func risk_label() -> String:
	return risk_name(risk)


func status_label() -> String:
	return String(STATUS_NAMES.get(status, "OFFERED"))


func is_open() -> bool:
	return status == Status.OFFERED or status == Status.ACTIVE


func is_active() -> bool:
	return status == Status.ACTIVE


func is_finished() -> bool:
	return status == Status.COMPLETE or status == Status.FAILED \
		or status == Status.EXPIRED


func hours_left() -> float:
	if deadline_minute < 0.0:
		return float(time_limit_hours)
	return maxf(deadline_minute - TimeManager.total_minutes, 0.0) / 60.0


func is_overdue() -> bool:
	return status == Status.ACTIVE and deadline_minute >= 0.0 \
		and TimeManager.total_minutes > deadline_minute


func time_text() -> String:
	if time_limit_hours <= 0:
		return "no limit"
	if status != Status.ACTIVE:
		return "%dh" % time_limit_hours
	return "%.1fh left" % hours_left()


func to_dict() -> Dictionary:
	return {
		"id": String(job_id),
		"contact": String(contact_id),
		"objective": int(objective),
		"target": String(target_id),
		"target_name": target_name,
		"quantity": target_quantity,
		"reward": reward,
		"risk": int(risk),
		"hours": time_limit_hours,
		"deadline": deadline_minute,
		"reputation": reputation_reward,
		"status": int(status),
		"progress": progress,
	}


static func from_dict(state: Dictionary) -> IllegalJobData:
	var job := IllegalJobData.new()
	job.job_id = StringName(state.get("id", ""))
	job.contact_id = StringName(state.get("contact", ""))
	job.objective = int(state.get("objective", 0)) as Objective
	job.target_id = StringName(state.get("target", ""))
	job.target_name = String(state.get("target_name", "Target"))
	job.target_quantity = int(state.get("quantity", 1))
	job.reward = int(state.get("reward", 0))
	job.risk = int(state.get("risk", 1)) as Risk
	job.time_limit_hours = int(state.get("hours", 8))
	job.deadline_minute = float(state.get("deadline", -1.0))
	job.reputation_reward = int(state.get("reputation", 3))
	job.status = int(state.get("status", 0)) as Status
	job.progress = int(state.get("progress", 0))
	return job
