extends Node
## The vans the company owns, and who drives them.
##
## Not a second vehicle registry. A company van is an ordinary OwnedVehicle
## whose `owner_id` is a business rather than the player, so it wears, is
## repaired, is valued and is spawned by exactly the code that already does all
## of that for the player's car. What lives here is the part the registry has no
## opinion about: which van belongs to which route, who is driving it, and
## whether it is out on a job right now.
##
## The accounting rule matters. A company van is bought with company money and
## counts towards company value; it must not also appear in the player's
## personal vehicle total, or the same van is worth double on the profile
## screen. See `VehicleRegistry.total_value`, which now excludes them.

signal fleet_changed()
signal vehicle_assigned(record: OwnedVehicle, kind: StringName, target: StringName)

enum Assignment { NONE, WAREHOUSE, BRANCH, ROUTE }

## Units a van can carry in one trip. A shipment bigger than this is split
## across several, which is what §111 asks for without modelling a cargo bay.
const VAN_CAPACITY := 220
const CAR_CAPACITY := 45

var save_id: StringName = &"company_fleet"

## vehicle instance id -> {"kind": Assignment, "target": StringName}
var _assignments: Dictionary = {}
## vehicle instance id -> transfer id it is currently running.
var _busy: Dictionary = {}


func _ready() -> void:
	add_to_group(&"saveable")


## Where a company vehicle stands when it is not out. The kerb outside the
## property it belongs to, which is forgiving enough that nobody has to reverse
## into a loading dock. §112.
func _delivery_bay_for(business: BusinessInstance) -> Transform3D:
	var unit := PropertyManager.by_id(business.property_id) if business != null else null
	if unit == null:
		return Transform3D.IDENTITY
	var at := Transform3D.IDENTITY
	at.origin = unit.global_position + Vector3(0.0, 0.4, 4.0)
	return at


# --- The fleet -----------------------------------------------------------

## Every vehicle owned by a business rather than by the player.
func company_vans() -> Array[OwnedVehicle]:
	var found: Array[OwnedVehicle] = []
	for record in VehicleRegistry.get_fleet():
		if is_company_owned(record):
			found.append(record)
	return found


static func is_company_owned(record: OwnedVehicle) -> bool:
	return record != null and record.owner_id != &"player" and record.owner_id != &""


func vehicle_by_id(instance_id: StringName) -> OwnedVehicle:
	if instance_id == &"":
		return null
	var record := VehicleRegistry.by_id(instance_id)
	return record if is_company_owned(record) else null


## A van that is not already out on a job and is fit to drive.
func free_van() -> OwnedVehicle:
	for record in company_vans():
		if is_busy(record) or record.stolen:
			continue
		# A wreck is not a delivery van. §106: the shipment waits rather than
		# going out in something that cannot make the journey.
		if record.health_fraction() < 0.25:
			continue
		return record
	return null


func is_busy(record: OwnedVehicle) -> bool:
	return record != null and _busy.has(record.instance_id)


func set_vehicle_busy(record: OwnedVehicle, transfer_id: StringName) -> void:
	if record != null:
		_busy[record.instance_id] = transfer_id


func clear_vehicle_task(instance_id: StringName) -> void:
	_busy.erase(instance_id)


func cargo_capacity(record: OwnedVehicle) -> int:
	if record == null:
		return 0
	var data := record.data()
	if data == null:
		return CAR_CAPACITY
	# A van is a van because of what it is, not because of a flag: the model's
	# own size decides, so a later cargo model needs no change here.
	return VAN_CAPACITY if data.is_van() else CAR_CAPACITY


# --- Buying and selling --------------------------------------------------

## Buys a van onto a business's books. Company money out, company asset in —
## the player's own cash is not touched, which is the whole point of §155.
func buy_for_company(model_id: StringName, payer: BusinessInstance) -> OwnedVehicle:
	if payer == null:
		return null
	var model := VehicleCatalogue.data_for(model_id)
	if model == null:
		return null
	var price := model.price_new
	if not payer.debit(price, "Company vehicle — %s" % model.display_name, &"equipment"):
		GameManager.notify(
			"THE BUSINESS CANNOT AFFORD THAT VAN", GameManager.Tone.BAD
		)
		return null
	# Parked at whichever property the business trades from, so a van bought
	# for a branch is standing outside that branch.
	var record := VehicleRegistry.grant(model_id, _delivery_bay_for(payer))
	if record == null:
		return null
	record.owner_id = payer.business_id
	record.purchase_price = price
	_assignments[record.instance_id] = {
		"kind": Assignment.BRANCH, "target": payer.business_id,
	}
	fleet_changed.emit()
	CompanyManager.note_milestone(&"first_van")
	GameManager.notify(
		"COMPANY VEHICLE BOUGHT\n%s" % model.display_name.to_upper(), GameManager.Tone.GOOD
	)
	AudioManager.play(&"purchase", AudioBuses.SFX, -8.0)
	return record


