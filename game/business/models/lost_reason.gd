class_name LostReason
extends RefCounted
## Why somebody who wanted to spend money did not.
##
## The point of naming these rather than counting one lost_sales number is that
## the player can act on them. "Fourteen lost customers" is a shrug; "fourteen
## turned away, no seating" is a decision to buy another table.

const NO_STOCK := &"no_stock"
const TOO_EXPENSIVE := &"too_expensive"
const QUEUE_TOO_LONG := &"queue_too_long"
const NO_SEATING := &"no_seating"
const BUSINESS_FULL := &"business_full"
const SERVICE_TOO_SLOW := &"service_too_slow"
const NO_STAFF := &"no_staff"
const TOO_DIRTY := &"too_dirty"

const ALL: Array[StringName] = [
	NO_STOCK, TOO_EXPENSIVE, QUEUE_TOO_LONG, NO_SEATING,
	BUSINESS_FULL, SERVICE_TOO_SLOW, NO_STAFF, TOO_DIRTY,
]

const LABELS := {
	NO_STOCK: "No stock",
	TOO_EXPENSIVE: "Too expensive",
	QUEUE_TOO_LONG: "Queue too long",
	NO_SEATING: "No seating",
	BUSINESS_FULL: "Business full",
	SERVICE_TOO_SLOW: "Service too slow",
	NO_STAFF: "Nobody serving",
	TOO_DIRTY: "Place was filthy",
}


static func label(reason: StringName) -> String:
	return String(LABELS.get(reason, "Walked out"))
