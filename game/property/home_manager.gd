extends Node
## Furniture, home storage and how comfortable a place is to live in.
##
## The counterpart to VehicleRegistry, and the same shape: records are the
## truth, the boxes in the room are views of them. A flat the player furnished
## and then walked out of still knows exactly where its sofa is, and puts it
## back in the same place when they walk in again.
##
## Furniture is bought at a shop and delivered, rather than carried: nobody puts
## a wardrobe in their pocket. Delivery is a short wait on the game clock and
## then the pieces are waiting at home to be placed.

signal furniture_changed()
signal furniture_bought(record: OwnedFurniture)
signal furniture_delivered(count: int)
signal furniture_placed(record: OwnedFurniture)
signal furniture_stored(record: OwnedFurniture)
signal storage_changed(residence_id: StringName)

enum BuyResult { OK, CANNOT_AFFORD, NO_SUCH_ITEM }

## In-game minutes between paying for something and it turning up at home. Long
## enough to be a delivery, short enough that nobody is left waiting about.
const DELIVERY_MINUTES := 45

## A home with nothing in it still holds a few things — a cupboard exists in
## any flat. Storage furniture adds to this.
const BASE_STORAGE_SLOTS := 6

var _owned: Array[OwnedFurniture] = []
var _next_number: int = 1
## Furniture paid for and on its way: [{furniture_id, price, arrives_at}].
var _pending: Array[Dictionary] = []
## One Inventory node per residence, created the first time it is asked for.
var _storage: Dictionary = {}


## What the save file calls this.
var save_id: StringName = &"home_manager"


func _ready() -> void:
	add_to_group(&"saveable")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	TimeManager.minute_passed.connect(_on_minute_passed)


# --- Ownership -----------------------------------------------------------

func all_furniture() -> Array[OwnedFurniture]:
	return _owned.duplicate()


func by_id(instance_id: StringName) -> OwnedFurniture:
	for record in _owned:
		if record.instance_id == instance_id:
			return record
	return null


## Bought but not yet put anywhere. What the placement mode offers.
func in_storage() -> Array[OwnedFurniture]:
	var found: Array[OwnedFurniture] = []
	for record in _owned:
		if not record.is_placed():
			found.append(record)
	return found


func placed_in(residence_id: StringName) -> Array[OwnedFurniture]:
	var found: Array[OwnedFurniture] = []
	for record in _owned:
		if record.residence_id == residence_id:
			found.append(record)
	return found


func stored_count_of(furniture_id: StringName) -> int:
	var count := 0
	for record in in_storage():
		if record.furniture_id == furniture_id:
			count += 1
	return count


func pending_count() -> int:
	return _pending.size()


# --- Buying --------------------------------------------------------------

## Buys one or several of the same thing out of the player's own pocket. The
## money goes now and the furniture arrives later, which is what a delivery is.
func buy(furniture_id: StringName, quantity: int = 1) -> BuyResult:
	var definition := FurnitureCatalogue.by_id(furniture_id)
	if definition == null:
		return BuyResult.NO_SUCH_ITEM
	quantity = maxi(quantity, 1)
	var cost := definition.purchase_price * quantity
	if not EconomyManager.can_afford(cost):
		GameManager.notify(
			"NOT ENOUGH CASH\nNeed $%s" % EconomyManager.with_thousands_separator(cost),
			GameManager.Tone.BAD
		)
		return BuyResult.CANNOT_AFFORD
	if not EconomyManager.spend(cost, "%s x%d" % [definition.display_name, quantity]):
		return BuyResult.CANNOT_AFFORD

	var arrives := TimeManager.total_minutes + float(DELIVERY_MINUTES)
	for i in quantity:
		_pending.append({
			"furniture_id": furniture_id,
			"price": definition.purchase_price,
			"arrives_at": arrives,
		})
	GameManager.notify(
		"ORDERED\n%s x%d  -$%s" % [
			definition.display_name.to_upper(), quantity,
			EconomyManager.with_thousands_separator(cost)
		],
		GameManager.Tone.GOOD
	)
	furniture_changed.emit()
	return BuyResult.OK


## Puts a piece on the books outright. The delivery van, the debug tools and a
## starter flat's own fittings all arrive this way.
func grant(furniture_id: StringName, price: int = 0) -> OwnedFurniture:
	var definition := FurnitureCatalogue.by_id(furniture_id)
	if definition == null:
		return null
	var record := OwnedFurniture.new()
	record.instance_id = StringName("furn_%d" % _next_number)
	_next_number += 1
	record.furniture_id = furniture_id
	record.purchase_price = price if price > 0 else definition.purchase_price
	_owned.append(record)
	furniture_bought.emit(record)
	furniture_changed.emit()
	return record


