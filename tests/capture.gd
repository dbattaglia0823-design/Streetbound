extends SceneTree
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://capture.png")
	for child in scene.get_children():
		if child is CanvasLayer:
			child.tuning.visible = true
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://capture_tuning.png")
	quit()
