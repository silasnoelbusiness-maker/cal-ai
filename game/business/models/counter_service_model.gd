class_name CounterServiceModel
extends OperatingModel
## Made to order, handed over at a counter.
##
## The coffee shop, and anything else where one person both makes the thing and
## takes the money. Almost all of the retail model applies; what differs is who
## is behind the counter and the fact that seating is worth having even though
## nobody is served at it.


func customer_route() -> StringName:
	return &"counter"


func serving_role() -> int:
	return EmployeeData.Role.BARISTA


func serving_roles(_business: BusinessInstance) -> Array[int]:
	return [EmployeeData.Role.BARISTA, EmployeeData.Role.CASHIER]


## Somewhere to sit makes a cup of coffee worth more than the same cup carried
## out, so seats are a satisfaction bonus rather than a capacity limit.
func satisfaction_score(business: BusinessInstance, wait_penalty: float, quality: float = 70.0) -> float:
	var seats := business.count_of_role(EquipmentData.Role.SEATING)
	var comfort := minf(float(seats) * 3.0, 12.0)
	return super(business, wait_penalty, quality + comfort)
