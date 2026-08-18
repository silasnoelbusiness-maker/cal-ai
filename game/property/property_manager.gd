extends Node
## The letting agent.
##
## Owns the transaction side of renting: whether the player can afford a unit,
## taking the deposit and first rent, and charging rent on its cycle afterwards.
## Which unit is rented by whom is recorded on the property itself — this is the
## one place money moves for it.
##
## Deliberately thin. Everything it knows how to do is "find the properties in
## the world and act on them", so adding a second street of units is placing more
## CommercialProperty nodes and nothing here.

signal property_leased(property: CommercialProperty)
signal rent_paid(property: CommercialProperty, amount: int)
signal rent_missed(property: CommercialProperty, arrears: int)

enum LeaseResult { OK, ALREADY_LEASED, CANNOT_AFFORD, NO_PROPERTY }

const PROPERTY_GROUP := &"commercial_property"


func _ready() -> void:
	TimeManager.day_passed.connect(_on_day_passed)


func get_properties() -> Array[CommercialProperty]:
	var found: Array[CommercialProperty] = []
	for node in get_tree().get_nodes_in_group(PROPERTY_GROUP):
		var property := node as CommercialProperty
		if property != null:
			found.append(property)
	return found


func by_id(property_id: StringName) -> CommercialProperty:
	for property in get_properties():
		if property.property_id == property_id:
			return property
	return null


func vacant_properties() -> Array[CommercialProperty]:
	var found: Array[CommercialProperty] = []
	for property in get_properties():
		if property.is_vacant():
			found.append(property)
	return found


func leased_by_player() -> Array[CommercialProperty]:
	var found: Array[CommercialProperty] = []
	for property in get_properties():
		if property.is_leased_by_player():
			found.append(property)
	return found


func can_afford(property: CommercialProperty) -> bool:
	return property != null and EconomyManager.can_afford(property.move_in_cost())


## Signs a lease: deposit and first rent out of the player's pocket, then the
## property records the relationship. Two ledger entries rather than one, because
## a deposit is returnable and rent is not, and a later refund needs to be able
## to tell them apart.
func lease(property: CommercialProperty, tenant: StringName = &"player") -> LeaseResult:
	if property == null:
		return LeaseResult.NO_PROPERTY
	if not property.is_vacant():
		return LeaseResult.ALREADY_LEASED
	if not can_afford(property):
		GameManager.notify("NOT ENOUGH CASH\nNeed $%d" % property.move_in_cost(), GameManager.Tone.BAD)
		return LeaseResult.CANNOT_AFFORD

	EconomyManager.spend(property.deposit, "%s — commercial property deposit" % property.address)
	EconomyManager.spend(property.rent_amount, "%s — commercial rent" % property.address)
	property.begin_lease(tenant)

	GameManager.notify(
		"LEASE SIGNED\n%s  -$%d" % [property.address.to_upper(), property.move_in_cost()],
		GameManager.Tone.GOOD
	)
	property_leased.emit(property)
	return LeaseResult.OK


static func describe(result: LeaseResult) -> String:
	match result:
		LeaseResult.ALREADY_LEASED:
			return "ALREADY LET"
		LeaseResult.CANNOT_AFFORD:
			return "NOT ENOUGH CASH"
		LeaseResult.NO_PROPERTY:
			return "NO SUCH PROPERTY"
		_:
			return ""


## Rent day. The business trading from the unit pays if it can, because that is
## whose overhead it is; only if there is no business, or it is short, does the
## bill fall to the player's own pocket.
func charge_due_rent() -> void:
	for property in get_properties():
		if not property.is_rent_due():
			continue
		var paid := _collect(property)
		property.settle_rent(paid)
		if paid:
			GameManager.notify(
				"RENT PAID\n%s  -$%d" % [property.address.to_upper(), property.rent_amount],
				GameManager.Tone.INFO
			)
			rent_paid.emit(property, property.rent_amount)
		else:
			GameManager.notify(
				"RENT OVERDUE\n%s  $%d" % [property.address.to_upper(), property.arrears],
				GameManager.Tone.BAD
			)
			rent_missed.emit(property, property.arrears)


func _collect(property: CommercialProperty) -> bool:
	var reason := "%s — rent" % property.address
	var business := BusinessManager.business_for_property(property.property_id)
	if business != null and business.debit(property.rent_amount, reason, &"rent"):
		return true
	if property.tenant_id == &"player":
		return EconomyManager.spend(property.rent_amount, reason)
	return false


func _on_day_passed(_day_index: int) -> void:
	charge_due_rent()
