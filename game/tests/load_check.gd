extends Node

const MAIN_SCENE := preload("res://main.tscn")

func _ready() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	for i in 60:
		await get_tree().physics_frame
	for hour in [12.75, 15.0]:
		GameManager.player.global_position = Vector3(-30.0, 0.5, -181.0)
		TimeManager.set_total_minutes(hour * 60.0)
		for i in 200:
			await get_tree().physics_frame
		var near := 0
		var parking := 0
		for p in get_tree().get_nodes_in_group(&"pedestrian"):
			if p.is_stood_down():
				continue
			if p.global_position.distance_to(GameManager.player.global_position) < 60.0:
				near += 1
				if p.routine_activity() == RoutineActivity.Kind.PARK:
					parking += 1
		print("hour=", hour, " near=", near, " in_park=", parking)
	get_tree().quit()
