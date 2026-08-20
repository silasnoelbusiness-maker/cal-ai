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
	# Signing for a unit is a decision worth not losing.
	SaveManager.autosave("leased a unit")
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


# --- Residences ----------------------------------------------------------

func get_residences() -> Array[ResidenceProperty]:
	var found: Array[ResidenceProperty] = []
	for node in get_tree().get_nodes_in_group(&"residence"):
		var home := node as ResidenceProperty
		if home != null:
			found.append(home)
	return found


func residence_by_id(id: StringName) -> ResidenceProperty:
	for home in get_residences():
		if home.residence_id == id:
			return home
	return null


## Where the player wakes up. There is always exactly one, which is why a home
## cannot be given up without choosing another first.
func current_home() -> ResidenceProperty:
	for home in get_residences():
		if home.is_current_home():
			return home
	return null


## Signs a residential lease out of the player's own pocket. Two entries again,
## for the same reason: a deposit comes back and rent does not.
func lease_residence(home: ResidenceProperty) -> bool:
	if home == null or home.is_leased_by_player():
		return false
	if not EconomyManager.can_afford(home.move_in_cost()):
		GameManager.notify(
			"NOT ENOUGH CASH\nNeed $%d" % home.move_in_cost(), GameManager.Tone.BAD
		)
		return false
	EconomyManager.spend(home.deposit, "%s — deposit" % home.address)
	EconomyManager.spend(home.rent_amount, "%s — rent" % home.address)
	home.begin_lease()
	GameManager.notify(
		"APARTMENT RENTED\n%s  -$%d" % [home.address.to_upper(), home.move_in_cost()],
		GameManager.Tone.GOOD
	)
	return true


## Residential rent, on the same calendar as everything else. It comes out of the
## player's pocket — a flat is not a business expense.
func charge_due_residence_rent() -> void:
	for home in get_residences():
		if not home.is_rent_due():
			continue
		var paid := EconomyManager.spend(home.rent_amount, "%s — rent" % home.address)
		home.settle_rent(paid)
		GameManager.notify(
			"RENT PAID\n%s  -$%d" % [home.address.to_upper(), home.rent_amount] if paid
			else "RENT OVERDUE\n%s" % home.address.to_upper(),
			GameManager.Tone.INFO if paid else GameManager.Tone.BAD
		)


# --- Garages -------------------------------------------------------------

func get_garages() -> Array[GarageProperty]:
	return GarageProperty.all(get_tree())


func garage_by_id(id: StringName) -> GarageProperty:
	return GarageProperty.by_id(get_tree(), id)


func leased_garages() -> Array[GarageProperty]:
	var found: Array[GarageProperty] = []
	for garage in get_garages():
		if garage.is_leased_by_player():
			found.append(garage)
	return found


## Rents a garage out of the player's own pocket. A garage is somewhere to put
## your things, not a business expense, so it comes from the same account the
## flat does.
func lease_garage(garage: GarageProperty) -> bool:
	if garage == null or garage.is_leased_by_player():
		return false
	if not EconomyManager.can_afford(garage.move_in_cost()):
		GameManager.notify(
			"NOT ENOUGH CASH
Need $%d" % garage.move_in_cost(), GameManager.Tone.BAD
		)
		return false
	EconomyManager.spend(garage.deposit, "%s — deposit" % garage.display_name)
	EconomyManager.spend(garage.rent_amount, "%s — rent" % garage.display_name)
	garage.begin_lease()
	GameManager.notify(
		"GARAGE RENTED
%s  ·  %d bays" % [garage.display_name.to_upper(), garage.capacity],
		GameManager.Tone.GOOD
	)
	SaveManager.autosave("rented a garage")
	return true


## Garage rent, on the same calendar as everything else. A missed payment is
## recorded and said out loud; it never costs the player a car.
func charge_due_garage_rent() -> void:
	for garage in get_garages():
		if not garage.is_rent_due():
			continue
		var paid := EconomyManager.spend(garage.rent_amount, "%s — rent" % garage.display_name)
		garage.settle_rent(paid)
		GameManager.notify(
			"RENT PAID
%s  -$%d" % [garage.display_name.to_upper(), garage.rent_amount] if paid
			else "GARAGE RENT OVERDUE
%s" % garage.display_name.to_upper(),
			GameManager.Tone.INFO if paid else GameManager.Tone.BAD
		)


func _on_day_passed(_day_index: int) -> void:
	charge_due_rent()
	charge_due_residence_rent()
	charge_due_garage_rent()
