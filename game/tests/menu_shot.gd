extends Node
## Renders a front-end screen to a PNG. The main harness instances main.tscn;
## the menus are their own scene, so they need their own tiny harness.
##
##   godot --rendering-driver opengl3 --path game res://tests/menu_shot.tscn \
##       ++ out=shot.png screen=settings tab=0

const MENU_SCENE := preload("res://ui/menu/main_menu.tscn")

var _args: Dictionary = {}


func _ready() -> void:
	_parse_args()
	if _args.has("saves"):
		await _seed_saves()
	var menu: Control = MENU_SCENE.instantiate()
	add_child(menu)
	await _wait(20)

	match String(_args.get("screen", "menu")):
		"settings":
			menu.get_node("Settings").open()
			await _wait(6)
			menu.get_node("Settings")._show_tab(int(_args.get("tab", 0)))
		"load":
			menu._open_load_panel()
		_:
			pass

	await _wait(12)
	await RenderingServer.frame_post_draw

	var path := String(_args.get("out", "user://menu.png"))
	var image := get_viewport().get_texture().get_image()
	if image.save_png(path) != OK:
		push_error("Could not write %s" % path)
		get_tree().quit(1)
		return
	print("Wrote ", path)
	get_tree().quit(0)


## Real saves, written by playing: the world is built, saved to two manual slots
## and autosaved, then thrown away. Hand-written JSON would photograph the same
## but would not prove the slot list can read what the game actually writes.
func _seed_saves() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	add_child(world)
	await _wait(30)
	SaveManager.save_to_slot(1)
	EconomyManager.deposit(4200, "Screenshot seed", EconomyManager.Source.LEGAL)
	await _wait(10)
	SaveManager.save_to_slot(2)
	SaveManager.autosave("screenshot")
	await _wait(4)
	world.queue_free()
	await _wait(4)


func _parse_args() -> void:
	# Everything after `++`, which the engine hands over already separated.
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