## Sells a piece back. Only something in storage can go — a sofa has to be
## picked up off the floor before the van will take it.
func sell(record: OwnedFurniture) -> int:
	if record == null or not _owned.has(record) or record.is_placed():
		return 0
	var definition := record.data()
	if definition == null:
		return 0
	var paid := definition.resale_value()
	_owned.erase(record)
	EconomyManager.deposit(paid, "%s — sold" % definition.display_name)
	furniture_changed.emit()
	return paid


func _on_minute_passed(_hour: int, _minute: int) -> void:
	if _pending.is_empty():
		return
	var now := TimeManager.total_minutes
	var arrived := 0
	var still_waiting: Array[Dictionary] = []
	for order in _pending:
		if float(order.get("arrives_at", 0.0)) <= now:
			grant(StringName(order.get("furniture_id", "")), int(order.get("price", 0)))
			arrived += 1
		else:
			still_waiting.append(order)
	_pending = still_waiting
	if arrived > 0:
		GameManager.notify(
			"FURNITURE DELIVERED\n%d item%s waiting at home" % [
				arrived, "" if arrived == 1 else "s"
			],
			GameManager.Tone.GOOD
		)
		furniture_delivered.emit(arrived)
		furniture_changed.emit()


## Brings every outstanding delivery in now. The tests and the debug tools use
## it; a player waits for the van.
func deliver_now() -> int:
	var count := _pending.size()
	for order in _pending:
		grant(StringName(order.get("furniture_id", "")), int(order.get("price", 0)))
	_pending.clear()
	if count > 0:
		furniture_delivered.emit(count)
		furniture_changed.emit()
	return count


# --- Placement -----------------------------------------------------------

## Sets a piece down in a residence. The caller has already decided the spot is
## legal — see FurniturePlacement, which is what asks.
func place(record: OwnedFurniture, residence_id: StringName, at: Vector3, rotation_y: float) -> bool:
	if record == null or not _owned.has(record):
		return false
	record.residence_id = residence_id
	record.position = at
	record.rotation_y = rotation_y
	furniture_placed.emit(record)
	furniture_changed.emit()
	return true


## Picks it back up. It stays owned, which is the difference between storing
## something and selling it.
func store(record: OwnedFurniture) -> bool:
	if record == null or not _owned.has(record) or not record.is_placed():
		return false
	record.residence_id = &""
	record.position = Vector3.ZERO
	record.rotation_y = 0.0
	furniture_stored.emit(record)
	furniture_changed.emit()
	return true


## Whether a footprint would clash with anything already down in this room.
func overlaps_placed(
	residence_id: StringName, footprint: Rect2, ignore: OwnedFurniture = null
) -> bool:
	for record in placed_in(residence_id):
		if record == ignore:
			continue
		var size := record.footprint_size()
		var other := Rect2(
			record.position.x - size.x * 0.5, record.position.z - size.y * 0.5, size.x, size.y
		)
		if footprint.intersects(other):
			return true
	return false


# --- Home storage --------------------------------------------------------

## The cupboard at a given address. Personal items only — this is not the shop's
## stock room and not the player's pockets.
func storage_for(residence_id: StringName) -> Inventory:
	if _storage.has(residence_id) and is_instance_valid(_storage[residence_id]):
		return _storage[residence_id]
	var box := Inventory.new()
	box.name = "HomeStorage_%s" % residence_id
	box.slot_count = storage_slots_for(residence_id)
	add_child(box)
	box.changed.connect(func() -> void: storage_changed.emit(residence_id))
	_storage[residence_id] = box
	return box


## How much fits: a cupboard's worth by default, plus whatever storage
## furniture has been put in. Buying a wardrobe is how the number goes up.
func storage_slots_for(residence_id: StringName) -> int:
	var slots := BASE_STORAGE_SLOTS
	for record in placed_in(residence_id):
		var definition := record.data()
		if definition != null:
			slots += definition.storage_slots
	return slots


## Re-sizes a home's storage after its furniture changed. Never shrinks below
## what is already in there: taking a wardrobe out must not delete its contents.
func refresh_storage_capacity(residence_id: StringName) -> void:
	if not _storage.has(residence_id):
		return
	var box: Inventory = _storage[residence_id]
	var used := 0
	for slot in box.get_slots():
		if not slot.is_empty():
			used += 1
	box.slot_count = maxi(storage_slots_for(residence_id), used)


# --- Comfort and lifestyle ----------------------------------------------

