class_name ServiceResult
extends RefCounted
## What became of one customer.
##
## Returned by every OperatingModel so the near simulation, the far simulation
## and the tests all describe a visit in the same words. The money has already
## moved by the time one of these comes back — this is the account of it, not
## the instruction.

var served: bool = false
var revenue: int = 0
var units: int = 0
## Change to the business's running satisfaction, already applied.
var satisfaction: float = 0.0
## Empty when the customer got what they came for.
var lost_reason: StringName = &""
## 0-100, what this customer thought of the visit. Only meaningful when served.
var quality: float = 0.0


static func lost(reason: StringName, satisfaction: float = -0.25) -> ServiceResult:
	var result := ServiceResult.new()
	result.lost_reason = reason
	result.satisfaction = satisfaction
	return result


static func sale(revenue: int, units: int, satisfaction: float, quality: float = 70.0) -> ServiceResult:
	var result := ServiceResult.new()
	result.served = true
	result.revenue = revenue
	result.units = units
	result.satisfaction = satisfaction
	result.quality = quality
	return result
