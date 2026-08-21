extends Node
const MAIN_SCENE := preload("res://main.tscn")
var _main: Node3D

func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	for i in 6:
		await get_tree().process_frame
	_run()
	get_tree().quit()

func _run() -> void:
	print("--- probe P ---")
	EconomyManager.restore(500000)
	var market := CompanyDebug.stand_up(&"unit_main_18", &"convenience_store", "Silas Market", get_tree(), 40000)
	var branch := CompanyDebug.stand_up(&"unit_market_12", &"convenience_store", "Silas Central", get_tree(), 20000)
	print("shops: ", market, " ", branch)
	if market == null or branch == null:
		print("FAILED to stand up shops"); return

	var wh := CompanyDebug.stand_up_warehouse(market)
	print("warehouse: ", wh, " cap=", wh.capacity() if wh else 0)
	if wh == null: return
	CompanyDebug.add_racks(wh, 4)
	print("after racks cap=%d room=%d" % [wh.capacity(), wh.room_left()])

	# Bulk order with discount.
	var water := ItemCatalogue.by_id(&"bottled_water")
	var quote := LogisticsManager.bulk_quote(water, 300)
	print("bulk 300 water: gross=$%d discount=%.0f%% cost=$%d saved=$%d" % [
		quote["gross"], float(quote["discount"])*100.0, quote["cost"], quote["saved"]])
	var before_cash := market.cash_balance
	var res := LogisticsManager.order_to_warehouse(wh, &"bottled_water", 300)
	print("order result=%d  payer cash %d -> %d" % [res, before_cash, market.cash_balance])
	BusinessManager.deliver_now()
	print("warehouse holds water=%d used=%d" % [wh.held(&"bottled_water"), wh.used()])

	# Fleet.
	var fleet := CompanyDebug.stand_up_fleet(market)
	print("van=", fleet["van"], " driver=", fleet["driver"])
	print("personal vehicle value=$%d  company fleet value=$%d" % [
		VehicleRegistry.total_value(), CompanyFleet.fleet_value()])

	# The branch's back room is small, so make space the way a player would:
	# put what is there onto the shelves.
	for i in 3:
		BusinessManager.call("_restock_shelves", branch, 40)
	print("branch room after restocking: used=%d capacity=%d" % [
		branch.storage_used(), branch.storage_capacity()])

	# Transfer warehouse -> branch.
	var made := LogisticsManager.request_transfer(
		TransferOrder.Place.WAREHOUSE, wh.warehouse_id,
		TransferOrder.Place.BUSINESS, branch.business_id,
		{&"bottled_water": 80})
	var order: TransferOrder = made["order"]
	print("transfer result=%d order=%s status=%s" % [made["result"], order, order.status_name() if order else ""])
	if order == null: return
	print("  reserved at warehouse=%d available=%d held=%d" % [
		wh.reserved_of(&"bottled_water"), wh.available(&"bottled_water"), wh.held(&"bottled_water")])
	var branch_before := branch.storage_of(&"bottled_water")
	var d := LogisticsManager.dispatch_transfer(order)
	print("dispatch=%d status=%s eta=%s" % [d, order.status_name(), order.eta_text(TimeManager.total_minutes)])
	print("  after dispatch warehouse held=%d  branch=%d (unchanged)" % [
		wh.held(&"bottled_water"), branch.storage_of(&"bottled_water")])
	TimeManager.advance_minutes(200)
	LogisticsManager.advance_deliveries()
	print("  after arrival branch=%d (was %d) warehouse=%d status=%s note=%s" % [
		branch.storage_of(&"bottled_water"), branch_before,
		wh.held(&"bottled_water"), order.status_name(), order.note])
	print("  branch room: used=%d capacity=%d" % [
		branch.storage_used(), branch.storage_capacity()])

	# Distress.
	CompanyDebug.set_cash(branch, 0)
	var staff := branch.employees
	if not staff.is_empty():
		CompanyDebug.owe_wages(branch, staff[0], 900)
	FinanceManager.review(branch)
	print("branch distress=%s arrears=$%d" % [branch.distress_label(), branch.total_arrears()])
	var f := FinanceManager.forecast()
	print("forecast: cash=$%d due=$%d overdue=$%d projected=$%d runway=%.1f" % [
		f["cash"], f["due"], f["overdue"], f["projected"], f["runway_days"]])

	# Liquidation quote.
	var q := Liquidation.quote(branch)
	print("liquidation: raised=$%d owed=$%d left=$%d" % [q["raised"], q["owed"], q["left_over"]])
	print("--- probe P done ---")