## Sells one. The money goes back to the business that owns it, never to the
## player's pocket. §126.
func sell_company_vehicle(record: OwnedVehicle) -> int:
	if not is_company_owned(record):
		return 0
	if is_busy(record):
		GameManager.notify("THAT VAN IS OUT ON A DELIVERY", GameManager.Tone.BAD)
		return 0
	var owner := BusinessManager.by_id(record.owner_id)
	var paid := record.dealer_offer()
	VehicleRegistry.remove(record)
	_assignments.erase(record.instance_id)
	_busy.erase(record.instance_id)
	if owner != null and paid > 0:
		owner.credit(paid, "Sold %s" % record.display_name(), &"revenue")
	fleet_changed.emit()
	return paid


## What the company's vehicles are worth together. Feeds company value, and
## deliberately not the player's vehicle total.
func fleet_value() -> int:
	var total := 0
	for record in company_vans():
		total += record.market_value()
	return total


# --- Assignment ----------------------------------------------------------

func assignment_of(record: OwnedVehicle) -> Dictionary:
	if record == null:
		return {"kind": Assignment.NONE, "target": &""}
	return _assignments.get(
		record.instance_id, {"kind": Assignment.NONE, "target": &""}
	)


func assign(record: OwnedVehicle, kind: Assignment, target: StringName) -> void:
	if not is_company_owned(record):
		return
	_assignments[record.instance_id] = {"kind": kind, "target": target}
	vehicle_assigned.emit(record, StringName(Assignment.keys()[kind]), target)
	fleet_changed.emit()


func assignment_text(record: OwnedVehicle) -> String:
	var entry := assignment_of(record)
	var target := StringName(entry.get("target", &""))
	match int(entry.get("kind", Assignment.NONE)):
		Assignment.WAREHOUSE:
			var warehouse := LogisticsManager.warehouse_by_id(target)
			return warehouse.display_name if warehouse != null else "Warehouse"
		Assignment.BRANCH:
			var business := BusinessManager.by_id(target)
			return business.business_name if business != null else "Branch"
		Assignment.ROUTE:
			var route := LogisticsManager.route_by_id(target)
			return route.display_name if route != null else "Route"
		_:
			return "Unassigned"


# --- Drivers -------------------------------------------------------------

## Everybody employed anywhere in the company to drive.
func drivers() -> Array[EmployeeData]:
	var found: Array[EmployeeData] = []
	for business in BusinessManager.get_businesses():
		for worker in business.employees:
			if worker.role == EmployeeData.Role.DELIVERY_DRIVER:
				found.append(worker)
	return found


## A driver on shift now and not already out. One person cannot drive two vans,
## which is the same rule the backup pool works by.
func free_driver(hour: int) -> EmployeeData:
	var out := {}
	for id: StringName in _busy:
		var order := LogisticsManager.transfer_by_id(StringName(_busy[id]))
		if order != null and order.is_moving():
			out[order.assigned_driver_id] = true
	for worker in drivers():
		if not worker.is_on_shift(hour) or out.has(worker.employee_id):
			continue
		return worker
	return null


func clear() -> void:
	_assignments.clear()
	_busy.clear()


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var stored := {}
	for id: StringName in _assignments:
		var entry: Dictionary = _assignments[id]
		stored[String(id)] = {
			"kind": int(entry.get("kind", Assignment.NONE)),
			"target": String(entry.get("target", "")),
		}
	var running := {}
	for id: StringName in _busy:
		running[String(id)] = String(_busy[id])
	return {"assignments": stored, "busy": running}


func load_state(state: Dictionary) -> void:
	clear()
	for key in state.get("assignments", {}):
		var entry: Dictionary = state["assignments"][key]
		_assignments[StringName(key)] = {
			"kind": int(entry.get("kind", Assignment.NONE)),
			"target": StringName(entry.get("target", "")),
		}
	for key in state.get("busy", {}):
		_busy[StringName(key)] = StringName(state["busy"][key])