## How pleasant a home is, 0-100, from what is actually in it. An empty flat
## scores low and is still perfectly playable — comfort is a reward, never a
## requirement.
func comfort_of(residence_id: StringName) -> int:
	var total := 0
	for record in placed_in(residence_id):
		var definition := record.data()
		if definition != null:
			total += definition.comfort_value
	# Forty points of furniture is a thoroughly comfortable flat.
	return clampi(roundi(float(total) / 40.0 * 100.0), 0, 100)


## What the furniture in a home is worth to the lifestyle score.
##
## Only the best few pieces in each category count. That is the whole answer to
## the twenty-identical-plants problem, and it is a rule rather than a fudge:
## a second sofa does not make a flat twice as nice, and the third does nothing.
const CATEGORY_LIMIT := 2

func furniture_lifestyle(residence_id: StringName) -> int:
	var by_category: Dictionary = {}
	for record in placed_in(residence_id):
		var definition := record.data()
		if definition == null:
			continue
		var bucket: Array = by_category.get(definition.category, [])
		bucket.append(definition.lifestyle_value)
		by_category[definition.category] = bucket

	var total := 0
	for category in by_category:
		var values: Array = by_category[category]
		values.sort()
		values.reverse()
		for i in mini(values.size(), CATEGORY_LIMIT):
			total += int(values[i])
	return total


## The best bed in the home, for how well the player sleeps. Null when there is
## none, which is the starter flat's fitted bed doing its job instead.
func best_bed(residence_id: StringName) -> FurnitureData:
	var best: FurnitureData = null
	for record in placed_in(residence_id):
		var definition := record.data()
		if definition == null or not definition.is_bed():
			continue
		if best == null or definition.comfort_value > best.comfort_value:
			best = definition
	return best


## What the furniture would fetch if it were all sold. Counted into net worth at
## resale value rather than at what it cost, because that is what it is worth.
func furniture_resale_value() -> int:
	var total := 0
	for record in _owned:
		var definition := record.data()
		if definition != null:
			total += definition.resale_value()
	return total


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var items: Array = []
	for record in _owned:
		items.append(record.to_dictionary())

	var boxes: Dictionary = {}
	for residence_id: StringName in _storage:
		var box: Inventory = _storage[residence_id]
		if not is_instance_valid(box):
			continue
		var slots: Array = []
		for slot in box.get_slots():
			if slot.is_empty():
				continue
			slots.append({
				"id": String(slot.item.id), "quantity": slot.quantity, "stolen": slot.stolen,
			})
		boxes[String(residence_id)] = slots

	return {
		"furniture": items,
		"next_number": _next_number,
		"pending": _pending.duplicate(true),
		"storage": boxes,
	}


func load_state(state: Dictionary) -> void:
	_owned.clear()
	for entry: Dictionary in state.get("furniture", []):
		var record := OwnedFurniture.from_dictionary(entry)
		if record.data() == null:
			# An item the catalogue no longer has. Dropped rather than kept as
			# a piece nothing can draw or sell.
			continue
		if record.instance_id == &"":
			record.instance_id = StringName("furn_%d" % _next_number)
			_next_number += 1
		_owned.append(record)
	_next_number = maxi(int(state.get("next_number", _next_number)), _highest_number() + 1)

	_pending.clear()
	for order: Dictionary in state.get("pending", []):
		_pending.append(order.duplicate())

	for box: Inventory in _storage.values():
		if is_instance_valid(box):
			box.queue_free()
	_storage.clear()
	var boxes: Dictionary = state.get("storage", {})
	for key in boxes:
		var residence_id := StringName(key)
		var box := storage_for(residence_id)
		box.clear()
		for entry: Dictionary in boxes[key]:
			var item := ItemCatalogue.by_id(StringName(entry.get("id", "")))
			if item == null:
				continue
			var quantity := int(entry.get("quantity", 0))
			var stolen := int(entry.get("stolen", 0))
			if stolen > 0:
				box.add(item, stolen, true)
			if quantity - stolen > 0:
				box.add(item, quantity - stolen, false)
	furniture_changed.emit()


func _highest_number() -> int:
	var highest := 0
	for record in _owned:
		var digits := String(record.instance_id).trim_prefix("furn_")
		if digits.is_valid_int():
			highest = maxi(highest, int(digits))
	return highest


## Wipes everything. The test harness and a new game need this; nothing else.
func clear() -> void:
	_owned.clear()
	_pending.clear()
	for box: Inventory in _storage.values():
		if is_instance_valid(box):
			box.queue_free()
	_storage.clear()
	_next_number = 1
	furniture_changed.emit()
